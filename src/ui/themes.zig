const std = @import("std");

/// Tokyo Night color theme variants
pub const TokyoNightVariant = enum {
    night,  // Default dark theme
    moon,   // Softer contrast
    storm,  // Warmer tones

    pub fn fromString(s: []const u8) ?TokyoNightVariant {
        if (std.mem.eql(u8, s, "night")) return .night;
        if (std.mem.eql(u8, s, "moon")) return .moon;
        if (std.mem.eql(u8, s, "storm")) return .storm;
        return null;
    }
};

/// ANSI color codes
pub const AnsiColor = struct {
    fg: []const u8,
    bg: []const u8,
    bold: []const u8 = "\x1b[1m",
    dim: []const u8 = "\x1b[2m",
    italic: []const u8 = "\x1b[3m",
    underline: []const u8 = "\x1b[4m",
    reset: []const u8 = "\x1b[0m",
};

/// Tokyo Night theme colors
pub const Theme = struct {
    // Base colors
    bg: []const u8,
    bg_dark: []const u8,
    bg_highlight: []const u8,
    terminal_black: []const u8,
    fg: []const u8,
    fg_dark: []const u8,
    fg_gutter: []const u8,
    dark3: []const u8,
    comment: []const u8,
    dark5: []const u8,

    // Syntax colors
    blue: []const u8,
    cyan: []const u8,
    blue1: []const u8,
    blue2: []const u8,
    blue5: []const u8,
    blue6: []const u8,
    blue7: []const u8,
    magenta: []const u8,
    magenta2: []const u8,
    purple: []const u8,
    orange: []const u8,
    yellow: []const u8,
    green: []const u8,
    green1: []const u8,
    green2: []const u8,
    teal: []const u8,
    red: []const u8,
    red1: []const u8,

    /// Get ANSI escape codes for a color
    pub fn ansi(self: *const Theme, color: []const u8) []const u8 {
        _ = self;
        return color;
    }

    /// Get theme by variant
    pub fn get(variant: TokyoNightVariant) Theme {
        return switch (variant) {
            .night => tokyoNight(),
            .moon => tokyoMoon(),
            .storm => tokyoStorm(),
        };
    }
};

/// Tokyo Night (default) - Deep dark theme
fn tokyoNight() Theme {
    return .{
        .bg = "\x1b[48;2;26;27;38m",           // #1a1b26
        .bg_dark = "\x1b[48;2;22;22;30m",      // #16161e
        .bg_highlight = "\x1b[48;2;41;46;66m", // #292e42
        .terminal_black = "\x1b[38;2;21;25;41m", // #15161e
        .fg = "\x1b[38;2;192;202;245m",        // #c0caf5
        .fg_dark = "\x1b[38;2;169;177;214m",   // #a9b1d6
        .fg_gutter = "\x1b[38;2;59;66;82m",    // #3b4261
        .dark3 = "\x1b[38;2;68;75;106m",       // #444b6a
        .comment = "\x1b[38;2;118;129;168m",   // #565f89
        .dark5 = "\x1b[38;2;115;124;159m",     // #737aa2

        .blue = "\x1b[38;2;122;162;247m",      // #7aa2f7
        .cyan = "\x1b[38;2;125;207;255m",      // #7dcfff
        .blue1 = "\x1b[38;2;42;195;222m",      // #2ac3de
        .blue2 = "\x1b[38;2;0;219;222m",       // #0db9d7
        .blue5 = "\x1b[38;2;137;221;255m",     // #89ddff
        .blue6 = "\x1b[38;2;180;249;248m",     // #b4f9f8
        .blue7 = "\x1b[38;2;148;226;213m",     // #394b70
        .magenta = "\x1b[38;2;187;154;247m",   // #bb9af7
        .magenta2 = "\x1b[38;2;255;117;255m",  // #ff007c
        .purple = "\x1b[38;2;157;124;216m",    // #9d7cd8
        .orange = "\x1b[38;2;255;158;100m",    // #ff9e64
        .yellow = "\x1b[38;2;224;175;104m",    // #e0af68
        .green = "\x1b[38;2;158;206;106m",     // #9ece6a
        .green1 = "\x1b[38;2;115;218;202m",    // #73daca
        .green2 = "\x1b[38;2;65;166;181m",     // #41a6b5
        .teal = "\x1b[38;2;29;200;205m",       // #1abc9c
        .red = "\x1b[38;2;247;118;142m",       // #f7768e
        .red1 = "\x1b[38;2;219;75;75m",        // #db4b4b
    };
}

