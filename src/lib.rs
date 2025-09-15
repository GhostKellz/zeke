//! # ZEKE - The Rust-Native AI Dev Companion
//!
//! ZEKE is a high-performance AI development companion that provides seamless integration
//! with multiple AI providers including OpenAI, Claude, GitHub Copilot, Ollama, and GhostLLM.
//!
//! ## Features
//!
//! - **Multi-Provider Support**: Switch between AI providers on the fly
//! - **Async-First**: Built on Tokio for high-performance async operations
//! - **Neovim Integration**: Native RPC support for Neovim plugins
//! - **Streaming Responses**: Real-time token streaming for interactive applications
//! - **Configuration Management**: Flexible configuration system
//! - **Error Handling**: Comprehensive error types and handling
//!
//! ## Usage
//!
//! ```rust
//! use zeke::{providers::ProviderManager, config::ZekeConfig};
//!
//! #[tokio::main]
//! async fn main() -> zeke::error::ZekeResult<()> {
//!     let config = ZekeConfig::default();
//!     let manager = ProviderManager::new();
//!
//!     // Use the AI providers
//!     Ok(())
//! }
//! ```

pub mod providers;
pub mod streaming;
pub mod config;
pub mod error;
pub mod api;
pub mod tools;
pub mod auth;
pub mod mcp;

// Optional modules
#[cfg(feature = "agents")]
pub mod agents;

#[cfg(feature = "git")]
pub mod git;

// Re-export commonly used types
pub use error::{ZekeError, ZekeResult};
pub use config::ZekeConfig;
pub use providers::{Provider, ProviderManager, ChatRequest, ChatResponse};
pub use api::{ApiServer, start_api_server};
pub use tools::{ToolRegistry, ToolInput, ToolOutput};
pub use auth::{AuthToken, AuthProvider};
pub use mcp::{McpManager, McpServer, McpTool, McpResource};

// Integration types are defined in this module

// Re-export git operations when feature is enabled
#[cfg(feature = "git")]
pub use git::{GitManager, GitStatus, CommitInfo};

/// The current version of ZEKE
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Initialize ZEKE with default configuration
pub async fn init() -> ZekeResult<ProviderManager> {
    let manager = ProviderManager::new();
    Ok(manager)
}

/// Initialize ZEKE with custom configuration
pub async fn init_with_config(_config: ZekeConfig) -> ZekeResult<ProviderManager> {
    let manager = ProviderManager::new();
    Ok(manager)
}

/// High-level API for GhostFlow integration
pub struct ZekeApi {
    provider_manager: ProviderManager,
}

impl ZekeApi {
    /// Create a new ZekeApi instance
    pub async fn new() -> ZekeResult<Self> {
        let mut provider_manager = ProviderManager::new();
        provider_manager.initialize_default_providers().await?;
        Ok(Self { provider_manager })
    }

    /// Ask a question to the specified AI provider
    pub async fn ask(&self, provider: &str, question: &str, model: Option<&str>) -> ZekeResult<Response> {
        let api_response = self.provider_manager.ask(provider, question, model).await?;
        Ok(Response {
            content: api_response.content,
            provider: api_response.provider,
            model: api_response.model,
            usage: api_response.usage.map(|u| Usage {
                total_tokens: u.total_tokens,
                prompt_tokens: u.prompt_tokens,
                completion_tokens: u.completion_tokens,
            }),
        })
    }

    /// List available AI providers
    pub async fn list_providers(&self) -> ZekeResult<Vec<ProviderInfo>> {
        let api_providers = self.provider_manager.list_provider_info().await?;
        Ok(api_providers.into_iter().map(|p| ProviderInfo {
            name: p.name,
            status: p.status,
            models: p.models,
        }).collect())
    }

    /// Get the status of all providers
    pub async fn get_provider_status(&self) -> Vec<(Provider, providers::ProviderHealth)> {
        self.provider_manager.get_provider_status().await
    }

    /// Set the current default provider
    pub async fn set_current_provider(&self, provider: &str) -> ZekeResult<()> {
        let provider_enum = provider.parse::<Provider>()?;
        self.provider_manager.set_current_provider(provider_enum).await;
        Ok(())
    }

    /// Get git operations manager (when git feature is enabled)
    #[cfg(feature = "git")]
    pub fn git(&self) -> ZekeResult<git::GitManager> {
        git::GitManager::new()
    }

    /// Get git operations manager for specific path (when git feature is enabled)
    #[cfg(feature = "git")]
    pub fn git_with_path(&self, path: std::path::PathBuf) -> git::GitManager {
        git::GitManager::with_path(path)
    }
}

/// Response from AI provider
#[derive(Debug, Clone)]
pub struct Response {
    pub content: String,
    pub provider: String,
    pub model: String,
    pub usage: Option<Usage>,
}

/// Token usage information
#[derive(Debug, Clone)]
pub struct Usage {
    pub total_tokens: u32,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
}

/// Provider information
#[derive(Debug, Clone)]
pub struct ProviderInfo {
    pub name: String,
    pub status: String,
    pub models: Vec<String>,
}