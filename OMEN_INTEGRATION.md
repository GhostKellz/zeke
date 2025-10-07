# Zeke + OMEN Integration Guide

Comprehensive guide for integrating [Zeke](https://github.com/ghostkellz/zeke) - the lightning-fast AI development companion built in Zig - with OMEN's intelligent model routing and provider management.

## Overview

**Zeke** is a cutting-edge AI-powered development companion written in Zig v0.16 that provides:
- Multi-provider AI integration (Copilot, OpenAI, Claude, Ollama, Gemini)
- Inline code completion and chat interfaces
- Real-time file watching with AST analysis
- Intelligent TODO tracking and code actions

**OMEN** enhances Zeke by providing:
- Smart model routing based on intent and cost
- Unified API across all providers
- Usage quotas and budget controls
- Local Ollama integration for fast, cost-free inference

Together, they create a powerful, cost-effective, and lightning-fast AI coding experience.

## Why Integrate Zeke with OMEN?

| Benefit | Description |
|---------|-------------|
| 🚀 **Performance** | Zig's native speed + OMEN's smart routing = sub-100ms AI responses |
| 💰 **Cost Optimization** | OMEN routes code tasks to local Ollama, reasoning to Claude/GPT |
| 🧠 **Intelligent Routing** | Automatic model selection based on task type (code, refactor, explain) |
| 🔌 **Simplified Config** | Single OMEN endpoint replaces multiple provider configurations |
| 📊 **Usage Tracking** | Centralized monitoring of all AI requests and costs |
| 🏠 **Homelab Ready** | Leverage local GPUs (4090/3070) via Ollama for privacy and speed |

## Quick Start

### 1. Configure Zeke to Use OMEN

Update your Zeke configuration to point to OMEN:

```zig
// ~/.config/zeke/config.zig or zeke.toml equivalent
const ZekeConfig = struct {
    provider: ProviderConfig = .{
        .type = .openai_compatible,
        .base_url = "http://localhost:8080/v1",  // OMEN endpoint
        .api_key = "your-omen-api-key",
        .model = "auto",  // Let OMEN choose optimal model
    },

    // Optional: Tag requests for better routing
    default_tags: ?TagConfig = .{
        .intent = "code",
        .project = "my-project",
        .priority = "low-latency",
    },
};
```

Or via environment variables:

```bash
# ~/.bashrc or ~/.zshrc
export ZEKE_API_BASE="http://localhost:8080/v1"
export ZEKE_API_KEY="your-omen-api-key"
export ZEKE_MODEL="auto"
export ZEKE_INTENT="code"  # Hint for OMEN routing
```

### 2. Configure OMEN for Zeke Workloads

Optimize OMEN for typical Zeke usage patterns:

```toml
# omen.toml
[routing]
# Prefer local models for Zeke's high-frequency requests
prefer_local_for = ["code", "completion", "refactor", "tests"]
fallback_to_cloud = true  # Use Claude/GPT for complex reasoning

[providers.ollama]
endpoints = ["http://localhost:11434", "http://gpu-node:11434"]
models = [
    "deepseek-coder:6.7b",     # Best for code completion
    "codellama:13b-instruct",  # Code explanation
    "qwen2.5-coder:7b",        # Refactoring
]
priority = 100  # Try local first

[providers.anthropic]
api_key = "env:ANTHROPIC_API_KEY"
models = ["claude-3-5-sonnet-20241022"]
use_for = ["reason", "architecture", "complex-refactor"]
priority = 50

[providers.openai]
api_key = "env:OPENAI_API_KEY"
models = ["gpt-4-turbo-preview"]
use_for = ["reason", "documentation"]
priority = 40

[cache]
enabled = true
backend = "redis"
ttl_seconds = 3600  # Cache completions for 1 hour
```

### 3. Launch the Stack

```bash
# Start OMEN
docker compose up -d omen redis

# Or run OMEN natively
cargo run --release --bin omen

# Pull recommended Ollama models
ollama pull deepseek-coder:6.7b
ollama pull codellama:13b-instruct
ollama pull qwen2.5-coder:7b

# Test Zeke → OMEN connection
zeke --check-connection
# or
curl http://localhost:8080/health
```

## Usage Examples

### CLI: Code Generation

```bash
# Zeke routes through OMEN for optimal model selection
zeke ask "Write a Zig function to parse JSON with error handling"

# OMEN routes to DeepSeek Coder (local, fast, free)
```

### CLI: Code Explanation

```bash
# Explain complex code
zeke explain src/parser.zig

# OMEN uses CodeLlama for local explanation
```

### CLI: Refactoring

```bash
# Refactor with context awareness
zeke refactor --file src/server.zig --intent "Extract HTTP handlers"

# OMEN assesses complexity:
# - Simple: Local Qwen2.5-Coder
# - Complex: Claude 3.5 Sonnet
```

### Watch Mode: Real-time Assistance

```bash
# Start Zeke watch mode with OMEN backend
zeke watch --project my-zig-app

# Monitors file changes, runs AST analysis
# Auto-suggests fixes via OMEN
# Routes to local models for speed
```

### Neovim Plugin Integration

```lua
-- ~/.config/nvim/lua/plugins/zeke.lua
return {
  "ghostkellz/zeke.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("zeke").setup({
      provider = {
        type = "openai_compatible",
        base_url = "http://localhost:8080/v1",  -- OMEN
        api_key = os.getenv("OMEN_API_KEY"),
        model = "auto",
      },

      -- Zeke-specific settings
      completion = {
        enabled = true,
        trigger_chars = { ".", ":", "(", "[" },
        debounce_ms = 150,
      },

      chat = {
        enabled = true,
        keybind = "<leader>zc",
      },

      actions = {
        explain = "<leader>ze",
        refactor = "<leader>zr",
        tests = "<leader>zt",
        docs = "<leader>zd",
      },

      -- OMEN routing hints
      tags = {
        intent = "code",
        editor = "neovim",
        language = "zig",  -- Auto-detected
      },
    })
  end,
}
```

### Inline Completion

```zig
// Type code, Zeke suggests completions via OMEN
const std = @import("std");

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // <Tab> - Zeke/OMEN completes with DeepSeek Coder (local)
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_size = 10 * 1024 * 1024; // 10MB
    return try file.readToEndAlloc(allocator, max_size);
}
```

## Advanced Integration

### Intent-Based Routing

Configure OMEN to route Zeke requests based on task complexity:

```toml
# omen.toml
[routing.intents.code]
primary_provider = "ollama"
fallback_providers = ["anthropic", "openai"]
max_tokens_local = 2048  # Use local if response < 2K tokens

[routing.intents.completion]
primary_provider = "ollama"
model = "deepseek-coder:6.7b"
timeout_ms = 500  # Fast completions only
no_fallback = true  # Never wait for cloud

[routing.intents.refactor]
complexity_threshold = "medium"
simple_provider = "ollama"  # qwen2.5-coder
complex_provider = "anthropic"  # claude-3.5-sonnet

[routing.intents.architecture]
primary_provider = "anthropic"  # Always use Claude for architecture
model = "claude-3-5-sonnet-20241022"

[routing.intents.tests]
primary_provider = "ollama"
model = "codellama:13b-instruct"
fallback_providers = ["anthropic"]
```

### Zig FFI Integration (Advanced)

Call OMEN directly from Zeke's Zig code:

```zig
// zeke/src/omen_client.zig
const std = @import("std");
const http = std.http;

pub const OmenClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,
    client: http.Client,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, api_key: []const u8) !OmenClient {
        return OmenClient{
            .allocator = allocator,
            .base_url = base_url,
            .api_key = api_key,
            .client = http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *OmenClient) void {
        self.client.deinit();
    }

    pub fn complete(
        self: *OmenClient,
        prompt: []const u8,
        tags: ?CompletionTags,
    ) ![]const u8 {
        var buf: [4096]u8 = undefined;
        const url = try std.fmt.bufPrint(&buf, "{s}/v1/chat/completions", .{self.base_url});

        const payload = try std.json.stringifyAlloc(self.allocator, .{
            .model = "auto",
            .messages = &[_]Message{
                .{ .role = "user", .content = prompt },
            },
            .stream = false,
            .tags = tags orelse .{
                .intent = "code",
                .source = "zeke",
            },
        }, .{});
        defer self.allocator.free(payload);

        var req = try self.client.request(.POST, try std.Uri.parse(url), .{
            .allocator = self.allocator,
            .extra_headers = &[_]http.Header{
                .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }, .{});
        defer req.deinit();

        try req.writer().writeAll(payload);
        try req.finish();

        var response_buf = std.ArrayList(u8).init(self.allocator);
        try req.reader().readAllArrayList(&response_buf, 1024 * 1024);

        return response_buf.toOwnedSlice();
    }
};

const Message = struct {
    role: []const u8,
    content: []const u8,
};

const CompletionTags = struct {
    intent: []const u8 = "code",
    source: []const u8 = "zeke",
    language: ?[]const u8 = null,
    complexity: ?[]const u8 = null,
};
```

### Multi-Model Strategy

Use different models for different Zeke features:

```bash
# Completions: Fast local model
ZEKE_COMPLETION_MODEL="deepseek-coder:6.7b"

# Chat: Balanced cloud model
ZEKE_CHAT_MODEL="auto"  # Let OMEN decide

# Refactor: High-quality model
ZEKE_REFACTOR_MODEL="claude-3-5-sonnet-20241022"

# Tests: Specialized model
ZEKE_TEST_MODEL="codellama:13b-instruct"
```

Update OMEN to respect model hints:

```toml
[routing]
honor_model_requests = true  # Use requested model if available
fallback_to_auto = true  # Fall back to auto-routing if unavailable
```

## Performance Optimization

### Latency Targets

Configure OMEN for Zeke's performance requirements:

```toml
[performance]
# Inline completion must be fast
completion_timeout_ms = 300
completion_max_latency_ms = 200

# Chat can be slower for quality
chat_timeout_ms = 30000
chat_prefer_quality = true

# Refactor needs balance
refactor_timeout_ms = 15000
refactor_prefer_local = true

[cache]
# Aggressive caching for repeated patterns
enabled = true
completion_ttl = 7200  # 2 hours
chat_ttl = 3600       # 1 hour
```

### Connection Pooling

```toml
[http]
max_connections_per_provider = 100
keepalive = true
connection_timeout_ms = 2000
tcp_nodelay = true  # Low latency for Zeke
```

### Local Ollama Optimization

```bash
# Run Ollama with optimizations for Zeke workloads
OLLAMA_NUM_PARALLEL=4 \
OLLAMA_MAX_LOADED_MODELS=3 \
OLLAMA_KEEP_ALIVE=30m \
ollama serve

# Load models into memory
ollama run deepseek-coder:6.7b ""
ollama run codellama:13b-instruct ""
ollama run qwen2.5-coder:7b ""
```

## Docker Compose Stack

Complete development environment:

```yaml
# docker-compose.yml
version: '3.8'

services:
  omen:
    image: ghcr.io/ghostkellz/omen:latest
    restart: unless-stopped
    environment:
      OMEN_BIND: "0.0.0.0:8080"
      OMEN_REDIS_URL: "redis://redis:6379"

      # Providers
      OMEN_ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
      OMEN_OPENAI_API_KEY: "${OPENAI_API_KEY}"
      OMEN_OLLAMA_ENDPOINTS: "http://ollama:11434"

      # Zeke optimizations
      OMEN_ROUTER_PREFER_LOCAL_FOR: "code,completion,refactor,tests"
      OMEN_COMPLETION_TIMEOUT_MS: "300"
      OMEN_ENABLE_CACHE: "true"
      OMEN_CACHE_COMPLETION_TTL: "7200"
    ports:
      - "8080:8080"
    volumes:
      - ./omen-data:/app/data
    depends_on:
      - redis
      - ollama

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    environment:
      OLLAMA_NUM_PARALLEL: "4"
      OLLAMA_MAX_LOADED_MODELS: "3"
      OLLAMA_KEEP_ALIVE: "30m"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data

volumes:
  ollama_data:
  redis_data:
```

## Zeke Command Examples

### Code Generation

```bash
# Generate Zig HTTP server
zeke ask "Create an async HTTP server in Zig using std.http"
# OMEN → DeepSeek Coder (local, 150ms response)

# Generate with context
zeke ask --context src/main.zig "Add middleware support to this server"
# OMEN → Qwen2.5-Coder (local, understands context)
```

### Code Explanation

```bash
# Explain complex algorithm
zeke explain src/allocator.zig
# OMEN → CodeLlama (local, detailed explanations)

# Explain with specific focus
zeke explain --focus "memory management" src/allocator.zig
# OMEN → Claude 3.5 Sonnet (complex topic, needs reasoning)
```

### Refactoring

```bash
# Simple refactor
zeke refactor --extract-function handleRequest src/server.zig
# OMEN → Qwen2.5-Coder (local, simple task)

# Complex refactor
zeke refactor --pattern "Extract all HTTP handlers to separate files" src/
# OMEN → Claude 3.5 Sonnet (architectural change, needs reasoning)
```

### Test Generation

```bash
# Generate unit tests
zeke test --file src/parser.zig
# OMEN → CodeLlama (local, specialized for tests)

# Generate with coverage
zeke test --coverage 90 --file src/parser.zig
# OMEN → Claude 3.5 Sonnet (high coverage needs comprehensive thinking)
```

### Watch Mode

```bash
# Monitor project, auto-fix issues
zeke watch --auto-fix --project .
# Continuous: OMEN routes each fix to optimal model
# Simple fixes → Local Ollama (fast)
# Complex issues → Claude (quality)
```

## Monitoring & Metrics

### Track Zeke Usage in OMEN

```bash
# View Zeke-specific metrics
curl http://localhost:8080/admin/metrics?source=zeke

# Response:
{
  "total_requests": 1543,
  "completions": 892,
  "chat": 421,
  "refactor": 164,
  "tests": 66,
  "local_model_usage": "87%",
  "avg_latency_ms": 145,
  "cost_usd": 0.23,  # Only 13% used cloud models
  "cache_hit_rate": "62%"
}
```

### Prometheus Metrics

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'omen-zeke'
    static_configs:
      - targets: ['localhost:8080']
    metric_relabel_configs:
      - source_labels: [source]
        regex: 'zeke'
        action: keep
```

## Troubleshooting

### Slow Completions

```bash
# Check OMEN routing decisions
curl http://localhost:8080/admin/debug?request_id=abc123

# Common fixes:
# 1. Ensure Ollama models are preloaded
ollama list

# 2. Check network latency to OMEN
ping omen.local

# 3. Enable completion cache
OMEN_ENABLE_CACHE=true

# 4. Reduce completion timeout
OMEN_COMPLETION_TIMEOUT_MS=200
```

### Wrong Model Selection

```bash
# Force specific model for testing
zeke ask --model "deepseek-coder:6.7b" "Write a function"

# Check OMEN routing rules
curl http://localhost:8080/admin/routing/rules

# Update intent classification
cat > omen.toml <<EOF
[routing.intents.completion]
primary_provider = "ollama"
model = "deepseek-coder:6.7b"
force = true  # Never route elsewhere
EOF
```

### High Costs

```bash
# Analyze cloud usage
curl http://localhost:8080/admin/costs?group_by=intent

# Typical issue: Completions going to cloud
# Fix: Update routing rules
[routing]
prefer_local_for = ["completion", "code", "refactor"]
max_cloud_requests_per_hour = 50  # Limit cloud usage
```

## Best Practices

### 1. Use Tags for Better Routing

```bash
# In Zeke requests, include tags
zeke ask --tag intent:code --tag complexity:simple "..."
# Helps OMEN make better routing decisions
```

### 2. Preload Models

```bash
# Add to startup script
ollama pull deepseek-coder:6.7b
ollama run deepseek-coder:6.7b ""  # Load into memory
```

### 3. Monitor Costs

```bash
# Daily cost report
curl http://localhost:8080/admin/costs/daily | jq

# Set budget alerts
OMEN_BUDGET_ALERT_THRESHOLD_USD=10
OMEN_BUDGET_ALERT_EMAIL=dev@example.com
```

### 4. Cache Aggressively

```toml
[cache]
enabled = true
completion_ttl = 7200  # 2 hours
chat_ttl = 3600
# Completions are repetitive, cache heavily
```

## Integration with Other Ghost Stack Tools

### Zeke + Jarvis + OMEN

```bash
# Zeke for coding (via OMEN)
zeke ask "Write async HTTP client"

# Jarvis for DevOps (via OMEN)
jarvis "Deploy this to Proxmox"

# Both use same OMEN backend for consistency
```

### Zeke + GhostFlow + OMEN

```yaml
# ghostflow workflow
nodes:
  - id: code_gen
    type: tool
    tool: zeke
    config:
      omen_endpoint: http://localhost:8080/v1
      command: "ask"
      prompt: "{{ workflow.input }}"
```

## Migration Guide

### From Copilot to Zeke + OMEN

```bash
# Before: GitHub Copilot
# - Proprietary
# - Limited to GPT models
# - No local option
# - Expensive at scale

# After: Zeke + OMEN
# - Open source
# - Multi-provider (Claude, GPT, local)
# - 87% local routing (free)
# - Full control

# Steps:
1. Install Zeke: zig build install
2. Configure OMEN endpoint
3. Install zeke.nvim or use CLI
4. Remove Copilot subscription
```

## Next Steps

1. **Install Zeke**: Clone and build from [github.com/ghostkellz/zeke](https://github.com/ghostkellz/zeke)
2. **Configure OMEN**: Use routing rules optimized for Zeke workloads
3. **Install zeke.nvim**: For Neovim integration
4. **Set Up Ollama**: Pull recommended models for local inference
5. **Test & Monitor**: Track costs, latency, and routing decisions

## Resources

- [Zeke GitHub](https://github.com/ghostkellz/zeke)
- [Zeke.nvim Plugin](https://github.com/ghostkellz/zeke.nvim)
- [OMEN Documentation](https://github.com/ghostkellz/omen)
- [Ghost Stack Integration](./GHOST_INTEGRATIONS.md)

---

**Built with the Ghost Stack**

⚡ **Zig** • 🦀 **Rust** • 👻 **Ghost Stack** • 🤖 **AI-Powered**
