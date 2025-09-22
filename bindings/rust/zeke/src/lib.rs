//! # Zeke - AI Development Companion for Rust
//!
//! Zeke is a powerful AI development companion that provides seamless integration
//! with multiple AI providers including OpenAI, Claude, GitHub Copilot, Ollama, and GhostLLM.
//!
//! This crate provides safe, high-level Rust bindings for the Zeke Zig library,
//! offering memory-safe access to AI capabilities with automatic resource management.
//!
//! ## Features
//!
//! - **Multi-Provider Support**: OpenAI, Claude, GitHub Copilot, Ollama, GhostLLM
//! - **GPU Acceleration**: GhostLLM integration with CUDA/Metal support
//! - **Streaming Responses**: Real-time token streaming for interactive applications
//! - **Automatic Failover**: Health monitoring and provider switching
//! - **Memory Safety**: RAII-based resource management
//! - **Async Support**: Tokio integration for non-blocking operations
//!
//! ## Quick Start
//!
//! ```rust
//! use zeke::{Zeke, Config, Provider};
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     // Initialize Zeke with OpenAI
//!     let zeke = Zeke::builder()
//!         .provider(Provider::OpenAI)
//!         .api_key("your-api-key-here")
//!         .model("gpt-4")
//!         .temperature(0.7)
//!         .build()?;
//!
//!     // Send a chat message
//!     let response = zeke.chat("Hello, AI!").await?;
//!     println!("Response: {}", response.content);
//!
//!     Ok(())
//! }
//! ```
//!
//! ## Streaming Example
//!
//! ```rust
//! use zeke::{Zeke, Provider};
//! use futures::StreamExt;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let zeke = Zeke::builder()
//!         .provider(Provider::OpenAI)
//!         .api_key("your-api-key")
//!         .build()?;
//!
//!     let mut stream = zeke.chat_stream("Tell me a story").await?;
//!     while let Some(chunk) = stream.next().await {
//!         match chunk {
//!             Ok(chunk) => print!("{}", chunk.content),
//!             Err(e) => eprintln!("Stream error: {}", e),
//!         }
//!     }
//!
//!     Ok(())
//! }
//! ```

#![cfg_attr(docsrs, feature(doc_cfg))]
#![deny(missing_docs)]
#![warn(clippy::all)]

// Re-export commonly used types
pub use config::{Config, ConfigBuilder};
pub use error::{Error, Result};
pub use provider::Provider;
pub use response::{ChatResponse, StreamChunk};
pub use zeke::Zeke;

#[cfg(feature = "ghostllm")]
#[cfg_attr(docsrs, doc(cfg(feature = "ghostllm")))]
pub use ghostllm::GhostLLM;

// Internal modules
mod config;
mod error;
mod provider;
mod response;
mod zeke;

#[cfg(feature = "ghostllm")]
mod ghostllm;

#[cfg(feature = "async")]
mod stream;

// Utility modules
mod ffi_utils;

/// Prelude module for convenient imports
pub mod prelude {
    pub use crate::{Config, ConfigBuilder, Error, Provider, Result, Zeke};

    #[cfg(feature = "ghostllm")]
    pub use crate::GhostLLM;
}

// Version information
/// The version of this crate
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The version of the underlying Zeke library
pub const ZEKE_VERSION: &str = "0.2.0";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_constants() {
        assert!(!VERSION.is_empty());
        assert!(!ZEKE_VERSION.is_empty());
    }
}