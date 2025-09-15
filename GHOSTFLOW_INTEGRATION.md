# Zeke Integration Guide

## Overview
Integration strategy for incorporating Zeke as a crate dependency into GhostFlow for AI-powered coding workflows and development automation.

## Integration Options

### Option 1: GitHub Crate Dependency (Recommended)
```toml
# crates/ghostflow-nodes/Cargo.toml
[dependencies]
zeke = { git = "https://github.com/ghostkellz/zeke" }
```

### Option 2: Local Crate Reference
```toml
# crates/ghostflow-nodes/Cargo.toml
[dependencies]
zeke = { path = "../../external/zeke" }
```

## Required GhostFlow Changes

### 1. Add Zeke Dependencies

#### Update Workspace Dependencies
```toml
# Cargo.toml (workspace root)
[workspace.dependencies]
# Existing dependencies...

# Zeke integration
zeke = { git = "https://github.com/ghostkellz/zeke" }

# Additional dependencies Zeke brings
ratatui = "0.24"
crossterm = "0.27"
rmp-serde = "1.1"
rmpv = "1.0"
oauth2 = "4.4"
```

#### Update Node Crate Dependencies
```toml
# crates/ghostflow-nodes/Cargo.toml
[dependencies]
ghostflow-core = { workspace = true }
ghostflow-schema = { workspace = true }

# Zeke integration
zeke = { workspace = true }

# For AI coding features
tokio = { workspace = true }
serde = { workspace = true }
```

### 2. Create AI Coding Nodes

