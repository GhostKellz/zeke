# Zeke Specifications

**Version:** 0.1.0-alpha
**Last Updated:** 2025-10-12
**Status:** Design Phase

---

## 🎯 Vision

**Zeke** is a **universal AI coding assistant** that operates in two modes:

1. **Completion Mode** (<100ms) - Real-time inline suggestions (GitHub Copilot-style)
2. **Agentic Mode** (minutes) - Multi-step autonomous tasks (Claude Code-style)

**Core Philosophy:**
- ⚡ **Fast** - Zig-native performance, <1ms IPC overhead
- 🔌 **Universal** - Works with any editor via RPC/MCP
- 🤖 **Model-agnostic** - Ollama, OpenAI, Claude, GitHub, etc.
- 🏠 **Local-first** - Privacy-focused, optional cloud
- 🛠️ **Extensible** - Plugin system for custom providers/tools

---

## 📐 Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                 Zeke Daemon (Zig)                            │
│                 Universal AI Engine                           │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Completion Engine (Reactive)                          │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • Inline suggestions (<100ms)                         │ │
│  │  • Function completions                                │ │
│  │  • Multi-line blocks                                   │ │
│  │  • Context-aware (LSP, git, file tree)                 │ │
│  │  • Caching & streaming                                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Agentic Engine (Proactive)                            │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • Plan-execute-verify loop                            │ │
│  │  • Tool calling (files, LSP, git, shell)               │ │
│  │  • Multi-step tasks                                    │ │
│  │  • Autonomous execution                                │ │
│  │  • State management                                    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Provider Management                                    │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • Ollama (local models)                               │ │
│  │  • OpenAI (GPT-4, GPT-3.5)                             │ │
│  │  • Anthropic (Claude 3 Opus/Sonnet)                    │ │
│  │  • GitHub Models (via OAuth)                           │ │
│  │  • Google (Gemini Pro)                                 │ │
│  │  • Custom endpoints (self-hosted)                      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Protocol Layer                                         │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • zRPC (local IPC, <1ms)                              │ │
│  │  • MCP via glyph (context/tools)                       │ │
│  │  • HTTP/REST (cloud providers)                         │ │
│  │  • WebSocket (streaming)                               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Context Engine                                         │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • LSP integration (symbols, types, errors)            │ │
│  │  • Git awareness (diffs, blame, history)               │ │
│  │  • File tree (project structure)                       │ │
│  │  • Semantic search (RAG over codebase)                 │ │
│  │  • Recent edits (temporal context)                     │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Infrastructure                                         │ │
│  │  ─────────────────────────────────────────────────────│ │
│  │  • Rate limiting & quotas                              │ │
│  │  • Response caching (LRU, TTL)                         │ │
│  │  • Cost tracking                                       │ │
│  │  • Auth management (OAuth, API keys)                   │ │
│  │  • Telemetry (opt-in)                                  │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ (clients)
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌────────────────┐  ┌──────────────┐  ┌────────────────┐
│  zeke.grim     │  │  zeke.nvim   │  │  zeke CLI      │
│  (Ghostlang)   │  │  (Lua)       │  │  (Terminal)    │
└────────────────┘  └──────────────┘  └────────────────┘
```

---

## 🔧 Core Components

### 1. Completion Engine

**Purpose:** Real-time code suggestions (<100ms latency)

**Responsibilities:**
- Monitor text changes via client
- Generate context (cursor, surrounding code, LSP symbols)
- Request completion from provider
- Stream response to client
- Cache frequent patterns

**Performance Targets:**
- First token: <50ms
- Full completion: <100ms
- Cache hit: <5ms

**Implementation:**
```zig
// src/completion/engine.zig
pub const CompletionEngine = struct {
    providers: ProviderPool,
    cache: CompletionCache,
    context: ContextGatherer,
    config: CompletionConfig,

    pub fn complete(
        self: *CompletionEngine,
        request: CompletionRequest,
    ) !CompletionResponse {
        // 1. Check cache
        if (self.cache.get(request.context_hash)) |cached| {
            return cached;
        }

        // 2. Gather context
        const ctx = try self.context.gather(request);

        // 3. Select provider
        const provider = try self.providers.select(ctx);

        // 4. Request completion
        const result = try provider.complete(ctx);

        // 5. Cache result
        self.cache.put(request.context_hash, result);

        return result;
    }
};
```

---

### 2. Agentic Engine

**Purpose:** Multi-step autonomous tasks (minutes to hours)

**Responsibilities:**
- Parse user task into plan
- Execute steps sequentially
- Call tools (file ops, LSP, git, shell)
- Verify results
- Handle errors & retry
- Update user on progress

**Workflow:**
```
User: "Add comprehensive tests for this module"
  ↓
