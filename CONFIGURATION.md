# Zeke Configuration Guide

Complete guide for configuring Zeke AI development assistant.

---

## 📁 Configuration Locations

### Primary Configuration
- **Config File**: `~/.config/zeke/zeke.toml` (auto-created)
- **Credentials**: `~/.config/zeke/credentials.json` (encrypted, 0600 permissions)
- **Storage**: `~/.local/share/zeke/zeke_data.db`

### Environment Variables
All configuration can be overridden via environment variables (see below).

---

## 🔑 API Key Configuration

### Quick Setup (Recommended)

```bash
# Anthropic Claude (best for code)
zeke auth anthropic sk-ant-api-key-here

# OpenAI GPT
zeke auth openai sk-proj-api-key-here

# xAI Grok
zeke auth xai xai-api-key-here

# Azure OpenAI
zeke auth azure your-azure-api-key

# Ollama (no auth needed - works out of the box!)
# Just make sure Ollama is running: ollama serve
```

### Environment Variables (Alternative)

```bash
# API Keys
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-proj-..."
export XAI_API_KEY="xai-..."
export AZURE_OPENAI_API_KEY="..."
```

### Verify Authentication

```bash
# Test specific provider
zeke auth test anthropic
zeke auth test openai
zeke auth test xai

# List configured providers
zeke auth list
```

---

## 🌐 Provider Endpoints

### Default Endpoints

| Provider | Default Endpoint |
|----------|-----------------|
| Claude | `https://api.anthropic.com` |
| OpenAI | `https://api.openai.com` |
| xAI | `https://api.x.ai` |
| Azure | `https://YOUR_RESOURCE.openai.azure.com` |
| Ollama | `http://localhost:11434` |

### Custom Endpoints (Environment Variables)

```bash
# Override provider endpoints
export ZEKE_CLAUDE_ENDPOINT="https://api.anthropic.com"
export ZEKE_OPENAI_ENDPOINT="https://api.openai.com"
export ZEKE_XAI_ENDPOINT="https://api.x.ai"
export ZEKE_OLLAMA_ENDPOINT="http://localhost:11434"

# For Docker Ollama
export ZEKE_OLLAMA_ENDPOINT="http://localhost:11434"
# OR with custom port
export ZEKE_OLLAMA_ENDPOINT="http://192.168.1.100:11434"
# OR Docker container IP
export ZEKE_OLLAMA_ENDPOINT="http://172.17.0.2:11434"
```

---

## 🐳 Ollama with Docker

### Option 1: Docker Host Network (Recommended)

```bash
# Run Ollama in Docker with host network
docker run -d \
  --name ollama \
  --network host \
  -v ollama:/root/.ollama \
  ollama/ollama

# Zeke will connect to http://localhost:11434 automatically
zeke chat "hello"
```

### Option 2: Port Mapping

```bash
# Run Ollama with port mapping
docker run -d \
  --name ollama \
  -p 11434:11434 \
  -v ollama:/root/.ollama \
  ollama/ollama

# No configuration needed - Zeke uses localhost:11434 by default
zeke chat "hello"
```

### Option 3: Custom Network/IP

```bash
# Find your Docker container IP
docker inspect ollama | grep IPAddress

# Set custom endpoint
export ZEKE_OLLAMA_ENDPOINT="http://172.17.0.2:11434"
zeke chat "hello"
```

### Pull Models in Docker

```bash
# Pull models inside Ollama container
docker exec -it ollama ollama pull llama3.2:3b
docker exec -it ollama ollama pull qwen2.5-coder:7b
docker exec -it ollama ollama pull codellama

# List available models
docker exec -it ollama ollama list
```

---

## ☁️ Azure OpenAI Configuration

Azure requires additional configuration beyond just the API key.

### Method 1: Environment Variables (Recommended)

```bash
export AZURE_OPENAI_API_KEY="your-api-key"
export AZURE_OPENAI_RESOURCE_NAME="your-resource-name"
export AZURE_OPENAI_DEPLOYMENT_NAME="your-deployment"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"

# Optional: API version (defaults to 2024-02-15-preview)
export AZURE_OPENAI_API_VERSION="2024-02-15-preview"
```

