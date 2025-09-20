# GhostStack Overview – Unified AI + DevOps Architecture

This document describes how **GhostLLM, Zeke, Jarvis, and GhostFlow** interoperate to form a unified AI‑native development and operations ecosystem. It also defines how we leverage both **cloud providers** (Claude, GPT, Copilot, Grok, Gemini) and **local models** (Ollama on 4090/3070) with seamless routing and *clean, low‑latency swaps* between agents.

---

## 1. Core Projects & Responsibilities

### **GhostLLM** – The Brain

* Rust‑native enterprise LLM proxy + router.
* Provides an **OpenAI‑compatible API** (`/v1/chat/completions`, `/responses`, etc.).
* Manages **multi‑provider routing**:

  * Anthropic Claude (Pro via Google SSO)
  * OpenAI GPT‑4/5
  * GitHub Copilot (via GitHub/Azure fallback)
  * Grok (xAI)
  * Google Gemini
  * Local Ollama (4090 workstation + 3070 server)
* Features:

  * Auth: Google/GitHub/Microsoft SSO, API key storage.
  * Usage: per‑provider quotas, cost tracking, throttling.
  * Routing: intent detection + weights + quotas.
  * Streaming: WebSocket + REST.
  * GhostWarden module: consent + policy enforcement.

👉 **GhostLLM is the single entry point**. Every other project consumes it.

---

### **Zeke** – Developer Companion (ClaudeCode replacement)

* Rust‑native Neovim + CLI/TUI plugin.
* Provides:

  * Floating chat/action panel (like claude‑code.nvim).
  * Inline completions, `/explain`, `/fix`, `/test` commands.
  * Action proposals → user approves (Allow once/Allow all/Deny).
  * Diff previews, file patch integration.
* Delegates **all LLM traffic** to GhostLLM.
* Optimized for **fast coding workflows**.

👉 **Zeke never stores API keys**. It’s a client UI bound to GhostLLM.

---

### **Jarvis** – System & Infra Copilot

* Rust‑native CLI daemon.
* Focused on:

  * Arch Linux management (AUR, Snapper, Btrfs).
  * Homelab/infra orchestration (Proxmox, Docker, DNS, VPN).
  * Crypto/smart contract monitoring.
* Uses GhostLLM for reasoning → translates natural language → CLI/system commands.
* Long‑lived agent with background monitoring.

👉 **Jarvis = your AI‑powered sysadmin + crypto watchdog**.

---

### **GhostFlow** – Orchestration Layer

* Rust‑native workflow engine (n8n alternative).
* Local‑first, with Leptos GUI.
* Provides:

  * Node‑based workflow editor.
  * Connectors: HTTP, webhook, DB, AI nodes, Jarvis nodes.
  * Orchestration of **both AI and system tasks**.
* Delegates LLM calls to GhostLLM.
* Delegates system calls to Jarvis.

👉 **GhostFlow = automation + GUI orchestration**.

---

## 2. Model Routing & Clean Swaps

GhostLLM must intelligently choose providers **without user waiting or context loss**.

### Strategy

1. **Intent Detection** (code vs chat vs infra vs crypto vs math).
2. **Cost + Quota Check** (don’t burn Claude if near cap, prefer local if idle).
3. **Latency Awareness** (prefer 4090 Ollama for short hops, fallback to Claude/GPT for long reasoning).
4. **Session Stickiness**:

   * A conversation/session stays on one model unless explicitly re‑routed.
   * Router can upgrade model mid‑stream only if user enables *auto‑swap*.

### Fast Swaps

* **GhostLLM keeps context buffer** in Redis/SQLite.
* On swap:

  * Replay conversation history to new model.
  * Maintain `session_id` for Zeke/Jarvis.
* To user, swap feels instantaneous (stream pauses <250ms, resumes from new model).

👉 Goal: **Switch models without losing tokens, time, or context.**

---

## 3. Local vs Cloud Usage

* **Local (4090/3070 via Ollama)**

  * Default for: code completions, regex, refactors, quick tests.
  * Models: DeepSeek‑Coder, Llama‑3, Qwen‑2.5, others.
  * Advantage: 0 cost, low latency.
* **Cloud (Claude/GPT/Grok/Gemini)**

  * Used for: long reasoning, large context, high accuracy tasks.
  * Claude Pro + GPT‑5 reserved for complex coding/design.
  * Copilot used inside Neovim for inline assist if desired.

Routing example:

```
Explain systemd crash → Claude 3.5 Pro
Refactor Rust function → DeepSeek‑Coder (Ollama 4090)
Generate tests across repo → GPT‑5 (cloud)
Monitor smart contract event → Grok
Fix pacman conflict on Arch → Jarvis (calls GhostLLM for reasoning)
```

---

## 4. GhostWarden (Policy + Security)

* Embedded in GhostLLM.
* Defines rules like:

```toml
[capabilities]
fs.write = "prompt"
cmd.exec  = "deny"
net.http  = "allow"

[scopes]
"repo:ghostctl".fs.write = "allow"
```

* Enforces **Allow once / Allow all / Deny** workflow.
* Ensures AI never runs unsafe actions without explicit approval.

---

## 5. Workflow Example

**Scenario: Refactor & Deploy Rust Service**

1. In Neovim, user hits `<leader>z` → opens Zeke panel.
2. Zeke sends context → GhostLLM.
3. GhostLLM detects coding intent → routes to DeepSeek‑Coder (Ollama 4090).
4. LLM proposes patch → GhostWarden intercepts → user approves.
5. Patch applied.
6. Jarvis monitors build → detects cargo failure.
7. Jarvis requests explanation → GhostLLM routes to GPT‑5.
8. GhostFlow triggers pipeline → runs deploy node → pushes to Proxmox container.

All with **seamless model swaps** and **single consent flow**.

---

## 6. Roadmap Priorities

**Phase 1 – GhostLLM Core**

* Provider adapters: Claude, OpenAI, Ollama.
* Routing engine (intent + quota + latency).
* WebSocket streaming.
* GhostWarden MVP.

**Phase 2 – Zeke.nvim**

* Floating panel, diff preview.
* Action approval UI.
* Connect to GhostLLM.

**Phase 3 – Jarvis**

* System command library (Arch, Proxmox, Docker).
* Agent/daemon mode.
* Connect to GhostLLM for reasoning.

**Phase 4 – GhostFlow**

* Leptos UI for workflows.
* AI + system nodes.
* Orchestration with Jarvis + GhostLLM.

**Phase 5 – Optimization**

* Fast model swap pipeline (<250ms pause).
* Usage dashboard.
* Multi‑GPU Ollama scheduling (4090 vs 3070).

---

## 7. Key Principles

* **One brain (GhostLLM)**, many faces (Zeke, Jarvis, GhostFlow).
* **Local‑first** (4090/3070 Ollama) with cloud assist.
* **Agentic, but user‑guarded** (GhostWarden approval).
* **Seamless model swaps** – no lost time, no lost context.
* **Composable** – GhostFlow orchestrates, Jarvis automates, Zeke develops.

---

## 8. Vision

GhostStack becomes the **first Rust‑native, multi‑agent ecosystem** that:

* Matches and surpasses ClaudeCode/Copilot.
* Runs *local + cloud* models together.
* Lets users **trust AI in system + dev workflows** through guardrails.
* Provides both **pro GUI (GhostFlow)** and **power CLI (Jarvis/Zeke)**.
* Ensures you always get the **fastest, cheapest, and safest** model for the task.

