TODO — Zeke CLI (Core)

Goal: Claude-Code–class CLI with local (Ollama) + cloud (OpenAI/Azure/Anthropic) behind one switch.
Non-goals (here): Neovim/Grim plugins, UI polish — separate repos.

0) Done When (Definition of Done)

zeke ask|edit|explain|test works end-to-end using model aliases.

Single /v1 base URL (Omen or LiteLLM) configured in zeke.toml.

Ollama models selectable (code-fast, code-plus).

OpenAI/Azure working via API key.

Claude works via API key and Google sign-in (token exchange).

Glyph MCP tools wired for file read/write/scan/search with diff/patch apply.

Minimal logs + retries; errors are user-legible.

1) Config & Boot

 Create ~/.config/zeke/zeke.toml with provider aliases.

 Load env vars securely; never print keys.

 Health check command: zeke doctor (pings /v1, lists models, checks Glyph tools).

# ~/.config/zeke/zeke.toml
[api]
base_url = "http://localhost:8080/v1"   # Omen or LiteLLM
api_key  = "env:ZEKE_API_KEY"           # optional; per-provider keys below

[aliases]
code-fast   = "ollama:deepseek-coder:14b"
code-plus   = "ollama:deepseek-coder:33b"
code-smart  = "azure:gpt-5-codex"       # or openai:gpt-4o-mini
reason-deep = "anthropic:claude-3-5-sonnet"

[providers.openai]
api_key = "env:OPENAI_API_KEY"

[providers.azure]
endpoint = "https://your-aoai.openai.azure.com/"
api_key  = "env:AZURE_OPENAI_API_KEY"

[providers.anthropic]
api_key = "env:ANTHROPIC_API_KEY"       # if not using Google OIDC path

[providers.ollama]
endpoints = "http://127.0.0.1:11434"    # CSV allowed
timeout_ms = 45000


Env vars:

export OPENAI_API_KEY=...
export AZURE_OPENAI_API_KEY=...
export ANTHROPIC_API_KEY=...            # optional if using Google sign-in
export OLLAMA_HOST=http://127.0.0.1:11434

2) Omen / LiteLLM Wiring (OpenAI-compat)

 Implement OpenAI /v1/chat/completions client with SSE streaming.

 --model <alias|raw> → resolves via [aliases] or passes raw model name.

 Tags/metadata: intent=code|reason|tests, project, editor=cli.

CLI UX:

zeke ask "why is my iterator alloc-heavy?" --model code-fast
zeke edit --file src/lib.rs --instruction "inline small fns; reduce allocs"
zeke explain --file build.zig
zeke test --project .

3) Glyph MCP Tooling (Rust)

 Wire MCP client to Glyph (stdio or ws).

 Implement calls:

read_file(path) -> {contents}

write_file(path, contents|patch)

scan_workspace(root, globs, ignore_git)

search(root, pattern, ripgrep_opts)

 Diff/patch flow: LLM → unified diff → apply_patch via Glyph tool.

Acceptance tests:

 zeke edit produces a diff and applies cleanly on 10 sample repos.

 Rollback on failure (git stash or backup file).

4) Local Ollama (Deepseek et al.)

 Fast model listing from Ollama endpoints.

 Basic prompt shaping for code tasks (short context, strict format).

 Fallback strategy: if Ollama timeout → use code-smart alias (cloud).

Health checks:

zeke doctor --ollama
# prints reachable endpoints, models, and avg latency

5) Auth
5.1 API Keys (baseline)

 Read OPENAI_API_KEY, AZURE_OPENAI_API_KEY, ANTHROPIC_API_KEY.

 Redact in logs; validate at startup with a cheap /models call.

5.2 Google Sign-In → Claude (OIDC)

 zeke login google opens device flow / local callback.

 Exchange Google OIDC token → Omen backend issues Zeke token or maps to Anthropic key (server side).

 Persist short-lived session token to keyring (libsecret/keychain); no plaintext on disk.

CLI UX:

zeke login google   # prints account, expires, providers enabled
zeke whoami         # shows active identity + scopes

6) UX & Ergonomics

 Progress spinners & byte counters for streaming.

 --dry-run prints diff without applying.

 --context flags: --lines-before, --lines-after, --files path1,path2.

 ~/.config/zeke/snippets/ prompt templates (TOML/Markdown).

7) Reliability

 Retries with jitter (network/provider).

 Timeouts per provider (Ollama longer for 33B).

 Circuit breaker per endpoint; auto-degrade to next alias.

 Minimal telemetry (failed/success ops, latency histograms).

8) Minimal Docs

 README.md quick start (Omen + Ollama + OpenAI keys).

 CONFIG.md (zeke.toml schema).

 USAGE.md with 10 copy-paste recipes (ask/edit/explain/test, dry-run, model switch).

9) Quick Validation Script

 scripts/smoke.sh:

checks /v1 reachability,

runs ask, edit --dry-run,

exercises Glyph tools,

sanity on Ollama (deepseek 14/33B).

10) Nice-to-Have (after core lands)

 Embeddings (/v1/embeddings) for semantic search cache.

 Simple “context pack” file (list of paths + summaries).

 zeke doctor --fix (auto-create zeke.toml, suggest env setup).

Tiny Reference: Omen docker-compose (dev)
services:
  omen:
    image: ghcr.io/yourorg/omen:latest
    environment:
      OMEN_BIND: "0.0.0.0:8080"
      OMEN_OPENAI_API_KEY: "${OPENAI_API_KEY}"
      OMEN_ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
      OMEN_OLLAMA_ENDPOINTS: "http://host.docker.internal:11434"
      OMEN_BUDGET_MONTHLY_USD: "100"
    ports: ["8080:8080"]


Priority order: Config + Omen client → Glyph tools → Ollama wiring → API-key auth → Google sign-in for Claude → UX polish → retries/health.

That’s the shortest path to a Claude-Code-class Zeke CLI with local & cloud models under one roof.
