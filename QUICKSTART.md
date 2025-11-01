# Zeke Quick Start Guide
**Get up and running in 5 minutes!**

---

## What is Zeke?

Zeke is a **Zig-native AI development companion** that provides:
- 🤖 Multi-provider AI support (Claude, OpenAI, GitHub Copilot, Ollama, GhostLLM)
- 🔐 **Premium OAuth** - Use your existing Claude Max / Copilot Pro subscriptions
- ⚡ Native performance - 10x faster than Node.js alternatives
- 🛠️ Smart editing tools for code generation and refactoring
- 📋 MCP (Model Context Protocol) support for extensibility

---

## Installation

### Option 1: From Source (Recommended for development)

```bash
# Clone the repository
git clone https://github.com/GhostKellz/zeke
cd zeke

# Build with Zig (requires Zig 0.16.0-dev or later)
zig build

# Install binary
sudo cp zig-out/bin/zeke /usr/local/bin/

# Verify installation
zeke --version
```

### Option 2: Arch Linux (AUR)

```bash
yay -S zeke
# or
paru -S zeke
```

### Option 3: Install Script

```bash
curl -fsSL https://zeke.cktech.org/install.sh | bash
```

---

## Quick Setup (2 minutes)

### 1. Choose Your AI Provider

Zeke supports multiple AI providers. Pick one based on your needs:

#### **Option A: Local AI (Free, Private)** ⭐ Recommended

```bash
# Start Ollama (Docker)
docker run -d --name ollama --network host ollama/ollama

# Pull a coding model
docker exec ollama ollama pull qwen2.5-coder:7b

# Test it
zeke chat "Write a hello world in Zig"
```

#### **Option B: Claude Max (Premium OAuth)** 💎

If you have a **Claude Max subscription** ($20/month), use OAuth:

```bash
# Authenticate with Claude (one-time setup)
zeke auth claude

# Follow the prompts:
# 1. Browser opens to console.anthropic.com
# 2. Login and authorize
# 3. Copy the FULL authorization code (includes # character)
# 4. Paste back in terminal
# 5. Done!

# Test it
zeke chat "Explain async in Zig" --provider anthropic
```

**Savings**: Use your existing Claude Max subscription instead of paying separately for API access!

📚 **[Detailed OAuth Setup Guide →](docs/oauth/README.md)**

#### **Option C: GitHub Copilot (Premium OAuth)** 🚀

If you have a **GitHub Copilot Pro subscription** ($10/month):

```bash
# Authenticate with GitHub (device flow)
zeke auth copilot

# Follow the prompts:
# 1. Terminal shows a code and URL
# 2. Visit https://github.com/login/device
# 3. Enter the code shown
# 4. Authorize the application
# 5. Done!

# Test it
zeke chat "Generate a REST API in Rust" --provider github
```

📚 **[Detailed OAuth Setup Guide →](docs/oauth/README.md)**

#### **Option D: API Keys (Paid, Traditional)**

For OpenAI, Anthropic API, etc.:

```bash
# Set environment variables
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."

# Test it
zeke chat "Hello" --provider openai
```

---

### 2. Verify Installation

Check that everything is working:

```bash
# Run health check
zeke doctor

# Expected output:
# ✅ Ollama is healthy (or your chosen provider)
# ✅ Authentication configured
# ✅ Database accessible
```

---

## Basic Usage

### Chat with AI

```bash
# Simple question
zeke chat "How do I parse JSON in Zig?"

# Specify provider (optional)
zeke chat "Explain async" --provider anthropic

# Stream response
zeke chat "Long explanation..." --stream
```

### Code Generation

```bash
# Generate code
zeke generate function "Calculate fibonacci sequence"

# Generate tests
zeke generate test src/myfile.zig

# Generate from template
zeke new my-api --template rust-axum
```

### Code Analysis

```bash
# Analyze code
zeke analyze src/

# Find issues
zeke doctor --verbose
```

### Authentication Management

