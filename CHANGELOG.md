# Changelog

All notable changes to Zeke will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2025-11-01

### Added - Premium OAuth Authentication 💎
- **Anthropic Claude Max OAuth** (PKCE Flow)
  - Full OAuth 2.0 implementation with PKCE (RFC 7636)
  - Manual authorization code entry flow (matches OpenCode)
  - Automatic gzip response decompression
  - Secure token storage in system keyring
  - Access token (8 hours) + refresh token support
  - Command: `zeke auth claude`
  - **Value**: Use existing $20/month Claude Max subscription, save $50-100/month in API costs

- **GitHub Copilot Pro OAuth** (Device Flow)
  - OAuth 2.0 Device Authorization Grant (RFC 8628)
  - Terminal-based device flow with animated spinner
  - No callback server needed
  - 10-minute authorization timeout
  - Command: `zeke auth copilot` or `zeke auth github`
  - **Value**: Use existing $10/month Copilot Pro subscription

- **System Keyring Integration**
  - Linux: GNOME Keyring / KWallet via `secret-tool`
  - macOS: Keychain via `security` command (ready, not yet tested)
  - Windows: Credential Manager via PowerShell (ready, not yet tested)
  - No plain-text token storage
  - Encrypted at rest by OS

- **New CLI Commands**
  - `zeke auth claude` - Authenticate with Claude Max
  - `zeke auth copilot` - Authenticate with GitHub Copilot
  - `zeke auth status` - Show authentication status for all providers
  - `zeke auth logout <provider>` - Remove OAuth tokens

- **Documentation**
  - `docs/oauth/README.md` - Comprehensive OAuth guide
  - `docs/oauth/implementation.md` - Technical implementation details
  - `docs/oauth/testing.md` - Testing procedures
  - `docs/oauth/success.md` - Implementation success story
  - `docs/claude/oauth.md` - Claude-specific OAuth documentation

### Changed
- Updated README with OAuth feature highlights
- Enhanced QUICKSTART with OAuth setup instructions
- Updated `zeke auth status` to show OAuth tokens
- Enhanced `zeke doctor` to check OAuth token validity

### Fixed
- Zig 0.16.0-dev API compatibility issues:
  - `std.io` module removal (use `std.fs.File` directly)
  - `std.mem.split()` renamed to `std.mem.splitScalar()`
  - `std.http.Client` API changes
  - `ArrayList` initialization API changes
- Memory leaks in OAuth token handling
- Gzip response decompression for Anthropic API
- Authorization code format handling (`code#state` split)
- Token exchange request format (JSON POST instead of form-urlencoded)

### Technical Details
- **PKCE Implementation**: RFC 7636 compliant with SHA-256 challenge
- **Token Exchange**: JSON POST to `https://console.anthropic.com/v1/oauth/token`
- **Scopes**: `org:create_api_key user:profile user:inference`
- **Client IDs**:
  - Anthropic: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public)
  - GitHub: `Iv1.b507a08c87ecfe98` (VS Code public client)
- **Decompression**: External `gunzip` for gzip-compressed responses
- **Zero External Dependencies**: Uses only Zig standard library + system tools

### Testing
- ✅ Live tested with real Claude Max account
- ✅ Token storage and retrieval verified
- ✅ Authentication status display working
- ⏳ GitHub Copilot OAuth (not yet tested with real account)
- ⏳ Token refresh logic (implemented, not yet tested)
- ⏳ macOS/Windows keyring (implemented, not yet tested)

### Removed
- Old `docs/ghostllm/` directory (outdated auto-generated docs)

## [0.3.0] - 2025-10-26

### Added
- **OAuth Broker Architecture**: Google and GitHub OAuth with broker-based authentication
- **MCP (Model Context Protocol)**: Full support for MCP servers via stdio, WebSocket, and Docker transports
- **Enhanced Provider Support**:
  - Azure OpenAI integration with deployment configuration
  - Google Gemini provider
  - xAI Grok integration
