# GhostLLM + Zeke CLI Integration Guide

This document provides comprehensive instructions for integrating the Zeke CLI with GhostLLM's unified proxy system.

## Overview

Zeke is a high-performance Rust-native AI coding assistant that can be seamlessly integrated with GhostLLM to provide:

- **Unified Provider Management**: Access all AI providers through GhostLLM's routing engine
- **GhostWarden Security**: Consent-based AI interactions with project-scope permissions
- **Cost Optimization**: Intelligent routing between local Ollama and cloud providers
- **Session Persistence**: Maintain conversation context across model switches

## Quick Start

### 1. Install Dependencies

```bash
# Install GhostLLM
git clone https://github.com/ghostkellz/ghostllm
cd ghostllm
cargo build --release

# Install Zeke CLI
git clone https://github.com/ghostkellz/zeke
cd zeke
cargo build --release
```

### 2. Start GhostLLM Proxy

```bash
cd ghostllm
./target/release/ghostllm-proxy serve --dev
```

GhostLLM will start on `http://localhost:8080` with the following endpoints:
- Health: `http://localhost:8080/health`
- Models: `http://localhost:8080/v1/models`
- Chat: `http://localhost:8080/v1/chat/completions`

### 3. Configure Zeke

Create or update your Zeke configuration file:

```toml
# ~/.config/zeke/zeke.toml

[api]
# Point Zeke to GhostLLM instead of individual providers
base_url = "http://localhost:8080/v1"
api_key = "" # Managed by GhostLLM

[models]
# Use GhostLLM's intelligent routing
default = "auto"
code_completion = "deepseek-coder"
chat = "claude-3-sonnet"
reasoning = "gpt-4"

[ghostllm]
# GhostLLM-specific settings
enable_routing = true
enable_consent = true
session_persistence = true
cost_tracking = true

[security]
# GhostWarden integration
auto_approve_read = true
auto_approve_write = false
project_scope = "repo:current"
```

## Integration Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Zeke CLI      │───▶│   GhostLLM      │───▶│   Providers     │
│                 │    │   Proxy         │    │                 │
│ • Commands      │    │ • Routing       │    │ • Claude        │
│ • Context       │    │ • GhostWarden   │    │ • OpenAI        │
│ • Sessions      │    │ • Caching       │    │ • Ollama        │
│ • File Ops      │    │ • Analytics     │    │ • Gemini        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Zeke Commands with GhostLLM

### Basic Usage

```bash
# Start interactive session
zeke chat

# Explain code with automatic model routing
zeke explain src/main.rs

# Generate tests using best model for task
zeke test --file src/lib.rs

# Code completion with local model preference
zeke complete --context 5
```

### Advanced Commands

```bash
# Force specific model
zeke chat --model claude-3-sonnet

# Enable debug mode to see routing decisions
zeke --debug chat

# Work with project scope
zeke --project-scope "repo:ghostllm" review src/

# Batch operations with cost limits
zeke batch --max-cost 1.00 explain src/**/*.rs
```

## GhostWarden Integration

### Consent Flow

When Zeke requests an action that requires consent:

```bash
$ zeke edit src/main.rs "Add error handling"

🛡️  GhostWarden Consent Required
Action: FileWrite { path: "src/main.rs" }
Project: repo:ghostllm
Context: Code modification requested

[A]llow Once  [S]ession  [P]roject  [D]eny  [?] Help:
```

### Response Options

- **Allow Once**: Approve this single operation
- **Session**: Approve for entire Zeke session
- **Project**: Approve for all operations in this project
- **Deny**: Block the operation

### Scope-Based Permissions

```toml
# ~/.config/zeke/permissions.toml

[scopes."repo:ghostllm"]
file_write = "allow"
command_exec = "prompt"
network_request = "allow"

[scopes."repo:*"]
file_write = "prompt"
command_exec = "deny"
network_request = "prompt"
```

## Configuration Examples

### Development Setup

```toml
# ~/.config/zeke/profiles/development.toml

[profile.development]
name = "Local Development"

[api]
base_url = "http://localhost:8080/v1"

[models]
# Prefer local models for development
default = "ollama:deepseek-coder"
fallback = ["ollama:llama3", "claude-3-haiku"]

[ghostwarden]
auto_approve_read = true
auto_approve_write = true # Trust local development
warn_on_cloud_usage = true

[features]
streaming = true
context_window = 8192
```

### Production Setup

```toml
# ~/.config/zeke/profiles/production.toml

[profile.production]
name = "Production Environment"

[api]
base_url = "https://ghostllm.yourcompany.com/v1"
api_key_cmd = "your-auth-command"

[models]
# Use high-quality models for production
default = "claude-3-sonnet"
fallback = ["gpt-4", "claude-3-haiku"]

[ghostwarden]
auto_approve_read = false
auto_approve_write = false # Strict consent
require_mfa = true

[limits]
daily_cost_limit = 10.00
session_timeout = 3600
```

