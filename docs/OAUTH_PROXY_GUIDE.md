# OAuth Proxy Configuration Guide

## Overview

Zeke supports configurable OAuth redirect URIs, allowing you to route authentication through custom OAuth proxy servers (like Shade) instead of localhost. This is useful for:

- **Cloud/Remote Deployments**: When localhost isn't accessible from the OAuth provider
- **Corporate Environments**: Route through company authentication infrastructure
- **Multi-Device Workflows**: Use one OAuth proxy instance for all your Zeke installations
- **Enhanced Security**: Centralize OAuth token handling in a dedicated service

## Default Behavior (Localhost)

By default, Zeke uses localhost for OAuth callbacks:

```bash
# Works out of the box - no configuration needed
zeke auth google
# Redirects to: http://localhost:8765/callback
```

## Custom OAuth Proxy Setup

### Environment Variables

Zeke supports provider-specific and general OAuth redirect URIs via environment variables:

#### Provider-Specific (Highest Priority)
```bash
export ZEKE_GOOGLE_REDIRECT_URI="https://auth.cktech.org/callback/google"
export ZEKE_GITHUB_REDIRECT_URI="https://auth.cktech.org/callback/github"
export ZEKE_AZURE_REDIRECT_URI="https://auth.cktech.org/callback/azure"
```

#### General Fallback
```bash
# Used for any provider without a specific override
export ZEKE_OAUTH_REDIRECT_URI="https://auth.cktech.org/callback"
```

#### OAuth Broker Endpoint
```bash
# Hosted Shade instance used by `zeke auth google` (default when unset)
export ZEKE_OAUTH_BROKER_URL="https://auth.cktech.org"

# Set to "local" to bypass the broker and run OAuth against your own
# localhost callback (requires GOOGLE_CLIENT_ID/SECRET locally)
# export ZEKE_OAUTH_BROKER_URL="local"
```

### Priority Order

1. Provider-specific env var (e.g., `ZEKE_GOOGLE_REDIRECT_URI`)
2. General redirect URI (`ZEKE_OAUTH_REDIRECT_URI`)
3. Default localhost (`http://localhost:8765/callback`)

## OAuth Proxy Requirements

Your OAuth proxy server (e.g., Shade) must support **two callback methods**:

### Method 1: Direct Code Relay (Simple)

Forward the authorization code to Zeke's local callback:

```
Google/GitHub → https://auth.cktech.org/callback/google?code=ABC123
               ↓
Shade → http://localhost:8765/callback?code=ABC123
        ↓
Zeke exchanges code for tokens
```

### Method 2: Token Exchange (Advanced)

Complete the token exchange on the proxy and POST tokens to Zeke:

```
Google/GitHub → https://auth.cktech.org/callback/google?code=ABC123
               ↓
Shade (exchanges code for tokens)
       ↓
Shade → POST http://localhost:8765/callback
        {
          "access_token": "ya29.a0...",
          "refresh_token": "1//...",
          "expires_in": 3600
        }
        ↓
Zeke stores tokens
```

**Recommended**: Method 2 is more secure as client secrets never leave the proxy server.

## Example: Shade Integration

### 1. Configure Google OAuth Credentials

In [Google Cloud Console](https://console.cloud.google.com/apis/credentials):

```
Authorized redirect URIs:
  https://auth.cktech.org/callback/google
```

### 2. Configure Environment Variables

```bash
# In ~/.bashrc, ~/.zshrc, or your shell config
export ZEKE_GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export ZEKE_GOOGLE_CLIENT_SECRET="your-client-secret"
export ZEKE_GOOGLE_REDIRECT_URI="https://auth.cktech.org/callback/google"
```

### 3. Run OAuth Flow

```bash
zeke auth google
```

**Output:**
```
🔐 Starting Google OAuth for Claude Max + ChatGPT Pro...
  Redirect URI: https://auth.cktech.org/callback/google

Opening browser for Google Sign-in...
Waiting for OAuth callback on http://localhost:8765/callback...
✅ Received tokens directly from OAuth proxy
✅ Google OAuth successful!
  You can now use Claude Max and ChatGPT Pro via Google
```

## Callback Server Details

Zeke's local callback server (`http://localhost:8765/callback`) accepts:

### GET Requests (Direct OAuth Callback)
```http
GET /callback?code=4/0AeanS0... HTTP/1.1
Host: localhost:8765
```

### POST Requests (Token from Proxy)
```http
POST /callback HTTP/1.1
Host: localhost:8765
Content-Type: application/json

{
  "access_token": "ya29.a0AfB_...",
  "refresh_token": "1//0gOY4qZ...",
  "expires_in": 3599
}
```

**Response:**
```json
{"status":"success"}
```

## Security Considerations

⚠️ **Important Security Notes:**

1. **HTTPS Required**: Custom redirect URIs should use HTTPS in production
2. **Trusted Proxies**: Only use OAuth proxies you control or trust completely
3. **Client Secrets**: With Method 2, client secrets only exist on the proxy (more secure)
4. **Local Callback**: The local callback server only listens on `127.0.0.1` (localhost)
5. **Timeout**: OAuth callback server times out after 5 minutes

## Troubleshooting

### Browser Opens but Callback Never Completes

- Check that your OAuth proxy is POSTing to `http://localhost:8765/callback`
- Verify the proxy is running and accessible from your machine
- Check Zeke's console output for callback server status

### "Invalid Redirect URI" Error from OAuth Provider

- Ensure the redirect URI in Google/GitHub OAuth app matches `ZEKE_GOOGLE_REDIRECT_URI`
- Check for typos or trailing slashes

### Tokens Not Saved

- Verify JSON format in POST body matches the schema
- Check Zeke logs for parsing errors
- Ensure `expires_in` is an integer (seconds)

## Supported Providers

- ✅ **Google OAuth** (for Claude Max, ChatGPT Pro via Google)
- ✅ **GitHub OAuth** (for GitHub Copilot)
- ⏳ **Azure/Microsoft Entra** (coming soon - `ZEKE_AZURE_REDIRECT_URI`)

## Example Shade Proxy Implementation

Here's a minimal example of an OAuth proxy endpoint:

```typescript
// Shade: Google OAuth callback handler
app.get('/callback/google', async (req, res) => {
  const { code } = req.query;

  // Exchange code for tokens
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      redirect_uri: 'https://auth.cktech.org/callback/google',
      grant_type: 'authorization_code',
    }),
  });

  const tokens = await tokenResponse.json();

  // Forward tokens to Zeke's local callback
  await fetch('http://localhost:8765/callback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      expires_in: tokens.expires_in,
    }),
  });

  res.send('✅ Authentication successful! You can close this window.');
});
```

## Further Reading

- [Google OAuth 2.0 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Zeke Authentication Module](../src/auth/mod.zig)
