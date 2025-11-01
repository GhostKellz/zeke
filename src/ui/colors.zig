const std = @import("std");
const themes = @import("themes.zig");

/// Global theme instance (loaded once at startup)
var global_theme: ?themes.Theme = null;
var theme_loaded = false;

/// Initialize the global theme (call once at startup)
pub fn initTheme(allocator: std.mem.Allocator) void {
    if (!theme_loaded) {
        global_theme = themes.getCurrentTheme(allocator);
        theme_loaded = true;
    }
}

/// Get the current theme
pub fn getTheme() themes.Theme {
    if (global_theme) |theme| {
        return theme;
    }
    // Fallback to night theme if not initialized
    return themes.Theme.get(.night);
}

/// Color helpers for common UI elements
pub const Colors = struct {
    /// Success messages (green)
    pub inline fn success() []const u8 {
        return getTheme().green;
    }

    /// Error messages (red)
    pub inline fn error_() []const u8 {
        return getTheme().red;
    }

    /// Warning messages (yellow)
    pub inline fn warning() []const u8 {
        return getTheme().yellow;
    }

    /// Info messages (blue)
    pub inline fn info() []const u8 {
        return getTheme().blue;
    }

    /// Highlight/emphasis (cyan)
    pub inline fn highlight() []const u8 {
        return getTheme().cyan;
    }

    /// Muted/dim text (comment color)
    pub inline fn muted() []const u8 {
        return getTheme().comment;
    }

    /// Primary accent (magenta)
    pub inline fn accent() []const u8 {
        return getTheme().magenta;
    }

    /// Code/command text (orange)
    pub inline fn code() []const u8 {
        return getTheme().orange;
    }

    /// Links (blue1)
    pub inline fn link() []const u8 {
        return getTheme().blue1;
    }

    /// Reset to default
    pub inline fn reset() []const u8 {
        return "\x1b[0m";
    }
};

/// Print colored text with automatic reset
pub fn print(comptime color_fn: fn () []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}", .{color_fn()});
    std.debug.print(fmt, args);
    std.debug.print("{s}", .{Colors.reset()});
}

/// Print success message
pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    print(Colors.success, fmt, args);
}

/// Print error message
pub fn printError(comptime fmt: []const u8, args: anytype) void {
    print(Colors.error_, fmt, args);
}

/// Print warning message
pub fn printWarning(comptime fmt: []const u8, args: anytype) void {
    print(Colors.warning, fmt, args);
}

/// Print info message
pub fn printInfo(comptime fmt: []const u8, args: anytype) void {
    print(Colors.info, fmt, args);
}

/// Print highlighted text
pub fn printHighlight(comptime fmt: []const u8, args: anytype) void {
    print(Colors.highlight, fmt, args);
}

/// Print muted text
pub fn printMuted(comptime fmt: []const u8, args: anytype) void {
    print(Colors.muted, fmt, args);
}

/// Print code/command
pub fn printCode(comptime fmt: []const u8, args: anytype) void {
    print(Colors.code, fmt, args);
}

/// Print link
pub fn printLink(comptime fmt: []const u8, args: anytype) void {
    print(Colors.link, fmt, args);
}
