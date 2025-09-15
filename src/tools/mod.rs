use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use crate::error::{ZekeError, ZekeResult};

pub mod read;
pub mod write;
pub mod edit;
pub mod glob;
pub mod grep;
pub mod bash;
pub mod webfetch;
pub mod todo;

pub use read::ReadTool;
pub use write::WriteTool;
pub use edit::EditTool;
pub use glob::GlobTool;
pub use grep::GrepTool;
pub use bash::BashTool;
pub use webfetch::WebFetchTool;
pub use todo::{TodoTool, Task, TaskStatus, TaskManager};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ToolInput {
    Read { file_path: PathBuf },
    Write { file_path: PathBuf, content: String },
    Edit { file_path: PathBuf, old_string: String, new_string: String },
    Glob { pattern: String, path: Option<PathBuf> },
    Grep { pattern: String, path: Option<PathBuf>, file_type: Option<String> },
    Bash { command: String, timeout: Option<u64> },
    WebFetch { url: String, prompt: String },
    Todo {
        action: String,
        task_id: Option<String>,
        content: Option<String>,
        active_form: Option<String>,
        status: Option<TaskStatus>,
        priority: Option<u8>
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolOutput {
    pub success: bool,
    pub content: String,
    pub error: Option<String>,
}

#[async_trait]
pub trait Tool: Send + Sync {
    async fn execute(&self, input: ToolInput) -> ZekeResult<ToolOutput>;
    fn name(&self) -> &str;
    fn description(&self) -> &str;
}

pub struct ToolRegistry {
    tools: Vec<Box<dyn Tool>>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        let mut registry = Self {
            tools: Vec::new(),
        };

        // Register default tools
        registry.register(Box::new(ReadTool::new()));
        registry.register(Box::new(WriteTool::new()));
        registry.register(Box::new(EditTool::new()));
        registry.register(Box::new(GlobTool::new()));
        registry.register(Box::new(GrepTool::new()));
        registry.register(Box::new(BashTool::new()));
        registry.register(Box::new(WebFetchTool::new()));
        registry.register(Box::new(TodoTool::new()));

        registry
    }

    pub fn register(&mut self, tool: Box<dyn Tool>) {
        self.tools.push(tool);
    }

    pub async fn execute_tool(&self, tool_name: &str, input: ToolInput) -> ZekeResult<ToolOutput> {
        for tool in &self.tools {
            if tool.name() == tool_name {
                return tool.execute(input).await;
            }
        }

        Err(ZekeError::invalid_input(format!("Tool '{}' not found", tool_name)))
    }

    pub fn list_tools(&self) -> Vec<(&str, &str)> {
        self.tools.iter().map(|tool| (tool.name(), tool.description())).collect()
    }
}

impl Default for ToolRegistry {
    fn default() -> Self {
        Self::new()
    }
}