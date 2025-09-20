# ZEKE.md

This file provides context for Zeke when working with this codebase.

## Project Overview

**Zeke** - The next-generation AI development companion built with Rust. A high-performance alternative to Claude Code with enhanced features, provider flexibility, and seamless integration with development workflows.

## Core Architecture

### Provider Abstraction Layer

Zeke supports multiple connection modes through its unified provider router:

- **Direct Mode**: Connect directly to individual AI providers (Claude API, OpenAI API, etc.)
- **GhostLLM Mode**: Connect via GhostLLM proxy with intelligent routing and consent system
- **Auto Mode**: Automatically detect and prefer GhostLLM if available, fallback to direct connections

### Key Components

1. **Provider Router** (`src/providers/router.rs`) - Intelligent routing with health checking and fallback
2. **Action Approval System** (`src/actions/mod.rs`) - GhostWarden-compatible approval flow
3. **WebSocket Streaming** (`src/streaming/mod.rs`) - Real-time streaming for all providers
4. **Configuration Management** (`src/config/mod.rs`) - Flexible configuration system
5. **RPC/IPC Bridge** - Communication protocol for Neovim integration

## Configuration

### Default Configuration Structure

```toml
# ~/.config/zeke/zeke.toml
[router]
mode = "auto"  # "auto", "direct", "ghostllm"

[router.ghostllm]
base_url = "http://localhost:8080/v1"
enable_routing = true
enable_consent = true
session_persistence = true
cost_tracking = true
health_check_timeout_ms = 5000

[router.direct]
preferred_provider = "claude"
fallback_order = ["claude", "openai", "ollama"]
prefer_local = true

[router.security]
auto_approve_read = true
auto_approve_write = false
require_mfa = false
project_scope = "repo:current"

[providers.claude]
api_key = "${CLAUDE_API_KEY}"

[providers.openai]
api_key = "${OPENAI_API_KEY}"

[providers.ollama]
base_url = "http://localhost:11434"

[auth]
github_token = "${GITHUB_TOKEN}"
```

### Environment Variables

Core environment variables Zeke recognizes:

