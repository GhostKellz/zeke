# ZEKE UI Design Specification
## Tokyo Night Theme - Inspired by Claude Code

### Reference
Based on Claude Code screenshot but with ZEKE branding and Tokyo Night color palette.

---

## Color Palette (Tokyo Night - Night variant)

### Background Colors
- **Primary Background:** `#1a1b26` (main dark background)
- **Secondary Background:** `#16161e` (darker panels)
- **Border/Accent:** `#2ac3de` (teal - replaces Claude's orange)
- **Panel Divider:** `#414868` (subtle borders)

### Text Colors
- **Primary Text:** `#c0caf5` (bright text - cyan-blue instead of Claude's blue)
- **Secondary Text:** `#9aa5ce` (dimmed text)
- **Accent Text:** `#7dcfff` (bright teal-cyan)
- **Success/Highlight:** `#9ece6a` (minty green - replaces orange accents)
- **Error/Warning:** `#f7768e` (soft red)

### Brand Colors
- **ZEKE Logo Text:** `#7dcfff` (bright teal-cyan)
- **Version/Model:** `#9aa5ce` (dimmed cyan)
- **Active Elements:** `#2ac3de` (teal highlight)

---

## Layout Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│ [dots]                    ZEKE v0.3.2                        [•••]      │ ← Title bar
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────┬───────────────────────────────────────────┐  │
│  │                      │                                           │  │
│  │  Welcome back User!  │  Tips for getting started                 │  │
│  │                      │  Run /init to create a ZEKE.md file...    │  │
│  │      ⚡ ZEKE         │  Note: You have launched zeke in...        │  │
│  │                      │                                           │  │
│  │  Sonnet 4.5 • Model  │  Recent activity                          │  │
│  │  /current/directory  │  No recent activity                       │  │
│  │                      │                                           │  │
│  └──────────────────────┴───────────────────────────────────────────┘  │
│                                                                         │
│  > command input here                                                  │
│                                                                         │
│  · Status message (esc to interrupt)                                   │
│                                                                         │
│  > Try "edit <filepath> to ..."                                        │
│                                                                         │
│  ? for shortcuts                      Thinking off (tab to toggle)     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Specifications

### 1. Title Bar
- **Background:** `#1a1b26`
- **Border:** `#2ac3de` (2px teal border around entire window)
- **Text:** "ZEKE v0.3.2" in `#7dcfff` (teal-cyan)
- **Dots:** macOS-style traffic lights (red, yellow, green) on left
- **Status indicators:** Colored dots on right

### 2. Info Panel (Left Side)
- **Background:** `#16161e` (slightly darker)
- **Border:** `#2ac3de` (teal accent)
- **Welcome text:** `#7dcfff` (bright teal-cyan)
- **Logo:** "⚡ ZEKE" in large ASCII art or stylized text
  - Color: `#2ac3de` (teal) with `#9ece6a` (minty green) accents
- **Model info:** `#9aa5ce` (dimmed)
- **Directory:** `#9aa5ce` (dimmed)

### 3. Tips Panel (Right Side)
- **Background:** Same as left (`#16161e`)
- **Headers:** `#f7768e` (soft red/orange) for "Tips" and "Recent activity"
- **Body text:** `#c0caf5` (main text color)
- **Highlights:** `#2ac3de` (teal) for commands like `/init`

### 4. Command Input Area
- **Prompt:** `>` in `#7dcfff` (teal)
- **Input text:** `#c0caf5` (bright text)
- **Placeholder:** `#565f89` (very dimmed)

### 5. Status Line
- **Background:** Transparent or `#1a1b26`
- **Status messages:**
  - Normal: `#f7768e` (soft red) for "Contemplating..."
  - Success: `#9ece6a` (minty green)
  - Info: `#7dcfff` (teal)

### 6. Footer
- **Shortcuts hint:** `#565f89` (dimmed) - "? for shortcuts"
- **Toggle status:** `#9aa5ce` (secondary text) - "Thinking off (tab to toggle)"

---

## ASCII Art / Logo Options

### Option 1: Simple Lightning Bolt
```
  ⚡ ZEKE
```
Color: Gradient from `#2ac3de` to `#9ece6a`

### Option 2: Stylized Text Banner
```
╔═══════════════════════════════╗
║     ⚡  Z E K E  v0.3.2       ║
╚═══════════════════════════════╝
```
Border: `#2ac3de`, Text: `#7dcfff`

### Option 3: Minimal Box
```
┌─────────────┐
│  ⚡  ZEKE   │
└─────────────┘
```
Border: `#2ac3de`, Text: `#9ece6a`

---

## Differences from Claude Code

| Element | Claude Code | ZEKE |
|---------|-------------|------|
| **Primary Border** | Orange (#ff9900) | Teal (#2ac3de) |
| **Accent Color** | Orange | Minty Green (#9ece6a) |
| **Background** | Dark blue-gray | Tokyo Night black (#1a1b26) |
| **Logo** | Robot icon | "ZEKE" text / lightning bolt |
| **Main Text** | Blue tint | Cyan-teal tint (#7dcfff) |
| **Headers** | Orange | Soft red/orange (#f7768e) |

---

## Implementation Notes

1. **TUI Framework:** Phantom (already integrated)
2. **Color support:** ANSI 256-color mode
3. **Layout:** Use Phantom's panel system
4. **Animations:** Subtle fade-ins, no distracting effects
5. **Responsive:** Adapt to terminal width (min 80 cols recommended)

---

## Example Color Usage in Code

```zig
const Colors = struct {
    bg_primary: []const u8 = "\x1b[48;2;26;27;38m",      // #1a1b26
    bg_secondary: []const u8 = "\x1b[48;2;22;22;30m",    // #16161e
    border_accent: []const u8 = "\x1b[38;2;42;195;222m", // #2ac3de
    text_primary: []const u8 = "\x1b[38;2;192;202;245m", // #c0caf5
    text_accent: []const u8 = "\x1b[38;2;125;207;255m",  // #7dcfff
    green_accent: []const u8 = "\x1b[38;2;158;206;106m", // #9ece6a
    soft_red: []const u8 = "\x1b[38;2;247;118;142m",     // #f7768e
    reset: []const u8 = "\x1b[0m",
};
```

---

## Next Steps

1. Create ASCII art variations for the logo
2. Implement color scheme in Phantom TUI
3. Design panel layouts with responsive sizing
4. Add smooth transitions and animations
5. Test in various terminal emulators
