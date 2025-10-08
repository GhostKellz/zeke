# OMEN Docker Stack for Zeke Ecosystem

Complete guide for deploying OMEN using Docker Compose and integrating it with Glyph, Zeke CLI, and zeke.nvim.

## Overview

This guide covers the deployment of OMEN using the Docker Compose stack located in `/data/projects/zeke/omen/`. OMEN provides unified AI model routing for the entire Zeke ecosystem:

- **Zeke CLI** → OMEN → Smart model routing (local Ollama or cloud providers)
- **zeke.nvim** → OMEN → Seamless Neovim AI integration
- **Glyph MCP Server** → OMEN → File operations with AI assistance

### Why Docker?

| Benefit | Description |
|---------|-------------|
| 🚀 **Quick Start** | Full stack running in minutes with `docker compose up` |
| 🔧 **Consistent Environment** | Same setup across dev/staging/production |
| 📦 **Batteries Included** | OMEN + Redis + optional Ollama in one stack |
| 🔄 **Easy Updates** | Pull new images and restart - no rebuild needed |
| 🎯 **Isolation** | Services run in containers without polluting host system |

## Current Status & Known Issues

**OMEN RC1 Status**: ✅ Ready for Zeke Integration (with workaround)

### ✅ What's Working (Production Ready)

| Feature | Status | Notes |
|---------|--------|-------|
| 🏥 Provider Health Checks | ✅ Perfect | 1-100ms latency tracking |
| 📊 Smart Routing Scores | ✅ Perfect | Cost/latency/reliability scoring |
| 🔍 Model Discovery | ✅ Working | 20+ Ollama models + cloud providers |
| 🤝 Ollama Integration | ✅ Perfect | Detects all local models via host network |
| 🌐 Gemini Provider | ✅ Working | 3 models detected |
| 🧠 Claude Provider | ✅ Working | Available for routing |

**This is enough for Zeke integration!** The provider discovery and health scoring (which is what Zeke needs for smart routing) works perfectly.

### ⚠️ Known Issues (OMEN v0.1.1-rc1)

**Issue #1: Chat Completions JSON Parsing Bug** (Non-blocking for Zeke)
- **Symptom**: `/v1/chat/completions` returns `Invalid JSON: data did not match any variant of untagged enum MessageContent`
- **Impact**: Cannot use OMEN's chat completions endpoint
- **Workaround**: Zeke uses OMEN for provider selection, then routes directly to providers for completions
- **Status**: Reported to OMEN team (see `/data/projects/omen/OMEN_DEV_FIX.md`)

**Issue #2: Azure OpenAI Provider Unhealthy**
- **Symptom**: `relative URL without a base` error
- **Impact**: Azure provider not available for routing
- **Workaround**: Use OpenAI, Gemini, or Ollama providers instead
- **Status**: Known bug, being investigated

**Issue #3: OpenAI Health Check Failing**
- **Symptom**: Health check reports unhealthy despite valid API key
- **Impact**: OpenAI models not included in routing decisions
- **Workaround**: Use Gemini or Ollama as cloud/local providers
- **Status**: May be key permissions or rate limiting

### 🎯 Recommended Architecture (Current)

**Hybrid Approach:**
```
Zeke CLI/Neovim
    │
    ├─→ OMEN (GET /omen/providers/scores) ─→ Get provider health scores
    │                                         Decide best model to use
    │
    └─→ Direct to Provider (POST /v1/chat/completions)
        ├─→ Ollama (http://localhost:11434)
        ├─→ Gemini (https://generativelanguage.googleapis.com)
        └─→ Claude (https://api.anthropic.com)
```

**Benefits:**
- ✅ Smart routing based on OMEN's excellent scoring algorithm
- ✅ Bypasses chat completion parsing bug
- ✅ Full control over completion requests
- ✅ Can migrate to full OMEN routing when bug is fixed