- `CLAUDE_API_KEY` - Claude API authentication
- `OPENAI_API_KEY` - OpenAI API authentication
- `GITHUB_TOKEN` - GitHub integration
- `GHOSTLLM_URL` - GhostLLM proxy URL (default: http://localhost:8080)
- `GHOSTLLM_API_KEY` - GhostLLM authentication token
- `ZEKE_CONFIG_PATH` - Custom config file location

## Action Approval System

### Security Model

Zeke implements a comprehensive action approval system compatible with GhostWarden:

#### Approval Levels

- **Allow Once** - Approve this single operation
- **Allow Session** - Approve for entire session
- **Allow Project** - Approve for all operations in this project
- **Deny** - Block this operation

#### Action Types

The system categorizes and manages these action types:

```rust
pub enum ActionType {
    FileWrite { path: String },
    FileRead { path: String },
    FileDelete { path: String },
    CommandExecution { command: String },
    NetworkRequest { url: String },
    GitCommit { message: String },
    GitPush { remote: String, branch: String },
    ProjectSearch { pattern: String },
    ProjectModify { scope: String },
}
```

#### Approval Rules

Configure automatic approval rules:

```rust
// Auto-approve file reads in project scope
let rule = ApprovalRule::allow_file_reads_in_project("/path/to/project");

// Deny dangerous commands
let rule = ApprovalRule::deny_dangerous_commands();
```

### Terminal Approval Interface

When running in CLI mode, Zeke presents a user-friendly approval interface:

```
🛡️  Action Approval Required
┌─────────────────────────────────────────────┐
│ Action: Write to file: src/main.rs         │
│ Context: Implementing new feature          │
│ Project: /home/user/my-project             │
└─────────────────────────────────────────────┘

Options:
  [A] Allow Once    - Approve this single operation
  [S] Allow Session - Approve for entire session
  [P] Allow Project - Approve for all operations in this project
  [D] Deny          - Block this operation
  [?] Help          - Show more information

Your choice [A/S/P/D/?]:
```

## WebSocket Streaming

### Architecture

Zeke implements high-performance WebSocket streaming for real-time AI responses:

- **Server**: TCP listener with WebSocket upgrade support
- **Client Management**: Connection tracking with authentication
- **Message Protocol**: JSON-RPC 2.0 with custom streaming extensions
- **Provider Integration**: Unified streaming across all AI providers

### Message Types

```rust
pub enum StreamMessage {
    ChatDelta {
        id: String,
        delta: String,
        model: String,
        provider: String,
        finished: bool,
    },
    Error {
        id: String,
        error: String,
        code: Option<i32>,
    },
    StreamStart {
        id: String,
        model: String,
        provider: String,
    },
    StreamEnd {
        id: String,
        total_tokens: Option<u32>,
    },
    Ping { timestamp: u64 },
    Pong { timestamp: u64 },
}
```

### Integration with Neovim

The WebSocket server enables seamless integration with zeke.nvim:

1. **Discovery**: Lock files at `~/.zeke/sessions/[port].lock`
2. **Authentication**: UUID v4 tokens for secure connections
3. **Protocol**: MCP-compatible message format
4. **Performance**: < 50ms response times, minimal memory footprint

## CLI Commands

### Core Commands

```bash
# Provider management
zeke provider list                    # List available providers
zeke provider status                  # Show provider health
zeke provider test <provider>         # Test provider connectivity

# Router management
zeke router status                    # Show router configuration
zeke router switch <mode>             # Switch between direct/ghostllm/auto
zeke router test                      # Test all provider connectivity
zeke router chat "hello"              # Test chat functionality

# Chat and interaction
zeke chat                            # Start interactive chat
zeke ask "question"                  # Single question
zeke explain <file>                  # Explain code file
zeke fix <file>                      # Fix errors in file
zeke test <file>                     # Generate tests for file

# File operations
zeke diff <file1> <file2>            # Show differences
zeke apply <patch>                   # Apply changes with approval
```

### Advanced Usage

```bash
# Force specific provider mode
zeke --provider direct chat
zeke --provider ghostllm ask "question"

# Enable streaming
zeke chat --stream

# Project-wide operations
zeke refactor --scope project
zeke search --pattern "TODO"

# Git integration
zeke commit --message "AI-generated commit"
zeke review --branch feature/new-api
```

## Integration Patterns

### Neovim Integration (zeke.nvim)

Zeke integrates with Neovim through zeke.nvim plugin:

#### Key Features

- **Chat Interface**: Floating windows with markdown rendering
- **Code Actions**: Inline explain, fix, test, refactor
- **File Operations**: Diff previews with approval flow
- **Streaming**: Real-time response rendering
- **Context**: Automatic project and selection context

#### Required Setup

```lua
-- ~/.config/nvim/lua/plugins/zeke.lua
return {
  'ghostkellz/zeke.nvim',
  config = function()
    require('zeke').setup({
      provider = 'auto',
      websocket_port = 8081,
      auto_start_server = true,
      approval_ui = 'native',  -- 'native' or 'terminal'
    })
  end,
  keys = {
    { '<leader>z', '<cmd>ZekeToggle<cr>', desc = 'Toggle Zeke' },
    { '<leader>ze', '<cmd>ZekeExplain<cr>', desc = 'Explain code' },
    { '<leader>zf', '<cmd>ZekeFix<cr>', desc = 'Fix errors' },
    { '<leader>zt', '<cmd>ZekeTest<cr>', desc = 'Generate tests' },
  }
}
```

### IDE Integration

Zeke follows the claude-code.nvim protocol for IDE compatibility:

- **WebSocket Server**: RFC 6455 compliant with MCP message format
- **Discovery System**: Lock files for client discovery
- **Authentication**: Token-based secure handshake
- **Tool Protocol**: JSON Schema-based tool definitions

## Performance Targets

### Response Times

- **Command Response**: < 50ms
- **WebSocket Connection**: < 100ms setup
- **Provider Switching**: < 250ms (model swap target)
- **File Operations**: < 200ms for typical files

### Resource Usage

- **Memory**: < 50MB baseline, < 200MB with active sessions
- **CPU**: Minimal background usage, burst during AI requests
- **Network**: Efficient provider connection pooling

## Security Model

### Authentication & Authorization

1. **Provider Authentication**: Secure API key management
2. **Session Management**: UUID-based session tracking
3. **Action Approval**: Granular permission system
4. **Project Scope**: Sandboxed operation boundaries

### Data Protection

- **Local Processing**: Context extraction happens locally
- **Secure Transmission**: TLS for all provider communications
- **No Data Retention**: Zeke doesn't store conversation history
- **Audit Logging**: Comprehensive action logging for security

### Permission Levels

```rust
pub struct SecurityConfig {
    pub auto_approve_read: bool,      // Auto-approve file reads
    pub auto_approve_write: bool,     // Auto-approve file writes
    pub require_mfa: bool,            // Multi-factor authentication
    pub project_scope: Option<String>, // Limit operations to project
}
```

## Development Workflow

### Common Development Commands

```bash
# Build and test
cargo build --release
cargo test
cargo check

# Run with specific provider
PROVIDER=claude ./target/release/zeke chat
PROVIDER=ghostllm ./target/release/zeke chat

# Debug mode with logging
RUST_LOG=debug ./target/release/zeke router status

# Test router functionality
./target/release/zeke router test
./target/release/zeke router switch ghostllm
./target/release/zeke router chat "test message"
```

### Configuration Testing

```bash
# Test different configurations
zeke --config ./configs/development.toml chat
zeke --config ./configs/production.toml provider status

# Validate configuration
zeke config validate
zeke config show
```

## Troubleshooting

### Common Issues

#### Provider Connection Failures

```bash
# Check provider status
zeke provider status

# Test specific provider
zeke provider test claude
zeke provider test openai

# Check router mode
zeke router status
```

#### GhostLLM Integration Issues

```bash
# Verify GhostLLM availability
curl http://localhost:8080/health

# Check router auto-detection
zeke router switch auto
zeke router status

# Force direct mode if needed
zeke router switch direct
```

#### WebSocket Connection Issues

```bash
# Check WebSocket server
zeke stream status

# Test WebSocket connectivity
websocat ws://localhost:8081

# Check lock files
ls -la ~/.zeke/sessions/
```

### Debug Logging

Enable comprehensive logging:

```bash
export RUST_LOG=zeke=debug,zeke::providers=trace
./target/release/zeke chat
```

## Performance Optimization

### Provider Optimization

- **Connection Pooling**: Reuse HTTP connections across requests
- **Request Batching**: Combine multiple operations when possible
- **Caching**: Cache provider capabilities and model information
- **Health Monitoring**: Proactive provider health checking

### Streaming Optimization

- **Buffer Management**: Efficient WebSocket buffer handling
- **Chunk Processing**: Optimal chunk sizes for smooth streaming
- **Connection Limits**: Prevent resource exhaustion
- **Heartbeat Protocol**: Maintain connection health

## Future Enhancements

### Planned Features

1. **Omen Integration**: github.com/ghostkellz/omen crate integration
2. **Enhanced Context**: Better project-wide context extraction
3. **Plugin System**: Extensible plugin architecture
4. **Multi-Language Support**: Enhanced language-specific features
5. **Advanced Streaming**: Parallel provider streaming

### Roadmap

- **v0.4.0**: Omen crate integration, enhanced streaming
- **v0.5.0**: Plugin system, advanced context management
- **v1.0.0**: Production-ready release with full feature parity

## Contributing

### Development Setup

```bash
# Clone and setup
git clone https://github.com/ghostkellz/zeke
cd zeke
cargo build

# Run tests
cargo test

# Install locally
cargo install --path .
```

### Code Quality

- **Formatting**: Use `cargo fmt`
- **Linting**: Use `cargo clippy`
- **Testing**: Comprehensive test coverage
- **Documentation**: Keep ZEKE.md updated

## License

MIT License - see LICENSE file for details.

---

**Note**: This documentation follows the claude-code.nvim pattern but adapted for Zeke's Rust-based architecture and enhanced feature set.