# Anthropic Claude OAuth Integration

**Use your Claude Max subscription with Zeke** - No separate API costs required!

---

## Overview

Zeke integrates directly with **Anthropic Claude Max** using OAuth 2.0 authentication. This allows you to use your existing $20/month Claude Max subscription instead of paying separately for API access.

### Benefits
- ✅ **Save $50-100/month** - Use existing subscription instead of API billing
- ✅ **Premium Access** - Full Claude Max features and rate limits
- ✅ **Secure** - OAuth 2.0 with PKCE, no API keys to manage
- ✅ **Automatic** - Tokens refresh automatically (coming soon)
- ✅ **One-time setup** - Authenticate once, tokens persist

---

## Quick Start

### 1. Prerequisites
- Active **Claude Max subscription** ($20/month)
- Account at https://console.anthropic.com
- Linux: `secret-tool` installed for keyring storage

### 2. Authenticate
```bash
zeke auth claude
```

### 3. Follow the Prompts
1. Browser opens to `console.anthropic.com`
2. Login with your Claude Max account
3. Click "Authorize" to grant Zeke access
4. Copy the **full authorization code** (includes `#` character)
5. Paste it back in the terminal
6. Done! Token stored securely in system keyring

### 4. Verify
```bash
zeke auth status
# Should show: ✅ anthropic OAuth (from keyring)
```

---

## How It Works

### OAuth Flow

```
┌─────────────┐
│ User runs   │
│ zeke auth   │
│  claude     │
└──────┬──────┘
       │
       v
┌─────────────────────────────────┐
│ 1. Generate PKCE Challenge      │
│    - code_verifier (random)     │
│    - code_challenge (SHA-256)   │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 2. Open Browser                 │
│    console.anthropic.com/oauth  │
│    ?code_challenge=...          │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 3. User Authorizes              │
│    - Login to Claude Max        │
│    - Review permissions         │
│    - Click "Authorize"          │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 4. Receive Code                 │
│    Format: code123#state456     │
│    User copies and pastes       │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 5. Exchange Code for Tokens     │
│    POST /v1/oauth/token         │
│    {code, state, verifier}      │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 6. Receive Tokens               │
│    - access_token (8 hours)     │
│    - refresh_token (long-lived) │
└──────┬──────────────────────────┘
       │
       v
┌─────────────────────────────────┐
│ 7. Store in Keyring             │
│    - Encrypted by OS            │
│    - Persists across sessions   │
└─────────────────────────────────┘
```

### Security Features

1. **PKCE (Proof Key for Code Exchange)**
   - Prevents authorization code interception
   - No client secret required
   - SHA-256 code challenge
   - Cryptographically secure

2. **System Keyring Storage**
   - Linux: GNOME Keyring / KWallet
   - Encrypted at rest
   - No plain-text storage
   - Automatic OS-level security

3. **Token Lifecycle**
   - Access token: 8 hours (28800 seconds)
   - Refresh token: Long-lived
   - Automatic refresh (coming soon)
   - Secure memory handling

---

## OAuth Endpoints

### Authorization
```
https://console.anthropic.com/oauth/authorize
```

**Parameters**:
- `code=true` - Request authorization code
- `client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e` - Public client ID
- `response_type=code` - Authorization code flow
- `redirect_uri=https://console.anthropic.com/oauth/code/callback` - Anthropic's callback
- `scope=org:create_api_key user:profile user:inference` - Required permissions
- `code_challenge=[SHA256]` - PKCE challenge
- `code_challenge_method=S256` - SHA-256 hashing
- `state=[random]` - CSRF protection

### Token Exchange
```
POST https://console.anthropic.com/v1/oauth/token
Content-Type: application/json
```

**Request Body**:
```json
{
  "code": "abc123...",
  "state": "xyz789...",
  "grant_type": "authorization_code",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
  "code_verifier": "[random_string]"
}
```

**Response**:
```json
{
  "token_type": "Bearer",
  "access_token": "sk-ant-oat01-...",
  "expires_in": 28800,
  "refresh_token": "sk-ant-ort01-...",
  "scope": "user:inference user:profile",
  "organization": {
    "uuid": "...",
    "name": "..."
  },
  "account": {
    "uuid": "...",
    "email_address": "..."
  }
}
```

---

## Scopes

Zeke requests the following OAuth scopes:

### `org:create_api_key`
- Create API keys for the organization
- Required for programmatic access
- Allows Zeke to generate tokens

### `user:profile`
- Read user profile information
- Access to account details
- Organization membership

### `user:inference`
- Access to Claude AI inference
- Make requests to Claude models
- Use Claude Max features

---

## Token Types

### Access Token
- **Format**: `sk-ant-oat01-...`
- **Lifetime**: 8 hours (28800 seconds)
- **Usage**: Bearer token for API requests
- **Refresh**: Use refresh token when expired