See [Integration Patterns](#integration-patterns-workaround) section below for implementation details.

## Prerequisites

```bash
# Required
docker --version          # Docker 24.0+
docker compose version    # Docker Compose v2.20+

# Optional (for local AI)
nvidia-smi               # NVIDIA GPU + drivers for Ollama
```

## Stack Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Zeke Ecosystem                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐     │
│  │   Zeke   │  │  zeke    │  │     Glyph MCP    │     │
│  │   CLI    │  │  .nvim   │  │      Server      │     │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘     │
│       │             │                 │                 │
│       └─────────────┼─────────────────┘                 │
│                     │                                   │
│                     ▼                                   │
│         ╔═══════════════════════════╗                  │
│         ║  OMEN Gateway (Port 8080) ║                  │
│         ║  OpenAI-Compatible API    ║                  │
│         ╚═══════════════════════════╝                  │
│                     │                                   │
│         ┌───────────┼───────────────────────┐          │
│         │           │                       │          │
│         ▼           ▼                       ▼          │
│    ┌────────┐  ┌────────┐            ┌──────────┐     │
│    │ Redis  │  │ Ollama │            │  Cloud   │     │
│    │ Cache  │  │ Local  │            │ Providers│     │
│    └────────┘  │  GPU   │            │(Anthropic│     │
│                └────────┘            │ OpenAI)  │     │
│                                      └──────────┘     │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Set Up Environment

Create an `.env` file in the zeke project root:

```bash
cd /data/projects/zeke

cat > .env <<'EOF'
# Provider API Keys (comment out any you don't use)
ANTHROPIC_API_KEY=sk-ant-api03-xxx
OPENAI_API_KEY=sk-xxx
XAI_API_KEY=xai-xxx
GOOGLE_API_KEY=xxx
# AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
# AZURE_OPENAI_API_KEY=xxx

# Budget Controls
OMEN_BUDGET_MONTHLY_USD=150

# Routing Preferences
OMEN_ROUTER_PREFER_LOCAL_FOR=code,completion,refactor,tests
EOF

chmod 600 .env  # Protect sensitive keys
```

### 2. Review Docker Configuration

The stack configuration is in `omen/docker-compose.yml`:

```bash
cat omen/docker-compose.yml
```

**Key services:**
- `omen`: Main gateway (port 8080)
- `redis`: Caching and rate limiting
- `ollama`: Optional local GPU inference (requires `--profile local-ai`)

### 3. Launch the Stack

**Basic stack (OMEN + Redis only):**
```bash
cd /data/projects/zeke
docker compose -f omen/docker-compose.yml up -d
```

**With local Ollama (requires NVIDIA GPU):**
```bash
docker compose -f omen/docker-compose.yml --profile local-ai up -d
```

**Check status:**
```bash
docker compose -f omen/docker-compose.yml ps
```

### 4. Verify Health

```bash
# Test OMEN health endpoint
curl http://localhost:8080/health | jq

# Expected output:
# {
#   "service": "omen",
#   "version": "0.1.0",
#   "status": "healthy",
#   "providers": ["anthropic", "openai", "ollama"]
# }

# Test readiness
curl http://localhost:8080/ready | jq

# List available models
curl http://localhost:8080/v1/models | jq '.data[].id'
```

### 5. Pull Local Models (if using Ollama)

```bash
# Recommended models for Zeke workloads
docker exec omen-ollama ollama pull deepseek-coder:6.7b
docker exec omen-ollama ollama pull qwen2.5-coder:7b
docker exec omen-ollama ollama pull codellama:13b-instruct

# Verify models
docker exec omen-ollama ollama list
```

## Integration: Zeke CLI

### Configure Zeke

Edit your Zeke configuration to use the OMEN Docker endpoint:

**Option A: Configuration file (`~/.config/zeke/config.json`)**

```json
{
  "services": {
    "omen": {
      "enabled": true,
      "base_url": "http://localhost:8080/v1",
      "api_key": "optional-if-configured",
      "health_check": "/health",
      "health_check_interval_s": 60,
      "timeout_ms": 30000
    }
  },
  "model_aliases": {
    "fast": "deepseek-coder:6.7b",
    "smart": "claude-3-5-sonnet-20241022",
    "local": "qwen2.5-coder:7b",
    "balanced": "auto"
  },
  "routing": {
    "prefer_local": true,
    "fallback_to_cloud": true,
    "max_cloud_cost_cents": 200
  }
}
```

**Option B: Environment variables**

```bash
# Add to ~/.bashrc or ~/.zshrc
export ZEKE_API_BASE="http://localhost:8080/v1"
export ZEKE_API_KEY=""  # Optional
export ZEKE_MODEL="auto"
export ZEKE_INTENT="code"
```

### Usage Examples

```bash
# Code generation (routes to local DeepSeek Coder)
zeke ask "Write a Zig function to parse JSON with error handling"

# Code explanation (uses local CodeLlama)
zeke explain src/main.zig

# Complex refactoring (OMEN decides: local for simple, Claude for complex)
zeke refactor --file src/server.zig --intent "Extract HTTP handlers"

# Use specific model
zeke ask --model "claude-3-5-sonnet-20241022" "Architect a distributed system"

# Use alias
zeke ask --model fast "Generate unit test for this function"
```

### Watch Mode

```bash
# Monitor project and auto-suggest fixes via OMEN
zeke watch --project . --auto-fix

# OMEN automatically routes:
# - Simple syntax fixes → Local Ollama (fast, free)
# - Complex logic issues → Claude (quality)
```

## Integration Patterns (Workaround)

Due to the chat completions parsing bug in OMEN RC1, use this hybrid pattern for production:

### Pattern 1: Smart Routing with Direct Completion

**Step 1: Query OMEN for provider scores**
```bash
# Get current provider health and recommendations
curl http://localhost:8080/omen/providers/scores | jq

# Example response:
# [
#   {
#     "provider_id": "ollama",
#     "provider_name": "Ollama",
#     "overall_score": 99.994,
#     "latency_ms": 1,
#     "recommended": true
#   },
#   {
#     "provider_id": "gemini",
#     "overall_score": 92.5,
#     "latency_ms": 88,
#     "recommended": true
#   }
# ]
```

**Step 2: Select best provider based on intent**
```bash
# For code completion (prefer local + low latency):
PROVIDER="ollama"
MODEL="deepseek-coder:6.7b"

# For reasoning (prefer quality):
PROVIDER="gemini"
MODEL="gemini-1.5-flash"
```

**Step 3: Route directly to provider**
```bash
# To Ollama
curl http://localhost:11434/api/generate \
  -d '{
    "model": "deepseek-coder:6.7b",
    "prompt": "Write a Zig function to parse JSON",
    "stream": false
  }'

# To Gemini (via native API)
curl https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent \
  -H "x-goog-api-key: $GOOGLE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{"text": "Explain this algorithm"}]
    }]
  }'
```

### Pattern 2: Zeke Router Implementation

**In Zeke's Zig code** (`src/router/smart_router.zig`):

```zig
const std = @import("std");
const http = std.http;

pub const SmartRouter = struct {
    allocator: std.mem.Allocator,
    omen_url: []const u8,
    providers: std.StringHashMap(ProviderClient),

    pub fn init(allocator: std.mem.Allocator, omen_url: []const u8) !SmartRouter {
        return SmartRouter{
            .allocator = allocator,
            .omen_url = omen_url,
            .providers = std.StringHashMap(ProviderClient).init(allocator),
        };
    }

    pub fn selectProvider(self: *SmartRouter, intent: []const u8) !ProviderScore {
        // Step 1: Query OMEN for provider scores
        const scores_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/omen/providers/scores",
            .{self.omen_url}
        );
        defer self.allocator.free(scores_url);

        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var buf: [8192]u8 = undefined;
        const uri = try std.Uri.parse(scores_url);
        var req = try client.request(.GET, uri, .{ .allocator = self.allocator }, .{});
        defer req.deinit();

        try req.finish();
        const body = try req.reader().readAll(&buf);

        // Step 2: Parse JSON and find best provider
        const parsed = try std.json.parseFromSlice(
            []ProviderScore,
            self.allocator,
            body,
            .{}
        );
        defer parsed.deinit();

        // Step 3: Apply intent-based filtering
        for (parsed.value) |score| {
            if (std.mem.eql(u8, intent, "code") or std.mem.eql(u8, intent, "completion")) {
                // Prefer local + low latency
                if (score.latency_ms < 100 and score.recommended) {
                    return score;
                }
            } else if (std.mem.eql(u8, intent, "reasoning")) {
                // Prefer quality providers (Gemini, Claude)
                if (score.overall_score > 90 and !std.mem.eql(u8, score.provider_id, "ollama")) {
                    return score;
                }
            }
        }

        // Fallback: use first recommended provider
        for (parsed.value) |score| {
            if (score.recommended) return score;
        }

        return error.NoProvidersAvailable;
    }

    pub fn complete(
        self: *SmartRouter,
        provider: []const u8,
        model: []const u8,
        prompt: []const u8,
    ) ![]const u8 {
        // Route directly to provider, bypassing OMEN's completions endpoint
        if (std.mem.eql(u8, provider, "ollama")) {
            return try self.completeOllama(model, prompt);
        } else if (std.mem.eql(u8, provider, "gemini")) {
            return try self.completeGemini(model, prompt);
        } else {
            return error.UnsupportedProvider;
        }
    }

    fn completeOllama(self: *SmartRouter, model: []const u8, prompt: []const u8) ![]const u8 {
        // Direct Ollama API call
        const url = "http://localhost:11434/api/generate";
        // ... implementation
    }

    fn completeGemini(self: *SmartRouter, model: []const u8, prompt: []const u8) ![]const u8 {
        // Direct Gemini API call
        // ... implementation
    }
};

const ProviderScore = struct {
    provider_id: []const u8,
    provider_name: []const u8,
    overall_score: f64,
    latency_ms: u64,
    recommended: bool,
};
```

### Pattern 3: Configuration for Hybrid Mode

**Update `~/.config/zeke/config.json`:**

```json
{
  "routing": {
    "mode": "hybrid",  // Use OMEN for scoring, direct for completions
    "omen": {
      "enabled": true,
      "scores_endpoint": "http://localhost:8080/omen/providers/scores",
      "health_check": "http://localhost:8080/health",
      "refresh_interval_s": 60
    }
  },

  "providers": {
    "ollama": {
      "enabled": true,
      "endpoint": "http://localhost:11434",
      "models": [
        "deepseek-coder:6.7b",
        "qwen2.5-coder:7b",
        "codellama:13b-instruct"
      ],
      "use_for": ["code", "completion", "tests"]
    },
    "gemini": {
      "enabled": true,
      "api_key": "env:GOOGLE_API_KEY",
      "models": ["gemini-1.5-flash", "gemini-1.5-pro"],
      "use_for": ["reasoning", "architecture"]
    },
    "anthropic": {
      "enabled": true,
      "api_key": "env:ANTHROPIC_API_KEY",
      "models": ["claude-3-5-sonnet-20241022"],
      "use_for": ["reasoning", "complex-refactor"]
    }
  },

  "intent_mapping": {
    "code": { "prefer": "ollama", "max_latency_ms": 200 },
    "completion": { "prefer": "ollama", "max_latency_ms": 150 },
    "tests": { "prefer": "ollama", "max_latency_ms": 300 },
    "reasoning": { "prefer": "gemini", "max_latency_ms": 5000 },
    "architecture": { "prefer": "anthropic", "max_latency_ms": 10000 }
  }
}
```

### Pattern 4: Migration Path (When OMEN Bug is Fixed)

Once OMEN team fixes the MessageContent parsing bug:

**Before (Hybrid):**
```zig
// Step 1: Get scores from OMEN
const score = try router.selectProvider("code");

// Step 2: Route directly to provider
const result = try router.complete(score.provider_id, "deepseek-coder:6.7b", prompt);
```

**After (Full OMEN):**
```zig
// Single request to OMEN - it handles everything
const result = try omenClient.complete(.{
    .model = "auto",  // OMEN chooses based on scores
    .messages = &[_]Message{
        .{ .role = "user", .content = prompt }
    },
});
```

**Migration is simple:** Just change routing mode in config from `"hybrid"` to `"full"`.

### Why This Hybrid Approach Works

| Aspect | Benefit |
|--------|---------|
| 🎯 **Smart Routing** | Leverages OMEN's excellent scoring algorithm |
| ⚡ **Performance** | Direct provider calls avoid proxy overhead |
| 🛡️ **Reliability** | Bypasses parsing bug, no waiting for fix |
| 🔧 **Maintainable** | Easy migration when OMEN bug is fixed |
| 📊 **Observable** | Can monitor OMEN scores + direct provider metrics |

## Integration: zeke.nvim

### Installation

**Using lazy.nvim:**

```lua
-- ~/.config/nvim/lua/plugins/zeke.lua
return {
  "ghostkellz/zeke.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("zeke").setup({
      -- OMEN Docker endpoint
      provider = {
        type = "openai_compatible",
        base_url = "http://localhost:8080/v1",
        api_key = os.getenv("OMEN_API_KEY") or "",
        model = "auto",  -- Let OMEN route intelligently
      },

      -- Completion settings
      completion = {
        enabled = true,
        trigger_chars = { ".", ":", "(", "[", "{" },
        debounce_ms = 150,
        max_lines = 50,  -- Context window
      },

      -- Chat interface
      chat = {
        enabled = true,
        keybind = "<leader>zc",
        model = "smart",  -- Use alias from OMEN
      },

      -- Code actions
      actions = {
        explain = "<leader>ze",
        refactor = "<leader>zr",
        tests = "<leader>zt",
        docs = "<leader>zd",
        fix = "<leader>zf",
      },

      -- OMEN routing hints (helps with model selection)
      tags = {
        intent = "code",
        editor = "neovim",
        source = "zeke.nvim",
      },

      -- Performance tuning
      performance = {
        completion_timeout_ms = 300,  -- Fast completions
        chat_timeout_ms = 30000,
        cache_enabled = true,
      },
    })
  end,
}
```

### Usage in Neovim

```vim
" Inline completion
" Type code, press <Tab> to accept AI suggestion
" OMEN routes to local DeepSeek Coder (fast, sub-200ms)

" Open chat
<leader>zc

" Explain code under cursor
<leader>ze

" Refactor selection
<leader>zr (in visual mode)

" Generate tests
<leader>zt

" Generate documentation
<leader>zd

" Quick fix
<leader>zf
```

### Example Workflow

1. **Coding:** Type code, get inline completions from local Ollama (fast)
2. **Stuck:** Hit `<leader>zc` to open chat, ask Claude for architectural guidance
3. **Refactor:** Select code, hit `<leader>zr`, OMEN routes to appropriate model
4. **Document:** Hit `<leader>zd`, local model generates docstrings

## Integration: Glyph MCP Server

Glyph is an MCP (Model Context Protocol) server that provides file operations and diff tools. It can use OMEN for AI-powered file analysis and transformations.

### Configure Glyph with OMEN

**Option A: Glyph configuration file**

```toml
# ~/.config/glyph/config.toml
[ai]
provider = "openai_compatible"
base_url = "http://localhost:8080/v1"
api_key = ""  # Optional
model = "auto"

[ai.routing_hints]
intent = "code"
source = "glyph"
priority = "low-latency"

[mcp]
transport = "stdio"  # or "websocket"
tools = ["fs.read", "fs.write", "fs.list", "diff.generate", "diff.apply"]
```

**Option B: Environment variables**

```bash
export GLYPH_AI_PROVIDER="openai_compatible"
export GLYPH_AI_BASE_URL="http://localhost:8080/v1"
export GLYPH_AI_MODEL="auto"
```

### Zeke + Glyph + OMEN Stack

Complete configuration for all three working together:

```json
// ~/.config/zeke/config.json
{
  "services": {
    // Glyph MCP server (file operations)
    "glyph": {
      "enabled": true,
      "mcp": {
        "stdio": {
          "command": "/data/projects/glyph/target/release/glyph",
          "args": ["serve", "--transport", "stdio"],
          "env": {
            "GLYPH_AI_PROVIDER": "openai_compatible",
            "GLYPH_AI_BASE_URL": "http://localhost:8080/v1",
            "GLYPH_AI_MODEL": "auto"
          }
        }
      },
      "health_check_interval_s": 30,
      "timeout_ms": 5000
    },

    // OMEN gateway (model routing)
    "omen": {
      "enabled": true,
      "base_url": "http://localhost:8080/v1",
      "health_check": "/health",
      "health_check_interval_s": 60,
      "timeout_ms": 30000
    }
  },

  "model_aliases": {
    "fast": "deepseek-coder:6.7b",
    "smart": "claude-3-5-sonnet-20241022",
    "local": "qwen2.5-coder:7b"
  }
}
```

### Example: AI-Powered File Operations

```bash
# Zeke spawns Glyph, which uses OMEN for AI
zeke serve --verbose

# In another terminal:
# Glyph reads file, uses OMEN to analyze and suggest improvements
zeke ask "Analyze src/main.zig and suggest performance improvements"

# Glyph generates diff, uses OMEN to validate changes
zeke edit "Refactor allocator usage in src/memory.zig"
```

## Advanced Configuration

### Custom OMEN Routing Rules

Create `omen/omen.toml` and mount it in docker-compose:

```toml
# omen/omen.toml
[routing]
prefer_local_for = ["code", "completion", "refactor", "tests"]
fallback_to_cloud = true
honor_model_requests = true

# Intent-specific routing
[routing.intents.completion]
primary_provider = "ollama"
model = "deepseek-coder:6.7b"
timeout_ms = 300
no_fallback = true

[routing.intents.code]
primary_provider = "ollama"
fallback_providers = ["anthropic", "openai"]
max_tokens_local = 4096

[routing.intents.refactor]
complexity_threshold = "medium"
simple_provider = "ollama"
simple_model = "qwen2.5-coder:7b"
complex_provider = "anthropic"
complex_model = "claude-3-5-sonnet-20241022"

[routing.intents.architecture]
primary_provider = "anthropic"
model = "claude-3-5-sonnet-20241022"
no_local = true

# Provider-specific settings
[providers.ollama]
endpoints = ["http://ollama:11434"]
models = [
    "deepseek-coder:6.7b",
    "qwen2.5-coder:7b",
    "codellama:13b-instruct"
]
priority = 100
timeout_ms = 5000

[providers.anthropic]
api_key = "env:ANTHROPIC_API_KEY"
models = ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
priority = 50
max_rpm = 50

[providers.openai]
api_key = "env:OPENAI_API_KEY"
models = ["gpt-4o", "gpt-4o-mini"]
priority = 40
max_rpm = 60

# Caching
[cache]
enabled = true
backend = "redis"
redis_url = "redis://redis:6379"
ttl_seconds = 3600
completion_ttl = 7200  # Cache completions longer

# Performance
[performance]
max_connections_per_provider = 100
keepalive = true
connection_timeout_ms = 2000
tcp_nodelay = true
```

**Mount in docker-compose:**

```yaml
# omen/docker-compose.yml (add to omen service volumes)
volumes:
  - omen_data:/app/data
  - ./omen.toml:/app/omen.toml:ro  # Add this line
```

### GPU Optimization for Ollama

```yaml
# omen/docker-compose.yml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: omen-ollama
    restart: unless-stopped
    environment:
      # Parallel request handling
      OLLAMA_NUM_PARALLEL: "4"
      OLLAMA_MAX_LOADED_MODELS: "3"

      # Keep models in VRAM for fast responses
      OLLAMA_KEEP_ALIVE: "30m"

      # GPU memory management
      OLLAMA_MAX_VRAM: "16GB"  # Adjust for your GPU

      # Performance tuning
      OLLAMA_FLASH_ATTENTION: "true"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all  # or "1" for single GPU
              capabilities: [gpu]
```

**Preload models into memory:**

```bash
# After pulling models, keep them loaded
docker exec omen-ollama ollama run deepseek-coder:6.7b ""
docker exec omen-ollama ollama run qwen2.5-coder:7b ""
docker exec omen-ollama ollama run codellama:13b-instruct ""

# These stay in VRAM for 30 minutes (OLLAMA_KEEP_ALIVE)
```

## Monitoring & Debugging

### View Logs

```bash
# All services
docker compose -f omen/docker-compose.yml logs -f

# Specific service
docker compose -f omen/docker-compose.yml logs -f omen
docker compose -f omen/docker-compose.yml logs -f ollama

# Last 100 lines
docker compose -f omen/docker-compose.yml logs --tail 100 omen
```

### Check Metrics

```bash
# Provider health and scores
curl http://localhost:8080/omen/providers/scores | jq

# Request statistics
curl http://localhost:8080/omen/stats | jq

# Cache statistics (if Redis enabled)
docker exec omen-redis redis-cli INFO stats
```

### Debug Mode

```bash
# Enable verbose logging
docker compose -f omen/docker-compose.yml down

# Edit docker-compose.yml, add to omen service:
#   environment:
#     RUST_LOG: "debug"
#     OMEN_LOG_LEVEL: "debug"

docker compose -f omen/docker-compose.yml up -d
docker compose -f omen/docker-compose.yml logs -f omen
```

### Test Script

Use the included test script:

```bash
cd /data/projects/zeke/omen
./test_docker.sh

# Expected output:
# 🧪 Testing OMEN Docker Stack...
# 📦 Building Docker image...
# ✅ Build successful
# 🚀 Starting stack...
# 🔍 Testing endpoints...
# ✅ All tests passed! OMEN is ready for Zeke integration.
```

## Troubleshooting

### Issue: Slow Completions

**Symptoms:** Inline completions take >500ms

**Solutions:**

1. **Ensure local models are loaded:**
   ```bash
   docker exec omen-ollama ollama list
   # If not loaded, run:
   docker exec omen-ollama ollama run deepseek-coder:6.7b ""
   ```

2. **Check routing is using Ollama:**
   ```bash
   curl http://localhost:8080/omen/providers/scores | jq
   # Ollama should have high score for code intents
   ```

3. **Reduce completion timeout:**
   ```json
   // zeke.nvim config
   {
     "performance": {
       "completion_timeout_ms": 200
     }
   }
   ```

4. **Enable aggressive caching:**
   ```toml
   # omen.toml
   [cache]
   enabled = true
   completion_ttl = 7200
   ```

### Issue: Wrong Model Selected

**Symptoms:** OMEN routes to expensive cloud model for simple tasks

**Solutions:**

1. **Check routing rules:**
   ```bash
   cat omen/omen.toml | grep prefer_local_for
   ```

2. **Force specific model for testing:**
   ```bash
   zeke ask --model "deepseek-coder:6.7b" "Write a function"
   ```

3. **Update routing hints:**
   ```json
   {
     "tags": {
       "intent": "code",
       "complexity": "simple",
       "prefer_local": true
     }
   }
   ```

### Issue: High Cloud Costs

**Symptoms:** Unexpected charges from Anthropic/OpenAI

**Solutions:**

1. **Check which requests went to cloud:**
   ```bash
   curl http://localhost:8080/omen/stats | jq '.provider_usage'
   ```

2. **Enable budget limits:**
   ```bash
   # .env file
   OMEN_BUDGET_MONTHLY_USD=50
   OMEN_SOFT_LIMIT_ANTHROPIC=30
   OMEN_SOFT_LIMIT_OPENAI=20
   ```

3. **Force local-only mode:**
   ```toml
   # omen.toml
   [routing]
   prefer_local_for = ["*"]  # Route everything to Ollama
   fallback_to_cloud = false  # Never use cloud
   ```

### Issue: Docker Compose Won't Start

**Symptoms:** `docker compose up` fails

**Solutions:**

1. **Check Docker daemon:**
   ```bash
   docker ps
   ```

2. **Check port conflicts:**
   ```bash
   sudo lsof -i :8080
   sudo lsof -i :11434
   ```

3. **Check .env file:**
   ```bash
   cat .env | grep -v "^#"
   # Should show at least one API key
   ```

4. **Check logs:**
   ```bash
   docker compose -f omen/docker-compose.yml logs
   ```

### Issue: Ollama GPU Not Detected

**Symptoms:** Ollama running on CPU

**Solutions:**

1. **Verify NVIDIA drivers:**
   ```bash
   nvidia-smi
   ```

2. **Check Docker GPU support:**
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
   ```

3. **Install nvidia-container-toolkit:**
   ```bash
   sudo apt-get install -y nvidia-container-toolkit
   sudo systemctl restart docker
   ```

## Production Deployment

### Persistent Data

The stack uses named volumes for persistence:

```yaml
volumes:
  omen_data:      # Database, logs
  redis_data:     # Cache
  ollama_data:    # Model files (~15GB per model)
```

**Backup volumes:**

```bash
# Create backup directory
mkdir -p /data/backups/omen

# Backup database
docker run --rm \
  -v omen_data:/data \
  -v /data/backups/omen:/backup \
  alpine tar czf /backup/omen-db-$(date +%Y%m%d).tar.gz /data

# Backup Ollama models
docker run --rm \
  -v ollama_data:/data \
  -v /data/backups/omen:/backup \
  alpine tar czf /backup/ollama-models-$(date +%Y%m%d).tar.gz /data
```

### External Access

**Option A: Reverse Proxy (Recommended)**

```nginx
# /etc/nginx/sites-available/omen
server {
    listen 443 ssl http2;
    server_name omen.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/omen.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/omen.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts for long-running requests
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
```

**Option B: Direct Exposure**

```yaml
# docker-compose.yml (modify ports)
services:
  omen:
    ports:
      - "0.0.0.0:8080:8080"  # Expose to network
```

⚠️ **Security:** Add authentication, rate limiting, and TLS!

### Multi-Node Ollama

Run Ollama on multiple GPU nodes:

```yaml
# docker-compose.yml
services:
  omen:
    environment:
      # Multiple Ollama endpoints
      OMEN_OLLAMA_ENDPOINTS: "http://gpu1.local:11434,http://gpu2.local:11434,http://gpu3.local:11434"
```

OMEN load balances across all endpoints.

## Best Practices

### 1. Preload Models

```bash
# Add to startup script
docker exec omen-ollama ollama pull deepseek-coder:6.7b
docker exec omen-ollama ollama run deepseek-coder:6.7b ""
```

### 2. Monitor Costs

```bash
# Daily cost check
curl http://localhost:8080/omen/stats | jq '.costs'

# Set alerts
OMEN_BUDGET_ALERT_THRESHOLD_USD=10
OMEN_BUDGET_ALERT_WEBHOOK=https://hooks.slack.com/...
```

### 3. Use Caching

```toml
[cache]
enabled = true
completion_ttl = 7200  # Completions are repetitive
chat_ttl = 3600
```

### 4. Tag Requests

```bash
# Help OMEN route better
zeke ask --tag intent:code --tag complexity:simple "..."
```

### 5. Use Model Aliases

```json
{
  "model_aliases": {
    "fast": "deepseek-coder:6.7b",
    "smart": "claude-3-5-sonnet-20241022"
  }
}
```

Then use: `zeke ask --model fast "..."`

### 6. Health Check Automation

```bash
# Add to cron
*/5 * * * * curl -f http://localhost:8080/health || systemctl restart docker-compose@omen
```

## Migration from Existing Setup

### From Direct Provider Calls

**Before:**
```json
{
  "anthropic": {
    "api_key": "sk-ant-xxx",
    "base_url": "https://api.anthropic.com"
  },
  "openai": {
    "api_key": "sk-xxx",
    "base_url": "https://api.openai.com/v1"
  }
}
```

**After:**
```json
{
  "omen": {
    "base_url": "http://localhost:8080/v1",
    "model": "auto"
  }
}
```

Benefits: One endpoint, smart routing, cost controls.

### From Standalone Ollama

**Before:**
```bash
ollama run deepseek-coder:6.7b
curl http://localhost:11434/api/generate
```

**After:**
```bash
docker compose -f omen/docker-compose.yml --profile local-ai up -d
curl http://localhost:8080/v1/chat/completions
```

Benefits: Unified API, fallback to cloud, usage tracking.

## Next Steps

1. **Start the stack:** `docker compose -f omen/docker-compose.yml up -d`
2. **Pull models:** `docker exec omen-ollama ollama pull deepseek-coder:6.7b`
3. **Configure Zeke:** Update `~/.config/zeke/config.json`
4. **Test integration:** `zeke ask "test message"`
5. **Install zeke.nvim:** Follow Neovim configuration above
6. **Monitor costs:** `curl http://localhost:8080/omen/stats`

## Resources

- [OMEN Repository](https://github.com/ghostkellz/omen)
- [Zeke Repository](https://github.com/ghostkellz/zeke)
- [Glyph Repository](https://github.com/ghostkellz/glyph)
- [OMEN Integration Guide](../OMEN_INTEGRATION.md)
- [Glyph Integration Guide](../GLYPH_INTEGRATION.md)
- [Ollama Documentation](https://ollama.ai/docs)

## Getting Help

**Check logs:**
```bash
docker compose -f omen/docker-compose.yml logs -f omen
```

**Run diagnostics:**
```bash
zeke doctor  # Check Zeke configuration
./omen/test_docker.sh  # Test OMEN stack
```

**Common issues:** See [Troubleshooting](#troubleshooting) section above.

---

**Built with the Ghost Stack**

⚡ **Zig** • 🦀 **Rust** • 🐳 **Docker** • 🤖 **AI-Powered**