Plan:
  1. Analyze module structure
  2. Identify testable functions
  3. Generate test cases
  4. Write test file
  5. Run tests
  6. Fix any failures
  ↓
Execute each step...
  ↓
Result: tests/module.test.zig created, 15 tests passing
```

**Implementation:**
```zig
// src/agent/engine.zig
pub const AgenticEngine = struct {
    planner: TaskPlanner,
    executor: StepExecutor,
    tools: ToolRegistry,
    verifier: ResultVerifier,

    pub fn execute(
        self: *AgenticEngine,
        task: Task,
        callbacks: ProgressCallbacks,
    ) !TaskResult {
        // 1. Generate plan
        const plan = try self.planner.generate(task);
        callbacks.onPlan(plan);

        // 2. Execute steps
        for (plan.steps) |step| {
            callbacks.onStepStart(step);

            const result = try self.executor.run(step);

            if (!result.success) {
                // Retry or replan
                const fixed_plan = try self.planner.replan(plan, result);
                // ...
            }

            callbacks.onStepComplete(step, result);
        }

        // 3. Verify final result
        const verification = try self.verifier.check(plan);

        return TaskResult{
            success = verification.passed,
            output = verification.output,
        };
    }
};
```

---

### 3. Provider System

**Architecture:**
```
┌────────────────────────────────────────────────┐
│  Provider Interface (abstract)                 │
├────────────────────────────────────────────────┤
│  fn complete(ctx: Context) !CompletionResponse │
│  fn chat(messages: []Message) !ChatResponse    │
│  fn cost() f64                                  │
│  fn rate_limit() ?RateLimit                    │
└────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Ollama     │ │   OpenAI     │ │   Claude     │
│  Provider    │ │  Provider    │ │  Provider    │
└──────────────┘ └──────────────┘ └──────────────┘
```

**Provider Selection Strategy:**
1. **Manual** - User-specified provider
2. **Auto** - Choose based on:
   - Task complexity
   - Required latency
   - Cost constraints
   - Rate limit status
3. **Fallback** - Auto-switch on error/limit
4. **Cheapest** - Optimize for cost
5. **Fastest** - Optimize for latency

**Implementation:**
```zig
// src/providers/provider.zig
pub const Provider = struct {
    name: []const u8,
    model: []const u8,
    type: ProviderType, // local, cloud

    vtable: *const ProviderVTable,

    pub const ProviderVTable = struct {
        complete: *const fn (
            self: *Provider,
            ctx: Context,
        ) anyerror!CompletionResponse,

        chat: *const fn (
            self: *Provider,
            messages: []Message,
        ) anyerror!ChatResponse,

        cost_per_token: *const fn (self: *Provider) f64,
        rate_limit: *const fn (self: *Provider) ?RateLimit,
    };
};

// src/providers/ollama.zig
pub const OllamaProvider = struct {
    base: Provider,
    url: []const u8,
    model: []const u8,

    pub fn init(url: []const u8, model: []const u8) OllamaProvider {
        return .{
            .base = .{
                .name = "ollama",
                .model = model,
                .type = .local,
                .vtable = &vtable,
            },
            .url = url,
            .model = model,
        };
    }

    const vtable = Provider.ProviderVTable{
        .complete = complete,
        .chat = chat,
        .cost_per_token = costPerToken,
        .rate_limit = rateLimit,
    };

    fn complete(
        provider: *Provider,
        ctx: Context,
    ) !CompletionResponse {
        const self = @fieldParentPtr(OllamaProvider, "base", provider);

        // HTTP request to Ollama API
        const response = try http.post(
            self.url ++ "/api/generate",
            .{
                .model = self.model,
                .prompt = ctx.prompt,
                .stream = false,
            },
        );

        return CompletionResponse{
            .text = response.response,
            .provider = self.base.name,
            .model = self.model,
            .cached = false,
        };
    }

    // ... other methods
};
```

---

### 4. Protocol Layer

#### zRPC (Local IPC)

**Purpose:** Fast communication between zeke daemon and local clients

**Features:**
- Unix domain sockets (Linux/macOS) or named pipes (Windows)
- msgpack serialization (faster than JSON)
- <1ms round-trip latency
- Binary protocol

**Example:**
```zig
// Client (zeke.grim)
const zrpc = @import("zrpc");

const client = try zrpc.Client.connect("/tmp/zeke.sock");
defer client.close();

