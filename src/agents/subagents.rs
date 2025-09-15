use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, error};

use crate::error::{ZekeError, ZekeResult};
use crate::providers::{ProviderManager, ChatRequest, ChatMessage, ChatResponse};
use crate::tools::{ToolRegistry, ToolInput, ToolOutput};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum SubagentType {
    CodeReviewer,
    TestGenerator,
    Debugger,
    Refactorer,
    DocumentationWriter,
    SecurityAnalyzer,
    PerformanceOptimizer,
    GeneralPurpose,
}

impl std::str::FromStr for SubagentType {
    type Err = ZekeError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "code-reviewer" | "reviewer" => Ok(SubagentType::CodeReviewer),
            "test-generator" | "tester" => Ok(SubagentType::TestGenerator),
            "debugger" | "debug" => Ok(SubagentType::Debugger),
            "refactorer" | "refactor" => Ok(SubagentType::Refactorer),
            "documentation-writer" | "docs" => Ok(SubagentType::DocumentationWriter),
            "security-analyzer" | "security" => Ok(SubagentType::SecurityAnalyzer),
            "performance-optimizer" | "performance" => Ok(SubagentType::PerformanceOptimizer),
            "general-purpose" | "general" => Ok(SubagentType::GeneralPurpose),
            _ => Err(ZekeError::invalid_input(format!("Unknown subagent type: {}", s))),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubagentTask {
    pub id: String,
    pub agent_type: SubagentType,
    pub description: String,
    pub context: SubagentContext,
    pub status: TaskStatus,
    pub result: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub completed_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubagentContext {
    pub files: Vec<String>,
    pub code_snippets: Vec<CodeSnippet>,
    pub additional_context: HashMap<String, String>,
    pub requirements: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeSnippet {
    pub file_path: String,
    pub content: String,
    pub language: Option<String>,
    pub line_range: Option<(usize, usize)>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Copy)]
pub enum TaskStatus {
    Pending,
    Running,
    Completed,
    Failed,
}

#[async_trait]
pub trait Subagent: Send + Sync {
    async fn execute(&self, task: &SubagentTask, provider: &ProviderManager, tools: &ToolRegistry) -> ZekeResult<String>;
    fn get_type(&self) -> SubagentType;
    fn get_description(&self) -> &str;
    fn get_system_prompt(&self) -> &str;
}

pub struct CodeReviewerAgent;

#[async_trait]
impl Subagent for CodeReviewerAgent {
    async fn execute(&self, task: &SubagentTask, provider: &ProviderManager, _tools: &ToolRegistry) -> ZekeResult<String> {
        let mut messages = vec![
            ChatMessage {
                role: "system".to_string(),
                content: self.get_system_prompt().to_string(),
            }
        ];

        // Add context about the code to review
        let mut context_message = format!("Please review the following code:\n\n");
        context_message.push_str(&format!("Task: {}\n\n", task.description));

        for snippet in &task.context.code_snippets {
            context_message.push_str(&format!("File: {}\n", snippet.file_path));
            if let Some((start, end)) = snippet.line_range {
                context_message.push_str(&format!("Lines {}-{}:\n", start, end));
            }
            context_message.push_str("```");
            if let Some(lang) = &snippet.language {
                context_message.push_str(lang);
            }
            context_message.push('\n');
            context_message.push_str(&snippet.content);
            context_message.push_str("\n```\n\n");
        }

        if !task.context.requirements.is_empty() {
            context_message.push_str("Requirements to check:\n");
            for req in &task.context.requirements {
                context_message.push_str(&format!("- {}\n", req));
            }
            context_message.push('\n');
        }

        messages.push(ChatMessage {
            role: "user".to_string(),
            content: context_message,
        });

        let request = ChatRequest {
            messages,
            model: None,
            temperature: Some(0.3), // Lower temperature for more consistent reviews
            max_tokens: Some(2048),
            stream: Some(false),
        };

        let response = provider.chat_completion(&request).await?;
        Ok(response.content)
    }

    fn get_type(&self) -> SubagentType {
        SubagentType::CodeReviewer
    }

    fn get_description(&self) -> &str {
        "Reviews code for quality, best practices, potential bugs, and security issues"
    }

    fn get_system_prompt(&self) -> &str {
        "You are an expert code reviewer with deep knowledge of software engineering best practices. \
        Your role is to thoroughly review code and provide constructive feedback. Focus on:\n\n\
        1. Code quality and readability\n\
        2. Best practices and conventions\n\
        3. Potential bugs and edge cases\n\
        4. Security vulnerabilities\n\
        5. Performance considerations\n\
        6. Maintainability and extensibility\n\n\
        Provide specific, actionable feedback with examples when possible. \
        Be thorough but concise, and always maintain a helpful and professional tone."
    }
}

pub struct TestGeneratorAgent;

#[async_trait]
impl Subagent for TestGeneratorAgent {
    async fn execute(&self, task: &SubagentTask, provider: &ProviderManager, _tools: &ToolRegistry) -> ZekeResult<String> {
        let mut messages = vec![
            ChatMessage {
                role: "system".to_string(),
                content: self.get_system_prompt().to_string(),
            }
        ];

        let mut context_message = format!("Generate comprehensive tests for the following code:\n\n");
        context_message.push_str(&format!("Task: {}\n\n", task.description));

        for snippet in &task.context.code_snippets {
            context_message.push_str(&format!("File: {}\n", snippet.file_path));
            context_message.push_str("```");
            if let Some(lang) = &snippet.language {
                context_message.push_str(lang);
            }
            context_message.push('\n');
            context_message.push_str(&snippet.content);
            context_message.push_str("\n```\n\n");
        }

        if !task.context.requirements.is_empty() {
            context_message.push_str("Testing requirements:\n");
            for req in &task.context.requirements {
                context_message.push_str(&format!("- {}\n", req));
            }
        }

        messages.push(ChatMessage {
            role: "user".to_string(),
            content: context_message,
        });

        let request = ChatRequest {
            messages,
            model: None,
            temperature: Some(0.2),
            max_tokens: Some(3072),
            stream: Some(false),
        };

        let response = provider.chat_completion(&request).await?;
        Ok(response.content)
    }

    fn get_type(&self) -> SubagentType {
        SubagentType::TestGenerator
    }

    fn get_description(&self) -> &str {
        "Generates comprehensive unit tests, integration tests, and test cases for code"
    }

    fn get_system_prompt(&self) -> &str {
        "You are an expert test engineer specializing in creating comprehensive test suites. \
        Your role is to generate thorough, well-structured tests that cover:\n\n\
        1. Happy path scenarios\n\
        2. Edge cases and boundary conditions\n\
        3. Error handling and exception cases\n\
        4. Input validation\n\
        5. Integration points\n\
        6. Performance considerations\n\n\
        Generate tests using appropriate testing frameworks for the language. \
        Include setup, teardown, mocking when needed, and clear test descriptions. \
        Ensure tests are maintainable, readable, and follow testing best practices."
    }
}

pub struct DebuggerAgent;

#[async_trait]
impl Subagent for DebuggerAgent {
    async fn execute(&self, task: &SubagentTask, provider: &ProviderManager, _tools: &ToolRegistry) -> ZekeResult<String> {
        let mut messages = vec![
            ChatMessage {
                role: "system".to_string(),
                content: self.get_system_prompt().to_string(),
            }
        ];

        let mut context_message = format!("Debug the following issue:\n\n");
        context_message.push_str(&format!("Problem: {}\n\n", task.description));

        for snippet in &task.context.code_snippets {
            context_message.push_str(&format!("File: {}\n", snippet.file_path));
            context_message.push_str("```");
            if let Some(lang) = &snippet.language {
                context_message.push_str(lang);
            }
            context_message.push('\n');
            context_message.push_str(&snippet.content);
            context_message.push_str("\n```\n\n");
        }

        // Add additional context like error messages, logs, etc.
        for (key, value) in &task.context.additional_context {
            context_message.push_str(&format!("{}: {}\n", key, value));
        }

        messages.push(ChatMessage {
            role: "user".to_string(),
            content: context_message,
        });

        let request = ChatRequest {
            messages,
            model: None,
            temperature: Some(0.1), // Very low temperature for precise debugging
            max_tokens: Some(2048),
            stream: Some(false),
        };

        let response = provider.chat_completion(&request).await?;
        Ok(response.content)
    }

    fn get_type(&self) -> SubagentType {
        SubagentType::Debugger
    }

    fn get_description(&self) -> &str {
        "Analyzes code issues, identifies bugs, and provides debugging solutions"
    }

    fn get_system_prompt(&self) -> &str {
        "You are an expert debugger with deep knowledge of various programming languages and debugging techniques. \
        Your role is to analyze code issues and provide solutions. Focus on:\n\n\
        1. Identifying the root cause of the issue\n\
        2. Explaining why the bug occurs\n\
        3. Providing step-by-step debugging approach\n\
        4. Suggesting specific fixes with code examples\n\
        5. Recommending preventive measures\n\
        6. Identifying potential related issues\n\n\
        Be systematic in your analysis, provide clear explanations, and offer practical solutions. \
        Consider edge cases and provide multiple approaches when applicable."
    }
}

pub struct GeneralPurposeAgent;

#[async_trait]
impl Subagent for GeneralPurposeAgent {
    async fn execute(&self, task: &SubagentTask, provider: &ProviderManager, _tools: &ToolRegistry) -> ZekeResult<String> {
        let mut messages = vec![
            ChatMessage {
                role: "system".to_string(),
                content: self.get_system_prompt().to_string(),
            }
        ];

        let mut context_message = format!("Task: {}\n\n", task.description);

        if !task.context.code_snippets.is_empty() {
            context_message.push_str("Code context:\n");
            for snippet in &task.context.code_snippets {
                context_message.push_str(&format!("File: {}\n", snippet.file_path));
                context_message.push_str("```");
                if let Some(lang) = &snippet.language {
                    context_message.push_str(lang);
                }
                context_message.push('\n');
                context_message.push_str(&snippet.content);
                context_message.push_str("\n```\n\n");
            }
        }

        if !task.context.files.is_empty() {
            context_message.push_str("Relevant files:\n");
            for file in &task.context.files {
                context_message.push_str(&format!("- {}\n", file));
            }
            context_message.push('\n');
        }

        for (key, value) in &task.context.additional_context {
            context_message.push_str(&format!("{}: {}\n", key, value));
        }

        messages.push(ChatMessage {
            role: "user".to_string(),
            content: context_message,
        });

        let request = ChatRequest {
            messages,
            model: None,
            temperature: Some(0.7),
            max_tokens: Some(4096),
            stream: Some(false),
        };

        let response = provider.chat_completion(&request).await?;
        Ok(response.content)
    }

    fn get_type(&self) -> SubagentType {
        SubagentType::GeneralPurpose
    }

    fn get_description(&self) -> &str {
        "Handles complex multi-step tasks and general development questions"
    }

    fn get_system_prompt(&self) -> &str {
        "You are a general-purpose AI assistant specialized in software development. \
        You can help with a wide range of tasks including code analysis, problem-solving, \
        architecture decisions, and development questions. \n\n\
        You have access to various tools including file operations, code analysis, \
        and research capabilities. Use these tools when needed to provide comprehensive \
        and accurate assistance. \n\n\
        Always strive to provide detailed, well-reasoned responses with practical examples."
    }
}

pub struct SubagentManager {
    agents: HashMap<SubagentType, Arc<dyn Subagent>>,
    active_tasks: RwLock<HashMap<String, SubagentTask>>,
    provider_manager: Arc<ProviderManager>,
    tool_registry: Arc<ToolRegistry>,
}

impl SubagentManager {
    pub fn new(provider_manager: Arc<ProviderManager>, tool_registry: Arc<ToolRegistry>) -> Self {
        let mut agents: HashMap<SubagentType, Arc<dyn Subagent>> = HashMap::new();

        agents.insert(SubagentType::CodeReviewer, Arc::new(CodeReviewerAgent));
        agents.insert(SubagentType::TestGenerator, Arc::new(TestGeneratorAgent));
        agents.insert(SubagentType::Debugger, Arc::new(DebuggerAgent));
        agents.insert(SubagentType::GeneralPurpose, Arc::new(GeneralPurposeAgent));

        Self {
            agents,
            active_tasks: RwLock::new(HashMap::new()),
            provider_manager,
            tool_registry,
        }
    }

    pub async fn create_task(
        &self,
        agent_type: SubagentType,
        description: String,
        context: SubagentContext,
    ) -> ZekeResult<String> {
        let task_id = uuid::Uuid::new_v4().to_string();
        let task = SubagentTask {
            id: task_id.clone(),
            agent_type,
            description,
            context,
            status: TaskStatus::Pending,
            result: None,
            created_at: chrono::Utc::now(),
            completed_at: None,
        };

        let mut active_tasks = self.active_tasks.write().await;
        active_tasks.insert(task_id.clone(), task);

        info!("Created subagent task: {}", task_id);
        Ok(task_id)
    }

    pub async fn execute_task(&self, task_id: &str) -> ZekeResult<String> {
        let mut active_tasks = self.active_tasks.write().await;

        let task = active_tasks.get_mut(task_id)
            .ok_or_else(|| ZekeError::invalid_input(format!("Task '{}' not found", task_id)))?;

        task.status = TaskStatus::Running;

        let agent = self.agents.get(&task.agent_type)
            .ok_or_else(|| ZekeError::invalid_input(format!("No agent available for type: {:?}", task.agent_type)))?;

        debug!("Executing task '{}' with agent type: {:?}", task_id, task.agent_type);

        match agent.execute(task, &self.provider_manager, &self.tool_registry).await {
            Ok(result) => {
                task.status = TaskStatus::Completed;
                task.result = Some(result.clone());
                task.completed_at = Some(chrono::Utc::now());

                info!("Completed subagent task: {}", task_id);
                Ok(result)
            }
            Err(e) => {
                task.status = TaskStatus::Failed;
                error!("Failed to execute task '{}': {}", task_id, e);
                Err(e)
            }
        }
    }

    pub async fn get_task_status(&self, task_id: &str) -> Option<TaskStatus> {
        let active_tasks = self.active_tasks.read().await;
        active_tasks.get(task_id).map(|task| task.status.clone())
    }

    pub async fn get_task_result(&self, task_id: &str) -> Option<String> {
        let active_tasks = self.active_tasks.read().await;
        active_tasks.get(task_id).and_then(|task| task.result.clone())
    }

    pub async fn list_available_agents(&self) -> Vec<(SubagentType, &str)> {
        self.agents
            .iter()
            .map(|(agent_type, agent)| (agent_type.clone(), agent.get_description()))
            .collect()
    }

    pub async fn execute_task_immediately(
        &self,
        agent_type: SubagentType,
        description: String,
        context: SubagentContext,
    ) -> ZekeResult<String> {
        let task_id = self.create_task(agent_type, description, context).await?;
        self.execute_task(&task_id).await
    }
}