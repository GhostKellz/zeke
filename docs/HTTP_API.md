# Zeke HTTP API Documentation

Complete reference for integrating with Zeke's HTTP API for AI-powered code assistance.

## Table of Contents
- [Quick Start](#quick-start)
- [Base Configuration](#base-configuration)
- [Authentication](#authentication)
- [Endpoints](#endpoints)
- [Request/Response Formats](#requestresponse-formats)
- [Error Handling](#error-handling)
- [Examples](#examples)

## Quick Start

### Starting the Server

```bash
# Start with default config (~/.config/zeke/config.json)
zeke serve

# Start on custom port
zeke serve --port 8080

# Start with specific config
zeke serve --config /path/to/config.json
```

### Test the Connection

```bash
curl http://localhost:7878/health
# {"status":"ok","version":"0.3.0"}
```

## Base Configuration

### Environment Variables

```bash
# Required for cloud providers
export ANTHROPIC_API_KEY="your-key"
export OPENAI_API_KEY="your-key"

# Optional: Local Ollama
export OLLAMA_HOST="http://localhost:11434"

# Optional: OMEN cloud routing
export OMEN_BASE="http://localhost:3000"
```

### Configuration File

Create `~/.config/zeke/config.json` (see `config.example.json`):

```json
{
  "default_model": "qwen2.5-coder:7b",
  "smart_routing": true,
  "endpoints": {
    "ollama": "http://localhost:11434",
    "omen": "http://localhost:3000"
  },
  "routing": {
    "prefer_local": true,
    "fallback_to_cloud": true,
    "max_cloud_cost_cents": 200
  }
}
```

## Authentication

### API Keys

Zeke uses environment-based authentication:

- **Local Ollama**: No authentication required
- **Cloud Providers**: Set `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`
- **OMEN**: Inherits provider keys

### OAuth (Optional)

For Google/GitHub SSO:

```bash
zeke auth google    # OAuth flow for Claude/Vertex AI
zeke auth github    # OAuth flow for Copilot models
```

## Endpoints

### Health Check

**GET** `/health`

Check if the server is running.

**Response:**
```json
{
  "status": "ok",
  "version": "0.3.0"
}
```

---

### Chat Completion

**POST** `/api/chat`

Multi-turn conversational AI interface.

**Request:**
```json
{
  "message": "Explain the Repository pattern",
  "model": "smart",              // Optional: model alias or name
  "temperature": 0.7,            // Optional: 0.0-2.0
  "max_tokens": 1024,            // Optional: max response tokens
  "intent": "explain",           // Optional: code/explain/refactor/tests
  "language": "python",          // Optional: target language
  "complexity": "medium",        // Optional: simple/medium/complex
  "project": "my-app"            // Optional: project name for routing
}
```

**Response:**
```json
{
  "response": "The Repository pattern is a design pattern...",
  "model": "qwen2.5-coder:7b",
  "provider": "ollama",
  "tokens_in": 45,
  "tokens_out": 312,
  "latency_ms": 1847
}
```

---

### Code Completion

**POST** `/api/complete`

Inline code completion and autocomplete.

**Request:**
```json
{
  "prompt": "def factorial(n):",
  "language": "python",
  "max_tokens": 256,
  "temperature": 0.2
}
```

**Response:**
```json
{
  "completion": "\n    if n <= 1:\n        return 1\n    return n * factorial(n - 1)",
  "model": "qwen2.5-coder:7b",
  "provider": "ollama",
  "tokens_in": 12,
  "tokens_out": 38,
  "latency_ms": 523
}
```

---

### Code Explanation

**POST** `/api/explain`

Explain code snippets in natural language.

**Request:**
```json
{
  "code": "const memoize = fn => { const cache = new Map(); return (...args) => { const key = JSON.stringify(args); return cache.has(key) ? cache.get(key) : cache.set(key, fn(...args)).get(key); }; };",
  "language": "javascript",
  "detail_level": "high"      // Optional: low/medium/high
}
```

**Response:**
```json
{
  "explanation": "This code implements memoization, a performance optimization technique...",
  "model": "claude-3-5-sonnet-20241022",
  "provider": "anthropic",
  "tokens_in": 87,
  "tokens_out": 245,
  "latency_ms": 2134
}
```

---

### Code Edit

**POST** `/api/edit`

Edit code with AI assistance (supports MCP file operations).

#### Direct Code Edit

**Request:**
```json
{
  "code": "def greet(name):\n    print(f'Hello {name}')",
  "instruction": "Add type hints and docstring",
  "language": "python"
}
```

#### File-Based Edit (MCP)

**Request:**
```json
{
  "file": "/path/to/file.py",
  "instruction": "Refactor to use async/await",
  "language": "python",
  "dry_run": true              // Optional: generate diff without applying
}
```

**Response:**
```json
{
  "edited_code": "def greet(name: str) -> None:\n    \"\"\"Print a greeting message.\"\"\"\n    print(f'Hello {name}')",
  "diff": "@@ -1,2 +1,3 @@\n-def greet(name):\n+def greet(name: str) -> None:\n+    \"\"\"Print a greeting message.\"\"\"\n     print(f'Hello {name}')",
  "model": "qwen2.5-coder:7b",
  "provider": "ollama",
  "tokens_in": 45,
  "tokens_out": 78,
  "latency_ms": 1245
}
```

---

### Status

**GET** `/api/status`

Get server and routing statistics.

**Response:**
```json
{
  "status": "running",
  "uptime_seconds": 3600,
  "providers": {
    "ollama": "healthy",
    "omen": "healthy",
    "mcp": "connected"
  },
  "routing_stats": {
    "total_requests": 1523,
    "local_requests": 1234,
    "cloud_requests": 289,
    "avg_latency_ms": 876
  }
}
```

## Request/Response Formats

### Common Request Parameters

All endpoints support these optional routing hints:

| Parameter | Type | Description | Values |
|-----------|------|-------------|--------|
| `intent` | string | Task type for smart routing | `code`, `completion`, `refactor`, `tests`, `explain`, `architecture`, `reason` |
| `language` | string | Programming language | `python`, `javascript`, `rust`, `zig`, etc. |
| `complexity` | string | Estimated task complexity | `simple`, `medium`, `complex` |
| `project` | string | Project name for context | Any string |
| `priority` | string | Routing priority | `low-latency`, `high-quality`, `cost-effective` |

### Common Response Fields

All API responses include:

| Field | Type | Description |
|-------|------|-------------|
| `model` | string | Actual model used |
| `provider` | string | Provider that handled request (`ollama`, `anthropic`, `openai`, `omen`) |
| `tokens_in` | number | Input tokens consumed |
| `tokens_out` | number | Output tokens generated |
| `latency_ms` | number | Response time in milliseconds |

### Smart Routing Behavior

Zeke automatically routes requests based on:

1. **Intent**: `code`/`completion`/`refactor` → Local Ollama (fast)
2. **Complexity**: `simple` → Local, `complex` → Cloud (quality)
3. **Fallback**: Local timeout/error → Automatic cloud escalation
4. **Cost**: Respects `max_cloud_cost_cents` configuration

## Error Handling

### Error Response Format

```json
{
  "error": "Error message",
  "code": "ERROR_CODE",
  "details": "Additional context"
}
```

### Common HTTP Status Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 400 | Bad Request | Invalid JSON, missing required fields |
| 500 | Internal Server Error | Provider failure, routing error |
| 503 | Service Unavailable | All providers down |

### Example Error Response

```json
{
  "error": "All providers unavailable",
  "code": "NoProvidersAvailable",
  "details": "Ollama: connection refused, OMEN: timeout"
}
```

## Examples

### Python Client

```python
import requests

BASE_URL = "http://localhost:7878"

def chat(message: str, language: str = None) -> dict:
    response = requests.post(
        f"{BASE_URL}/api/chat",
        json={
            "message": message,
            "language": language,
            "intent": "explain",
        }
    )
    return response.json()

# Usage
result = chat("How do I use async/await?", "python")
print(result["response"])
print(f"Provider: {result['provider']}, Latency: {result['latency_ms']}ms")
```

### JavaScript/TypeScript Client

```typescript
const ZEKE_API = "http://localhost:7878";

interface CompletionRequest {
  prompt: string;
  language?: string;
  max_tokens?: number;
}

async function complete(req: CompletionRequest): Promise<any> {
  const response = await fetch(`${ZEKE_API}/api/complete`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  return response.json();
}

// Usage
const result = await complete({
  prompt: "function isPrime(n) {",
  language: "javascript",
  max_tokens: 256,
});
console.log(result.completion);
```

### Rust Client

```rust
use reqwest;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct EditRequest {
    code: String,
    instruction: String,
    language: String,
}

#[derive(Deserialize)]
struct EditResponse {
    edited_code: String,
    model: String,
    provider: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();

    let request = EditRequest {
        code: "fn main() { println!(\"Hello\"); }".to_string(),
        instruction: "Add error handling".to_string(),
        language: "rust".to_string(),
    };

    let response = client
        .post("http://localhost:7878/api/edit")
        .json(&request)
        .send()
        .await?
        .json::<EditResponse>()
        .await?;

    println!("Edited code:\n{}", response.edited_code);
    println!("Provider: {}", response.provider);
    Ok(())
}
```

### Bash/cURL

```bash
#!/usr/bin/env bash

# Chat completion
curl -X POST http://localhost:7878/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Explain Python decorators",
    "language": "python",
    "intent": "explain"
  }'

# Code completion
curl -X POST http://localhost:7878/api/complete \
  -H 'Content-Type: application/json' \
  -d '{
    "prompt": "class User:",
    "language": "python",
    "max_tokens": 512
  }'

# File-based edit with MCP
curl -X POST http://localhost:7878/api/edit \
  -H 'Content-Type: application/json' \
  -d '{
    "file": "src/main.py",
    "instruction": "Add comprehensive docstrings",
    "language": "python",
    "dry_run": true
  }'
```

## Advanced Features

### MCP Integration

When Glyph MCP is configured, the `/api/edit` endpoint supports:

- **File-based operations**: Pass `file` instead of `code`
- **Automatic diff generation**: Get unified diffs via `diff.generate`
- **Safe application**: `dry_run: true` previews changes
- **Tool metrics**: MCP operations logged to `tool_calls` table

**Configuration:**

```json
{
  "services": {
    "glyph": {
      "enabled": true,
      "mcp": {
        "stdio": {
          "command": "/path/to/glyph",
          "args": ["serve", "--transport", "stdio"]
        }
      }
    }
  }
}
```

### WebSocket MCP (Real-time)

For persistent connections and streaming:

```json
{
  "services": {
    "glyph": {
      "enabled": true,
      "mcp": {
        "websocket": {
          "url": "ws://localhost:8080/mcp"
        }
      }
    }
  }
}
```

WebSocket transport provides:
- Persistent connections (no spawn overhead)
- Automatic reconnection
- Ping/pong keep-alive
- Lower latency for repeated calls

### Metrics & Observability

All requests are logged to `~/.local/share/zeke/routing.db`:

```sql
-- View recent routing decisions
SELECT
  provider, model, intent, latency_ms, tokens_in, tokens_out, cost_cents
FROM routing_stats
ORDER BY created_at DESC LIMIT 10;

-- MCP tool performance
SELECT
  tool_name, AVG(latency_ms) as avg_latency, COUNT(*) as calls
FROM tool_calls
GROUP BY tool_name;
```

## Best Practices

### 1. Use Model Aliases

Configure aliases in `config.json` for easy switching:

```json
{
  "model_aliases": {
    "fast": "llama3.2:1b",
    "smart": "claude-3-5-sonnet-20241022",
    "local": "qwen2.5-coder:7b",
    "balanced": "llama3.2:3b"
  }
}
```

Then use in requests:
```json
{"message": "...", "model": "fast"}
```

### 2. Set Intent for Better Routing

Help Zeke choose the right provider:

```json
{
  "message": "...",
  "intent": "completion",     // → Local Ollama (fast)
  "complexity": "simple"
}
```

vs

```json
{
  "message": "...",
  "intent": "architecture",   // → Cloud provider (quality)
  "complexity": "complex"
}
```

### 3. Use Dry Run for Code Edits

Always preview changes before applying:

```json
{
  "file": "critical_file.py",
  "instruction": "refactor",
  "dry_run": true              // Get diff first
}
```

### 4. Monitor Health

Regular health checks in production:

```bash
*/5 * * * * curl -f http://localhost:7878/health || alert
```

### 5. Handle Escalation

Check `provider` in responses to detect cloud escalation:

```python
result = chat("complex architecture question")
if result["provider"] != "ollama":
    print(f"⚠️ Escalated to {result['provider']}")
    print(f"Cost estimate: ${result.get('cost_estimate', 0):.4f}")
```

## Troubleshooting

### Server Won't Start

```bash
# Check if port is in use
lsof -i :7878

# Check config validity
cat ~/.config/zeke/config.json | jq .

# Run with debug logging
zeke serve --log-level debug
```

### "No providers available"

```bash
# Run health check
zeke doctor

# Check Ollama
docker ps | grep ollama

# Check OMEN
curl http://localhost:3000/health
```

### MCP Not Working

```bash
# Test MCP connection
zeke glyph ls

# Check Glyph process
ps aux | grep glyph

# Test stdio transport
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | /path/to/glyph serve --transport stdio
```

### High Latency

```sql
-- Check routing stats
sqlite3 ~/.local/share/zeke/routing.db "
  SELECT provider, AVG(latency_ms), COUNT(*)
  FROM routing_stats
  GROUP BY provider;
"

-- Check for cloud escalation
sqlite3 ~/.local/share/zeke/routing.db "
  SELECT COUNT(*) as escalated_requests
  FROM routing_stats
  WHERE escalated = 1;
"
```

## Support

- **GitHub Issues**: https://github.com/anthropics/zeke/issues
- **Documentation**: https://github.com/anthropics/zeke/docs
- **CLI Help**: `zeke --help`, `zeke doctor`
