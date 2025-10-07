# Glyph Integration with Zeke

This document describes how to integrate [Glyph](https://github.com/ghostkellz/glyph), the MCP (Model Context Protocol) server, with Zeke for enhanced file operations and code manipulation.

## Overview

Glyph provides MCP tools that Zeke can use for:
- **File Operations**: Read, write, and list files (`fs.read`, `fs.write`, `fs.list`)
- **Diff Operations**: Generate and apply diffs (`diff.generate`, `diff.apply`)
- **Code Editing**: Apply AI-generated code changes safely

Zeke communicates with Glyph using the Model Context Protocol over stdio or WebSocket.

## Architecture

```
┌──────────────────────────────────────────┐
│ Zeke CLI                                 │
│  • MCP Client (src/mcp/client.zig)      │
│  • Smart Router                          │
│  • Health Checks & Metrics              │
└──────────────┬───────────────────────────┘
               │ JSON-RPC over stdio/ws
               ▼
       ┌───────────────┐
       │ Glyph MCP     │
       │ Server (Rust) │
       │  • fs.read    │
       │  • fs.write   │
       │  • fs.list    │
       │  • diff.apply │
       │  • diff.gen   │
       └───────────────┘
```

## Setup

### Option A: Local Development (Recommended)

Best for active development when APIs are still evolving.

#### 1. Build Glyph

```bash
cd /data/projects/glyph
cargo build --release
```

The binary will be at: `/data/projects/glyph/target/release/glyph`

#### 2. Configure Zeke

Create or edit `~/.config/zeke/config.json`:

```json
{
  "services": {
    "glyph": {
      "enabled": true,
      "mcp": {
        "stdio": {
          "command": "/data/projects/glyph/target/release/glyph",
          "args": ["serve", "--transport", "stdio"]
        }
      },
      "health_check_interval_s": 30,
      "timeout_ms": 5000
    },
    "omen": {
      "enabled": true,
      "base_url": "http://localhost:3000",
      "health_check": "/health",
      "health_check_interval_s": 60,
      "timeout_ms": 10000
    }
  },
  "model_aliases": {
    "fast": "llama3.2:1b",
    "smart": "claude-3-5-sonnet-20241022",
    "local": "qwen2.5-coder:7b",
    "balanced": "llama3.2:3b"
  }
}
```

#### 3. Run Zeke

```bash
zeke serve --verbose
```

Zeke will automatically spawn Glyph as a child process.

### Option B: Production/CI (Git Submodule)

For reproducible builds and CI pipelines.

#### 1. Add Glyph as Submodule

```bash
cd /data/projects/zeke
git submodule add https://github.com/ghostkellz/glyph third_party/glyph
git -C third_party/glyph checkout <pinned_commit_sha>
git add .gitmodules third_party/glyph
git commit -m "Add glyph submodule @ <sha>"
```

#### 2. Build in CI

```yaml
# .github/workflows/build.yml
- name: Build Glyph
  run: |
    cd third_party/glyph
    cargo build --release
```

#### 3. Configure with Relative Path

```json
{
  "services": {
    "glyph": {
      "mcp": {
        "stdio": {
          "command": "./third_party/glyph/target/release/glyph",
          "args": ["serve", "--transport", "stdio"]
        }
      }
    }
  }
}
```

### Option C: WebSocket Transport

For distributed deployments where Glyph runs on a separate server.

#### 1. Start Glyph with WebSocket

```bash
glyph serve --transport ws --port 8080
```

#### 2. Configure Zeke

```json
{
  "services": {
    "glyph": {
      "mcp": {
        "websocket": {
          "url": "ws://localhost:8080"
        }
      }
    }
  }
}
```

## Environment Variables

You can also configure Glyph via environment variables:

```bash
# Stdio transport
export GLYPH_MCP_COMMAND="/path/to/glyph"

# WebSocket transport
export GLYPH_MCP_WS="ws://localhost:8080"

# OMEN cloud routing
export OMEN_BASE_URL="http://localhost:3000"
```

## Usage

### From Zeke Code

```zig
const std = @import("std");
const zeke = @import("zeke");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load config
    const cfg = try zeke.config.loadConfig(allocator);
    defer cfg.deinit();

    // Initialize MCP client for Glyph
    if (cfg.services.glyph) |glyph_cfg| {
        var mcp = try zeke.mcp.McpClient.initFromConfig(allocator, glyph_cfg);
        defer mcp.deinit();

        // Read a file
        const content = try mcp.readFile("src/main.zig");
        defer content.deinit();
        std.debug.print("File content: {s}\n", .{content.content});

        // Write a file
        _ = try mcp.writeFile("output.txt", "Hello from Zeke!");

        // Generate diff
        const diff = try mcp.generateDiff("old content", "new content");
        defer diff.deinit();
        std.debug.print("Diff: {s}\n", .{diff.content});

        // Apply diff
        _ = try mcp.applyDiff("src/file.zig", diff.content);
    }
}
```

### Available MCP Tools

#### `fs.read`
Read file contents.

```zig
const result = try mcp.readFile("/path/to/file");
defer result.deinit();
```

#### `fs.write`
Write content to a file.

```zig
const result = try mcp.writeFile("/path/to/file", "content");
defer result.deinit();
```

#### `fs.list`
List directory contents.

```zig
const result = try mcp.listDirectory("/path/to/dir");
defer result.deinit();
```

#### `diff.generate`
Generate a unified diff between two strings.

```zig
const result = try mcp.generateDiff("old", "new");
defer result.deinit();
```

#### `diff.apply`
Apply a unified diff to a file.

```zig
const result = try mcp.applyDiff("/path/to/file", diff_content);
defer result.deinit();
```

## Health Checks & Metrics

Zeke automatically tracks Glyph health and performance.

### View Service Health

```bash
zeke health glyph
```

Output:
```
Service: glyph
Status: healthy
Latency: 12ms
Last Checked: 2025-10-07 02:30:15
```

### Metrics Database

Health checks and tool calls are recorded in `~/.local/share/zeke/routing.db`:

**`service_health` table:**
- service: "glyph", "omen", "ollama"
- status: "healthy", "degraded", "down", "unknown"
- latency_ms: Response time
- last_checked: Unix timestamp

**`tool_calls` table:**
- tool_name: "fs.read", "fs.write", etc.
- service: "glyph"
- latency_ms: Tool execution time
- success: 1 or 0
- created_at: Unix timestamp

### Query Metrics

```sql
-- Recent tool calls
SELECT tool_name, latency_ms, success, created_at
FROM tool_calls
WHERE service = 'glyph'
ORDER BY created_at DESC
LIMIT 100;

-- Average latency per tool
SELECT tool_name, AVG(latency_ms) as avg_latency, COUNT(*) as count
FROM tool_calls
WHERE service = 'glyph'
GROUP BY tool_name;

-- Success rate
SELECT
  tool_name,
  SUM(success) * 100.0 / COUNT(*) as success_rate
FROM tool_calls
WHERE service = 'glyph'
GROUP BY tool_name;
```

## Troubleshooting

### Glyph Process Won't Start

**Check binary exists:**
```bash
ls -la /data/projects/glyph/target/release/glyph
```

**Run manually:**
```bash
/data/projects/glyph/target/release/glyph serve --transport stdio
```

**Check permissions:**
```bash
chmod +x /data/projects/glyph/target/release/glyph
```

### Connection Timeouts

Increase timeout in config:
```json
{
  "services": {
    "glyph": {
      "timeout_ms": 10000
    }
  }
}
```

### MCP Protocol Errors

Enable verbose logging:
```bash
ZEKE_LOG_LEVEL=debug zeke serve --verbose
```

Check JSON-RPC messages in stderr.

### Health Checks Failing

Manually test Glyph:
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}' | glyph serve --transport stdio
```

## Model Aliases

Configure quick model selection:

```json
{
  "model_aliases": {
    "fast": "llama3.2:1b",      // Quick responses, local
    "smart": "claude-3-5-sonnet-20241022",  // Complex reasoning, cloud
    "local": "qwen2.5-coder:7b",  // Best local coding model
    "balanced": "llama3.2:3b"      // Good balance
  }
}
```

Use in Zeke CLI:
```bash
zeke chat --model fast "Explain this code"
zeke edit --model smart "Refactor for performance"
```

## Integration with Smart Router

Zeke's smart router automatically selects between local (Ollama) and cloud (OMEN) based on:
- Task complexity
- Token count
- Cost preferences
- Provider availability

Configure routing preferences:
```json
{
  "routing": {
    "prefer_local": true,
    "fallback_to_cloud": true,
    "max_cloud_cost_cents": 200
  }
}
```

## Further Reading

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [Glyph Repository](https://github.com/ghostkellz/glyph)
- [Zeke Documentation](./README.md)
- [Watch Mode Guide](./WATCH_MODE.md)