```bash
# Check auth status
zeke auth status

# Login with Claude Max
zeke auth claude

# Login with GitHub Copilot
zeke auth copilot

# Logout
zeke auth logout anthropic
```

---

## Advanced Features

### 1. HTTP Server Mode (for Editor Integration)

```bash
# Start server (default port: 7878)
zeke serve

# Custom port
zeke serve --port 8080

# Now your editor can connect via HTTP!
```

### 2. Neovim Integration

```lua
-- In your init.lua
require('zeke').setup({
  server_url = "http://localhost:7878",
  auto_start = true,
})

-- Use in Neovim:
-- :Zeke explain
-- :Zeke refactor
-- :Zeke generate test
```

### 3. File Editing (Smart Edit)

```bash
# Edit a file with AI
zeke edit src/main.zig "add error handling"

# Refactor across multiple files
zeke refactor "rename function parseConfig to loadConfig"

# Preview changes before applying
zeke edit src/main.zig "optimize" --dry-run
```

### 4. Configuration

```bash
# View config
zeke config show

# Set default provider
zeke config set provider ollama

# Edit config file
zeke config edit
```

---

## Troubleshooting

### Ollama not found

```bash
# Check if Ollama is running
docker ps | grep ollama

# Start Ollama
docker start ollama

# Or install Ollama locally
curl -fsSL https://ollama.com/install.sh | sh
```

### OAuth not working

```bash
# Check auth status
zeke auth status

# Re-authenticate
zeke auth claude  # or copilot

# Check system keyring
# Linux: Ensure gnome-keyring or kwallet is installed
# macOS: Uses Keychain (built-in)
# Windows: Uses Credential Manager (built-in)
```

### Permission denied

```bash
# Make sure zeke is executable
chmod +x /usr/local/bin/zeke

# Or run from build directory
./zig-out/bin/zeke
```

---

## Performance Tips

1. **Use Ollama for quick queries** (fastest, free)
2. **Use Claude for complex reasoning** (best quality)
3. **Use GitHub Copilot for code completion** (optimized for code)
4. **Enable caching** for repeated queries

---

## What's Next?

### Learn More
- [Full Documentation](https://zeke.cktech.org/docs)
- [OAuth Authentication Guide](./docs/oauth/README.md)
- [Claude OAuth Setup](./docs/claude/oauth.md)
- [Architecture Overview](./docs/ARCHITECTURE.md)
- [Development Guide](./docs/DEVELOPMENT.md)

### Get Involved
- [GitHub Repository](https://github.com/GhostKellz/zeke)
- [Report Issues](https://github.com/GhostKellz/zeke/issues)
- [Contribute](./CONTRIBUTING.md)
- [Join Community](https://discord.gg/ghostkellz)

### Advanced Topics
- [MCP Integration](./docs/mcp.md)
- [Plugin Development](./docs/plugins.md)
- [Building from Source](./docs/building.md)
- [Architecture Overview](./docs/architecture.md)

---

## Cheat Sheet

```bash
# Quick reference
zeke chat "question"              # Ask AI a question
zeke generate function "desc"     # Generate code
zeke edit file.zig "change"       # Edit file with AI
zeke refactor "change"            # Refactor code
zeke analyze src/                 # Analyze code
zeke serve                        # Start HTTP server
zeke auth claude                  # OAuth login (Claude Max)
zeke auth copilot                 # OAuth login (GitHub Copilot)
zeke auth status                  # Check authentication
zeke doctor                       # System health check
zeke config show                  # View configuration
zeke --help                       # Show all commands
```

---

## Support

Need help? We're here for you:

- 📚 [Documentation](https://zeke.cktech.org/docs)
- 💬 [Discord Community](https://discord.gg/ghostkellz)
- 🐛 [Report Bug](https://github.com/GhostKellz/zeke/issues)
- 📧 Email: support@cktech.org

---

**Ready to code with AI? Start with:**
```bash
zeke chat "Hello, Zeke! What can you do?"
```

Enjoy coding with Zeke! ⚡🤖
