North star

One OpenAI-compatible base URL for Zeke (Omen or LiteLLM).

Model aliases (e.g., code-fast, code-smart, reason-deep) that map to local Ollama or cloud providers.

Editor parity: inline completions, chat actions, diff-apply, multi-file context.

Glyph for tools (fs read/write/search) + Rune only for hot file ops.

Architecture (practical)
Zeke CLI / zeke.nvim / zeke.grim
    │
    ├─ Glyph (MCP) → tools: read_file, write_file, scan, search  (Rune optional under the hood)
    │
    └─ OpenAI-compatible endpoint (choose one per environment)
         • Omen  (preferred long-term: auth/quotas/routing)
         • LiteLLM (you already have it; great for quick start)
             ↳ Providers: OpenAI/Azure • Anthropic • Gemini • Ollama (Deepseek, Llama, etc.)


Decision: Point Zeke at one /v1 URL (Omen or LiteLLM). You can switch later without changing Zeke.

Concrete next steps (2-week sprint)
Week 1 — Zeke core + routing

Provider shim (OpenAI spec) in Zeke:

Chat/completions, embeddings, tool_calls passthrough.

SSE/WebSocket streaming.

Model aliases in zeke.toml:

code-fast -> ollama:deepseek-coder:14b

code-plus -> ollama:deepseek-coder:33b

code-smart -> azure:gpt-5-codex (or OpenAI fallback)

reason-deep-> anthropic:claude-3.5

Context packer:

Selected region + N lines context, plus path + lang.

Optional “context set” (multiple files) with token budgeter.

Patch pathway:

LLM → diff/edits → apply via Glyph MCP tools.

Use Rune only if it gives measurable wins on apply_patch & search.

Week 2 — zeke.nvim parity moves

Inline completion (ghost text) + accept/next/dismiss keymaps.

Chat panel with streaming, quick actions (/explain, /fix, /test).

Diff-apply UI (preview → accept/reject) for edits.

File tree & visual selection → context (send to Zeke).

Model switcher (command + UI): :ZekeModel code-fast|code-smart|….

Ship this, then do Zeke.grim (same API—different host editor binding).

Minimal configs you can drop in
1) Zeke config (~/.config/zeke/zeke.toml)
[api]
# Point this at Omen OR LiteLLM (OpenAI-compatible)
base_url = "http://localhost:8080/v1"
api_key  = "env:ZEKE_API_KEY"  # or unused for local

[aliases]
code-fast   = "ollama:deepseek-coder:14b"
code-plus   = "ollama:deepseek-coder:33b"
code-smart  = "openai:gpt-4o-mini"          # or azure:gpt-5-codex
reason-deep = "anthropic:claude-3-5-sonnet"
local       = "ollama:llama3.1:8b-instruct"

[providers.openai]
api_key = "env:OPENAI_API_KEY"

[providers.azure]
endpoint = "https://your-aoai.openai.azure.com/"
api_key  = "env:AZURE_OPENAI_API_KEY"
# optional: deployment=model mappings if AOAI uses deployments

[providers.anthropic]
api_key = "env:ANTHROPIC_API_KEY"

[providers.ollama]
# Can be a CSV for multiple instances; Zeke can pick fastest/healthy
endpoints = "http://127.0.0.1:11434,http://192.168.1.50:11434"
timeout_ms = 45000


Keep Anthropic “Google sign-in” for later; prioritize API key path now (fewer moving parts).

2) LiteLLM quick route (if you keep it)
# litellm.yaml
model_list:
  - model_name: code-fast
    litellm_params: { model: "ollama/deepseek-coder:14b", api_base: "http://127.0.0.1:11434" }
  - model_name: code-plus
    litellm_params: { model: "ollama/deepseek-coder:33b", api_base: "http://127.0.0.1:11434" }
  - model_name: code-smart
    litellm_params: { model: "gpt-4o-mini", api_key: "${OPENAI_API_KEY}" }


Run LiteLLM with --config and set Zeke’s base_url to it.

3) Omen route (preferred long term)

Expose /v1/*, register providers (OpenAI/Azure/Anthropic/Ollama), enable quotas & stickiness.

Zeke uses model="auto" or your aliases; Omen chooses local Ollama for short code tasks, cloud for big reasoning.