#### New File: `crates/ghostflow-nodes/src/zeke_coding.rs`
```rust
use ghostflow_core::{Node, NodeDefinition, ExecutionContext, Result};
use ghostflow_schema::{InputDefinition, OutputDefinition, ParameterDefinition};
use zeke::{providers::ProviderManager, cli::commands::ask::AskCommand};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use async_trait::async_trait;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeAskNode {
    pub provider: String,
    pub model: Option<String>,
}

#[async_trait]
impl Node for ZekeAskNode {
    fn definition(&self) -> NodeDefinition {
        NodeDefinition {
            name: "Zeke Ask".to_string(),
            category: "AI/Coding".to_string(),
            description: "Ask Zeke AI a coding question".to_string(),
            inputs: vec![
                InputDefinition::new("question", "string", true, Some("Coding question".to_string())),
                InputDefinition::new("context", "string", false, Some("Additional context".to_string())),
                InputDefinition::new("code", "string", false, Some("Code to analyze".to_string())),
            ],
            outputs: vec![
                OutputDefinition::new("answer", "string", "AI response"),
                OutputDefinition::new("provider_info", "object", "Provider metadata"),
            ],
            parameters: vec![
                ParameterDefinition::string("provider", true, Some("claude".to_string()), "AI provider"),
                ParameterDefinition::string("model", false, None, "Specific model"),
            ],
        }
    }

    async fn execute(&self, context: ExecutionContext) -> Result<Value> {
        let question = context.inputs["question"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing required input: question"))?;

        let mut prompt = question.to_string();

        if let Some(code) = context.inputs.get("code").and_then(|v| v.as_str()) {
            prompt.push_str(&format!("\n\nCode:\n```\n{}\n```", code));
        }

        if let Some(ctx) = context.inputs.get("context").and_then(|v| v.as_str()) {
            prompt.push_str(&format!("\n\nContext: {}", ctx));
        }

        let provider_manager = ProviderManager::new().await
            .map_err(|e| anyhow::anyhow!("Failed to initialize provider manager: {}", e))?;

        let response = provider_manager.ask(&self.provider, &prompt, self.model.as_deref()).await
            .map_err(|e| anyhow::anyhow!("Zeke ask failed: {}", e))?;

        Ok(json!({
            "answer": response.content,
            "provider_info": {
                "provider": response.provider,
                "model": response.model,
                "tokens_used": response.usage.map(|u| u.total_tokens),
            }
        }))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeExplainNode {
    pub provider: String,
    pub language: Option<String>,
}

#[async_trait]
impl Node for ZekeExplainNode {
    fn definition(&self) -> NodeDefinition {
        NodeDefinition {
            name: "Zeke Explain".to_string(),
            category: "AI/Coding".to_string(),
            description: "Explain code using Zeke AI".to_string(),
            inputs: vec![
                InputDefinition::new("code", "string", true, Some("Code to explain".to_string())),
                InputDefinition::new("focus", "string", false, Some("Specific aspect to explain".to_string())),
            ],
            outputs: vec![
                OutputDefinition::new("explanation", "string", "Code explanation"),
                OutputDefinition::new("breakdown", "object", "Detailed breakdown"),
            ],
            parameters: vec![
                ParameterDefinition::string("provider", true, Some("claude".to_string()), "AI provider"),
                ParameterDefinition::string("language", false, None, "Programming language"),
            ],
        }
    }

    async fn execute(&self, context: ExecutionContext) -> Result<Value> {
        let code = context.inputs["code"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing required input: code"))?;

        let language = self.language.as_deref()
            .or_else(|| context.inputs.get("language").and_then(|v| v.as_str()))
            .unwrap_or("unknown");

        let focus = context.inputs.get("focus").and_then(|v| v.as_str());

        let mut prompt = format!("Explain this {} code:\n\n```{}\n{}\n```", language, language, code);

        if let Some(focus_area) = focus {
            prompt.push_str(&format!("\n\nFocus on: {}", focus_area));
        }

        let provider_manager = ProviderManager::new().await?;
        let response = provider_manager.ask(&self.provider, &prompt, None).await?;

        Ok(json!({
            "explanation": response.content,
            "breakdown": {
                "language": language,
                "lines_of_code": code.lines().count(),
                "focus_area": focus,
                "provider": response.provider,
                "model": response.model
            }
        }))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeGenerateNode {
    pub provider: String,
    pub language: String,
    pub style: Option<String>,
}

#[async_trait]
impl Node for ZekeGenerateNode {
    fn definition(&self) -> NodeDefinition {
        NodeDefinition {
            name: "Zeke Generate".to_string(),
            category: "AI/Coding".to_string(),
            description: "Generate code using Zeke AI".to_string(),
            inputs: vec![
                InputDefinition::new("requirements", "string", true, Some("Code requirements".to_string())),
                InputDefinition::new("function_name", "string", false, Some("Function name".to_string())),
                InputDefinition::new("existing_code", "string", false, Some("Existing code context".to_string())),
            ],
            outputs: vec![
                OutputDefinition::new("code", "string", "Generated code"),
                OutputDefinition::new("tests", "string", "Generated tests"),
                OutputDefinition::new("documentation", "string", "Generated docs"),
            ],
            parameters: vec![
                ParameterDefinition::string("provider", true, Some("copilot".to_string()), "AI provider"),
                ParameterDefinition::string("language", true, Some("rust".to_string()), "Programming language"),
                ParameterDefinition::string("style", false, None, "Coding style guide"),
            ],
        }
    }

    async fn execute(&self, context: ExecutionContext) -> Result<Value> {
        let requirements = context.inputs["requirements"]
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing required input: requirements"))?;

        let function_name = context.inputs.get("function_name").and_then(|v| v.as_str());
        let existing_code = context.inputs.get("existing_code").and_then(|v| v.as_str());

        let mut prompt = format!(
            "Generate {} code based on these requirements:\n\n{}",
            self.language, requirements
        );

        if let Some(name) = function_name {
            prompt.push_str(&format!("\n\nFunction name: {}", name));
        }

        if let Some(code) = existing_code {
            prompt.push_str(&format!("\n\nExisting code context:\n```{}\n{}\n```", self.language, code));
        }

        if let Some(style) = &self.style {
            prompt.push_str(&format!("\n\nStyle guide: {}", style));
        }

        prompt.push_str(&format!(
            "\n\nGenerate:\n1. The {} implementation\n2. Unit tests\n3. Documentation comments",
            self.language
        ));

        let provider_manager = ProviderManager::new().await?;
        let response = provider_manager.ask(&self.provider, &prompt, None).await?;

        // Parse the response to extract code, tests, and docs
        let parsed = parse_generated_content(&response.content, &self.language);

        Ok(json!({
            "code": parsed.code,
            "tests": parsed.tests,
            "documentation": parsed.documentation,
            "metadata": {
                "language": self.language,
                "provider": response.provider,
                "model": response.model,
                "tokens_used": response.usage.map(|u| u.total_tokens)
            }
        }))
    }
}

// Helper function to parse generated content
fn parse_generated_content(content: &str, language: &str) -> ParsedContent {
    // Simple parsing logic - could be enhanced
    let mut code = String::new();
    let mut tests = String::new();
    let mut documentation = String::new();

    let sections: Vec<&str> = content.split("```").collect();

    for (i, section) in sections.iter().enumerate() {
        if section.starts_with(language) {
            let code_content = section.trim_start_matches(language).trim();
            if i == 1 {
                code = code_content.to_string();
            } else if code_content.contains("test") || code_content.contains("Test") {
                tests = code_content.to_string();
            }
        }
    }

    // Extract documentation from comments
    documentation = content.lines()
        .filter(|line| line.trim_start().starts_with("//") || line.trim_start().starts_with("///"))
        .collect::<Vec<_>>()
        .join("\n");

    ParsedContent { code, tests, documentation }
}