### Method 2: Config File

Edit `~/.config/zeke/zeke.toml`:

```toml
[endpoints]
azure = "https://your-resource.openai.azure.com"
azure_resource_name = "your-resource-name"
azure_deployment_name = "gpt-4-deployment"
azure_api_version = "2024-02-15-preview"
```

### Finding Your Azure Values

- **Resource Name**: From Azure portal → Your OpenAI resource → Overview
- **Deployment Name**: From Azure portal → Your OpenAI resource → Deployments
- **Endpoint**: `https://<resource-name>.openai.azure.com`
- **API Key**: From Azure portal → Your OpenAI resource → Keys and Endpoint

---

## 🔌 MCP (Model Context Protocol) Configuration

Zeke supports MCP servers via three transport methods:

### 1. Stdio Transport (Default)

```bash
# Environment variable
export ZEKE_MCP_COMMAND="/path/to/mcp-server"

# In config file
[services.glyph]
enabled = true
mcp_transport = "stdio"
mcp_command = "/usr/local/bin/mcp-server"
```

### 2. WebSocket Transport

```bash
# Environment variable
export ZEKE_MCP_WS="ws://localhost:8080/mcp"

# In config file
[services.glyph]
enabled = true
mcp_transport = "websocket"
mcp_url = "ws://localhost:8080/mcp"
```

### 3. Docker Transport (NEW!)

```bash
# Environment variable
export ZEKE_MCP_DOCKER_CONTAINER="mcp-server-container"

# In config file
[services.glyph]
enabled = true
mcp_transport = "docker"
docker_container = "mcp-server-container"
docker_command = "/app/mcp-server"
```

### Docker MCP Example

```bash
# Run MCP server in Docker
docker run -d \
  --name mcp-server \
  -v $(pwd):/workspace \
  your-mcp-image

# Configure Zeke to use it
export ZEKE_MCP_DOCKER_CONTAINER="mcp-server"

# Zeke will execute commands via:
# docker exec mcp-server /app/mcp-server <args>
```

---

## 🎯 Model Configuration

### Available Models

#### Claude 4.5 (Anthropic)
- `claude-sonnet-4.5` - Best balance of speed/quality
- `claude-opus-4.5` - Most capable, slower
- `claude-haiku-4.5` - Fastest, cheapest

#### OpenAI
- `gpt-4-turbo` - Latest GPT-4
- `gpt-3.5-turbo` - Fast and affordable

#### xAI Grok
- `grok-2-latest` - Latest Grok-2
- `grok-2-1212` - December 2024 release
- `grok-2-vision-1212` - With vision capabilities
- `grok-beta` - Beta features

#### Ollama (Local)
- `llama3.2:3b` - Fast local model
- `qwen2.5-coder:7b` - Code-focused
- Any model from `ollama list`

### Model Aliases

Use simple aliases instead of full model names:

```bash
# Smart (claude-opus-4.5)
zeke chat --model smart "complex problem"

# Balanced (claude-sonnet-4.5)
zeke chat --model balanced "normal question"

# Fast (claude-haiku-4.5)
zeke chat --model fast "quick question"

# Local (qwen2.5-coder:7b via Ollama)
zeke chat --model local "offline coding"
```

---

## 📝 Example Configurations

### Minimal (Ollama Only)

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model
ollama pull qwen2.5-coder:7b

# Use Zeke immediately - no config needed!
zeke chat "write a hello world in Zig"
```

### Professional Setup (All Providers)

```bash
# Set up API keys
zeke auth anthropic $ANTHROPIC_API_KEY
zeke auth openai $OPENAI_API_KEY
zeke auth xai $XAI_API_KEY

# Configure Ollama (Docker)
docker run -d --name ollama --network host -v ollama:/root/.ollama ollama/ollama
docker exec -it ollama ollama pull qwen2.5-coder:7b

# Verify all providers
zeke provider status
```

### Docker + MCP Setup

```bash
# Ollama in Docker
docker run -d \
  --name ollama \
  --network host \
  -v ollama:/root/.ollama \
  ollama/ollama

