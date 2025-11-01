# Tokyo Night TUI Customization Guide

Welcome to the ZEKE Tokyo Night TUI customization guide! This document explains how to customize colors, layouts, and behavior of the Tokyo Night themed terminal interface.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Color Customization](#color-customization)
3. [Layout Customization](#layout-customization)
4. [Creating Custom Themes](#creating-custom-themes)
5. [Advanced Customization](#advanced-customization)
6. [Terminal Compatibility](#terminal-compatibility)

---

## Quick Start

### Using the Tokyo Night TUI

```bash
# Launch the TUI
zeke tui

# Or with specific theme variant
zeke tui --theme night    # Default
zeke tui --theme storm    # Cooler tones
zeke tui --theme moon     # Softer colors
```

### Testing Colors

Preview the current color scheme:

```bash
# Show all Tokyo Night colors
zeke tui --show-colors

# Test in your terminal
echo -e "\x1b[38;2;42;195;222m██ Teal Border\x1b[0m"
echo -e "\x1b[38;2;158;206;106m██ Minty Green\x1b[0m"
echo -e "\x1b[38;2;125;207;255m██ Cyan Accent\x1b[0m"
```

---

## Color Customization

### Understanding the Color System

ZEKE uses semantic color names that map to Tokyo Night colors:

```zig
// Primary accents
logo_primary    = #2ac3de  (teal)
logo_accent     = #9ece6a  (minty green)
border_color    = #2ac3de  (teal)
active_element  = #9ece6a  (green)

// Text colors
header_text     = #7dcfff  (cyan)
fg              = #c0caf5  (main text)
fg_dark         = #a9b1d6  (dimmed)
comment         = #565f89  (very dim)

// Backgrounds
bg              = #1a1b26  (main)
bg_dark         = #16161e  (panels)
bg_highlight    = #292e42  (hover/active)
```

### Customizing Colors

#### Method 1: Config File (Recommended)

Create `~/.config/zeke/theme.toml`:

```toml
[theme.tokyo_night]
# Override specific colors
logo_primary = "#00d9ff"      # Custom teal
logo_accent = "#00ff9f"       # Custom green
border_color = "#00d9ff"
header_text = "#80ffea"

# Or change entire palette
[theme.tokyo_night.palette]
bg = "#1a1b26"
fg = "#c0caf5"
teal = "#00d9ff"
green = "#00ff9f"
cyan = "#80ffea"
```

#### Method 2: Environment Variables

```bash
# Override specific colors
export ZEKE_COLOR_BORDER="42,195,222"    # RGB format
export ZEKE_COLOR_ACCENT="158,206,106"
export ZEKE_COLOR_HEADER="125,207,255"

zeke tui
```

#### Method 3: Command Line Flags

```bash
zeke tui \
  --color-border="#2ac3de" \
  --color-accent="#9ece6a" \
  --color-header="#7dcfff"
```

### Predefined Color Schemes

ZEKE includes several pre-configured Tokyo Night variants:

```bash
# Night (default) - Deep blue, teal/green accents
zeke tui --theme night

# Storm - Cooler tones, blue-teal accents
zeke tui --theme storm

# Moon - Softer purples, teal accents
zeke tui --theme moon

# Day - Light mode (coming soon)
zeke tui --theme day
```

### Creating a Custom Accent Color

Want to replace teal/green with your own colors?

1. **Edit the source** (`src/tui/tokyo_night.zig`):

```zig
pub const TokyoNight = struct {
    // Your custom colors
    pub const blue1 = "\x1b[38;2;255;0;128m";  // Hot pink border
    pub const green = "\x1b[38;2;0;255;200m";  // Aqua accent
    pub const cyan = "\x1b[38;2;100;200;255m"; // Sky blue header

    // Keep semantic mappings
    pub const border_color = blue1;
    pub const active_element = green;
    pub const header_text = cyan;
    // ...
};
```

2. **Rebuild:**
```bash
zig build
```

---

## Layout Customization

### Adjusting Panel Sizes

Edit `src/tui/tokyo_night.zig`:

```zig
pub const WelcomeScreen = struct {
    // Change panel widths (default: 24 left, 49 right)
    const left_panel_width = 30;   // Wider left panel
    const right_panel_width = 45;  // Narrower right panel

    // Or make it responsive
    pub fn calculatePanelWidth(self: *Self, total_width: usize) struct { left: usize, right: usize } {
        return .{
            .left = total_width / 3,        // 1/3 for left
            .right = (total_width * 2) / 3, // 2/3 for right
        };
    }
};
```

### Customizing the Logo

Replace the "⚡ ZEKE" logo with your own ASCII art:

```zig
pub const ZekeLogo = struct {
    pub const custom =
        \\    ___   ____ _  ________
        \\   / _ | / __/| |/ / __/ /
        \\  / __ |/ _/  /    / _/_/ /__
        \\ /_/ |_/___/ /_/|_/___/____/
    ;
};

// Then use it in renderLeftPanel:
try writer.writeAll(ZekeLogo.custom);
```

### Hiding/Showing Panels

Toggle panels via config:

`~/.config/zeke/tui.toml`:

```toml
[panels]
show_welcome = true
show_tips = true
show_recent_activity = false  # Hide activity panel
show_footer = true
```

---

## Creating Custom Themes

### Step 1: Define Your Palette

Create `src/tui/themes/my_theme.zig`:

```zig
const std = @import("std");

pub const MyTheme = struct {
    // Define your colors
    pub const bg = "\x1b[48;2;20;20;30m";              // Dark purple bg
    pub const fg = "\x1b[38;2;220;220;255m";           // Light purple text
    pub const accent1 = "\x1b[38;2;255;100;200m";      // Pink
    pub const accent2 = "\x1b[38;2;100;200;255m";      // Blue
    pub const border = "\x1b[38;2;200;100;255m";       // Purple

    // Semantic mappings
    pub const border_color = border;
    pub const logo_primary = accent1;
    pub const logo_accent = accent2;
    pub const header_text = accent1;
    pub const active_element = accent2;
    // ... more mappings
};
```

### Step 2: Register the Theme

Edit `src/tui/mod.zig`:

```zig
const tokyo_night = @import("tokyo_night.zig");
const my_theme = @import("themes/my_theme.zig");

pub const ThemeRegistry = struct {
    pub fn get(name: []const u8) type {
        if (std.mem.eql(u8, name, "tokyo-night")) return tokyo_night.TokyoNight;
        if (std.mem.eql(u8, name, "my-theme")) return my_theme.MyTheme;
        return tokyo_night.TokyoNight; // default
    }
};
```

### Step 3: Use Your Theme

```bash
zeke tui --theme my-theme
```

---

## Advanced Customization

### Dynamic Color Switching

Implement time-based theme switching:

`~/.config/zeke/tui.toml`:

```toml
[theme.auto]
enabled = true

# Day hours: 6am-6pm
day_start = 6
day_end = 18
day_theme = "tokyo-night-day"

# Night theme for other hours
night_theme = "tokyo-night-night"
```

### Terminal-Specific Adjustments

Some terminals render colors differently:

`~/.config/zeke/terminal_overrides.toml`:

```toml
# Kitty terminal
[terminal.kitty]
brightness_boost = 1.1
saturation_boost = 1.05

# iTerm2
[terminal.iterm2]
brightness_boost = 0.95

# Alacritty
[terminal.alacritty]
# Alacritty renders Tokyo Night perfectly, no adjustments needed
```

### Custom Status Indicators

Customize status messages:

```zig
// In src/tui/tokyo_night.zig
pub const StatusMessages = struct {
    pub const thinking = "⚡ Contemplating...";
    pub const ready = "✓ Ready";
    pub const error_prefix = "✗ Error:";
    pub const working = "⚙ Processing...";
};
```

### Adding Custom Panels

Create a new panel type:

```zig
pub const CustomPanel = struct {
    fn render(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

        try writer.writeAll(c.bg_dark);
        try writer.writeAll(c.border_color);
        try writer.writeAll("┌─ My Custom Panel ─┐\n");

        // Your custom content here
        try writer.writeAll("│ Custom content     │\n");

        try writer.writeAll("└────────────────────┘\n");
        try writer.writeAll(c.reset);
    }
};
```

---

## Terminal Compatibility

### Recommended Terminals

**Full 24-bit color support:**
- ✅ Kitty
- ✅ Alacritty
- ✅ WezTerm
- ✅ iTerm2 (macOS)
- ✅ Windows Terminal

**Good support (may need config):**
- ⚠️ GNOME Terminal (enable "true color")
- ⚠️ Konsole (enable "true color")
- ⚠️ Tmux (needs `set -g default-terminal "tmux-256color"`)

**Limited support:**
- ❌ Standard xterm (fallback to 256 colors)
- ❌ Linux console (16 colors only)

### Checking Your Terminal

```bash
# Test 24-bit color support
curl -s https://gist.githubusercontent.com/XVilka/8346728/raw/24bit-color-test.sh | bash

# Or use ZEKE's built-in test
zeke tui --test-colors
```

### Fallback for Limited Terminals

If your terminal doesn't support 24-bit colors, ZEKE will automatically fall back to 256-color mode:

```bash
# Force 256-color mode
export COLORTERM=256color
zeke tui

# Force 16-color mode (minimal)
export COLORTERM=16color
zeke tui
```

---

## Examples

### Example 1: Cyberpunk Theme

```toml
# ~/.config/zeke/theme.toml
[theme.cyberpunk]
bg = "#0a0e27"
fg = "#00ff41"
accent1 = "#ff00ff"
accent2 = "#00ffff"
border = "#ff00ff"
```

### Example 2: Solarized-Inspired

```toml
[theme.solarized_dark]
bg = "#002b36"
fg = "#839496"
accent1 = "#268bd2"
accent2 = "#2aa198"
border = "#586e75"
```

### Example 3: High Contrast

```toml
[theme.high_contrast]
bg = "#000000"
fg = "#ffffff"
accent1 = "#00ff00"
accent2 = "#ffff00"
border = "#ffffff"
```

---

## Troubleshooting

### Colors Look Wrong

1. **Check terminal capabilities:**
   ```bash
   echo $COLORTERM  # Should be "truecolor" or "24bit"
   ```

2. **Verify terminal emulator settings:**
   - Enable "true color" / "24-bit color" in preferences
   - Disable any color themes that override ANSI codes

3. **Test with simple output:**
   ```bash
   printf "\x1b[38;2;42;195;222mTeal text\x1b[0m\n"
   ```

### TUI Doesn't Fit Screen

```bash
# Check terminal size
tput cols  # Width
tput lines # Height

# ZEKE requires minimum 80x24
```

### Performance Issues

```bash
# Disable animations
zeke tui --no-animations

# Reduce update frequency
zeke tui --fps 30  # Default is 60
```

---

## Contributing

Want to contribute a custom theme?

1. Create your theme in `src/tui/themes/your_theme.zig`
2. Add examples to `docs/TOKYO_NIGHT_CUSTOMIZATION.md`
3. Submit a PR with screenshots!

### Color Palette Requirements

- Maintain sufficient contrast (WCAG AA: 4.5:1 for text)
- Test in multiple terminals
- Provide both dark and light variants if possible

---

## Resources

- **Tokyo Night Official:** https://github.com/folke/tokyonight.nvim
- **ANSI Escape Codes:** https://en.wikipedia.org/wiki/ANSI_escape_code
- **True Color Test:** https://gist.github.com/XVilka/8346728
- **Color Contrast Checker:** https://webaim.org/resources/contrastchecker/

---

**Happy customizing!** 🎨

For questions or issues, open a GitHub issue or join our Discord.