#[derive(Debug)]
struct ParsedContent {
    code: String,
    tests: String,
    documentation: String,
}
```

### 3. Git Integration Nodes

#### New File: `crates/ghostflow-nodes/src/zeke_git.rs`
```rust
use ghostflow_core::{Node, NodeDefinition, ExecutionContext, Result};
use ghostflow_schema::{InputDefinition, OutputDefinition, ParameterDefinition};
use zeke::git::GitOperations;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use async_trait::async_trait;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeGitAnalysisNode {
    pub repository_path: String,
    pub analysis_type: GitAnalysisType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GitAnalysisType {
    CommitMessage,
    DiffSummary,
    ChangedFiles,
    BranchStatus,
}

#[async_trait]
impl Node for ZekeGitAnalysisNode {
    fn definition(&self) -> NodeDefinition {
        NodeDefinition {
            name: "Zeke Git Analysis".to_string(),
            category: "Development/Git".to_string(),
            description: "Analyze git repository using Zeke".to_string(),
            inputs: vec![
                InputDefinition::new("commit_hash", "string", false, Some("Specific commit".to_string())),
                InputDefinition::new("branch", "string", false, Some("Branch name".to_string())),
            ],
            outputs: vec![
                OutputDefinition::new("analysis", "string", "Git analysis result"),
                OutputDefinition::new("metadata", "object", "Git metadata"),
                OutputDefinition::new("suggestions", "array", "Improvement suggestions"),
            ],
            parameters: vec![
                ParameterDefinition::string("repository_path", true, Some(".".to_string()), "Repository path"),
                ParameterDefinition::enum_param("analysis_type", true, vec![
                    "commit_message", "diff_summary", "changed_files", "branch_status"
                ], "Type of analysis"),
            ],
        }
    }

    async fn execute(&self, context: ExecutionContext) -> Result<Value> {
        let git_ops = GitOperations::new(&self.repository_path)
            .map_err(|e| anyhow::anyhow!("Failed to initialize git operations: {}", e))?;

        let result = match self.analysis_type {
            GitAnalysisType::CommitMessage => {
                let commit = context.inputs.get("commit_hash")
                    .and_then(|v| v.as_str())
                    .unwrap_or("HEAD");
                git_ops.analyze_commit_message(commit).await?
            },
            GitAnalysisType::DiffSummary => {
                git_ops.get_diff_summary().await?
            },
            GitAnalysisType::ChangedFiles => {
                git_ops.get_changed_files().await?
            },
            GitAnalysisType::BranchStatus => {
                let branch = context.inputs.get("branch")
                    .and_then(|v| v.as_str())
                    .unwrap_or("HEAD");
                git_ops.get_branch_status(branch).await?
            },
        };

        Ok(json!({
            "analysis": result.summary,
            "metadata": {
                "repository": self.repository_path,
                "analysis_type": format!("{:?}", self.analysis_type),
                "commit_count": result.commit_count,
                "files_affected": result.files_affected,
                "timestamp": chrono::Utc::now()
            },
            "suggestions": result.suggestions
        }))
    }
}
```

### 4. CLI Integration

#### Add Zeke Commands
```rust
// crates/ghostflow-cli/src/commands/zeke.rs
use clap::Subcommand;
use zeke::{providers::ProviderManager, config::ZekeConfig};

#[derive(Subcommand)]
pub enum ZekeCommands {
    /// Ask Zeke a coding question
    Ask {
        #[arg(short, long)]
        provider: Option<String>,
        #[arg(short, long)]
        model: Option<String>,
        question: String,
    },
    /// Explain code using Zeke
    Explain {
        #[arg(short, long)]
        file: String,
        #[arg(short, long)]
        language: Option<String>,
    },
    /// Generate code using Zeke
    Generate {
        #[arg(short, long)]
        language: String,
        #[arg(short, long)]
        output: Option<String>,
        requirements: String,
    },
    /// List available AI providers
    Providers,
    /// Configure Zeke settings
    Config {
        #[command(subcommand)]
        command: ConfigCommands,
    },
}

#[derive(Subcommand)]
pub enum ConfigCommands {
    /// Set default provider
    SetProvider { provider: String },
    /// Set API key for provider
    SetKey { provider: String, key: String },
    /// Show current configuration
    Show,
}

pub async fn handle_zeke_command(cmd: ZekeCommands) -> anyhow::Result<()> {
    match cmd {
        ZekeCommands::Ask { provider, model, question } => {
            let provider_manager = ProviderManager::new().await?;
            let provider_name = provider.unwrap_or_else(|| "claude".to_string());

            let response = provider_manager.ask(&provider_name, &question, model.as_deref()).await?;

            println!("🤖 {}: {}", response.provider, response.content);
            if let Some(usage) = response.usage {
                println!("📊 Tokens used: {}", usage.total_tokens);
            }
        },
        ZekeCommands::Explain { file, language } => {
            let code = std::fs::read_to_string(&file)?;
            let lang = language.unwrap_or_else(|| detect_language(&file));

            let provider_manager = ProviderManager::new().await?;
            let prompt = format!("Explain this {} code:\n\n```{}\n{}\n```", lang, lang, code);

            let response = provider_manager.ask("claude", &prompt, None).await?;
            println!("📖 Code Explanation:\n{}", response.content);
        },
        ZekeCommands::Generate { language, output, requirements } => {
            let provider_manager = ProviderManager::new().await?;
            let prompt = format!("Generate {} code for: {}", language, requirements);

            let response = provider_manager.ask("copilot", &prompt, None).await?;

            if let Some(output_file) = output {
                std::fs::write(&output_file, &response.content)?;
                println!("✅ Generated code saved to: {}", output_file);
            } else {
                println!("🔧 Generated Code:\n{}", response.content);
            }
        },
        ZekeCommands::Providers => {
            let provider_manager = ProviderManager::new().await?;
            let providers = provider_manager.list_providers().await?;

            println!("Available AI Providers:");
            for provider in providers {
                println!("  • {} ({})", provider.name, provider.status);
            }
        },
        ZekeCommands::Config { command } => {
            handle_config_command(command).await?;
        },
    }
    Ok(())
}

async fn handle_config_command(cmd: ConfigCommands) -> anyhow::Result<()> {
    match cmd {
        ConfigCommands::SetProvider { provider } => {
            let mut config = ZekeConfig::load().await?;
            config.default_provider = provider.clone();
            config.save().await?;
            println!("✅ Default provider set to: {}", provider);
        },
        ConfigCommands::SetKey { provider, key } => {
            let mut config = ZekeConfig::load().await?;
            config.set_api_key(&provider, &key);
            config.save().await?;
            println!("✅ API key set for provider: {}", provider);
        },
        ConfigCommands::Show => {
            let config = ZekeConfig::load().await?;
            println!("🔧 Zeke Configuration:");
            println!("  Default Provider: {}", config.default_provider);
            println!("  Configured Providers: {:?}", config.get_configured_providers());
        },
    }
    Ok(())
}

fn detect_language(file_path: &str) -> String {
    match std::path::Path::new(file_path).extension().and_then(|s| s.to_str()) {
        Some("rs") => "rust",
        Some("py") => "python",
        Some("js") => "javascript",
        Some("ts") => "typescript",
        Some("go") => "go",
        Some("java") => "java",
        Some("cpp") | Some("cc") | Some("cxx") => "cpp",
        Some("c") => "c",
        _ => "unknown",
    }.to_string()
}
```

#### Update Main CLI
```rust
// crates/ghostflow-cli/src/main.rs
use clap::{Parser, Subcommand};
use commands::zeke::{ZekeCommands, handle_zeke_command};

#[derive(Parser)]
#[command(name = "ghostflow")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    // Existing commands...

    /// Zeke AI coding assistant
    #[command(subcommand)]
    Zeke(ZekeCommands),
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        // Existing command handlers...
        Commands::Zeke(cmd) => handle_zeke_command(cmd).await?,
    }

    Ok(())
}
```

### 5. Configuration Integration

#### Update GhostFlow Config
```rust
// crates/ghostflow-core/src/config.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GhostFlowConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub zeke: Option<ZekeConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeConfig {
    pub enabled: bool,
    pub default_provider: String,
    pub providers: std::collections::HashMap<String, ProviderConfig>,
    pub features: ZekeFeatures,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub enabled: bool,
    pub api_key: Option<String>,
    pub model: Option<String>,
    pub timeout_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeFeatures {
    pub git_integration: bool,
    pub code_generation: bool,
    pub explanation: bool,
    pub agents: bool,
}

