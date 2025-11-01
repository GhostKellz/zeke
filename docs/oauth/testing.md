# OAuth Testing Guide

## ✅ Build Status: READY

The OAuth implementation is now complete and matches OpenCode's working implementation.

---

## 🔐 Testing Claude Max OAuth

### Prerequisites
- You must have an active **Claude Max subscription** ($20/month)
- Your account at https://console.anthropic.com must be logged in
- A web browser installed on your system

### Step-by-Step Test

1. **Run the OAuth command**:
```bash
./zig-out/bin/zeke auth claude
```

2. **You'll see output like**:
```
🔐 Starting Anthropic OAuth authentication...

✓ Generated PKCE challenge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Anthropic Claude Max Authentication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Opening browser for authentication...
URL: https://console.anthropic.com/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&...

After logging in, you'll be redirected to a page with an authorization code.
Paste the authorization code here: _
```

3. **In the browser**:
   - Browser will open automatically to `console.anthropic.com`
   - Login with your Claude Max account if not already logged in
   - Click "Authorize" to grant Zeke access
   - You'll be redirected to a page showing an authorization code
   - The code will be in format: `abc123def456...#xyz789...` (code#state)

4. **Copy the ENTIRE authorization code**:
   - Select ALL the text shown on the redirect page
   - It should include the `#` character in the middle
   - Copy it to clipboard

5. **Paste back in terminal**:
   - Go back to your terminal where zeke is waiting
   - Paste the full authorization code
   - Press Enter

6. **Expected success output**:
```
✓ Received authorization code
🔄 Exchanging code for access token...

✅ Authentication successful!
   Access token expires in: 2592000 seconds
```

7. **Verify token storage**:
```bash
./zig-out/bin/zeke auth status
```

Expected output:
```
Authentication Status:
  ✅ Anthropic (OAuth): sk-ant-***...
```

---

## 🚀 Testing GitHub Copilot OAuth

### Prerequisites
- You must have an active **GitHub Copilot Pro subscription** ($10/month)
- Or **GitHub Copilot Business** through your organization
- A web browser installed on your system

### Step-by-Step Test

1. **Run the OAuth command**:
```bash
./zig-out/bin/zeke auth copilot
```

2. **You'll see output like**:
```
🔐 Starting GitHub Device Flow authentication...

✓ Device code received

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GitHub Authentication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Visit: https://github.com/login/device
Enter code: ABCD-1234

⏳ Waiting for authorization...
⠋ Waiting for authorization... (15s)
```

3. **In the browser**:
   - Browser will open automatically to `github.com/login/device`
   - Enter the code shown in terminal (e.g., `ABCD-1234`)
   - Click "Continue"
   - Review permissions requested
   - Click "Authorize"

4. **Back in terminal**:
   - The spinner will continue while waiting
   - Once you authorize in the browser, you'll see:

```
✓ Authorization successful!

✅ GitHub authentication successful!
   Token will expire in ~90 days
```

5. **Verify token storage**:
```bash
./zig-out/bin/zeke auth status
```

Expected output:
```
Authentication Status:
  ✅ GitHub Copilot (OAuth): gho_***...
```

---

## 🧪 Testing Both Providers

Once both are authenticated, test actual AI requests:

### Test with Claude Max:
```bash
./zig-out/bin/zeke chat "Explain how PKCE works in OAuth 2.0" --provider anthropic
```

### Test with GitHub Copilot:
```bash
./zig-out/bin/zeke chat "Generate a REST API in Rust" --provider github
```

---

## 🔍 Troubleshooting

### Claude OAuth Issues

**Problem**: "Invalid OAuth Request: Unknown scope"
- ✅ **FIXED** - Now using correct scopes: `org:create_api_key user:profile user:inference`

**Problem**: "Missing scope parameter"
- ✅ **FIXED** - Scopes are now included in authorization URL

**Problem**: "Token exchange failed"
- Check that you copied the ENTIRE authorization code including the `#` character
- Try authenticating again: `./zig-out/bin/zeke auth claude`

**Problem**: Browser doesn't open
- Manually copy the URL shown in terminal
- Open it in your browser
- Complete the flow and paste the code back

### GitHub OAuth Issues

**Problem**: "Device code expired"
- The device code is only valid for 15 minutes
- Run the command again to get a new code

**Problem**: "Polling timed out"
- You have 10 minutes to complete authorization
- If timeout occurs, run the command again

**Problem**: "Token not valid for Copilot"
- Ensure you have an active Copilot Pro or Business subscription
- Check your GitHub account at https://github.com/settings/copilot

### Keyring Issues

**Linux**: Ensure you have `secret-tool` installed:
```bash
# Arch/Manjaro
sudo pacman -S libsecret

# Ubuntu/Debian
sudo apt install libsecret-tools

# Fedora
sudo dnf install libsecret
```

**macOS**: Uses Keychain (built-in, no setup needed)

**Windows**: Uses Credential Manager (built-in, no setup needed)

---

## ✅ Success Criteria

After successful testing, you should be able to:

1. ✅ Run `zeke auth claude` and complete OAuth flow
2. ✅ Run `zeke auth copilot` and complete OAuth flow
3. ✅ See both providers in `zeke auth status`
4. ✅ Make AI requests using `--provider anthropic` or `--provider github`
5. ✅ Tokens persist across terminal sessions (stored in keyring)
6. ✅ No need to re-authenticate until tokens expire

---

## 📊 What to Report

After testing, please report:

### Success Case:
```
✅ Claude OAuth: Working
   - Browser opened: Yes/No
   - Code entry: Successful
   - Token stored: Yes
   - AI request: Working

✅ GitHub OAuth: Working
   - Browser opened: Yes/No
   - Device code entry: Successful
   - Token stored: Yes
   - AI request: Working
```

### Failure Case:
```
❌ Claude OAuth: Failed
   - Error message: [exact error text]
   - Step failed at: [authorization/code exchange/token storage]
   - Browser logs: [any console errors]

❌ GitHub OAuth: Failed
   - Error message: [exact error text]
   - Step failed at: [device code/polling/token storage]
```

---

## 🎯 Next Steps After Successful Testing

1. Update PROGRESS_NOV1_2025.md with test results
2. Fix config module crash (next priority bug)
3. Fix database initialization error
4. Add automated integration tests
5. Document in README for public release

---

**Status**: Ready for live testing with real accounts
**Last Updated**: November 1, 2025
**Implementation**: Matches OpenCode's proven working approach
