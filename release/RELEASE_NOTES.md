# Zeke v0.3.0 Release Notes

**Release Date**: October 26, 2025
**Codename**: "Broker"

## Overview

Zeke v0.3.0 is a major release bringing production-ready OAuth authentication, Model Context Protocol (MCP) support, and a comprehensive multi-provider AI routing system. This release represents the transition from MVP to Alpha status with significant architectural improvements.

## Highlights

### 🔐 OAuth Broker Architecture
- **Google OAuth**: Authenticate for Claude Max and ChatGPT Pro access
- **GitHub OAuth**: Authenticate for GitHub Copilot Pro
- **Secure Token Management**: Encrypted credential storage with 0600 permissions
- **Broker-based Flow**: Improved security with auth.cktech.org broker

### 🔌 Model Context Protocol (MCP)
- **Full MCP Support**: stdio, WebSocket, and Docker transports
- **Tool Integration**: Seamless integration with MCP-compatible tools
- **File Operations**: Safe file editing with diff preview and rollback
- **Dynamic Tool Discovery**: Automatic tool registration and validation

### 🌐 Enhanced Provider Support
- **7 AI Providers**: OpenAI, Claude, xAI, Google Gemini, Azure, Ollama, GitHub Copilot
- **Smart Routing**: Intent and complexity-based model selection
- **Automatic Fallback**: Graceful degradation from local to cloud
- **Cost Management**: Configurable cloud cost limits

### ⚙️ Configuration System
- **TOML Format**: Human-readable configuration with `zeke.toml`
- **Environment Variables**: Full override capability
- **Provider Priorities**: Configurable fallback chains
- **Per-provider Settings**: Temperature, max_tokens, custom endpoints

## What's New

### New Features

#### CLI Commands
```bash
# Configuration management
zeke config get default.provider
zeke config set providers.ollama.model "qwen2.5-coder:7b"
zeke config validate

# Authentication
zeke auth google          # Google OAuth for Claude/ChatGPT
zeke auth github          # GitHub OAuth for Copilot
zeke auth openai <key>    # API key auth
zeke auth list            # List configured providers

# System diagnostics
zeke doctor               # Health check and diagnostics
zeke provider status      # Provider availability
```

#### API Enhancements
- **HTTP Server**: Production-ready REST API on port 7878
- **Streaming Support**: Real-time response streaming
- **WebSocket**: Bidirectional communication for MCP
- **Metrics**: Request tracking and performance monitoring

#### Developer Experience
- **Better Error Messages**: Detailed error context and suggestions
- **Debug Mode**: Comprehensive logging with `ZEKE_LOG_LEVEL=debug`
- **Hot Reload**: Configuration changes without restart
- **Health Checks**: `/health` and `/api/status` endpoints

### Breaking Changes

⚠️ **Configuration Format**: Migrated from JSON to TOML
```toml
# Old (config.json)
{
  "default_model": "qwen2.5-coder:7b"
}

# New (zeke.toml)
[default]
model = "qwen2.5-coder:7b"
provider = "ollama"
```

⚠️ **OAuth Flow**: Now uses broker architecture
- Old: Direct callbacks to localhost:8765
- New: Broker at auth.cktech.org with secure token exchange

⚠️ **Minimum Zig Version**: Now requires Zig 0.16.0-dev
- Zig 0.15.x has inline assembly issues that break zsync

### Improvements

#### Performance
- **10x faster startup**: Optimized dependency loading
- **Async I/O**: Non-blocking network operations with zsync 0.6.1
- **Connection pooling**: Reuse HTTP connections for better latency
- **Lazy initialization**: Providers loaded on-demand

#### Security
- **Encrypted credentials**: API keys encrypted at rest
- **Secure OAuth**: PKCE flow with state validation
- **Permission checks**: File operations require explicit approval
- **Audit logging**: All API calls logged to database

#### Reliability
- **Automatic retry**: Exponential backoff for transient failures
- **Circuit breaker**: Prevent cascade failures
- **Health monitoring**: Provider availability tracking
- **Graceful shutdown**: Clean resource cleanup

## Installation

### Quick Install
```bash
curl -fsSL https://zeke.cktech.org | bash
```

### From Source
```bash
git clone https://github.com/ghostkellz/zeke.git
cd zeke
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zeke /usr/local/bin/
```

### Arch Linux (AUR)
```bash
yay -S zeke
```

## Getting Started

### 1. Configure Providers

Create `~/.config/zeke/zeke.toml`:
```toml
[default]
provider = "ollama"
model = "qwen2.5-coder:7b"

[providers.ollama]
enabled = true
host = "http://localhost:11434"

[providers.claude]
enabled = true
model = "claude-3-5-sonnet-20241022"
```

### 2. Authenticate

```bash
# For Ollama (no auth needed)
docker run -d --name ollama --network host ollama/ollama
docker exec -it ollama ollama pull qwen2.5-coder:7b

# For cloud providers
zeke auth google    # Google OAuth
zeke auth github    # GitHub OAuth
zeke auth openai sk-...   # API key
```

### 3. Start Using Zeke

```bash
# Start HTTP server
zeke serve

# Chat with AI
zeke chat "Explain async/await in Zig"

# Code completion
zeke complete "def factorial(n):"

# Health check
zeke doctor
```

## Upgrade Guide

### From v0.2.x

1. **Backup existing config**:
   ```bash
   cp ~/.config/zeke/config.json ~/.config/zeke/config.json.bak
   ```

2. **Create new TOML config**:
   ```bash
   cp zeke.toml.example ~/.config/zeke/zeke.toml
   # Edit with your settings
   ```

3. **Re-authenticate providers**:
   ```bash
   zeke auth google
   zeke auth github
   ```

4. **Verify installation**:
   ```bash
   zeke --version  # Should show 0.3.0
   zeke doctor     # Check system health
   ```

## Known Issues

- **macOS Support**: Not yet tested, contributions welcome
- **Windows Support**: Planned for v0.4.0
- **Shell Completions**: Not yet implemented (planned for v0.3.1)
- **zdoc Updates**: Documentation generation needs refresh

See [GitHub Issues](https://github.com/ghostkellz/zeke/issues) for full list.

## Deprecations

- **JSON Configuration**: Will be removed in v0.4.0 (migration required)
- **Old OAuth Flow**: Direct localhost callbacks no longer supported

## Future Plans (v0.3.1+)

- **Shell Completions**: Bash, Zsh, Fish support
- **Windows Support**: Native Windows builds
- **Performance Dashboard**: Web UI for metrics
- **Custom Plugins**: Plugin API for extensions
- **Distributed Mode**: Multi-machine deployments

## Community

- **GitHub**: https://github.com/ghostkellz/zeke
- **Issues**: https://github.com/ghostkellz/zeke/issues
- **Email**: ckelley@ghostkellz.sh

## Contributors

Special thanks to all contributors who made this release possible!

- **Architecture**: OAuth broker and MCP integration
- **Documentation**: Comprehensive guides and API reference
- **Testing**: Cross-platform validation and bug fixes

## License

MIT License - See [LICENSE](../LICENSE) for details.

---

**Built with the Ghost Stack** 👻

Powered by: Zig 0.16, zsync, zqlite, phantom, flash, zhttp, grove, rune, ghostlang