impl Default for ZekeConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            default_provider: "claude".to_string(),
            providers: std::collections::HashMap::new(),
            features: ZekeFeatures {
                git_integration: true,
                code_generation: true,
                explanation: true,
                agents: false,
            },
        }
    }
}
```

### 6. Node Registry Updates

#### Update Node Registration
```rust
// crates/ghostflow-nodes/src/lib.rs
mod zeke_coding;
mod zeke_git;

pub use zeke_coding::{ZekeAskNode, ZekeExplainNode, ZekeGenerateNode};
pub use zeke_git::ZekeGitAnalysisNode;

pub fn register_all_nodes() -> Vec<Box<dyn Node>> {
    vec![
        // Existing nodes...

        // Zeke AI coding nodes
        Box::new(ZekeAskNode::default()),
        Box::new(ZekeExplainNode::default()),
        Box::new(ZekeGenerateNode::default()),
        Box::new(ZekeGitAnalysisNode::default()),
    ]
}
```

### 7. Web UI Integration

#### Add Zeke Status Component
```rust
// crates/ghostflow-ui/src/components/zeke_status.rs
use leptos::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ZekeStatus {
    enabled: bool,
    default_provider: String,
    available_providers: Vec<String>,
    features_enabled: Vec<String>,
}

#[component]
pub fn ZekeStatus() -> impl IntoView {
    let (status, set_status) = create_signal(None::<ZekeStatus>);

    create_effect(move |_| {
        spawn_local(async move {
            if let Ok(zeke_status) = fetch_zeke_status().await {
                set_status(Some(zeke_status));
            }
        });
    });

    view! {
        <div class="zeke-status-card">
            <h3>"Zeke AI Assistant"</h3>
            {move || match status() {
                Some(status) => view! {
                    <div class="status-content">
                        <div class="status-indicator" class:enabled=status.enabled>
                            {if status.enabled { "🤖 Active" } else { "⏸️ Disabled" }}
                        </div>
                        <div class="provider-info">
                            <span class="label">"Default Provider:"</span>
                            <span class="value">{&status.default_provider}</span>
                        </div>
                        <div class="providers-list">
                            <span class="label">"Available:"</span>
                            <div class="provider-badges">
                                {status.available_providers.iter().map(|provider| {
                                    view! { <span class="provider-badge">{provider}</span> }
                                }).collect::<Vec<_>>()}
                            </div>
                        </div>
                        <div class="features-list">
                            <span class="label">"Features:"</span>
                            <div class="feature-badges">
                                {status.features_enabled.iter().map(|feature| {
                                    view! { <span class="feature-badge">{feature}</span> }
                                }).collect::<Vec<_>>()}
                            </div>
                        </div>
                    </div>
                }.into_view(),
                None => view! {
                    <div class="loading">"Loading Zeke status..."</div>
                }.into_view(),
            }}
        </div>
    }
}

