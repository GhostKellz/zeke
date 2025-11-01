const std = @import("std");

/// Theme name constants
pub const GHOST_HACKER_BLUE = "ghost-hacker-blue";
pub const TOKYONIGHT_NIGHT = "tokyonight-night";
pub const TOKYONIGHT_STORM = "tokyonight-storm";
pub const TOKYONIGHT_MOON = "tokyonight-moon";

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse hex color string (RRGGBB or #RRGGBB format) into Color
    pub fn fromHex(hex: []const u8) !Color {
        const color_str = if (std.mem.startsWith(u8, hex, "#")) hex[1..] else hex;
        if (color_str.len != 6) return error.InvalidHexColor;

        const r = try std.fmt.parseInt(u8, color_str[0..2], 16);
        const g = try std.fmt.parseInt(u8, color_str[2..4], 16);
        const b = try std.fmt.parseInt(u8, color_str[4..6], 16);

        return .{ .r = r, .g = g, .b = b };
    }

    /// Convert color to ANSI 24-bit escape sequence
    pub fn toAnsi(self: Color, allocator: std.mem.Allocator, is_bg: bool) ![]const u8 {
        if (is_bg) {
            return try std.fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
        } else {
            return try std.fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
        }
    }
};

/// Theme color palette
pub const Theme = struct {
    allocator: std.mem.Allocator,
    name: []const u8,

    // Core colors
    fg: Color,
    bg: Color,

    // Gray scale
    gray1: Color,
    gray2: Color,
    gray3: Color,

    // Primary colors
    red1: Color,
    red2: Color,
    orange: Color,
    yellow: Color,
    green1: Color,
    green2: Color,

    // Blues and cyans
    blue1: Color,
    blue2: Color,
    blue3: Color,
    blue4: Color,
    blue5: Color,
    blue6: Color,

    // Special colors (for ghost-hacker-blue)
    mint: ?Color,
    teal: ?Color,
    magenta: ?Color,
    pink: ?Color,

    pub fn deinit(self: *Theme) void {
        self.allocator.free(self.name);
    }

    /// Load theme from YAML file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Theme {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);

        return try parseYaml(allocator, content, path);
    }

    /// Simple YAML parser for our theme format
    fn parseYaml(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !Theme {
        var theme = Theme{
            .allocator = allocator,
            .name = undefined,
            .fg = undefined,
            .bg = undefined,
            .gray1 = undefined,
            .gray2 = undefined,
            .gray3 = undefined,
            .red1 = undefined,
            .red2 = undefined,
            .orange = undefined,
            .yellow = undefined,
            .green1 = undefined,
            .green2 = undefined,
            .blue1 = undefined,
            .blue2 = undefined,
            .blue3 = undefined,
            .blue4 = undefined,
            .blue5 = undefined,
            .blue6 = undefined,
            .mint = null,
            .teal = null,
            .magenta = null,
            .pink = null,
        };

        // Extract theme name from path
        const basename = std.fs.path.basename(path);
        const name_end = std.mem.indexOf(u8, basename, ".yml") orelse basename.len;
        theme.name = try allocator.dupe(u8, basename[0..name_end]);

        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_colors_section = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Skip comments and empty lines
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Check if we're in colors section
            if (std.mem.eql(u8, trimmed, "colors:")) {
                in_colors_section = true;
                continue;
            }

            // Exit colors section when we hit another top-level key
            if (!std.mem.startsWith(u8, trimmed, " ") and std.mem.indexOf(u8, trimmed, ":") != null) {
                in_colors_section = false;
            }

            if (!in_colors_section) continue;

            // Parse color line: "  key:  "value""
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_idx| {
                const key = std.mem.trim(u8, trimmed[0..colon_idx], &std.ascii.whitespace);
                const value_part = std.mem.trim(u8, trimmed[colon_idx + 1 ..], &std.ascii.whitespace);

                // Extract hex value (remove quotes and comments)
                var hex: []const u8 = value_part;
                if (std.mem.startsWith(u8, value_part, "\"")) {
                    const end_quote = std.mem.indexOfScalar(u8, value_part[1..], '"') orelse continue;
                    hex = value_part[1 .. end_quote + 1];
                }

                // Parse the color
                const color = Color.fromHex(hex) catch continue;

                // Assign to appropriate field
                if (std.mem.eql(u8, key, "fg")) {
                    theme.fg = color;
                } else if (std.mem.eql(u8, key, "bg")) {
                    theme.bg = color;
                } else if (std.mem.eql(u8, key, "gray1")) {
                    theme.gray1 = color;
                } else if (std.mem.eql(u8, key, "gray2")) {
                    theme.gray2 = color;
                } else if (std.mem.eql(u8, key, "gray3")) {
                    theme.gray3 = color;
                } else if (std.mem.eql(u8, key, "red1")) {
                    theme.red1 = color;
                } else if (std.mem.eql(u8, key, "red2")) {
                    theme.red2 = color;
                } else if (std.mem.eql(u8, key, "orange")) {
                    theme.orange = color;
                } else if (std.mem.eql(u8, key, "yellow")) {
                    theme.yellow = color;
                } else if (std.mem.eql(u8, key, "green1")) {
                    theme.green1 = color;
                } else if (std.mem.eql(u8, key, "green2")) {
                    theme.green2 = color;
                } else if (std.mem.eql(u8, key, "blue1")) {
                    theme.blue1 = color;
                } else if (std.mem.eql(u8, key, "blue2")) {
                    theme.blue2 = color;
                } else if (std.mem.eql(u8, key, "blue3")) {
                    theme.blue3 = color;
                } else if (std.mem.eql(u8, key, "blue4")) {
                    theme.blue4 = color;
                } else if (std.mem.eql(u8, key, "blue5")) {
                    theme.blue5 = color;
                } else if (std.mem.eql(u8, key, "blue6")) {
                    theme.blue6 = color;
                } else if (std.mem.eql(u8, key, "mint")) {
                    theme.mint = color;
                } else if (std.mem.eql(u8, key, "teal")) {
                    theme.teal = color;
                } else if (std.mem.eql(u8, key, "magenta")) {
                    theme.magenta = color;
                } else if (std.mem.eql(u8, key, "pink")) {
                    theme.pink = color;
                }
            }
        }

        return theme;
    }

    /// Load the ghost-hacker-blue theme
    pub fn loadGhostHackerBlue(allocator: std.mem.Allocator) !Theme {
        const theme_path = "archive/vivid/ghost-hacker-blue.yml";
        return loadFromFile(allocator, theme_path);
    }

    /// Load Tokyo Night theme
    pub fn loadTokyoNightNight(allocator: std.mem.Allocator) !Theme {
        const theme_path = "archive/vivid/tokyonight-night.yml";
        return loadFromFile(allocator, theme_path);
    }
};

test "Color fromHex" {
    const color = try Color.fromHex("c8d3f5");
    try std.testing.expectEqual(@as(u8, 0xc8), color.r);
    try std.testing.expectEqual(@as(u8, 0xd3), color.g);
    try std.testing.expectEqual(@as(u8, 0xf5), color.b);
}

test "Color toAnsi foreground" {
    const color = Color{ .r = 200, .g = 211, .b = 245 };
    const allocator = std.testing.allocator;

    const ansi_fg = try color.toAnsi(allocator, false);
    defer allocator.free(ansi_fg);

    try std.testing.expectEqualStrings("\x1b[38;2;200;211;245m", ansi_fg);
}

test "Color toAnsi background" {
    const color = Color{ .r = 34, .g = 36, .b = 54 };
    const allocator = std.testing.allocator;

    const ansi_bg = try color.toAnsi(allocator, true);
    defer allocator.free(ansi_bg);

    try std.testing.expectEqualStrings("\x1b[48;2;34;36;54m", ansi_bg);
}