# MCP server in Docker
docker run -d \
  --name mcp-server \
  -v $(pwd):/workspace \
  mcp-server-image

# Configure Zeke
export ZEKE_OLLAMA_ENDPOINT="http://localhost:11434"
export ZEKE_MCP_DOCKER_CONTAINER="mcp-server"

# Use it!
zeke chat "analyze this codebase"
```

---

## ⚙️ Advanced Configuration

### Provider Priorities

Edit `~/.config/zeke/zeke.toml`:

```toml
[providers]
default_provider = "ollama"  # Start with Ollama
fallback_enabled = true
auto_switch_on_failure = true
preferred_providers = ["claude", "openai", "xai", "ollama"]
```

### Streaming Configuration

```toml
[streaming]
enabled = true
chunk_size = 4096
timeout_ms = 30000
enable_websocket = true
websocket_port = 8081
```

### Logging

```bash
# Environment variables
export ZEKE_LOG_LEVEL="debug"  # debug, info, warn, err
export ZEKE_LOG_REQUESTS="true"

# In config file
log_level = "debug"
log_requests = true
log_file = "/tmp/zeke.log"
```

---

## 🔍 Troubleshooting

### Ollama Not Found

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# If using Docker
docker ps | grep ollama
docker logs ollama

# Check endpoint configuration
echo $ZEKE_OLLAMA_ENDPOINT
```

### API Key Issues

```bash
# Verify credentials file exists
cat ~/.config/zeke/credentials.json

# Test authentication
zeke auth test anthropic
zeke auth test openai

# Re-authenticate
zeke auth anthropic sk-ant-new-key
```

### Azure Connection Issues

```bash
# Verify Azure configuration
echo $AZURE_OPENAI_RESOURCE_NAME
echo $AZURE_OPENAI_DEPLOYMENT_NAME
echo $AZURE_OPENAI_ENDPOINT

# Test Azure endpoint manually
curl -X POST "$AZURE_OPENAI_ENDPOINT/openai/deployments/$AZURE_OPENAI_DEPLOYMENT_NAME/chat/completions?api-version=2024-02-15-preview" \
  -H "api-key: $AZURE_OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"test"}]}'
```

### Docker MCP Issues

```bash
# Verify container is running
docker ps | grep mcp

# Test manual execution
docker exec mcp-server /app/mcp-server --version

# Check Zeke logs
ZEKE_LOG_LEVEL=debug zeke chat "test"
```

---

## 📚 Quick Reference

### Environment Variables Summary

```bash
# API Keys
ANTHROPIC_API_KEY       # Claude API key
OPENAI_API_KEY          # OpenAI API key
XAI_API_KEY             # xAI/Grok API key
AZURE_OPENAI_API_KEY    # Azure OpenAI key

# Endpoints
ZEKE_OLLAMA_ENDPOINT    # Ollama URL (default: http://localhost:11434)
ZEKE_CLAUDE_ENDPOINT    # Claude endpoint
ZEKE_OPENAI_ENDPOINT    # OpenAI endpoint
ZEKE_XAI_ENDPOINT       # xAI endpoint

# Azure
AZURE_OPENAI_ENDPOINT         # Azure endpoint
AZURE_OPENAI_RESOURCE_NAME    # Azure resource
AZURE_OPENAI_DEPLOYMENT_NAME  # Azure deployment
AZURE_OPENAI_API_VERSION      # API version

# MCP
ZEKE_MCP_COMMAND              # MCP stdio command
ZEKE_MCP_WS                   # MCP WebSocket URL
ZEKE_MCP_DOCKER_CONTAINER     # MCP Docker container

# Features
ZEKE_LOG_LEVEL                # debug|info|warn|err
ZEKE_STREAMING_ENABLED        # true|false
```

---

## 🎉 You're All Set!

Start using Zeke:

```bash
# Use default provider (Ollama - no config needed!)
zeke chat "hello"

# Specific provider
zeke chat --provider claude "complex coding task"
zeke chat --provider xai "research question"

# Check system status
zeke doctor
zeke provider status
```

Need help? Run `zeke --help` or check the [main README](README.md).