- **Configuration System**:
  - TOML-based configuration (`zeke.toml`)
  - Environment variable overrides
  - Multi-provider fallback chains
- **Advanced Routing**:
  - Intent-based routing (code, explain, refactor, tests, architecture, reason)
  - Complexity-aware model selection
  - Cost-conscious cloud escalation
- **New CLI Commands**:
  - `zeke config` - Configuration management subcommands
  - `zeke auth <provider>` - Provider-specific authentication
  - `zeke doctor` - System health diagnostics
- **Tool System**:
  - Code generation tools (codegen.zig planned)
  - Editor integration tools (editor.zig planned)
  - Web search and fetch capabilities
  - Static analysis engine foundation
- **Documentation**:
  - Comprehensive HTTP API documentation
  - Configuration guide with Docker examples
  - Installation guide for multiple platforms

### Changed
- **Breaking**: Migrated from JSON to TOML configuration format
- **Breaking**: OAuth flow now uses broker architecture instead of direct callbacks
- Upgraded to Zig 0.16.0-dev
- Improved async runtime with zsync 0.6.1
- Enhanced HTTP client with zhttp 0.1.2
- Updated phantom TUI to v0.6.3
- Database layer upgraded to zqlite 1.3.3

### Fixed
- Tree-sitter symbol duplication issues
- Memory leaks in provider connection pooling
- OAuth token refresh race conditions
- MCP stdio transport deadlocks
- Configuration validation errors

### Security
- Credentials now stored with 0600 permissions
- Enhanced API key validation
- Secure OAuth state management

## [0.2.10] - 2025-10-07

### Fixed
- Removed duplicate tree-sitter symbols
- Build system improvements for clean compilation

## [0.2.9] - 2025-10-07

### Changed
- PKGBUILD improvements for Arch Linux packaging
- Optional zig dependency handling
- Better build-time error messages

## [0.2.8] - 2025-09-27

### Added
- Initial multi-provider AI support (OpenAI, Claude, Ollama)
- Basic HTTP server implementation
- TUI interface with phantom
- Database integration with zqlite
- GitHub Copilot integration
- Watch mode for file monitoring
- TODO tracker with Grove AST

### Changed
- Migrated to async-first architecture with zsync
- Improved error handling and fallbacks

## [0.2.0] - 2025-09-22

### Added
- Initial Zig implementation
- Core AI provider abstractions
- Basic CLI interface
- Configuration system
- SQLite database for state management

## [0.1.0] - 2025-07-14

### Added
- Project inception
- Initial design and architecture planning
- Proof of concept implementation

---

## Version Support

- **Current Stable**: v0.3.0
- **Minimum Zig**: 0.16.0-dev (0.15.x has inline assembly issues)
- **Supported Platforms**: Linux (x86_64, aarch64), macOS (planned), Windows (planned)

## Migration Guides

### Migrating from 0.2.x to 0.3.0

1. **Configuration Format Change**:
   ```bash
   # Backup old config
   cp ~/.config/zeke/config.json ~/.config/zeke/config.json.bak

   # Create new TOML config
   cp zeke.toml.example ~/.config/zeke/zeke.toml
   # Edit with your API keys and preferences
   ```

2. **OAuth Changes**:
   ```bash
   # Re-authenticate with new broker flow
   zeke auth google
   zeke auth github
   ```

3. **Provider Configuration**:
   - Update provider endpoints in `zeke.toml` under `[providers.<name>]`
   - Enable/disable providers with `enabled = true/false`
   - Set default provider with `[default] provider = "ollama"`

4. **MCP Setup** (if using):
   ```toml
   [services.glyph]
   enabled = true
   mcp_transport = "stdio"  # or "websocket", "docker"
   mcp_command = "/usr/local/bin/mcp-server"
   ```

## Links

- [GitHub Repository](https://github.com/ghostkellz/zeke)
- [Issue Tracker](https://github.com/ghostkellz/zeke/issues)
- [Documentation](https://github.com/ghostkellz/zeke/tree/main/docs)