## Advanced Features

### Model Routing

Zeke can leverage GhostLLM's intelligent routing:

```bash
# Let GhostLLM choose optimal model
zeke chat --auto-route

# Specify routing strategy
zeke explain --route-by cost     # Cheapest option
zeke explain --route-by speed    # Fastest response
zeke explain --route-by quality  # Best model for task
```

### Session Management

```bash
# Start named session
zeke session start --name "feature-auth"

# Resume session
zeke session resume "feature-auth"

# List sessions
zeke session list

# Session with model persistence
zeke session start --sticky-model claude-3-sonnet
```

### Batch Operations

```bash
# Process multiple files with cost control
zeke batch \
  --max-cost 5.00 \
  --prefer-local \
  --pattern "src/**/*.rs" \
  explain

# Generate tests for entire codebase
zeke batch \
  --model "deepseek-coder" \
  --output-dir "tests/generated" \
  test src/
```

## API Integration

### Direct API Usage

Zeke can also use GhostLLM's API directly:

```rust
// examples/zeke-ghostllm-integration.rs
use zeke_api::ZekeClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = ZekeClient::builder()
        .base_url("http://localhost:8080/v1")
        .with_ghostwarden(true)
        .build();

    let response = client
        .chat()
        .model("auto")
        .message("Explain this function")
        .context_from_file("src/main.rs")
        .send()
        .await?;

    println!("Response: {}", response.content);
    Ok(())
}
```

### RPC Integration

For deeper integration, Zeke can use GhostLLM's RPC interface:

```rust
// Custom Zeke plugin
use ghostllm_rpc::GhostLLMClient;

async fn custom_zeke_command() -> Result<(), Box<dyn std::error::Error>> {
    let client = GhostLLMClient::connect("http://localhost:8080").await?;

    // Get optimal model for task
    let model = client
        .route_request()
        .task_type("code_completion")
        .context_size(4096)
        .prefer_local(true)
        .get_best_model()
        .await?;

    println!("Using model: {}", model);
    Ok(())
}
```

## Troubleshooting

### Common Issues

1. **Connection Issues**
   ```bash
   # Check GhostLLM status
   curl http://localhost:8080/health

   # Check Zeke configuration
   zeke config validate
   ```

2. **Authentication Errors**
   ```bash
   # Check API configuration
   zeke config show api

   # Test authentication
   zeke auth test
   ```

3. **Model Not Found**
   ```bash
   # List available models
   zeke models list

   # Test specific model
   zeke test-model claude-3-sonnet
   ```

### Debug Mode

```bash
# Enable verbose logging
export ZEKE_LOG=debug
export GHOSTLLM_LOG=debug

# Run with debug output
zeke --debug chat
```

### Performance Tuning

```toml
# ~/.config/zeke/performance.toml

[performance]
# Reduce latency for local models
local_timeout = 5
cloud_timeout = 30

# Optimize context usage
smart_context = true
context_compression = true

# Cache frequent requests
enable_cache = true
cache_ttl = 3600
```

## Migration from Direct Provider Integration

### Before (Multiple Providers)

```toml
# Old Zeke configuration
[providers.openai]
api_key = "sk-..."
base_url = "https://api.openai.com/v1"

[providers.anthropic]
api_key = "sk-ant-..."
base_url = "https://api.anthropic.com/v1"

[providers.ollama]
base_url = "http://localhost:11434/v1"
```

### After (GhostLLM Unified)

```toml
# New GhostLLM configuration
[api]
base_url = "http://localhost:8080/v1"
# API keys managed by GhostLLM

[models]
# All providers accessible through unified interface
default = "auto"
```

## Best Practices

1. **Use Project Scopes**: Configure GhostWarden scopes for different projects
2. **Prefer Local Models**: Set local models as default for development
3. **Monitor Costs**: Enable cost tracking and set limits
4. **Session Management**: Use named sessions for context persistence
5. **Batch Operations**: Use batch commands for multiple file operations

## Support and Examples

- **Documentation**: See `/docs/zeke-integration/` for detailed examples
- **Examples**: Check `/examples/zeke-cli/` for working configurations
- **Issues**: Report integration issues to the GhostLLM repository
- **Community**: Join the GhostLLM Discord for support

## Next Steps

1. Set up basic integration with the quick start guide
2. Configure GhostWarden permissions for your projects
3. Experiment with model routing and fallback strategies
4. Set up monitoring and cost controls
5. Explore advanced features like batch operations and RPC integration