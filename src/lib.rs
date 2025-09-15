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