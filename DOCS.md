# Zeke Documentation

## Table of Contents

- [Getting Started](#getting-started)
- [Installation](#installation)
- [Configuration](#configuration)
- [Provider Setup](#provider-setup)
- [Usage Examples](#usage-examples)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Getting Started

Zeke is a next-generation AI development companion that provides seamless integration with multiple AI providers, git operations, and advanced coding workflows.

### What Zeke Does

- **Multi-Provider AI Access**: Switch between Claude, OpenAI, GitHub Copilot, local LLMs, and more
- **Intelligent Provider Selection**: Automatic fallback and health monitoring
- **Git Integration**: AI-powered commit messages, code analysis, and repository management
- **Library & CLI**: Use as a Rust library or standalone CLI tool
- **Neovim Plugin**: Native integration with Neovim for coding workflows

### Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │    │   Zeke Library   │    │   AI Providers  │
│   (GhostFlow)   │◄──►│     (Rust)       │◄──►│  Claude/OpenAI  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                               │
                       ┌──────────────────┐
                       │  Git Operations  │
                       │   & File Tools   │
                       └──────────────────┘
```

---

## Installation

### As a Library

Add to your `Cargo.toml`:

```toml
[dependencies]
zeke = { git = "https://github.com/ghostkellz/zeke", features = ["git"] }
```

### As a CLI Tool

```bash
git clone https://github.com/ghostkellz/zeke.git
cd zeke
cargo install --path .
```

### For Neovim

```lua
-- Using packer.nvim
use { 'ghostkellz/zeke', run = 'cargo build --release' }

-- Using lazy.nvim
{
    'ghostkellz/zeke',
    build = 'cargo build --release',
    config = function()
        -- Configuration here
    end
}
```

### System Requirements

- **Rust**: 1.70+
- **Git**: 2.0+ (for git features)
- **GitHub CLI**: Latest (for PR creation)
- **Node.js**: 16+ (for some provider integrations)

---

## Configuration

### Environment Variables

Zeke uses environment variables for API key configuration:

```bash
# AI Provider Keys
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GITHUB_TOKEN="ghp_..."

# Optional: Custom endpoints
export GHOSTLLM_BASE_URL="https://your-instance.com"
export OLLAMA_BASE_URL="http://localhost:11434"
```

### Configuration File

Create `~/.config/zeke/config.toml`:

```toml
[providers]
default = "claude"

[providers.openai]
enabled = true
api_key = "${OPENAI_API_KEY}"
timeout = "30s"
max_retries = 3

[providers.claude]
enabled = true
api_key = "${ANTHROPIC_API_KEY}"
timeout = "45s"
max_retries = 3

[providers.ghostllm]
enabled = true
base_url = "https://api.ghostllm.com"
api_key = "${GHOSTLLM_API_KEY}"
timeout = "5s"

[providers.ollama]
enabled = true
base_url = "http://localhost:11434"
timeout = "60s"

[git]
auto_commit_message = true
sign_commits = false

[ui]
theme = "dark"
show_token_usage = true
```

### Programmatic Configuration

```rust
use zeke::{ZekeConfig, ZekeApi};

let mut config = ZekeConfig::default();
config.default_provider = "claude".to_string();
config.api_timeout = Duration::from_secs(30);

let api = ZekeApi::new_with_config(config).await?;
```

---

## Provider Setup

### OpenAI

1. Get API key from [OpenAI Platform](https://platform.openai.com)
2. Set environment variable:
   ```bash
   export OPENAI_API_KEY="sk-..."
   ```
3. Test connection:
   ```bash
   zeke ask --provider openai "Hello, world!"
   ```

### Claude (Anthropic)

1. Get API key from [Anthropic Console](https://console.anthropic.com)
2. Set environment variable:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   ```
3. Test connection:
   ```bash
   zeke ask --provider claude "Explain Rust ownership"
   ```

### GitHub Copilot

1. Ensure you have a Copilot subscription
2. Install GitHub CLI: `gh auth login`
3. Set GitHub token:
   ```bash
   export GITHUB_TOKEN="ghp_..."
   ```
4. Test connection:
   ```bash
   zeke ask --provider copilot "Generate a Rust function"
   ```

### Ollama (Local)

1. Install [Ollama](https://ollama.ai)
2. Pull a model:
   ```bash
   ollama pull codellama
   ```
3. Start Ollama server:
   ```bash
   ollama serve
   ```
4. Test connection:
   ```bash
   zeke ask --provider ollama "Explain this code"
   ```

### GhostLLM

1. Get access to GhostLLM instance
2. Set configuration:
   ```bash
   export GHOSTLLM_BASE_URL="https://your-instance.com"
   export GHOSTLLM_API_KEY="your-key"
   ```
3. Test connection:
   ```bash
   zeke ask --provider ghostllm "Help me debug this"
   ```

---

## Usage Examples

### Basic CLI Usage

```bash
# Ask a question
zeke ask "How do I implement a binary tree in Rust?"

# Use specific provider
zeke ask --provider claude "Explain async/await"

# Use specific model
zeke ask --provider openai --model gpt-4 "Generate unit tests"

# Get help
zeke --help
```

### Library Usage

#### Simple Integration

```rust
use zeke::{ZekeApi, ZekeResult};

#[tokio::main]
async fn main() -> ZekeResult<()> {
    let api = ZekeApi::new().await?;

    let response = api.ask("claude", "What is Rust?", None).await?;
    println!("{}", response.content);

    Ok(())
}
```

#### Code Analysis

```rust
use zeke::ZekeApi;

async fn analyze_rust_code(code: &str) -> Result<String, Box<dyn std::error::Error>> {
    let api = ZekeApi::new().await?;

    let prompt = format!(
        "Analyze this Rust code for potential issues:\n\n```rust\n{}\n```\n\nProvide suggestions for improvement.",
        code
    );

    let response = api.ask("claude", &prompt, None).await?;
    Ok(response.content)
}
```

#### Git Operations

```rust
use zeke::ZekeApi;

async fn smart_commit() -> Result<(), Box<dyn std::error::Error>> {
    let api = ZekeApi::new().await?;
    let git = api.git()?;

    // Get staged changes
    let diff = git.diff(true).await?;

    if !diff.is_empty() {
        // Generate commit message
        let prompt = format!("Generate a concise git commit message for:\n{}", diff);
        let response = api.ask("claude", &prompt, None).await?;

        // Create commit
        let hash = git.commit(&response.content).await?;
        println!("Created commit: {}", hash);
    }

    Ok(())
}
```

### Provider Health Monitoring

```rust
use zeke::ZekeApi;

async fn monitor_providers() -> Result<(), Box<dyn std::error::Error>> {
    let api = ZekeApi::new().await?;

    let status = api.get_provider_status().await;

    for (provider, health) in status {
        println!("{:?}: {} ({}ms)",
            provider,
            if health.is_healthy { "✓" } else { "✗" },
            health.response_time.as_millis()
        );
    }

    Ok(())
}
```

### Batch Processing

```rust
use zeke::ZekeApi;
use futures::future::join_all;

async fn process_files_batch(files: Vec<&str>) -> Result<(), Box<dyn std::error::Error>> {
    let api = std::sync::Arc::new(ZekeApi::new().await?);

    let tasks: Vec<_> = files.into_iter().map(|file| {
        let api = api.clone();
        tokio::spawn(async move {
            let content = tokio::fs::read_to_string(file).await?;
            let prompt = format!("Review this code:\n{}", content);
            api.ask("claude", &prompt, None).await
        })
    }).collect();

    let results = join_all(tasks).await;

    for (i, result) in results.into_iter().enumerate() {
        match result? {
            Ok(response) => println!("File {}: {}", i, response.content),
            Err(e) => eprintln!("File {} failed: {}", i, e),
        }
    }

    Ok(())
}
```

---

## Advanced Features

### Provider Fallback Chain

Zeke automatically tries providers in order of priority when one fails:

```rust
// This will try: GhostLLM -> Claude -> OpenAI -> DeepSeek -> Copilot -> Ollama
let response = api.ask("auto", "Explain this code", None).await?;
```

### Custom Provider Configuration

```rust
use zeke::{ProviderManager, Provider, ProviderConfig};
use std::time::Duration;

let mut manager = ProviderManager::new();

// Configure custom timeout and retries
let config = ProviderConfig {
    provider: Provider::OpenAI,
    priority: 10,
    capabilities: vec![Capability::ChatCompletion, Capability::CodeGeneration],
    max_requests_per_minute: 100,
    timeout: Duration::from_secs(10),
    fallback_providers: vec![Provider::Claude],
};

manager.configure_provider(Provider::OpenAI, config).await?;
```

### Streaming Responses

```rust
use zeke::streaming::StreamManager;

let stream_manager = StreamManager::new();
let mut stream = stream_manager.start_chat_stream("claude", "Explain Rust step by step").await?;

while let Some(chunk) = stream.next().await {
    print!("{}", chunk.content);
    tokio::io::stdout().flush().await?;
}
```

### Agent System

```rust
use zeke::agents::{AgentManager, SubagentType};

let agent_manager = AgentManager::new();

// Use specialized agents for specific tasks
let security_analysis = agent_manager
    .execute_command("security", "analyze --file src/main.rs")
    .await?;

let blockchain_code = agent_manager
    .execute_command("blockchain", "generate --contract erc20")
    .await?;
```

### Tool Integration

```rust
use zeke::tools::{ToolRegistry, ToolInput, ToolOutput};

let mut registry = ToolRegistry::new();

// Register custom tools
registry.register_tool("file_analyzer", Box::new(FileAnalyzerTool));

// Use tools in AI workflows
let result = registry.execute_tool("file_analyzer", ToolInput {
    file_path: "src/main.rs".to_string(),
    analysis_type: "security".to_string(),
}).await?;
```

---

## Git Integration

### Automatic Commit Messages

```bash
# Stage your changes
git add .

# Let Zeke generate commit message
zeke git commit-message

# Or commit directly
zeke git commit
```

### Code Review

```bash
# Review staged changes
zeke git review --staged

# Review specific commit
zeke git review --commit abc123

# Review pull request
zeke git review --pr 123
```

### Branch Management

```bash
# Create feature branch with AI-suggested name
zeke git create-branch --feature "user authentication"

# Auto-generate PR description
zeke git create-pr --title "Add user auth" --auto-description
```

### Repository Analysis

```rust
use zeke::git::GitManager;

async fn analyze_repository() -> Result<(), Box<dyn std::error::Error>> {
    let git = GitManager::new()?;

    // Get recent commits
    let commits = git.get_recent_commits(10).await?;

    // Analyze commit patterns
    let commit_messages: Vec<_> = commits.iter().map(|c| &c.message).collect();
    let analysis_prompt = format!(
        "Analyze these commit messages for patterns:\n{}",
        commit_messages.join("\n")
    );

    let api = ZekeApi::new().await?;
    let analysis = api.ask("claude", &analysis_prompt, None).await?;

    println!("Repository Analysis:\n{}", analysis.content);

    Ok(())
}
```

---

## Neovim Integration

### Setup

```lua
-- init.lua
require('zeke').setup({
    provider = 'claude',
    keymaps = {
        ask = '<leader>za',
        explain = '<leader>ze',
        review = '<leader>zr',
        commit = '<leader>zc',
    },
    ui = {
        floating = true,
        width = 80,
        height = 20,
    }
})
```

### Usage

```vim
" Ask AI about selected code
:ZekeAsk "What does this function do?"

" Explain selected code
:ZekeExplain

" Generate tests for current function
:ZekeGenerate test

" Review current file
:ZekeReview

" Generate commit message
:ZekeCommit
```

### Custom Commands

```lua
-- Custom Neovim commands
vim.api.nvim_create_user_command('ZekeOptimize', function()
    local content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local code = table.concat(content, '\n')

    local prompt = 'Optimize this code for performance:\n' .. code
    require('zeke').ask(prompt, function(response)
        -- Handle response
        vim.notify(response)
    end)
end, {})
```

---

## Troubleshooting

### Common Issues

#### "Provider not available" Error

**Cause**: API key not set or provider not initialized

**Solution**:
```bash
# Check environment variables
echo $OPENAI_API_KEY
echo $ANTHROPIC_API_KEY

# Test provider directly
zeke providers list
zeke providers test claude
```

#### Network Connection Issues

**Cause**: Firewall, proxy, or network restrictions

**Solution**:
```bash
# Test connectivity
curl -I https://api.openai.com
curl -I https://api.anthropic.com

# Configure proxy if needed
export HTTP_PROXY=http://proxy:8080
export HTTPS_PROXY=http://proxy:8080
```

#### Git Operations Failing

**Cause**: Not in a git repository or permissions issues

**Solution**:
```bash
# Ensure you're in a git repo
git status

# Check git configuration
git config user.name
git config user.email

# Set if missing
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

#### High Token Usage

**Cause**: Large prompts or frequent requests

**Solution**:
```rust
// Monitor usage
let response = api.ask("claude", prompt, None).await?;
if let Some(usage) = response.usage {
    println!("Tokens used: {}", usage.total_tokens);
}

// Use shorter prompts
let concise_prompt = format!("Briefly explain: {}", code_snippet);
```

### Debug Mode

Enable debug logging:

```bash
export RUST_LOG=zeke=debug
zeke ask "test question"
```

### Provider Health Check

```bash
# Check all providers
zeke providers health

# Test specific provider
zeke providers test openai
```

### Configuration Validation

```bash
# Validate config file
zeke config validate

# Show current config
zeke config show
```

---

## FAQ

### General

**Q: Which AI provider should I use?**
A: It depends on your needs:
- **Claude**: Best for code analysis and explanations
- **OpenAI GPT-4**: Great for general coding tasks
- **GitHub Copilot**: Excellent for code completion
- **Ollama**: Best for offline/private use
- **GhostLLM**: Fastest responses if available

**Q: Can I use multiple providers simultaneously?**
A: Yes! Zeke automatically selects the best provider or you can specify one explicitly.

**Q: Is my code sent to AI providers?**
A: Only when you explicitly make requests. Zeke doesn't automatically send code.

### Library Integration

**Q: How do I integrate Zeke into my Rust project?**
A: Add it as a dependency and use the `ZekeApi`:
```toml
[dependencies]
zeke = { git = "https://github.com/ghostkellz/zeke" }
```

**Q: Can I use Zeke without git features?**
A: Yes, disable the git feature:
```toml
[dependencies]
zeke = { git = "https://github.com/ghostkellz/zeke", default-features = false }
```

**Q: Is Zeke thread-safe?**
A: Yes, all public APIs are thread-safe and can be used across async tasks.

### Performance

**Q: How can I reduce API costs?**
A:
- Use local models (Ollama) when possible
- Cache responses for repeated queries
- Use shorter, more specific prompts
- Monitor token usage with `response.usage`

**Q: Why are responses slow?**
A:
- Check network connectivity
- Try a different provider
- Reduce prompt length
- Use local models for faster responses

### Development

**Q: How do I contribute to Zeke?**
A: See `CONTRIBUTING.md` for guidelines on submitting issues and pull requests.

**Q: Can I add custom AI providers?**
A: Yes, implement the `ProviderClient` trait:
```rust
use zeke::providers::ProviderClient;

struct MyProvider;

#[async_trait]
impl ProviderClient for MyProvider {
    async fn chat_completion(&self, request: &ChatRequest) -> ZekeResult<ChatResponse> {
        // Implementation
    }
    // ... other methods
}
```

**Q: How do I report bugs?**
A: Open an issue on [GitHub](https://github.com/ghostkellz/zeke/issues) with:
- Zeke version
- Operating system
- Error message
- Steps to reproduce

### Security

**Q: How are API keys stored?**
A: API keys are read from environment variables and never stored in files by default.

**Q: Can I use Zeke in CI/CD?**
A: Yes, set environment variables in your CI/CD configuration:
```yaml
env:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Q: Is it safe to use in corporate environments?**
A: Consider using local models (Ollama) or private instances for sensitive code.

---

## Getting Help

- **Documentation**: This file and `API_DOCS.md`
- **Issues**: [GitHub Issues](https://github.com/ghostkellz/zeke/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ghostkellz/zeke/discussions)
- **Email**: Contact the maintainers

---

## Next Steps

1. **Set up your providers** - Configure API keys for your preferred AI services
2. **Try the examples** - Run the code examples in this documentation
3. **Explore features** - Try git integration, different providers, and advanced features
4. **Integrate** - Add Zeke to your projects or workflow
5. **Contribute** - Help improve Zeke by reporting issues or contributing code

Happy coding with Zeke! 🚀