async fn fetch_zeke_status() -> Result<ZekeStatus, reqwest::Error> {
    let response = reqwest::get("http://localhost:3000/api/zeke/status").await?;
    response.json().await
}
```

### 8. Docker Integration

#### Update docker-compose.yml
```yaml
services:
  ghostflow:
    build: .
    ports:
      - "8080:8080"
      - "3000:3000"
    environment:
      - ZEKE_ENABLED=true
      - ZEKE_DEFAULT_PROVIDER=claude
      - CLAUDE_API_KEY=${CLAUDE_API_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    volumes:
      - ./workspace:/workspace
      - ~/.config/zeke:/app/.config/zeke
    depends_on:
      - postgres
```

## Required Zeke Changes

### 1. Structure for Crate Publishing
```toml
# zeke/Cargo.toml
[package]
name = "zeke"
version = "0.3.0"
edition = "2024"
description = "AI-powered coding companion"
license = "MIT"
repository = "https://github.com/ghostkellz/zeke"

# Make sure to expose library interface
[lib]
name = "zeke"
path = "src/lib.rs"

[[bin]]
name = "zeke"
path = "src/main.rs"
```

### 2. Expose Public APIs
```rust
// zeke/src/lib.rs
pub mod providers;
pub mod cli;
pub mod git;
pub mod config;
pub mod auth;

// Re-export main types for external use
pub use providers::ProviderManager;
pub use config::ZekeConfig;
pub use cli::commands;

// Public API for GhostFlow integration
pub struct ZekeApi {
    provider_manager: ProviderManager,
}

impl ZekeApi {
    pub async fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let provider_manager = ProviderManager::new().await?;
        Ok(Self { provider_manager })
    }

    pub async fn ask(&self, provider: &str, question: &str, model: Option<&str>) -> Result<Response, Box<dyn std::error::Error>> {
        self.provider_manager.ask(provider, question, model).await
    }

    pub async fn list_providers(&self) -> Result<Vec<ProviderInfo>, Box<dyn std::error::Error>> {
        self.provider_manager.list_providers().await
    }
}