const response = try client.call("completion.request", .{
    .buffer = buffer_content,
    .cursor = .{ .line = 42, .col = 15 },
    .language = "zig",
});
```

```zig
// Server (zeke daemon)
const server = try zrpc.Server.init("/tmp/zeke.sock");

try server.register("completion.request", handleCompletion);

fn handleCompletion(req: CompletionRequest) !CompletionResponse {
    // ... completion logic
}
```

#### MCP via glyph

**Purpose:** Advanced context and tool calling

**Use Cases:**
- Get LSP symbols/types
- Execute git commands
- File tree traversal
- Terminal operations

**Integration:**
```zig
// src/protocols/mcp.zig
const glyph_client = try glyph.Client.connect("http://localhost:3000");

// Get LSP context
const symbols = try glyph_client.call("lsp/symbols", .{
    .file = "src/main.zig",
    .position = cursor_pos,
});

// Execute tool
const git_status = try glyph_client.call("git/status", .{
    .repo = project_root,
});
```

---

### 5. Context Engine

**Purpose:** Gather relevant context for AI requests

**Context Types:**

1. **Immediate Context** (always included)
   - Current buffer content
   - Cursor position
   - Language/filetype

2. **LSP Context** (if available)
   - Symbol at cursor
   - Type information
   - Function signatures
   - Documentation

3. **Git Context** (if in repo)
   - Current branch
   - Recent commits
   - Diff for current file
   - Blame for current line

4. **Project Context** (selective)
   - File tree structure
   - Related files (imports, dependencies)
   - Build configuration
   - README/docs

5. **Historical Context** (recent)
   - Recent edits in this file
   - Recently viewed files
   - Search history

**Context Budget:**
```
Target: 8k tokens (Claude Sonnet input)
Budget:
  - Immediate: 4k tokens (current file)
  - LSP: 1k tokens (symbols/types)
  - Git: 512 tokens (diffs/commits)
  - Project: 1.5k tokens (related files)
  - Historical: 1k tokens (recent edits)
```

**Implementation:**
```zig
// src/context/gatherer.zig
pub const ContextGatherer = struct {
    lsp_client: ?*LspClient,
    git_client: ?*GitClient,
    file_watcher: *FileWatcher,

    pub fn gather(
        self: *ContextGatherer,
        request: ContextRequest,
    ) !Context {
        var ctx = Context.init(allocator);

        // Always include immediate context
        try ctx.addImmediate(request);

        // Add LSP context if available
        if (self.lsp_client) |lsp| {
            const symbols = lsp.getSymbols(request.position);
            try ctx.addLsp(symbols);
        }

        // Add git context if in repo
        if (self.git_client) |git| {
            const diff = git.getDiff(request.file);
            try ctx.addGit(diff);
        }

        // Add related files
        const related = try self.findRelatedFiles(request.file);
        for (related) |file| {
            if (ctx.tokens_used < ctx.token_budget) {
                try ctx.addFile(file);
            }
        }

        return ctx;
    }
};
```

---

## 📝 Configuration

### zeke.toml

```toml
[daemon]
socket_path = "/tmp/zeke.sock"  # Unix socket
log_level = "info"              # debug, info, warn, error
pid_file = "/tmp/zeke.pid"

[modes]
completion = true               # Enable completion mode
agent = true                    # Enable agentic mode

[completion]
latency_target_ms = 100         # Target latency
cache_ttl_seconds = 300         # Cache TTL (5 min)
max_tokens = 500                # Max completion length
temperature = 0.2               # Low randomness
debounce_ms = 300               # Wait before requesting

[agent]
max_task_time_minutes = 60      # Timeout for long tasks
tool_calling = true             # Enable tool execution
auto_verify = true              # Verify results
max_retries = 3                 # Retry failed steps

[providers]
# Ollama (local)
[providers.ollama]
enabled = true
url = "http://localhost:11434"
models = ["codellama:13b", "deepseek-coder:6.7b"]
priority = 1                    # Try first

# OpenAI
[providers.openai]
enabled = true
api_key_cmd = "pass openai-key" # Secure key retrieval
models = ["gpt-4", "gpt-3.5-turbo"]
priority = 2

# Anthropic (Claude)
[providers.anthropic]
enabled = true
api_key_cmd = "pass anthropic-key"
models = ["claude-sonnet-4-5", "claude-opus-4"]
priority = 3

# GitHub Models
[providers.github]
enabled = false                 # Requires OAuth
auth = "oauth"
models = ["github-copilot"]

# Custom endpoint
[providers.custom]
enabled = false
endpoints = ["http://192.168.1.100:8080"]

[selection]
strategy = "auto"               # auto, manual, cheapest, fastest
fallback = true                 # Auto-fallback on error
prefer_local = true             # Prefer Ollama if available