### Refresh Token
- **Format**: `sk-ant-ort01-...`
- **Lifetime**: Long-lived (weeks/months)
- **Usage**: Obtain new access tokens
- **Storage**: Encrypted in system keyring

---

## Using Claude with OAuth

### Make AI Requests

```bash
# Simple chat
zeke chat "Explain async programming in Zig" --provider anthropic

# With streaming
zeke chat "Write a REST API server" --provider anthropic --stream

# Generate code
zeke generate function "Parse JSON with error handling"

# Analyze code
zeke analyze src/main.zig
```

### Configure as Default Provider

```bash
# Set Claude as default
zeke config set provider anthropic

# Now you can omit --provider flag
zeke chat "Hello, Claude!"
```

---

## Troubleshooting

### Common Issues

**Q: Browser doesn't open automatically**
- **A**: Copy the URL shown in terminal and open manually in your browser

**Q: "Invalid OAuth Request: Unknown scope"**
- **A**: This is fixed in the latest version. Make sure you're running the latest build.

**Q: Token exchange fails**
- **A**: Make sure you copied the ENTIRE authorization code including the `#` character
- **Example**: `abc123...#xyz789...`

**Q: "secret-tool not found"**
- **A**: Install libsecret:
  ```bash
  sudo pacman -S libsecret      # Arch
  sudo apt install libsecret-tools  # Ubuntu
  ```

**Q: Token expired**
- **A**: Re-authenticate with `zeke auth claude` (automatic refresh coming soon)

**Q: Want to switch accounts**
- **A**: Logout first: `zeke auth logout anthropic`, then `zeke auth claude`

---

## API Compatibility

### Supported Features
- ✅ Chat completions
- ✅ Streaming responses
- ✅ System messages
- ✅ Multi-turn conversations
- ✅ Temperature control
- ✅ Max tokens
- ✅ All Claude models (Opus, Sonnet, Haiku)

### OAuth vs API Key

| Feature | OAuth | API Key |
|---------|-------|---------|
| Cost | $20/mo (Max subscription) | Pay-per-use (~$50-100/mo) |
| Setup | One-time OAuth | Set environment variable |
| Security | System keyring | Plain-text env var |
| Refresh | Automatic (soon) | N/A |
| Rate Limits | Premium tier | Standard tier |
| Model Access | All Max models | Depends on billing |

---

## Implementation Details

### Technical Stack
- **Language**: Zig 0.16.0-dev
- **HTTP Client**: `std.http.Client`
- **JSON Parser**: `std.json`
- **Keyring**: `secret-tool` (Linux)
- **Compression**: `gunzip` (for gzip responses)
- **Security**: PKCE (RFC 7636)

### Source Files
```
src/auth/
├── anthropic_oauth.zig   # Main OAuth implementation
├── pkce.zig              # PKCE helper functions
├── keyring.zig           # System keyring integration
├── browser.zig           # Cross-platform browser opener
└── manager.zig           # Token management

src/providers/
└── anthropic.zig         # Claude API client (uses OAuth tokens)

src/cli/
└── auth.zig              # CLI authentication commands
```

---

## Known Limitations

1. **Manual Code Entry**
   - User must manually copy/paste authorization code
   - Unlike localhost callback (which Anthropic doesn't support)
   - Same approach as OpenCode

2. **Gzip Compression**
   - Server sends gzip-compressed responses
   - Requires external `gunzip` command
   - Automatic decompression implemented

3. **Token Refresh**
   - Not yet automatic (coming soon)
   - Must re-authenticate when token expires (8 hours)
   - Refresh token flow will be implemented

4. **Linux Only (Currently)**
   - Keyring integration tested on Linux
   - macOS/Windows support planned
   - Will use native keychain/credential manager

---

## Roadmap

### Coming Soon
- [ ] Automatic token refresh before expiration
- [ ] Background refresh daemon
- [ ] macOS Keychain integration
- [ ] Windows Credential Manager integration
- [ ] Multi-account support
- [ ] Token usage statistics

### Future Ideas
- [ ] OAuth for other providers (if available)
- [ ] Token sharing across team
- [ ] Usage analytics dashboard
- [ ] Rate limit monitoring

---

## References

### Documentation
- [Anthropic API Docs](https://docs.anthropic.com)
- [OAuth 2.0 Specification](https://oauth.net/2/)
- [PKCE (RFC 7636)](https://datatracker.ietf.org/doc/html/rfc7636)

### Related
- [OAuth Implementation Guide](../oauth/implementation.md)
- [Testing Guide](../oauth/testing.md)
- [Quick Start](../../QUICKSTART.md)

---

## Support

**Need help?**
- GitHub Issues: https://github.com/GhostKellz/zeke/issues
- Discord: https://discord.gg/ghostkellz
- Email: support@cktech.org

---

**Ready to use Claude Max with Zeke?**

```bash
zeke auth claude
```

✅ **Status**: Production ready - tested with real Claude Max accounts!

---

*Last Updated: November 1, 2025*
*Tested: ✅ Working with Claude Max subscriptions*
