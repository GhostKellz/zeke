# Zeke v0.3.2 - New Features 🚀

## What's New

### 🎨 Tokyo Night Theme System
- **Three beautiful variants:**
  - **Night** (default) - Deep dark theme with vibrant colors
  - **Moon** - Softer contrast for extended coding sessions
  - **Storm** - Warmer tones for a cozy feel

- **Easy configuration:**
  ```toml
  # ~/.config/zeke/zeke.toml
  [ui]
  theme = "night"  # or "moon", "storm"
  ```

- **True color ANSI support** for modern terminals (Ghostty, WezTerm, Kitty, Alacritty)

### 🔐 Secure API Key Storage
- **New commands:**
  ```bash
  zeke auth set-key google AIzaSy...   # Store securely in system keyring
  zeke auth get-key google              # Retrieve for debugging
  ```

- **Priority order:** Cache → Keyring → Environment variables
- **Platform support:** Linux (GNOME Keyring), macOS (Keychain), Windows (Credential Manager)

### 🤖 GitHub Copilot Pro Integration
- **Full OAuth support** - Use your $10/month subscription!
- **19+ premium models:**
  - GPT-5, GPT-5-Codex, GPT-5-Mini
  - Claude Opus 4, Claude Sonnet 4.5, Claude Haiku 4.5
  - Gemini 2.5 Pro, Gemini 2.0 Flash
  - O3, O3-Mini, O4-Mini
  - Grok Code Fast

### 📊 Models.dev Integration
- Comprehensive model database
- Model capabilities tracking (vision, reasoning, tool calls)
- Context/output limits
- Status tracking (active/deprecated/beta)

### 🧠 Smart Model Routing
- **Task-based routing:**
  - Code completion → `gpt-5-codex`
  - Code review → `claude-sonnet-4.5`
  - Reasoning → `claude-opus-4`
  - Fast response → Local Ollama

- **Automatic fallbacks** if primary provider fails
- **Cost-aware** - prefers local models when possible

## Value Proposition

**With OAuth:**
- Claude Pro ($20/month) + Copilot Pro ($10/month) = **$30/month**
- Access to 30+ premium models

**Without OAuth (API credits):**
- Claude API: $50-100/month
- OpenAI API: $50-100/month
- **Total: $100-200/month**

**💰 Save $70-170/month!**

## Quick Start

```bash
# 1. Authenticate with OAuth providers
zeke auth claude
zeke auth copilot

# 2. Store API keys securely (Google, etc.)
zeke auth set-key google YOUR_API_KEY

# 3. Configure theme (optional)
cp zeke.toml.example ~/.config/zeke/zeke.toml
# Edit [ui] theme = "night" / "moon" / "storm"

# 4. Use smart routing
zeke chat "Write a Zig function"
# Automatically routes to best model!
```

## Configuration Example

See `zeke.toml.example` for full configuration options:
- Theme selection
- Provider preferences
- Smart routing settings
- Performance tuning
- Security options

## Files Added

- `src/ui/themes.zig` - Tokyo Night theme system
- `src/models/mod.zig` - Model database
- `src/routing/smart_router.zig` - Intelligent routing
- `src/cli/auth.zig` - Enhanced with set-key/get-key
- `src/auth/manager.zig` - Keyring integration
- `zeke.toml.example` - Configuration template

## Next Release

- Full models.dev TOML parsing
- MCP integration enhancements
- Watch mode improvements
- More themes (Catppuccin, Gruvbox)

---