[context]
max_tokens = 8000               # Context window budget
include_lsp = true              # Include LSP symbols
include_git = true              # Include git info
include_files = true            # Include related files
semantic_search = false         # RAG (future)

[protocols]
zrpc = true                     # Local IPC
mcp_enabled = true              # MCP via glyph
mcp_url = "http://localhost:3000"
http_timeout_seconds = 30

[privacy]
telemetry = false               # No tracking
strip_secrets = true            # Remove API keys from logs
cache_locally = true            # Cache responses

[cost]
track_usage = true              # Track API costs
budget_monthly_usd = 50.0       # Budget limit
warn_threshold = 0.8            # Warn at 80%
```

---

## 🔌 API Reference

### Completion API

**Endpoint:** `completion.request`

**Request:**
```json
{
  "buffer": "fn fibonacci(n: u32) u32 {\n    ",
  "cursor": { "line": 1, "col": 4 },
  "language": "zig",
  "provider": "auto",
  "max_tokens": 500
}
```

**Response:**
```json
{
  "id": "comp_abc123",
  "text": "if (n <= 1) return n;\n    return fibonacci(n - 1) + fibonacci(n - 2);",
  "provider": "ollama",
  "model": "codellama:13b",
  "cached": false,
  "latency_ms": 87,
  "tokens": {
    "input": 45,
    "output": 22
  }
}
```

### Agentic API

**Endpoint:** `agent.execute`

**Request:**
```json
{
  "task": "Add comprehensive tests for this module",
  "context": {
    "file": "src/parser.zig",
    "selection": { "start": 1, "end": 150 }
  },
  "options": {
    "verify": true,
    "timeout_minutes": 10
  }
}
```

**Response (streaming):**
```json
// Event: plan
{
  "type": "plan",
  "steps": [
    "Analyze module structure",
    "Identify testable functions",
    "Generate test cases",
    "Write test file",
    "Run tests"
  ]
}

// Event: step_start
{
  "type": "step_start",
  "step": 1,
  "description": "Analyzing module structure..."
}

// Event: step_complete
{
  "type": "step_complete",
  "step": 1,
  "result": "Found 5 public functions to test"
}

// ... more events

// Event: complete
{
  "type": "complete",
  "success": true,
  "output": "Created tests/parser.test.zig with 15 tests (all passing)"
}
```

---

## 🏗️ Ghost Ecosystem Integration

### glyph (Rust MCP Server)

**Purpose:** Context provider and tool execution

**Integration:**
- Zeke daemon connects to glyph via HTTP/WebSocket
- Glyph exposes LSP, git, file, and terminal tools
- Zeke uses glyph for context gathering and tool calling

### zRPC (Zig RPC Library)

**Purpose:** Fast local IPC

**Integration:**
- Shared library between zeke daemon and clients
- Binary protocol, msgpack serialization
- <1ms latency for local requests

### omen (Observability)

**Purpose:** Monitoring and telemetry

**Integration:**
- Zeke exports metrics to omen
- Track: latency, errors, costs, cache hit rate
- Dashboard for debugging and optimization

### rune (Runtime Layer)

**Purpose:** Orchestration and deployment

**Integration:**
- Rune manages zeke daemon lifecycle
- Auto-restart on crash
- Load balancing across multiple instances

---

## 🚀 Development Roadmap

### Phase 1: Foundation (Q2 2025)
- ✅ Core daemon structure
- ✅ zRPC protocol implementation
- ✅ Ollama provider integration
- 🚧 Completion engine MVP
- 🚧 Basic context gathering

### Phase 2: Multi-Provider (Q3 2025)
- OpenAI provider
- Anthropic (Claude) provider
- Provider selection strategy
- Rate limiting & quotas
- Response caching

### Phase 3: Agentic Mode (Q4 2025)
- Task planner
- Tool calling framework
- Step executor
- Result verifier
- MCP integration via glyph

### Phase 4: Polish (Q1 2026)
- Performance optimization
- Cost tracking dashboard
- Advanced context (RAG)
- GitHub Models integration
- Production hardening

---

## 📊 Performance Targets

| Metric | Target | Stretch Goal |
|--------|--------|--------------|
| Completion latency | <100ms | <50ms |
| Cache hit latency | <10ms | <5ms |
| zRPC round-trip | <1ms | <500μs |
| Memory usage | <50MB | <25MB |
| Context gathering | <20ms | <10ms |
| Startup time | <1s | <500ms |

---

**Last Updated:** 2025-10-12
**Status:** Design Phase
**Owner:** Ghost Ecosystem Team