#[derive(Debug, Clone)]
pub struct Response {
    pub content: String,
    pub provider: String,
    pub model: String,
    pub usage: Option<Usage>,
}

#[derive(Debug, Clone)]
pub struct Usage {
    pub total_tokens: u32,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
}

#[derive(Debug, Clone)]
pub struct ProviderInfo {
    pub name: String,
    pub status: String,
    pub models: Vec<String>,
}
```

## Integration Timeline

### Week 1: Dependencies and Basic Integration
- [ ] Add Zeke as git dependency in GhostFlow
- [ ] Create basic Zeke nodes (Ask, Explain, Generate)
- [ ] Test compilation and basic functionality
- [ ] Update CI/CD to handle git dependencies

### Week 2: Advanced Nodes and Git Integration
- [ ] Complete Git analysis nodes
- [ ] Add error handling and validation
- [ ] Write unit tests for all nodes
- [ ] Integration testing with Zeke providers

### Week 3: CLI and Configuration
- [ ] Add Zeke CLI commands to GhostFlow
- [ ] Implement configuration management
- [ ] Add provider authentication
- [ ] Docker integration and testing

### Week 4: UI and Production Ready
- [ ] Web UI components for Zeke status
- [ ] Workflow templates for coding tasks
- [ ] Performance optimization
- [ ] Documentation and examples

## Success Criteria
1. ✅ Zeke accessible as crate dependency
2. ✅ Functional nodes for AI coding assistance
3. ✅ Git integration for automated analysis
4. ✅ CLI commands for direct Zeke interaction
5. ✅ Web UI showing Zeke status and capabilities
6. ✅ Docker deployment with Zeke integration
7. ✅ Comprehensive testing and documentation