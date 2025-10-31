<div align="center">
  <img src="assets/zeke-logo.png" alt="Zeke Logo" width="128" height="128" />
</div>

# ⚡ ZEKE v0.3.0 - The Zig-Native AI Dev Companion

<div align="center">

![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white)
![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-orange?style=for-the-badge)
![Multi-Provider AI](https://img.shields.io/badge/Multi--Provider-AI-blue?style=for-the-badge&logo=openai&logoColor=white)
![Async Runtime](https://img.shields.io/badge/Async-Runtime-green?style=for-the-badge&logo=lightning&logoColor=white)
![Version](https://img.shields.io/badge/Version-0.3.0-brightgreen?style=for-the-badge)

</div>

---
## 🧠 Guiding Principle
**Zeke thinks. Omen routes. GhostLLM speaks. Glyph connects. Rune acts. Grim creates.**

---
### The Next-Gen AI Copilot for CLI & Development Workflows
ZEKE brings lightning-fast, native Zig performance to AI-powered coding workflows, integrating:

* **GitHub Copilot** (chat, inline, code actions)
* **OpenAI** (GPT-4, GPT-4o, GPT-3.5)
* **Anthropic Claude** (3.5, 4, Pro via Google sign-in)
* **Ollama/local LLMs** (optional)
* **Google Gemini** 
* **LiteLLM integration AI proxy functionality** 
* **More soon!**

**Authenticate with GitHub, Google, OpenAI. Switch models live.**
Accept completions, chat, run `/explain`, `/fix`, and more—all inside Neovim or your terminal.

**Leverage existing language models and services like github copilot pro and quickly switch between models just like vscode + github copilot extension **

---

## ✨ Features

* ⚡ **Zig v0.16, Async-First:** Written entirely in Zig for pure speed and memory safety
* 🔥 **zsync Runtime:** True non-blocking async calls and parallel AI requests
* 🤖 **Multi-Backend:** Seamlessly use Copilot, ChatGPT, Claude, local LLMs
* 📝 **Chat + Actions:** Panel chat, inline, batch code actions, `/explain` & `/test` commands
* 🔑 **Auth:** Sign in with GitHub (Copilot), Google (Claude), OpenAI keys—configurable
* 🖥️ **Dev Focus:** Refactor, doc, review, batch ops—no cloud lock-in, all from Nvim & CLI
* 🔌 **Extensible:** CLI, TUI, and plugin API for automation, batch, and scripting
* 👁️ **Watch Mode (Revolutionary):** Real-time file watching with Grove AST, AI-powered fix suggestions, and auto-commit
* 📋 **TODO Tracker:** Intelligent TODO comment detection with priorities, categories, assignees, and issue tracking
* 🔍 **Codebase Indexing:** Fast symbol search, fuzzy matching, and AI context gathering across multi-language projects

---


## 📦 Quick Start

> **Requirements:**
>
> * Zig v0.16+
> * Neovim 0.9+
> * AI provider accounts

**Using Zig package manager:**
```sh
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz
zig build -Drelease-fast
```

**Or build from source:**
```sh
git clone https://github.com/ghostkellz/zeke.git
cd zeke
zig build -Drelease-fast
nvim
# Run :Zeke to launch the AI panel
```

**Or use your favorite plugin manager:**

```lua
-- Packer.nvim example
use { 'ghostkellz/zeke', run = 'zig build -Drelease-fast' }
```

---

## 🛠️ Keybindings (Default)

| Action                                    | Command / Keybinding   |
| ----------------------------------------- | ---------------------- |
| Open Zeke panel                           | `<leader>ac` / `:Zeke` |
| Accept suggestion                         | `<C-g>` / `<C-l>`      |
| Next/Prev suggestion                      | `<C-]>` / `<C-[>`      |
| Dismiss                                   | `<C-\\>`               |
| Open AI palette                           | `<leader>ai`           |
| Toggle inline AI                          | `<leader>at`           |
| Remap in `init.lua`/`zeke.toml` as needed |                        |

---

## 🔒 Auth Setup

* **Copilot:** `export GITHUB_TOKEN=ghp_xxx` (or sign in from panel)
* **Claude:** Google sign-in in the panel
* **OpenAI:** `export OPENAI_API_KEY=sk-xxx`
* **Ollama/local:** Set endpoint in `zeke.toml`

---

## 🌐 Model Switching (On the Fly)

Switch between AI providers and models live:

* `/model copilot`
* `/model gpt-4`
* `/model claude-4`
* `/model local`

---

## ⚡ Example Usage

### Chat & Completion
* `:Zeke` — Open the chat panel
* `<leader>ac` — Accept code completion
* `:Zeke explain` — Ask for code explanation
* `:Zeke test` — Ask for test cases
* `/model claude-3.5` — Change AI backend live

### Codebase Indexing (New!)
```sh
# Index your project for fast symbol search
zeke index build

# Search for symbols across your codebase
zeke index search "handleRequest"

# Find exact symbol by name
zeke index find "calculateTotal"

# Get relevant files for a task (AI context gathering)
zeke index context "implement user authentication"

# List all functions/structs/classes
zeke index functions
zeke index structs
zeke index classes

# Show index statistics
zeke index stats
```

### Watch Mode (Revolutionary!)
```sh
# Basic watch - monitors files and detects issues
zeke watch

# Auto-fix mode - applies AI-suggested fixes automatically
zeke watch --auto-fix

# Auto-commit mode - commits changes when tests pass
zeke watch --auto-commit

# Combined - full AI development loop
zeke watch --auto-fix --auto-commit
```

**What Watch Mode Does:**
* 📁 Watches files for changes with inotify (Linux) or fs events (macOS)
* 🌳 Parses code with Grove AST for syntax-aware analysis
* 🔍 Detects issues: unused variables, TODOs, missing tests, syntax errors
* 🤖 Generates fix suggestions via local Ollama LLM
* ✨ Auto-applies fixes when `--auto-fix` is enabled
* ✅ Runs tests before committing
* 📝 Auto-commits passing changes with `--auto-commit`

**TODO Detection Features:**
* Priority levels: `FIXME` (critical), `TODO!!!` (high), `TODO!!` (medium), `TODO!` (low)
* Categories: Bug Fix, Refactor, Optimization, Documentation, Feature, Security, Test
* Assignee tracking: `TODO(@username): message`
* Issue references: `TODO(#123): message`
* Context extraction with surrounding code

---

## 💡 Roadmap

* Project/file search and edit
* Claude Code CLI in your terminal
* Full zsh/bash AI autocomplete
* Multi-file refactor and review
* Plugin API for advanced automation

---

## 🤝 Contributing

PRs, issues, ideas, and flames welcome!
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for style and Zig patterns.

---

## 👻 Built with paranoia and joy by [GhostKellz](https://github.com/ghostkellz)

