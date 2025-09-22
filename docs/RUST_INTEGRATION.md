# Zeke Rust Integration Guide

[![Rust](https://img.shields.io/badge/rust-1.70+-blue.svg)](https://www.rust-lang.org/)
[![Zig](https://img.shields.io/badge/zig-0.11+-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-green.svg)](LICENSE)
[![Documentation](https://docs.rs/zeke/badge.svg)](https://docs.rs/zeke)

This guide covers integrating Zeke's AI development companion capabilities into Rust projects like **GhostFlow** and **Jarvis**. Zeke provides safe, high-level Rust bindings for multi-provider AI interactions with GPU acceleration support.

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Architecture Overview](#-architecture-overview)
- [Basic Usage](#-basic-usage)
- [Advanced Features](#-advanced-features)
- [GhostFlow Integration](#-ghostflow-integration)
- [Jarvis Integration](#-jarvis-integration)
- [Performance Optimization](#-performance-optimization)
- [Error Handling](#-error-handling)
- [Security Considerations](#-security-considerations)
- [Troubleshooting](#-troubleshooting)
- [API Reference](#-api-reference)

## 🚀 Quick Start

### Prerequisites

- **Rust 1.70+** with Cargo
- **Zig 0.11+** compiler (for FFI compilation)
- **Clang/LLVM** (for bindgen support)

### 30-Second Example

```toml
[dependencies]
zeke = { path = "path/to/zeke/bindings/rust/zeke" }
tokio = { version = "1.0", features = ["full"] }
```

```rust
use zeke::{Zeke, Provider};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize with OpenAI
    let zeke = Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()  // Reads OPENAI_API_KEY
        .model("gpt-4o")
        .temperature(0.7)
        .build()?;

    // Send a message
    let response = zeke.chat("Explain async/await in Rust").await?;
    println!("🤖 {}", response.content);
    
    Ok(())
}
```

## 📦 Installation

### Option 1: Direct Path Dependency (Development)

```toml
[dependencies]
zeke = { path = "../zeke/bindings/rust/zeke", features = ["async", "ghostllm"] }
```

### Option 2: Git Dependency

```toml
[dependencies]
zeke = { git = "https://github.com/ghostkellz/zeke", features = ["async", "ghostllm"] }
```

### Option 3: Build from Source

```bash
# Clone and build
git clone https://github.com/ghostkellz/zeke
cd zeke
chmod +x scripts/build-rust-bindings.sh
./scripts/build-rust-bindings.sh --release --features ghostllm,async

# Use in your project
# Add to Cargo.toml: zeke = { path = "path/to/zeke/bindings/rust/zeke" }
```

### Available Features

- `async` (default): Tokio-based async support with streaming
- `ghostllm` (default): GPU acceleration via GhostLLM
- `streaming`: Advanced streaming utilities
- `serde_support`: Enhanced serialization support

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Rust Application                   │
│                   (GhostFlow, Jarvis, etc.)                │
├─────────────────────────────────────────────────────────────┤
│                    Zeke High-Level API                     │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────────┐   │
│  │   Config    │ │    Zeke      │ │   GhostLLM         │   │
│  │   Builder   │ │   Client     │ │   GPU Accel        │   │
│  └─────────────┘ └──────────────┘ └────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Zeke-sys (FFI Layer)                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              C ABI Interface                        │   │
│  │  • Memory-safe wrappers                            │   │
│  │  • Automatic resource cleanup                       │   │
│  │  • Error code translation                          │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                   Zig Core Library                         │
│  ┌──────────────┐ ┌──────────────────┐ ┌──────────────┐   │
│  │ Multi-Provider│ │  GhostLLM       │ │   Streaming  │   │
│  │ Management    │ │  Integration    │ │   Support    │   │
│  └──────────────┘ └──────────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Provider Support Matrix

| Provider | Chat | Streaming | GPU | Auth Method | Status |
|----------|------|-----------|-----|-------------|--------|
| OpenAI | ✅ | ✅ | ❌ | API Key | Production |
| Claude | ✅ | ✅ | ❌ | API Key | Production |
| GhostLLM | ✅ | ✅ | ✅ | Optional | Production |
| GitHub Copilot | ✅ | ❌ | ❌ | OAuth | Beta |
| Ollama | ✅ | ✅ | ✅ | None | Production |

## 📚 Basic Usage

### Configuration Management

```rust
use zeke::{Config, Provider, Zeke};

// Method 1: Builder Pattern
let zeke = Zeke::builder()
    .provider(Provider::Claude)
    .api_key("your-claude-api-key")
    .model("claude-3-5-sonnet-20241022")
    .temperature(0.8)
    .max_tokens(4096)
    .streaming(true)
    .gpu(false)
    .timeout_secs(30)
    .build()?;

// Method 2: From Configuration File
let config = Config::from_file("zeke-config.toml")?;
let zeke = Zeke::new(config)?;

// Method 3: Environment-based
let zeke = Zeke::builder()
    .provider(Provider::OpenAI)
    .api_key_from_env()  // Reads OPENAI_API_KEY
    .model("gpt-4o")
    .build()?;
```

### Configuration File Format (TOML)

```toml
# zeke-config.toml
provider = "openai"
model = "gpt-4o"
temperature = 0.7
max_tokens = 2048
streaming = true
enable_gpu = false
enable_fallback = true
timeout_ms = 30000

[provider_settings]
"openai.organization" = "your-org-id"
"claude.version" = "2023-06-01"
```

### Simple Chat Interactions

```rust
use zeke::{Zeke, Provider, Error};

#[tokio::main]
async fn main() -> Result<(), Error> {
    let zeke = Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()
        .build()?;

    // Simple question
    let response = zeke.chat("What is the capital of France?").await?;
    println!("Answer: {}", response.content);
    println!("Tokens used: {:?}", response.tokens_used);
    println!("Response time: {:?}", response.response_time);

    // Code explanation
    let code_response = zeke.chat(
        "Explain this Rust code: `async fn fetch_data() -> Result<String, reqwest::Error>`"
    ).await?;
    println!("Explanation: {}", code_response.content);

    Ok(())
}
```

### Streaming Responses

```rust
use zeke::Zeke;
use futures::StreamExt;

async fn streaming_example() -> Result<(), Box<dyn std::error::Error>> {
    let zeke = Zeke::builder()
        .provider(Provider::Claude)
        .api_key_from_env()
        .streaming(true)
        .build()?;

    let mut stream = zeke.chat_stream("Write a short story about a robot").await?;
    
    print!("🤖 ");
    while let Some(chunk) = stream.next().await {
        match chunk {
            Ok(chunk) => {
                print!("{}", chunk.content);
                if chunk.is_final {
                    println!("\n✨ Story complete!");
                }
            }
            Err(e) => eprintln!("Stream error: {}", e),
        }
    }

    Ok(())
}
```

### Error Handling

```rust
use zeke::{Zeke, Error, Provider};

async fn robust_chat_example() -> Result<(), Box<dyn std::error::Error>> {
    let zeke = Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()
        .enable_fallback(true)  // Auto-fallback to other providers
        .build()?;

    match zeke.chat("Hello, AI!").await {
        Ok(response) => {
            println!("✅ Success: {}", response.content);
            println!("Provider used: {}", response.provider);
        }
        Err(Error::AuthenticationFailed { provider, message }) => {
            eprintln!("🔐 Auth failed for {}: {}", provider, message);
            // Handle re-authentication
        }
        Err(Error::NetworkError { message }) => {
            eprintln!("🌐 Network issue: {}", message);
            // Implement retry logic
        }
        Err(Error::RateLimitExceeded { retry_after, .. }) => {
            eprintln!("⏱️ Rate limited. Retry after: {:?}", retry_after);
            // Implement backoff
        }
        Err(e) => {
            eprintln!("❌ Other error: {}", e);
            return Err(e.into());
        }
    }

    Ok(())
}
```

## 🚀 Advanced Features

### Provider Management

```rust
use zeke::{Zeke, Provider};

async fn provider_management_example() -> Result<(), Box<dyn std::error::Error>> {
    let mut zeke = Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()
        .build()?;

    // Check current provider status
    let status = zeke.provider_status().await?;
    for provider_status in status {
        println!(
            "{}: {} ({}ms, {:.1}% errors)", 
            provider_status.provider,
            if provider_status.is_healthy { "✅" } else { "❌" },
            provider_status.response_time_ms,
            provider_status.error_rate * 100.0
        );
    }

    // Switch providers dynamically
    if !status.iter().any(|s| s.provider == Provider::OpenAI && s.is_healthy) {
        println!("OpenAI unhealthy, switching to Claude...");
        zeke.switch_provider(Provider::Claude).await?;
        zeke.set_auth_token("claude-api-key").await?;
    }

    // Test authentication
    match zeke.test_auth().await? {
        true => println!("🔐 Authentication successful"),
        false => println!("🔒 Authentication failed"),
    }

    Ok(())
}
```

### GhostLLM GPU Integration

```rust
use zeke::{Zeke, Provider};

#[cfg(feature = "ghostllm")]
async fn gpu_acceleration_example() -> Result<(), Box<dyn std::error::Error>> {
    let zeke = Zeke::builder()
        .provider(Provider::GhostLLM)
        .base_url("http://localhost:8080")
        .gpu(true)
        .build()?;

    // Initialize GPU acceleration
    let mut ghostllm = zeke.ghostllm();
    ghostllm.initialize().await?;

    // Get GPU information
    let gpu_info = ghostllm.gpu_info().await?;
    println!("🎮 GPU: {}", gpu_info.device_name);
    println!("📊 Memory: {:.1}% ({} MB / {} MB)", 
        gpu_info.memory_utilization_percent(),
        gpu_info.memory_used_mb,
        gpu_info.memory_total_mb
    );
    println!("🌡️ Temperature: {}°C", gpu_info.temperature_celsius);
    println!("⚡ Utilization: {}%", gpu_info.utilization_percent);

    // Health check
    if gpu_info.is_overheating() {
        println!("⚠️ GPU overheating! Consider reducing load.");
    }

    if gpu_info.is_high_load() {
        println!("⚠️ GPU under high load. Waiting for availability...");
        ghostllm.wait_for_availability(std::time::Duration::from_secs(30)).await?;
    }

    // Run benchmark
    let optimal_batch = ghostllm.optimal_batch_size().await?;
    println!("🎯 Optimal batch size: {}", optimal_batch);

    let benchmark = ghostllm.benchmark("llama2-7b", optimal_batch).await?;
    println!("🏃 Benchmark: {:.1} tokens/sec, {:.1}ms latency", 
        benchmark.tokens_per_second, 
        benchmark.latency_ms
    );

    // Use for generation
    let response = zeke.chat("Explain GPU computing").await?;
    println!("🤖 {}", response.content);

    Ok(())
}
```

### Concurrent Processing

```rust
use zeke::Zeke;
use tokio::task;

async fn concurrent_processing_example() -> Result<(), Box<dyn std::error::Error>> {
    let zeke = std::sync::Arc::new(
        Zeke::builder()
            .provider(Provider::OpenAI)
            .api_key_from_env()
            .build()?
    );

    let questions = vec![
        "What is machine learning?",
        "Explain blockchain technology",
        "How does quantum computing work?",
        "What is the future of AI?",
    ];

    // Process questions concurrently
    let tasks: Vec<_> = questions.into_iter().map(|question| {
        let zeke = Arc::clone(&zeke);
        let question = question.to_string();
        task::spawn(async move {
            let result = zeke.chat(&question).await;
            (question, result)
        })
    }).collect();

    // Collect results
    for task in tasks {
        match task.await? {
            (question, Ok(response)) => {
                println!("❓ {}", question);
                println!("🤖 {}\n", response.content);
            }
            (question, Err(e)) => {
                println!("❌ Error for '{}': {}", question, e);
            }
        }
    }

    Ok(())
}
```

## 🌊 GhostFlow Integration

[GhostFlow](https://github.com/ghostkellz/ghostflow) is a modern, fully free and open-source alternative to n8n. Here's how to integrate Zeke for AI-powered workflow automation:

### GhostFlow Node Implementation

```rust
// ghostflow/src/nodes/ai/zeke_node.rs
use serde::{Deserialize, Serialize};
use zeke::{Zeke, Provider, Config};
use ghostflow_core::{Node, NodeResult, ExecutionContext};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZekeNodeConfig {
    pub provider: String,
    pub model: String,
    pub temperature: f32,
    pub max_tokens: u32,
    pub system_prompt: Option<String>,
    pub stream_output: bool,
}

pub struct ZekeNode {
    config: ZekeNodeConfig,
    zeke: Option<Zeke>,
}

impl ZekeNode {
    pub fn new(config: ZekeNodeConfig) -> Self {
        Self { config, zeke: None }
    }

    async fn ensure_initialized(&mut self) -> Result<&Zeke, Box<dyn std::error::Error>> {
        if self.zeke.is_none() {
            let provider = match self.config.provider.as_str() {
                "openai" => Provider::OpenAI,
                "claude" => Provider::Claude,
                "ghostllm" => Provider::GhostLLM,
                "ollama" => Provider::Ollama,
                _ => return Err("Unsupported provider".into()),
            };

            let zeke = Zeke::builder()
                .provider(provider)
                .api_key_from_env()
                .model(&self.config.model)
                .temperature(self.config.temperature)
                .max_tokens(self.config.max_tokens)
                .streaming(self.config.stream_output)
                .build()?;

            self.zeke = Some(zeke);
        }

        Ok(self.zeke.as_ref().unwrap())
    }
}

#[async_trait::async_trait]
impl Node for ZekeNode {
    async fn execute(&mut self, context: &mut ExecutionContext) -> NodeResult {
        let zeke = self.ensure_initialized().await
            .map_err(|e| format!("Failed to initialize Zeke: {}", e))?;

        // Get input message from previous node
        let input_message = context.get_input("message")
            .ok_or("No input message provided")?
            .as_str()
            .ok_or("Input message must be a string")?;

        // Prepare the prompt
        let prompt = match &self.config.system_prompt {
            Some(system) => format!("{}\n\nUser: {}", system, input_message),
            None => input_message.to_string(),
        };

        if self.config.stream_output {
            // Streaming response for real-time workflows
            use futures::StreamExt;
            let mut stream = zeke.chat_stream(&prompt).await
                .map_err(|e| format!("Streaming failed: {}", e))?;

            let mut full_response = String::new();
            while let Some(chunk) = stream.next().await {
                match chunk {
                    Ok(chunk) => {
                        full_response.push_str(&chunk.content);
                        
                        // Emit partial result for real-time updates
                        context.emit_partial_result("ai_response", &chunk.content);
                        
                        if chunk.is_final {
                            break;
                        }
                    }
                    Err(e) => return Err(format!("Stream error: {}", e)),
                }
            }

            context.set_output("response", full_response);
            context.set_output("provider", zeke.current_provider().to_string());
        } else {
            // Standard response
            let response = zeke.chat(&prompt).await
                .map_err(|e| format!("Chat failed: {}", e))?;

            context.set_output("response", response.content);
            context.set_output("provider", response.provider.to_string());
            context.set_output("tokens_used", response.tokens_used.unwrap_or(0));
            context.set_output("response_time_ms", response.response_time.as_millis() as u64);
        }

        Ok(())
    }

    fn node_type(&self) -> &str {
        "ai.zeke"
    }

    fn display_name(&self) -> &str {
        "Zeke AI"
    }
}
```

### GhostFlow Workflow Example

```yaml
# ghostflow-workflows/ai-content-generation.yaml
name: "AI Content Generation Pipeline"
description: "Generate, review, and publish content using AI"

nodes:
  - id: trigger
    type: webhook
    config:
      path: /generate-content
      method: POST

  - id: content-generator
    type: ai.zeke
    config:
      provider: openai
      model: gpt-4o
      temperature: 0.8
      system_prompt: |
        You are a professional content writer. Create engaging, 
        SEO-optimized content based on the given topic and requirements.

  - id: content-reviewer
    type: ai.zeke
    config:
      provider: claude
      model: claude-3-5-sonnet-20241022
      temperature: 0.3
      system_prompt: |
        Review the following content for accuracy, tone, and quality. 
        Provide constructive feedback and suggest improvements.

  - id: content-optimizer
    type: ai.zeke
    config:
      provider: ghostllm
      model: llama2-7b
      temperature: 0.5
      stream_output: true
      system_prompt: |
        Optimize the content based on the review feedback. 
        Maintain the original intent while improving clarity and engagement.

  - id: publish
    type: webhook
    config:
      url: "https://cms.example.com/api/publish"
      method: POST

connections:
  - from: trigger
    to: content-generator
    data: { message: "$.body.topic" }
    
  - from: content-generator
    to: content-reviewer
    data: { message: "Review this content: $.response" }
    
  - from: content-reviewer
    to: content-optimizer
    data: { 
      message: "Original: $.content-generator.response\n\nFeedback: $.response"
    }
    
  - from: content-optimizer
    to: publish
    data: { 
      title: "$.trigger.body.title",
      content: "$.response",
      metadata: {
        generated_by: "zeke-ai",
        tokens_total: "$.*.tokens_used | add"
      }
    }
```

### GhostFlow Plugin Registration

```rust
// ghostflow/src/plugins/zeke_plugin.rs
use ghostflow_core::{Plugin, PluginMetadata, NodeFactory};

pub struct ZekePlugin;

impl Plugin for ZekePlugin {
    fn metadata(&self) -> PluginMetadata {
        PluginMetadata {
            name: "zeke-ai".to_string(),
            version: "0.2.0".to_string(),
            description: "Zeke AI integration for multi-provider LLM workflows".to_string(),
            author: "Zeke Team".to_string(),
            homepage: "https://github.com/ghostkellz/zeke".to_string(),
        }
    }

    fn register_nodes(&self, factory: &mut NodeFactory) {
        factory.register("ai.zeke", |config| {
            Box::new(ZekeNode::new(config))
        });
    }
}

// Register the plugin
#[no_mangle]
pub extern "C" fn plugin_init() -> Box<dyn Plugin> {
    Box::new(ZekePlugin)
}
```

## 🤖 Jarvis Integration

[Jarvis](https://github.com/ghostkellz/jarvis) is an AI platform for intelligent automation. Here's how to integrate Zeke:

### Jarvis Service Implementation

```rust
// jarvis/src/services/ai_service.rs
use std::sync::Arc;
use tokio::sync::RwLock;
use zeke::{Zeke, Provider, Config};
use tracing::{info, warn, error};

pub struct AIService {
    providers: Arc<RwLock<Vec<Zeke>>>,
    current_provider_index: Arc<RwLock<usize>>,
    config: AIServiceConfig,
}

#[derive(Clone)]
pub struct AIServiceConfig {
    pub providers: Vec<ProviderConfig>,
    pub fallback_enabled: bool,
    pub health_check_interval: std::time::Duration,
    pub max_retries: u32,
}

#[derive(Clone)]
pub struct ProviderConfig {
    pub provider: Provider,
    pub api_key: String,
    pub model: String,
    pub priority: u8, // Lower numbers = higher priority
}

impl AIService {
    pub async fn new(config: AIServiceConfig) -> Result<Self, Box<dyn std::error::Error>> {
        let mut providers = Vec::new();

        // Initialize all configured providers
        for provider_config in &config.providers {
            let zeke = Zeke::builder()
                .provider(provider_config.provider)
                .api_key(&provider_config.api_key)
                .model(&provider_config.model)
                .enable_fallback(config.fallback_enabled)
                .streaming(true)
                .build()?;

            // Test the provider
            match zeke.test_auth().await {
                Ok(true) => {
                    info!("✅ Provider {} authenticated successfully", provider_config.provider);
                    providers.push(zeke);
                }
                Ok(false) => {
                    warn!("❌ Provider {} authentication failed", provider_config.provider);
                }
                Err(e) => {
                    error!("❌ Provider {} error: {}", provider_config.provider, e);
                }
            }
        }

        if providers.is_empty() {
            return Err("No providers available".into());
        }

        // Sort by priority (lower number = higher priority)
        let mut provider_configs = config.providers.clone();
        provider_configs.sort_by_key(|p| p.priority);

        let service = Self {
            providers: Arc::new(RwLock::new(providers)),
            current_provider_index: Arc::new(RwLock::new(0)),
            config,
        };

        // Start health monitoring
        service.start_health_monitoring().await;

        Ok(service)
    }

    pub async fn chat(&self, message: &str) -> Result<String, Box<dyn std::error::Error>> {
        let max_retries = self.config.max_retries;
        let mut attempts = 0;

        while attempts < max_retries {
            let provider_index = {
                let index = self.current_provider_index.read().await;
                *index
            };

            let providers = self.providers.read().await;
            if let Some(zeke) = providers.get(provider_index) {
                match zeke.chat(message).await {
                    Ok(response) => {
                        info!("✅ Chat successful with provider {}", zeke.current_provider());
                        return Ok(response.content);
                    }
                    Err(e) => {
                        warn!("❌ Provider {} failed: {}", zeke.current_provider(), e);
                        
                        if self.config.fallback_enabled && attempts < max_retries - 1 {
                            self.switch_to_next_provider().await;
                        }
                    }
                }
            }

            attempts += 1;
        }

        Err("All providers failed".into())
    }

    pub async fn chat_stream<F>(&self, message: &str, callback: F) -> Result<(), Box<dyn std::error::Error>>
    where
        F: Fn(&str) + Send + Sync + 'static,
    {
        let providers = self.providers.read().await;
        let provider_index = *self.current_provider_index.read().await;
        
        if let Some(zeke) = providers.get(provider_index) {
            use futures::StreamExt;
            let mut stream = zeke.chat_stream(message).await?;
            
            while let Some(chunk) = stream.next().await {
                match chunk {
                    Ok(chunk) => {
                        callback(&chunk.content);
                        if chunk.is_final {
                            break;
                        }
                    }
                    Err(e) => {
                        error!("Stream error: {}", e);
                        return Err(e.into());
                    }
                }
            }
        }

        Ok(())
    }

    async fn switch_to_next_provider(&self) {
        let providers = self.providers.read().await;
        let mut index = self.current_provider_index.write().await;
        *index = (*index + 1) % providers.len();
        
        if let Some(zeke) = providers.get(*index) {
            info!("🔄 Switched to provider: {}", zeke.current_provider());
        }
    }

    async fn start_health_monitoring(&self) {
        let providers = Arc::clone(&self.providers);
        let interval = self.config.health_check_interval;

        tokio::spawn(async move {
            let mut health_check_interval = tokio::time::interval(interval);
            
            loop {
                health_check_interval.tick().await;
                
                let providers_guard = providers.read().await;
                for (i, zeke) in providers_guard.iter().enumerate() {
                    match zeke.health_check().await {
                        Ok(_) => {
                            info!("💚 Provider {} health check passed", zeke.current_provider());
                        }
                        Err(e) => {
                            warn!("💔 Provider {} health check failed: {}", zeke.current_provider(), e);
                            // Could implement provider replacement logic here
                        }
                    }
                }
            }
        });
    }

    pub async fn get_provider_status(&self) -> Vec<(Provider, bool, std::time::Duration)> {
        let providers = self.providers.read().await;
        let mut status = Vec::new();

        for zeke in providers.iter() {
            let start = std::time::Instant::now();
            let is_healthy = zeke.health_check().await.is_ok();
            let response_time = start.elapsed();
            
            status.push((zeke.current_provider(), is_healthy, response_time));
        }

        status
    }
}
```

### Jarvis Command Handler

```rust
// jarvis/src/commands/ai_commands.rs
use crate::services::AIService;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "jarvis")]
#[command(about = "Jarvis AI Platform")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Chat with AI
    Chat {
        #[arg(short, long)]
        message: String,
        #[arg(short, long)]
        stream: bool,
    },
    /// Get AI service status
    Status,
    /// Switch AI provider
    Switch {
        #[arg(short, long)]
        provider: String,
    },
    /// Run AI benchmark
    Benchmark {
        #[arg(short, long)]
        iterations: Option<u32>,
    },
}

pub async fn handle_command(
    ai_service: &AIService, 
    command: Commands
) -> Result<(), Box<dyn std::error::Error>> {
    match command {
        Commands::Chat { message, stream } => {
            if stream {
                println!("🤖 ");
                ai_service.chat_stream(&message, |chunk| {
                    print!("{}", chunk);
                }).await?;
                println!();
            } else {
                let response = ai_service.chat(&message).await?;
                println!("🤖 {}", response);
            }
        }

        Commands::Status => {
            let status = ai_service.get_provider_status().await;
            println!("🔍 AI Service Status:");
            for (provider, healthy, response_time) in status {
                let status_icon = if healthy { "✅" } else { "❌" };
                println!("  {} {} - {:?}", status_icon, provider, response_time);
            }
        }

        Commands::Switch { provider } => {
            // Implementation would require extending AIService
            println!("🔄 Switching to provider: {}", provider);
        }

        Commands::Benchmark { iterations } => {
            let iterations = iterations.unwrap_or(10);
            println!("🏃 Running benchmark with {} iterations...", iterations);
            
            let start = std::time::Instant::now();
            for i in 1..=iterations {
                let message = format!("Benchmark message #{}", i);
                match ai_service.chat(&message).await {
                    Ok(response) => {
                        println!("✅ Iteration {}: {} chars", i, response.len());
                    }
                    Err(e) => {
                        println!("❌ Iteration {}: {}", i, e);
                    }
                }
            }
            let duration = start.elapsed();
            
            println!("📊 Benchmark complete: {:?} total, {:?} per request", 
                duration, duration / iterations);
        }
    }

    Ok(())
}
```

### Jarvis Configuration

```rust
// jarvis/src/config.rs
use serde::{Deserialize, Serialize};
use zeke::Provider;

#[derive(Serialize, Deserialize)]
pub struct JarvisConfig {
    pub ai: AIServiceConfig,
    pub server: ServerConfig,
    pub logging: LoggingConfig,
}

#[derive(Serialize, Deserialize)]
pub struct AIServiceConfig {
    pub providers: Vec<ProviderConfig>,
    pub fallback_enabled: bool,
    pub health_check_interval_secs: u64,
    pub max_retries: u32,
}

#[derive(Serialize, Deserialize)]
pub struct ProviderConfig {
    pub provider: String,
    pub api_key_env: String, // Environment variable name
    pub model: String,
    pub priority: u8,
    pub base_url: Option<String>,
    pub enable_gpu: Option<bool>,
}

impl JarvisConfig {
    pub fn load() -> Result<Self, Box<dyn std::error::Error>> {
        let config_path = std::env::var("JARVIS_CONFIG")
            .unwrap_or_else(|_| "jarvis-config.toml".to_string());
        
        let config_str = std::fs::read_to_string(&config_path)?;
        let mut config: Self = toml::from_str(&config_str)?;
        
        // Load API keys from environment
        for provider in &mut config.ai.providers {
            if let Ok(api_key) = std::env::var(&provider.api_key_env) {
                // Store in memory securely (implementation specific)
            }
        }
        
        Ok(config)
    }
}
```

### Jarvis Main Application

```rust
// jarvis/src/main.rs
mod services;
mod commands;
mod config;

use commands::{Cli, handle_command};
use services::AIService;
use config::JarvisConfig;
use clap::Parser;
use tracing::{info, Level};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();

    info!("🚀 Starting Jarvis AI Platform");

    // Load configuration
    let config = JarvisConfig::load()?;
    
    // Initialize AI service
    let ai_service = AIService::new(config.ai).await?;
    
    // Parse command line arguments
    let cli = Cli::parse();
    
    // Handle the command
    handle_command(&ai_service, cli.command).await?;
    
    Ok(())
}
```

## 🎯 Performance Optimization

### Connection Pooling

```rust
use zeke::Zeke;
use std::sync::Arc;
use tokio::sync::Semaphore;

pub struct ZekePool {
    instances: Vec<Arc<Zeke>>,
    semaphore: Arc<Semaphore>,
}

impl ZekePool {
    pub async fn new(size: usize, config: Config) -> Result<Self, Box<dyn std::error::Error>> {
        let mut instances = Vec::with_capacity(size);
        
        for _ in 0..size {
            let zeke = Zeke::new(config.clone())?;
            instances.push(Arc::new(zeke));
        }
        
        Ok(Self {
            instances,
            semaphore: Arc::new(Semaphore::new(size)),
        })
    }
    
    pub async fn chat(&self, message: &str) -> Result<String, Box<dyn std::error::Error>> {
        let _permit = self.semaphore.acquire().await?;
        
        // Round-robin selection (simplified)
        let instance_idx = rand::random::<usize>() % self.instances.len();
        let zeke = &self.instances[instance_idx];
        
        let response = zeke.chat(message).await?;
        Ok(response.content)
    }
}
```

### Caching Strategy

```rust
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use sha2::{Sha256, Digest};

pub struct CachedZeke {
    zeke: Zeke,
    cache: Arc<RwLock<HashMap<String, (String, std::time::Instant)>>>,
    cache_ttl: std::time::Duration,
}

impl CachedZeke {
    pub fn new(zeke: Zeke, cache_ttl: std::time::Duration) -> Self {
        Self {
            zeke,
            cache: Arc::new(RwLock::new(HashMap::new())),
            cache_ttl,
        }
    }
    
    pub async fn chat(&self, message: &str) -> Result<String, Box<dyn std::error::Error>> {
        let key = self.hash_message(message);
        
        // Check cache first
        {
            let cache = self.cache.read().await;
            if let Some((response, timestamp)) = cache.get(&key) {
                if timestamp.elapsed() < self.cache_ttl {
                    return Ok(response.clone());
                }
            }
        }
        
        // Cache miss - call API
        let response = self.zeke.chat(message).await?;
        
        // Update cache
        {
            let mut cache = self.cache.write().await;
            cache.insert(key, (response.content.clone(), std::time::Instant::now()));
        }
        
        Ok(response.content)
    }
    
    fn hash_message(&self, message: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(message.as_bytes());
        hex::encode(hasher.finalize())
    }
}
```

### Batch Processing

```rust
use zeke::Zeke;
use futures::future::try_join_all;

pub async fn batch_process_messages(
    zeke: &Zeke,
    messages: Vec<String>,
    batch_size: usize,
) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let mut results = Vec::new();
    
    for chunk in messages.chunks(batch_size) {
        let tasks: Vec<_> = chunk.iter().map(|message| {
            zeke.chat(message)
        }).collect();
        
        let batch_results = try_join_all(tasks).await?;
        
        for response in batch_results {
            results.push(response.content);
        }
        
        // Rate limiting between batches
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    
    Ok(results)
}
```

## 🔒 Security Considerations

### API Key Management

```rust
use secrecy::{Secret, ExposeSecret};
use zeroize::Zeroize;

pub struct SecureZekeConfig {
    provider: Provider,
    api_key: Secret<String>,
    model: String,
}

impl SecureZekeConfig {
    pub fn new(provider: Provider, api_key: String, model: String) -> Self {
        Self {
            provider,
            api_key: Secret::new(api_key),
            model,
        }
    }
    
    pub fn from_env(provider: Provider) -> Result<Self, Box<dyn std::error::Error>> {
        let api_key = match provider {
            Provider::OpenAI => std::env::var("OPENAI_API_KEY")?,
            Provider::Claude => std::env::var("ANTHROPIC_API_KEY")?,
            _ => return Err("Environment variable not configured".into()),
        };
        
        // Immediately create Secret to protect key in memory
        let secure_key = Secret::new(api_key);
        
        Ok(Self {
            provider,
            api_key: secure_key,
            model: provider.default_model().to_string(),
        })
    }
    
    pub fn build_zeke(&self) -> Result<Zeke, Box<dyn std::error::Error>> {
        Zeke::builder()
            .provider(self.provider)
            .api_key(self.api_key.expose_secret())
            .model(&self.model)
            .build()
            .map_err(|e| e.into())
    }
}

impl Drop for SecureZekeConfig {
    fn drop(&mut self) {
        // Keys are automatically zeroized when Secret is dropped
    }
}
```

### Input Sanitization

```rust
pub fn sanitize_input(input: &str) -> Result<String, &'static str> {
    // Remove potentially harmful content
    let sanitized = input
        .chars()
        .filter(|c| c.is_ascii_graphic() || c.is_ascii_whitespace())
        .collect::<String>();
    
    // Length limits
    if sanitized.len() > 10_000 {
        return Err("Input too long");
    }
    
    if sanitized.trim().is_empty() {
        return Err("Empty input");
    }
    
    // Check for potential prompt injection
    let dangerous_patterns = [
        "ignore previous instructions",
        "forget everything above",
        "new instructions:",
        "system:",
        "assistant:",
    ];
    
    let lower_input = sanitized.to_lowercase();
    for pattern in &dangerous_patterns {
        if lower_input.contains(pattern) {
            return Err("Potentially dangerous input detected");
        }
    }
    
    Ok(sanitized)
}

pub async fn secure_chat(
    zeke: &Zeke, 
    raw_input: &str
) -> Result<String, Box<dyn std::error::Error>> {
    let sanitized_input = sanitize_input(raw_input)
        .map_err(|e| format!("Input validation failed: {}", e))?;
    
    let response = zeke.chat(&sanitized_input).await?;
    
    // Optionally sanitize output as well
    Ok(response.content)
}
```

### Rate Limiting

```rust
use std::sync::Arc;
use tokio::sync::Semaphore;
use tokio::time::{interval, Duration};

pub struct RateLimitedZeke {
    zeke: Zeke,
    semaphore: Arc<Semaphore>,
    rate_limit: u32,
}

impl RateLimitedZeke {
    pub fn new(zeke: Zeke, requests_per_minute: u32) -> Self {
        let semaphore = Arc::new(Semaphore::new(requests_per_minute as usize));
        
        // Replenish permits periodically
        let semaphore_clone = Arc::clone(&semaphore);
        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(60));
            loop {
                interval.tick().await;
                // Add permits back (up to the limit)
                let current_permits = semaphore_clone.available_permits();
                let permits_to_add = (requests_per_minute as usize).saturating_sub(current_permits);
                semaphore_clone.add_permits(permits_to_add);
            }
        });
        
        Self {
            zeke,
            semaphore,
            rate_limit: requests_per_minute,
        }
    }
    
    pub async fn chat(&self, message: &str) -> Result<String, Box<dyn std::error::Error>> {
        let _permit = self.semaphore.acquire().await?;
        let response = self.zeke.chat(message).await?;
        Ok(response.content)
    }
}
```

## 🚨 Troubleshooting

### Common Issues and Solutions

#### 1. Zig Compiler Not Found

```bash
# Error: Zig compiler not found
# Solution: Install Zig
curl -L https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar xJ
export PATH=$PATH:./zig-linux-x86_64-0.11.0

# Or use package manager
brew install zig        # macOS
pacman -S zig           # Arch Linux
```

#### 2. Bindgen Compilation Errors

```bash
# Error: bindgen failed
# Solution: Install clang/llvm
sudo apt install clang libclang-dev    # Ubuntu/Debian
brew install llvm                       # macOS
pacman -S clang                        # Arch Linux
```

#### 3. Linker Errors

```toml
# Add to Cargo.toml if needed
[build-dependencies]
cc = "1.0"

# For static linking issues
[profile.release]
lto = false  # Disable LTO if causing issues
```

#### 4. Authentication Failures

```rust
// Debug authentication issues
use zeke::{Zeke, Provider, Error};

async fn debug_auth() {
    let zeke = match Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()
        .build() {
        Ok(zeke) => zeke,
        Err(Error::ConfigError { message }) => {
            eprintln!("Config error: {}", message);
            return;
        }
        Err(e) => {
            eprintln!("Other error: {}", e);
            return;
        }
    };
    
    match zeke.test_auth().await {
        Ok(true) => println!("✅ Authentication successful"),
        Ok(false) => println!("❌ Authentication failed - check API key"),
        Err(e) => println!("❌ Auth test error: {}", e),
    }
}
```

#### 5. GPU/GhostLLM Issues

```rust
#[cfg(feature = "ghostllm")]
async fn debug_gpu() -> Result<(), Box<dyn std::error::Error>> {
    let zeke = Zeke::builder()
        .provider(Provider::GhostLLM)
        .base_url("http://localhost:8080")
        .gpu(true)
        .build()?;

    let mut ghostllm = zeke.ghostllm();
    
    match ghostllm.initialize().await {
        Ok(_) => println!("✅ GhostLLM initialized"),
        Err(e) => {
            println!("❌ GhostLLM init failed: {}", e);
            println!("💡 Check if GhostLLM server is running on localhost:8080");
            return Err(e);
        }
    }
    
    match ghostllm.gpu_info().await {
        Ok(info) => {
            println!("🎮 GPU: {}", info.device_name);
            if info.is_overheating() {
                println!("⚠️ GPU overheating! Temperature: {}°C", info.temperature_celsius);
            }
        }
        Err(e) => println!("❌ GPU info failed: {}", e),
    }
    
    Ok(())
}
```

### Performance Debugging

```rust
use std::time::Instant;
use tracing::{info, warn};

pub async fn benchmark_performance(zeke: &Zeke) -> Result<(), Box<dyn std::error::Error>> {
    let test_messages = vec![
        "Hello, world!",
        "Explain quantum computing",
        "Write a short poem about Rust",
    ];
    
    for message in test_messages {
        let start = Instant::now();
        
        match zeke.chat(message).await {
            Ok(response) => {
                let duration = start.elapsed();
                info!(
                    "✅ Message: '{}' | Response: {} chars | Time: {:?}",
                    message,
                    response.content.len(),
                    duration
                );
                
                if duration > std::time::Duration::from_secs(10) {
                    warn!("⚠️ Slow response detected: {:?}", duration);
                }
            }
            Err(e) => {
                warn!("❌ Failed for '{}': {}", message, e);
            }
        }
        
        // Small delay between requests
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    
    Ok(())
}
```

### Debug Logging

```rust
// Enable debug logging
use tracing::{Level, debug, info};
use tracing_subscriber;

fn init_logging() {
    tracing_subscriber::fmt()
        .with_max_level(Level::DEBUG)
        .with_target(false)
        .init();
}

// In your main function
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    init_logging();
    
    info!("🚀 Starting application with debug logging");
    
    let zeke = Zeke::builder()
        .provider(Provider::OpenAI)
        .api_key_from_env()
        .build()?;
    
    debug!("Zeke instance created successfully");
    
    // Your code here...
    
    Ok(())
}
```

## 📖 API Reference

### Core Types

```rust
// Main client
pub struct Zeke { /* ... */ }

// Configuration
pub struct Config { /* ... */ }
pub struct ConfigBuilder { /* ... */ }

// Providers
pub enum Provider {
    Copilot,
    Claude, 
    OpenAI,
    Ollama,
    GhostLLM,
}

// Responses
pub struct ChatResponse {
    pub id: Uuid,
    pub content: String,
    pub provider: Provider,
    pub tokens_used: Option<u32>,
    pub response_time: Duration,
    // ...
}

pub struct StreamChunk {
    pub stream_id: Uuid,
    pub content: String,
    pub chunk_index: u32,
    pub is_final: bool,
    // ...
}

// Errors
pub enum Error {
    InitializationFailed { message: String },
    AuthenticationFailed { provider: String, message: String },
    NetworkError { message: String },
    // ...
}
```

### Key Methods

```rust
impl Zeke {
    // Construction
    pub fn new(config: Config) -> Result<Self>;
    pub fn builder() -> ConfigBuilder;
    
    // Core functionality  
    pub async fn chat(&self, message: &str) -> Result<ChatResponse>;
    pub async fn chat_stream(&self, message: &str) -> Result<impl Stream<Item = Result<StreamChunk>>>;
    
    // Provider management
    pub async fn switch_provider(&mut self, provider: Provider) -> Result<()>;
    pub async fn set_auth_token(&self, token: &str) -> Result<()>;
    pub async fn test_auth(&self) -> Result<bool>;
    pub async fn provider_status(&self) -> Result<Vec<ProviderStatus>>;
    
    // Utility
    pub async fn health_check(&self) -> Result<()>;
    pub fn current_provider(&self) -> Provider;
    pub fn version() -> &'static str;
}
```

### GhostLLM API

```rust
#[cfg(feature = "ghostllm")]
impl Zeke {
    pub fn ghostllm(&self) -> GhostLLM<'_>;
}

pub struct GhostLLM<'a> { /* ... */ }

impl<'a> GhostLLM<'a> {
    pub async fn initialize(&mut self) -> Result<()>;
    pub async fn gpu_info(&self) -> Result<GpuInfo>;
    pub async fn benchmark(&self, model: &str, batch_size: u32) -> Result<BenchmarkResult>;
    pub async fn health_check(&self) -> Result<bool>;
    pub async fn optimal_batch_size(&self) -> Result<u32>;
}
```

## 🔗 Additional Resources

- **Main Repository**: https://github.com/ghostkellz/zeke
- **Rust Bindings Docs**: https://docs.rs/zeke
- **GhostFlow Integration**: https://github.com/ghostkellz/ghostflow
- **Jarvis Platform**: https://github.com/ghostkellz/jarvis
- **Zig Language**: https://ziglang.org/
- **Rust Book**: https://doc.rust-lang.org/book/

## 🤝 Contributing

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Test** your changes: `make test-full`
4. **Format** code: `make fmt`
5. **Lint** code: `make check`
6. **Commit** changes: `git commit -m 'Add amazing feature'`
7. **Push** to branch: `git push origin feature/amazing-feature`
8. **Open** a Pull Request

## 📄 License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT License ([LICENSE-MIT](LICENSE-MIT))

at your option.

---

**Built with ❤️ by the Zeke Team**