# Zeke Installation Guide

Multiple installation methods for Zeke AI Development Assistant.

## Quick Install (Recommended)

### One-line install:
```bash
curl -fsSL https://zeke.cktech.org | bash
```

Or download and inspect first:
```bash
curl -fsSL https://zeke.cktech.org -o install.sh
less install.sh
bash install.sh
```

## Manual Installation

### Arch Linux (AUR)

```bash
# Using yay
yay -S zeke

# Or manually with makepkg
git clone https://github.com/ghostkellz/zeke.git
cd zeke
makepkg -si
```

### From Source

**Requirements:**
- Zig >= 0.15.0
- Git
- zlib

**Build:**
```bash
git clone https://github.com/ghostkellz/zeke.git
cd zeke
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zeke /usr/local/bin/
```

## Post-Installation

### 1. Verify Installation
```bash
zeke --version
```

### 2. Configure Authentication

**For paid subscriptions (OAuth):**
```bash
zeke auth google    # Claude Max + ChatGPT Pro
zeke auth github    # GitHub Copilot Pro
```

**For API access:**
```bash
zeke auth openai <your-api-key>
zeke auth anthropic <your-api-key>
zeke auth azure <your-api-key>
```

### 3. Start Using Zeke

```bash
# Start HTTP server
zeke serve

# Ask a question
zeke ask "How do I implement a hash map in Zig?"

# View credentials
zeke auth list
```

## Optional Integrations

### OMEN (AI Model Router)

Deploy OMEN for smart model routing:

```bash
cd /data/projects/omen
docker compose up -d
```

Configure Zeke to use OMEN:
```json
// ~/.config/zeke/config.json
{
  "services": {
    "omen": {
      "enabled": true,
      "base_url": "http://localhost:8080/v1"
    }
  }
}
```

### Neovim Plugin

Install [zeke.nvim](https://github.com/ghostkellz/zeke.nvim) for seamless editor integration:

```lua
-- Using lazy.nvim
{
  "ghostkellz/zeke.nvim",
  config = function()
    require("zeke").setup({
      provider = {
        type = "openai_compatible",
        base_url = "http://localhost:7878/v1",
        model = "auto",
      },
    })
  end
}
```

## Uninstallation

### Remove Zeke (preserve config):
```bash
./test_cleanup.sh
```

### Full removal (including credentials):
```bash
./test_cleanup.sh --full
```

**WARNING:** `--full` deletes all saved API keys and OAuth tokens!

### Arch Linux:
```bash
sudo pacman -Rns zeke
```

## Configuration Directory

Zeke stores configuration and credentials in:
```
~/.config/zeke/
├── credentials.json   # OAuth tokens and API keys (600 permissions)
├── config.json        # User configuration
└── zeke.db           # Local database
```

## Environment Variables

Optional configuration via environment:

```bash
# Google OAuth (for zeke auth google)
export ZEKE_GOOGLE_CLIENT_ID="your-client-id"
export ZEKE_GOOGLE_CLIENT_SECRET="your-client-secret"

# GitHub OAuth (for zeke auth github)
export ZEKE_GITHUB_CLIENT_ID="your-client-id"
export ZEKE_GITHUB_CLIENT_SECRET="your-client-secret"

# Override config directory
export ZEKE_CONFIG_DIR="$HOME/.config/zeke"
```

## Troubleshooting

### "zig: command not found"

Install Zig from your package manager or from [ziglang.org](https://ziglang.org/download/).

### OAuth callback fails

Ensure port 8765 is not blocked:
```bash
sudo lsof -i :8765
```

### Permission denied on /usr/local/bin

Run with sudo or install to user directory:
```bash
INSTALL_DIR="$HOME/.local/bin" bash install.sh
```

Then add to PATH:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Distribution Setup

For maintainers setting up `https://zeke.cktech.org`:

### Nginx Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name zeke.cktech.org;

    ssl_certificate /etc/letsencrypt/live/zeke.cktech.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/zeke.cktech.org/privkey.pem;

    location / {
        return 302 https://raw.githubusercontent.com/ghostkellz/zeke/main/install.sh;
    }
}

server {
    listen 80;
    server_name zeke.cktech.org;
    return 301 https://$server_name$request_uri;
}
```

Or use GitHub Pages redirect:
```html
<!-- index.html -->
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=https://raw.githubusercontent.com/ghostkellz/zeke/main/install.sh">
</head>
<body>
    Redirecting to install script...
</body>
</html>
```

## Support

- **GitHub Issues**: https://github.com/ghostkellz/zeke/issues
- **Documentation**: https://github.com/ghostkellz/zeke/tree/main/docs
- **Email**: ckelley@ghostkellz.sh

## License

MIT License - see LICENSE file for details.

---

**Built with the Ghost Stack** 👻
