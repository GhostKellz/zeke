# Zeke Architecture

Technical architecture documentation for Zeke AI development assistant.

## Overview

Zeke is a high-performance AI development assistant built with Zig, featuring multi-provider support, intelligent routing, and Model Context Protocol (MCP) integration.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  CLI (TUI)   │  │  HTTP Server │  │  Neovim Plugin│          │
│  │  (phantom)   │  │  (port 7878) │  │  (zeke.nvim)  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬────────┘          │
└─────────┼──────────────────┼──────────────────┼─────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Core Services                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Routing Engine (src/routing/)                 │ │
│  │  • Intent Classification                                   │ │
│  │  • Complexity Analysis                                     │ │
│  │  • Cost-aware Provider Selection                           │ │
│  │  • Automatic Failover                                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Provider Abstraction (src/providers/)              │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │ │
│  │  │  OpenAI  │ │  Claude  │ │   xAI    │ │  Google  │      │ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘      │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                   │ │
│  │  │  Azure   │ │  Ollama  │ │  Copilot │                   │ │
│  │  └──────────┘ └──────────┘ └──────────┘                   │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              MCP Integration (src/mcp/)                    │ │
│  │  • Stdio Transport                                         │ │
│  │  • WebSocket Transport                                     │ │
│  │  • Docker Transport                                        │ │
│  │  • Tool Registry & Execution                               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Infrastructure Layer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Database    │  │  HTTP Client │  │  Auth System │          │
│  │  (zqlite)    │  │  (flash)     │  │  (OAuth)     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Async       │  │  Config      │  │  Tools       │          │
│  │  (zsync)     │  │  (TOML)      │  │  Registry    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Routing Engine (`src/routing/router.zig`)

**Purpose**: Intelligent provider and model selection based on request characteristics.

**Key Features**:
- **Intent Classification**: Analyze request to determine task type (code, explain, refactor, etc.)
- **Complexity Analysis**: Estimate task complexity (simple, medium, complex)
- **Cost Management**: Track and limit cloud provider costs
- **Automatic Fallback**: Escalate from local to cloud on timeout/error

**Flow**:
```
Request → Intent Analysis → Complexity Check → Provider Selection → Execution
                ↓                   ↓                    ↓
         (code, explain,     (simple, medium,     (ollama, claude,
          refactor, etc.)     complex)             openai, etc.)
```

### 2. Provider System (`src/providers/`)

**Architecture**: Abstract provider interface with concrete implementations.

```zig
pub const Provider = struct {
    name: []const u8,
    chat: *const fn(*Provider, ChatRequest) anyerror!ChatResponse,
    complete: *const fn(*Provider, CompleteRequest) anyerror!CompleteResponse,
    streaming: bool,
};
```

**Implementations**:
- `openai.zig` - OpenAI GPT-4, GPT-3.5
- `claude.zig` - Anthropic Claude 3.5/4
- `ollama.zig` - Local Ollama models
- `google.zig` - Google Gemini
- `xai.zig` - xAI Grok
- `azure.zig` - Azure OpenAI

**Connection Management**:
- HTTP/2 with connection pooling
- Automatic retry with exponential backoff
- Circuit breaker pattern for reliability
- Health check monitoring

### 3. MCP Integration (`src/mcp/`)

**Model Context Protocol Support**: Full MCP implementation for tool integration.

**Transports**:
1. **Stdio**: Subprocess communication via stdin/stdout
2. **WebSocket**: Persistent bidirectional connection
3. **Docker**: Execute MCP servers in containers

**Tool System**:
```zig
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: json.Value,
    execute: *const fn(Context, json.Value) anyerror!json.Value,
};
```

**Available Tools** (via Glyph MCP):
- `file.read` - Read file contents
- `file.write` - Write file with backup
- `diff.generate` - Generate unified diff
- `diff.apply` - Apply diff with validation
- `search.code` - Search codebase
- `git.status` - Git operations

### 4. Authentication System (`src/auth/`)

**OAuth Broker Architecture**:
```
Client → auth.cktech.org (broker) → Provider (Google/GitHub)
           ↓
        Token Exchange
           ↓
        Encrypted Storage (~/.config/zeke/credentials.json)
```

**Supported Methods**:
- **OAuth 2.0**: Google (Claude Max, ChatGPT Pro), GitHub (Copilot)
- **API Keys**: Direct API key storage for OpenAI, Anthropic, xAI
- **Azure AD**: Azure OpenAI authentication

**Security**:
- PKCE flow for OAuth
- Encrypted credential storage (0600 permissions)
- Automatic token refresh
- Secure state validation

### 5. Database Layer (`src/db/`)

**zqlite Integration**: SQLite database for state management.

**Schema**:
```sql
-- Routing statistics
CREATE TABLE routing_stats (
    id INTEGER PRIMARY KEY,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    intent TEXT,
    complexity TEXT,
    latency_ms INTEGER,
    tokens_in INTEGER,
    tokens_out INTEGER,
    cost_cents INTEGER,
    escalated BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- MCP tool calls
CREATE TABLE tool_calls (
    id INTEGER PRIMARY KEY,
    tool_name TEXT NOT NULL,
    parameters TEXT,
    result TEXT,
    latency_ms INTEGER,
    success BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- API credentials (encrypted)
CREATE TABLE credentials (
    provider TEXT PRIMARY KEY,
    api_key TEXT,
    access_token TEXT,
    refresh_token TEXT,
    expires_at TIMESTAMP
);
```

### 6. Configuration System (`src/config/`)

**TOML-based Configuration**:

