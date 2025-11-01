# ZEKE Nerd Fonts Guide

ZEKE's TUI uses Nerd Font icons for the best visual experience. Here are our recommended Nerd Fonts:

## Top Recommended Fonts

### 1. **FiraCode Nerd Font** ⭐ (Recommended)
- **Why:** Excellent ligatures, crisp icons, great readability
- **Install:** `yay -S ttf-firacode-nerd` or download from [Nerd Fonts](https://www.nerdfonts.com/font-downloads)
- **Terminal Config:** Set font to "FiraCode Nerd Font" or "FiraCode NF"

### 2. **JetBrains Mono Nerd Font**
- **Why:** Modern, excellent for long coding sessions, perfect ligatures
- **Install:** `yay -S ttf-jetbrains-mono-nerd`
- **Terminal Config:** Set font to "JetBrainsMono Nerd Font" or "JetBrainsMono NF"

### 3. **Iosevka Nerd Font**
- **Why:** Narrow, space-efficient, great for split screens
- **Install:** `yay -S ttf-iosevka-nerd`
- **Terminal Config:** Set font to "Iosevka Nerd Font" or "Iosevka NF"

### 4. **Hack Nerd Font**
- **Why:** Highly readable, classic monospace
- **Install:** `yay -S ttf-hack-nerd`
- **Terminal Config:** Set font to "Hack Nerd Font" or "Hack NF"

### 5. **CaskaydiaCove Nerd Font** (Cascadia Code)
- **Why:** Microsoft's modern font, excellent for Windows Terminal
- **Install:** `yay -S ttf-cascadia-code-nerd`
- **Terminal Config:** Set font to "CaskaydiaCove Nerd Font" or "CaskaydiaCove NF"

## Other Great Options

### **MesloLGS NF**
- Popular in Powerlevel10k themes
- `yay -S ttf-meslo-nerd`

### **IBM Plex Mono**
- Professional, corporate aesthetic
- `yay -S ttf-ibm-plex`

### **Source Code Pro**
- Adobe's classic programming font
- `yay -S ttf-sourcecodepro-nerd`

### **Space Mono**
- Geometric, unique retro-futuristic style
- `yay -S ttf-space-mono-nerd`

## Quick Installation (Arch Linux)

```bash
# Install all recommended fonts at once
yay -S ttf-firacode-nerd ttf-jetbrains-mono-nerd ttf-iosevka-nerd \
       ttf-hack-nerd ttf-cascadia-code-nerd ttf-meslo-nerd

# Or use pacman for some
sudo pacman -S ttf-firacode-nerd ttf-jetbrains-mono-nerd

# Install emoji and symbol support fonts
sudo pacman -S noto-fonts-emoji ttf-nerd-fonts-symbols-mono

# Optional: Additional fallback fonts
sudo pacman -S noto-fonts ttf-dejavu
```

## Installation (Other Distros)

### Ubuntu/Debian
```bash
# Download from Nerd Fonts releases
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip
unzip FiraCode.zip -d ~/.local/share/fonts
fc-cache -fv

# Install emoji and symbol support
sudo apt install fonts-noto-color-emoji fonts-noto
```

### macOS
```bash
brew tap homebrew/cask-fonts
brew install font-fira-code-nerd-font
brew install font-jetbrains-mono-nerd-font
brew install font-hack-nerd-font
brew install font-symbols-only-nerd-font

# Install emoji support (usually pre-installed on macOS)
# Apple Color Emoji is built-in
```

### Windows
Download from [Nerd Fonts Releases](https://github.com/ryanoasis/nerd-fonts/releases) and install via Windows Font Settings

## Terminal Configuration

### Alacritty (`~/.config/alacritty/alacritty.yml`)
```yaml
font:
  normal:
    family: "FiraCode Nerd Font"
    style: Regular
  bold:
    family: "FiraCode Nerd Font"
    style: Bold
  italic:
    family: "FiraCode Nerd Font"
    style: Italic
  size: 11.0

# Font fallback for better icon/emoji support
# Alacritty doesn't support fallback chains directly,
# but Nerd Fonts include most glyphs
```

### Kitty (`~/.config/kitty/kitty.conf`)
```
# Primary font
font_family      FiraCode Nerd Font Regular
bold_font        FiraCode Nerd Font Bold
italic_font      FiraCode Nerd Font Italic
bold_italic_font FiraCode Nerd Font Bold Italic
font_size        11.0

# Fallback fonts for missing glyphs
symbol_map U+E0A0-U+E0A3,U+E0B0-U+E0BF Symbols Nerd Font Mono
symbol_map U+E0C0-U+E0C8,U+E0CA,U+E0CC-U+E0D4 Symbols Nerd Font Mono
symbol_map U+23FB-U+23FE,U+2665,U+26A1,U+2B58 Symbols Nerd Font Mono
symbol_map U+E000-U+E00A Symbols Nerd Font Mono
symbol_map U+EA60-U+EBEB Symbols Nerd Font Mono
symbol_map U+E0A3,U+E0B4-U+E0C8,U+E0CA,U+E0CC-U+E0D2,U+E0D4 Symbols Nerd Font Mono
symbol_map U+E700-U+E7C5 Symbols Nerd Font Mono
symbol_map U+F000-U+F2E0 Symbols Nerd Font Mono
symbol_map U+E200-U+E2A9 Symbols Nerd Font Mono
symbol_map U+F500-U+FD46 Symbols Nerd Font Mono
symbol_map U+E300-U+E3EB Symbols Nerd Font Mono
symbol_map U+F400-U+F4A8,U+2665,U+26A1 Symbols Nerd Font Mono
```

### WezTerm (`~/.wezterm.lua`)
```lua
local wezterm = require 'wezterm'
local config = {}

-- Font with fallback chain
config.font = wezterm.font_with_fallback({
  { family = "FiraCode Nerd Font", weight = "Regular" },
  { family = "JetBrainsMono Nerd Font", weight = "Regular" }, -- fallback
  { family = "Symbols Nerd Font Mono", weight = "Regular" },
  { family = "Noto Color Emoji" },
  { family = "Noto Sans", weight = "Regular" },
})

-- Bold font with fallback
config.font_rules = {
  {
    intensity = 'Bold',
    italic = false,
    font = wezterm.font_with_fallback({
      { family = "FiraCode Nerd Font", weight = "Bold" },
      { family = "JetBrainsMono Nerd Font", weight = "Bold" },
      { family = "Symbols Nerd Font Mono", weight = "Bold" },
      { family = "Noto Color Emoji" },
      { family = "Noto Sans", weight = "Bold" },
    })
  },
  {
    intensity = 'Bold',
    italic = true,
    font = wezterm.font_with_fallback({
      { family = "FiraCode Nerd Font", weight = "Bold", italic = true },
      { family = "JetBrainsMono Nerd Font", weight = "Bold", italic = true },
      { family = "Symbols Nerd Font Mono", weight = "Bold" },
    })
  }
}

config.font_size = 11.0

return config
```

### Ghostty (`~/.config/ghostty/config`)
```
# Primary font
font-family = FiraCode Nerd Font
font-size = 11

# Font features
font-feature = -calt
font-feature = -liga
font-feature = -dlig

# Fallback fonts (Ghostty supports fallback chains)
font-family-bold = FiraCode Nerd Font Bold
font-family-italic = FiraCode Nerd Font Italic
font-family-bold-italic = FiraCode Nerd Font Bold Italic

# Additional fallbacks for icons/emoji
# Ghostty automatically falls back for missing glyphs
```

### Windows Terminal (`settings.json`)
```json
{
  "profiles": {
    "defaults": {
      "font": {
        "face": "FiraCode Nerd Font",
        "size": 11,
        "weight": "normal"
      }
    }
  },
  "schemes": [
    {
      "name": "Ghost Hacker Blue",
      "background": "#222436",
      "foreground": "#c8d3f5",
      "cursorColor": "#4fd6be",
      "selectionBackground": "#2d3f76",
      "black": "#444a73",
      "blue": "#82aaff",
      "brightBlack": "#636da6",
      "brightBlue": "#89ddff",
      "brightCyan": "#66ffe0",
      "brightGreen": "#66ffc2",
      "brightPurple": "#c099ff",
      "brightRed": "#ff757f",
      "brightWhite": "#c8d3f5",
      "brightYellow": "#ffc777",
      "cyan": "#4fd6be",
      "green": "#c3e88d",
      "purple": "#c099ff",
      "red": "#c53b53",
      "white": "#c0caf5",
      "yellow": "#ffc777"
    }
  ]
}
```

## Icons in ZEKE

ZEKE uses these Nerd Font icons:

- ⚡ - Logo (U+26A1)
- 📁 - Folders
- 📄 - Files
- ✓ - Success
- ✗ - Error
- ⚙ - Settings
- 🔍 - Search
- → - Arrows
- ├─ - Tree branches
- └─ - Tree endings

## Testing Your Font

Run this command to test if your Nerd Font is working:
```bash
echo "⚡ 📁 📄 ✓ ✗  "
```

If you see proper icons (not boxes), your font is configured correctly!

## Troubleshooting

**Icons show as boxes (□)?**
- Your terminal isn't using a Nerd Font
- Check your terminal's font settings
- Make sure font name matches exactly (including "Nerd Font" suffix)

**Font looks too small/large?**
- Adjust `font_size` in your terminal config
- Recommended sizes: 10-12 for most displays, 14-16 for 4K

**Ligatures not working?**
- Some terminals don't support ligatures (e.g., older GNOME Terminal)
- Try Alacritty, Kitty, WezTerm, or Ghostty for full ligature support

## More Information

- [Nerd Fonts Website](https://www.nerdfonts.com/)
- [Nerd Fonts GitHub](https://github.com/ryanoasis/nerd-fonts)
- [Nerd Fonts Cheat Sheet](https://www.nerdfonts.com/cheat-sheet)