/// Tokyo Moon - Softer contrast variant
fn tokyoMoon() Theme {
    return .{
        .bg = "\x1b[48;2;34;36;54m",           // #222436
        .bg_dark = "\x1b[48;2;27;29;42m",      // #1b1d2a
        .bg_highlight = "\x1b[48;2;46;49;72m", // #2e3148
        .terminal_black = "\x1b[38;2;25;27;40m", // #191b28
        .fg = "\x1b[38;2;192;202;245m",        // #c8d3f5
        .fg_dark = "\x1b[38;2;169;177;214m",   // #a9b8e8
        .fg_gutter = "\x1b[38;2;61;66;92m",    // #3d425c
        .dark3 = "\x1b[38;2;73;79;111m",       // #494f6f
        .comment = "\x1b[38;2;107;116;140m",   // #636da6
        .dark5 = "\x1b[38;2;131;145;182m",     // #828bb6

        .blue = "\x1b[38;2;130;170;255m",      // #82aaff
        .cyan = "\x1b[38;2;134;222;255m",      // #86e1fc
        .blue1 = "\x1b[38;2;59;202;237m",      // #3bcaed
        .blue2 = "\x1b[38;2;15;197;223m",      // #0fc5df
        .blue5 = "\x1b[38;2;137;221;255m",     // #89ddff
        .blue6 = "\x1b[38;2;180;249;248m",     // #b4f9f8
        .blue7 = "\x1b[38;2;100;114;154m",     // #64729a
        .magenta = "\x1b[38;2;198;160;246m",   // #c099ff
        .magenta2 = "\x1b[38;2;255;117;181m",  // #ff75b5
        .purple = "\x1b[38;2;182;141;244m",    // #b68df4
        .orange = "\x1b[38;2;255;152;102m",    // #ff9866
        .yellow = "\x1b[38;2;255;199;119m",    // #ffc777
        .green = "\x1b[38;2;195;232;141m",     // #c3e88d
        .green1 = "\x1b[38;2;77;231;171m",     // #4de7ab
        .green2 = "\x1b[38;2;73;179;181m",     // #49b3b5
        .teal = "\x1b[38;2;76;230;199m",       // #4ce6c7
        .red = "\x1b[38;2;255;117;127m",       // #ff757f
        .red1 = "\x1b[38;2;195;80;104m",       // #c35068
    };
}