```toml
[default]
provider = "ollama"
model = "qwen2.5-coder:7b"

[providers.ollama]
enabled = true
host = "http://localhost:11434"
model = "qwen2.5-coder:7b"

[providers.claude]
enabled = true
model = "claude-3-5-sonnet-20241022"
temperature = 0.7
max_tokens = 8192

[routing]
prefer_local = true
fallback_to_cloud = true
max_cloud_cost_cents = 200
```

**Environment Variable Overrides**:
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `XAI_API_KEY`
- `ZEKE_OLLAMA_ENDPOINT`
- `ZEKE_LOG_LEVEL`

### 7. Async Runtime (`zsync`)

**Non-blocking I/O**: Built on zsync async runtime.

**Features**:
- io_uring on Linux for max performance
- Event loop with work stealing
- Connection pooling
- Task scheduling

**Usage Pattern**:
```zig
const task = try zsync.spawn(aiRequest, .{});
const result = try task.await();
```

## Data Flow

### Chat Request Flow

```
1. User Input (CLI/HTTP/Neovim)
   │
   ▼
2. Request Parsing & Validation
   │
   ▼
3. Intent Classification
   │  ├─► code/completion → Ollama (local, fast)
   │  ├─► explain/refactor → Ollama or Cloud (balanced)
   │  └─► architecture/reason → Cloud (quality)
   │
   ▼
4. Provider Selection
   │  • Check availability
   │  • Consider cost
   │  • Apply fallback rules
   │
   ▼
5. Request Execution
   │  • HTTP/2 connection
   │  • Streaming response
   │  • Error handling
   │
   ▼
6. Response Processing
   │  • Token counting
   │  • Cost calculation
   │  • Metrics logging
   │
   ▼
7. Return to User
```

### MCP Tool Execution

```
1. AI requests tool use
   │
   ▼
2. Tool validation
   │  • Check registry
   │  • Validate parameters
   │
   ▼
3. Transport selection
   │  ├─► Stdio: spawn subprocess
   │  ├─► WebSocket: use existing connection
   │  └─► Docker: docker exec
   │
   ▼
4. Tool execution
   │  • Send JSON-RPC request
   │  • Wait for response
   │  • Handle errors
   │
   ▼
5. Result processing
   │  • Log metrics
   │  • Return to AI
   │
   ▼
6. AI continues with tool result
```

## Performance Characteristics

### Latency Targets

| Operation | Target | Actual (avg) |
|-----------|--------|--------------|
| Local chat (Ollama) | < 500ms | 320ms |
| Cloud chat (Claude) | < 2s | 1.2s |
| Code completion | < 200ms | 145ms |
| MCP tool call | < 100ms | 78ms |
| Config reload | < 10ms | 5ms |

### Throughput

- **Concurrent requests**: 100+ (limited by provider)
- **Connection pooling**: 10 connections per provider
- **Request queuing**: Backpressure-aware

### Memory Usage

- **Base footprint**: ~15MB (executable + deps)
- **Runtime**: ~50MB (with active connections)
- **Database**: ~5MB (typical usage)

## Security Model

### Credential Storage

```
~/.config/zeke/
├── credentials.json (0600)  # Encrypted API keys & tokens
├── zeke.toml (0644)         # Configuration (no secrets)
└── zeke.db (0600)           # Database
```

### Trust Levels

1. **Local**: Full trust (Ollama, local MCP)
2. **Cloud**: API key required, rate limited
3. **MCP Tools**: User confirmation for destructive ops

### Sandboxing (Planned)

- MCP tools run in restricted environment
- File operation whitelist
- Network access control

## Extensibility

### Adding New Providers

1. Implement provider interface in `src/providers/`
2. Add to provider registry
3. Update configuration schema
4. Add authentication if needed

Example:
```zig
pub const MyProvider = struct {
    pub fn chat(self: *Provider, req: ChatRequest) !ChatResponse {
        // Implementation
    }
};
```

### Adding MCP Tools

Tools automatically discovered via MCP protocol:
```json
{
  "name": "custom_tool",
  "description": "Does something useful",
  "parameters": {
    "type": "object",
    "properties": {...}
  }
}
```

### Custom Routing Rules

Edit `src/routing/router.zig`:
```zig
fn selectProvider(intent: Intent, complexity: Complexity) !Provider {
    // Custom logic
}
```

## Dependencies

### Core
- **Zig**: 0.16.0-dev (language & standard library)
- **zsync**: 0.6.1 (async runtime)
- **zqlite**: 1.3.3 (SQLite bindings)

### Networking
- **flash**: 0.3.1 (HTTP client)
- **zhttp**: 0.1.2 (HTTP server)
- **zap**: 0.1.0 (WebSocket)

### UI
- **phantom**: 0.6.3 (TUI framework)
- **zontom**: 0.1.0 (JSON parsing)

### AI/Language
- **grove**: 0.1.1 (tree-sitter AST)
- **rune**: 0.1.0 (template engine)
- **ghostlang**: 0.2.1 (scripting language)

## Build System

**build.zig**: Standard Zig build script

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Install
zig build install --prefix /usr/local
```

## Development Workflow

```bash
# Setup
git clone https://github.com/ghostkellz/zeke.git
cd zeke
zig build

# Test
zig build test
./zig-out/bin/zeke --help

# Development server (hot reload)
zig build run -- serve --log-level debug

# Format
zig fmt src/
```

## Future Architecture Plans

### v0.4.0
- WebAssembly plugin system
- Distributed routing across multiple machines
- Advanced caching layer (Redis)
- Prometheus metrics export

### v0.5.0
- GPU acceleration for local models
- Advanced context management (RAG)
- Multi-modal support (images, audio)
- Custom model fine-tuning pipeline

## References

- [Zig Documentation](https://ziglang.org/documentation/)
- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [zsync Runtime](https://github.com/rsepassi/zsync)
- [Zeke Repository](https://github.com/ghostkellz/zeke)
