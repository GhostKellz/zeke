# 🧠 **Ghost AI Stack Overview**

> *“The network has a soul — and every ghost a purpose.”*

The **Ghost AI Stack** is a unified ecosystem of Rust and Zig projects
designed to power intelligent editors, developer tools, and agent systems.
Each layer serves a distinct role — from local performance to multi-provider AI routing.

---

## 🕸️ **System Relationship Map**

```
                    ┌──────────────────────────┐
                    │        Applications       │
                    │──────────────────────────│
                    │  Grim (Editor Core)       │
                    │   ├─ Phantom.grim (Config)│
                    │   ├─ Zeke.grim (AI Plugin)│
                    │   └─ GhostLS / Grove      │
                    │                          │
                    │  Zeke (CLI / Local AI)    │
                    │  Jarvis (Agent Hub)       │
                    │  GhostFlow (Workflow Eng.)│
                    └────────────┬──────────────┘
                                 │
                                 ▼
          ┌────────────────────────────────────────┐
          │   Glyph (Rust — MCP / Protocol Core)   │
          │────────────────────────────────────────│
          │ • JSON-RPC / MCP Contracts             │
          │ • Consent / Audit / Tracing / Sessions │
          │ • FFI for Zig (Rune)                   │
          └────────────┬───────────────────────────┘
                       │
                       ▼
     ┌─────────────────────────────────────────────────┐
     │  Omen (Rust — AI Router / Provider Gateway)     │
     │─────────────────────────────────────────────────│
     │ • OpenAI-compatible API surface (`/v1/*`)       │
     │ • Multi-provider routing (Claude, OpenAI, etc.) │
     │ • Latency / Cost / Quota aware router           │
     │ • SSO, audit, rate limits                       │
     └────────────┬────────────────────────────────────┘
                  │
                  ▼
     ┌─────────────────────────────────────────────────┐
     │  GhostLLM (Rust — LiteLLM Alternative)          │
     │─────────────────────────────────────────────────│
     │ • Model adapters: OpenAI, Anthropic, Gemini,    │
     │   Ollama, Bedrock, Azure                        │
     │ • Tracks token usage / latency / cost           │
     │ • Shared backend for Glyph / Omen / Jarvis      │
     └────────────┬────────────────────────────────────┘
                  │
                  ▼
     ┌─────────────────────────────────────────────────┐
     │  Rune (Zig — Local Compute Layer)               │
     │─────────────────────────────────────────────────│
     │ • Fast file ops, scanning, diffs, patching      │
     │ • FFI interface to Rust via `rune-ffi`          │
     │ • Zero network, pure performance layer          │
     │ • Integrated in Grim, Zeke, and Jarvis          │
     └─────────────────────────────────────────────────┘
```

---

## 🧩 **Project Breakdown**

### 🌀 **Glyph**

**Language:** Rust
**Role:** Core MCP / Transport Protocol Layer

* Handles session, consent, tracing, and auditing.
* Defines the Machine Control Protocol (MCP).
* Intermediary between clients (Zeke/Jarvis) and AI providers (Omen).
* Provides clean FFI surface for Rune (Zig integration).

> *Think: “Law and structure of the Ghost network.”*

---

### ⚡ **Rune**

**Language:** Zig
**Role:** Local Performance / Compute Layer

* High-performance file operations, patching, and scanning.
* Provides FFI bridge to Rust and Grim.
* No network dependencies — purely local execution.
* Shared by Grim, Zeke, and Jarvis for fast I/O.

> *Think: “Muscle and reflexes of the system.”*

---

### 🧠 **Omen**

**Language:** Rust
**Role:** AI Gateway and Router

* OpenAI-compatible API surface (`/v1/chat/completions`).
* Supports Anthropic, OpenAI, Gemini, Ollama, Azure, Bedrock.
* Smart routing: latency, intent, and cost-based selection.
* Manages budgets, API keys, rate limits, and SSO auth.

> *Think: “Voice and gateway of the Ghost Stack.”*

---

### 💬 **Zeke**

**Language:** Rust + Ghostlang (GZA)
**Role:** Local AI CLI / Coding Assistant

* CLI and TUI client for code assistance, refactoring, and AI interaction.
* Connects to Glyph for MCP, Rune for file ops, and Omen for model routing.
* Powers **Zeke.nvim** and **Zeke.grim** plugins.
* Integrates directly with Grim and GhostLLM.

> *Think: “Mind and intuition — the local assistant.”*

---

### 🧑‍💻 **Jarvis**

**Language:** Rust
**Role:** Agent Runtime and Automation Hub

* CLI orchestrator for multi-agent tasks.
* Uses Glyph and Omen for coordination.
* Calls Zeke for reasoning and GhostFlow for workflows.
* Will later add scheduling, memory, and self-hosted agents.

> *Think: “Spirit and automation.”*

---

### ⚙️ **GhostFlow**

**Language:** Rust
**Role:** Workflow Engine (like n8n / Temporal)

* Connects Jarvis agents, Zeke tasks, and Omen model calls.
* Orchestrates actions, prompts, and responses through DAGs.
* Replays workflows with audit trail via Glyph.

> *Think: “Circulatory system — moves the lifeblood of automation.”*

---

### 🧩 **GhostLLM**

**Language:** Rust
**Role:** Unified Model Interface / LiteLLM Alternative

* Normalizes API surface across providers.
* Tracks latency, usage, and cost.
* Provides local + remote inference routing.
* Shared runtime for Glyph, Omen, and Jarvis.

> *Think: “Engine room — all model power flows from here.”*

---

### 🕯️ **Grim**

**Language:** Zig
**Role:** Editor Core

* Zig-native TUI editor (Neovim-class).
* Integrates Rune, GhostLS, Grove, and Zeke.grim.
* Configured and themed through **Phantom.grim**.

> *Think: “The body — where the ghosts do their work.”*

---

### 👻 **Phantom.grim**

**Language:** Zig / Ghostlang (GZA)
**Role:** Grim Starter Framework / Config Distro

* LazyVim-style starter for Grim.
* Uses Ghostlang for configuration (replacing Lua).
* Ships with pre-wired Zeke, GhostLS, Grove, and themes.

> *Think: “The soul inside Grim — possession complete.”*

---

## 🪞 **Stack Summary Table**

| Project          | Language   | Role                   | Depends On        | Used By                 |
| ---------------- | ---------- | ---------------------- | ----------------- | ----------------------- |
| **Omen**         | Rust       | AI Router / Gateway    | GhostLLM          | Glyph, Zeke, Jarvis     |
| **Glyph**        | Rust       | MCP Protocol Core      | Rune (FFI)        | Zeke, Jarvis, GhostFlow |
| **Rune**         | Zig        | Local Compute Layer    | —                 | Grim, Zeke, Jarvis      |
| **Zeke**         | Rust + GZA | AI CLI / Assistant     | Glyph, Rune, Omen | Grim, Zeke.nvim, Jarvis |
| **Jarvis**       | Rust       | Agent / Automation Hub | Glyph, Omen, Zeke | GhostFlow               |
| **GhostFlow**    | Rust       | Workflow Engine        | Glyph, GhostLLM   | Jarvis                  |
| **GhostLLM**     | Rust       | Model Abstraction      | —                 | Omen, Glyph, Jarvis     |
| **Grim**         | Zig        | Editor Core            | Rune, Zeke.grim   | Phantom.grim            |
| **Phantom.grim** | Zig + GZA  | Config Distro          | Grim              | —                       |

---

## 🧭 **Philosophy of the Stack**

> **Glyph = Law**
> **Omen = Voice**
> **Rune = Muscle**
> **Zeke = Mind**
> **Jarvis = Spirit**
> **GhostFlow = Pulse**
> **GhostLLM = Engine**
> **Grim = Body**
> **Phantom.grim = Soul**

Together, they form the **Ghost Stack** —
a unified, modular AI + developer ecosystem designed for performance,
clarity, and spectral beauty.

---

### 📜 Tagline Options

* “The Haunted Developer Stack.”
* “Infrastructure for Intelligent Editors.”
* “Possess your tools. Command the network.”
* “A living protocol for creative code.”