/// Tokyo Storm - Warmer tones variant
fn tokyoStorm() Theme {
    return .{
        .bg = "\x1b[48;2;36;40;59m",           // #24283b
        .bg_dark = "\x1b[48;2;31;35;51m",      // #1f2335
        .bg_highlight = "\x1b[48;2;43;48;71m", // #2b3047
        .terminal_black = "\x1b[38;2;27;30;46m", // #1b1e2e
        .fg = "\x1b[38;2;192;202;245m",        // #c0caf5
        .fg_dark = "\x1b[38;2;169;177;214m",   // #a9b1d6
        .fg_gutter = "\x1b[38;2;59;66;82m",    // #3b4261
        .dark3 = "\x1b[38;2;68;75;106m",       // #444b6a
        .comment = "\x1b[38;2;101;112;154m",   // #565f89
        .dark5 = "\x1b[38;2;115;124;159m",     // #737aa2

        .blue = "\x1b[38;2;122;162;247m",      // #7aa2f7
        .cyan = "\x1b[38;2;125;207;255m",      // #7dcfff
        .blue1 = "\x1b[38;2;42;195;222m",      // #2ac3de
        .blue2 = "\x1b[38;2;0;219;222m",       // #0db9d7
        .blue5 = "\x1b[38;2;137;221;255m",     // #89ddff
        .blue6 = "\x1b[38;2;180;249;248m",     // #b4f9f8
        .blue7 = "\x1b[38;2;57;75;112m",       // #394b70
        .magenta = "\x1b[38;2;187;154;247m",   // #bb9af7
        .magenta2 = "\x1b[38;2;255;117;255m",  // #ff007c
        .purple = "\x1b[38;2;157;124;216m",    // #9d7cd8
        .orange = "\x1b[38;2;255;158;100m",    // #ff9e64
        .yellow = "\x1b[38;2;224;175;104m",    // #e0af68
        .green = "\x1b[38;2;158;206;106m",     // #9ece6a
        .green1 = "\x1b[38;2;115;218;202m",    // #73daca
        .green2 = "\x1b[38;2;65;166;181m",     // #41a6b5
        .teal = "\x1b[38;2;29;200;205m",       // #1abc9c
        .red = "\x1b[38;2;247;118;142m",       // #f7768e
        .red1 = "\x1b[38;2;219;75;75m",        // #db4b4b
    };
}

/// Get current theme from config
pub fn getCurrentTheme(allocator: std.mem.Allocator) Theme {
    // Try to load from config file
    const config_path = getConfigPath(allocator) catch return Theme.get(.night);
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return Theme.get(.night);
    defer file.close();

    // Read file content with stat
    const stat = file.stat() catch return Theme.get(.night);
    const content = allocator.alloc(u8, stat.size) catch return Theme.get(.night);
    defer allocator.free(content);

    _ = file.readAll(content) catch return Theme.get(.night);

    // Simple TOML parsing - look for theme = "variant"
    if (std.mem.indexOf(u8, content, "theme = \"")) |start| {
        const after_eq = content[start + 9..];
        if (std.mem.indexOf(u8, after_eq, "\"")) |end| {
            const variant_str = after_eq[0..end];
            if (TokyoNightVariant.fromString(variant_str)) |variant| {
                return Theme.get(variant);
            }
        }
    }

    // Default to night
    return Theme.get(.night);
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fmt.allocPrint(allocator, "{s}/.config/zeke/zeke.toml", .{home});
}

/// Theme configuration helper
pub const ThemeConfig = struct {
    variant: TokyoNightVariant = .night,

    pub fn save(self: *const ThemeConfig, allocator: std.mem.Allocator) !void {
        const config_path = try getConfigPath(allocator);
        defer allocator.free(config_path);

        // Ensure directory exists
        const dir_path = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
        std.fs.makeDirAbsolute(dir_path) catch {};

        const file = try std.fs.createFileAbsolute(config_path, .{});
        defer file.close();

        const content = try std.fmt.allocPrint(allocator,
            \\# Zeke Configuration
            \\
            \\[ui]
            \\theme = "{s}"  # Options: night, moon, storm
            \\
            \\[providers]
            \\# Add your provider preferences here
            \\
        , .{@tagName(self.variant)});
        defer allocator.free(content);

        try file.writeAll(content);
    }
};

/// Print colored text using Tokyo Night theme
pub fn printColored(theme: *const Theme, color_name: []const u8, text: []const u8) void {
    const color = if (std.mem.eql(u8, color_name, "blue"))
        theme.blue
    else if (std.mem.eql(u8, color_name, "green"))
        theme.green
    else if (std.mem.eql(u8, color_name, "yellow"))
        theme.yellow
    else if (std.mem.eql(u8, color_name, "red"))
        theme.red
    else if (std.mem.eql(u8, color_name, "magenta"))
        theme.magenta
    else if (std.mem.eql(u8, color_name, "cyan"))
        theme.cyan
    else
        theme.fg;

    std.debug.print("{s}{s}\x1b[0m", .{ color, text });
}
