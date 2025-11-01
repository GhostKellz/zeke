const std = @import("std");

/// Cross-platform browser opener for OAuth flows
pub const BrowserOpener = struct {
    /// Open URL in the system's default browser
    pub fn open(allocator: std.mem.Allocator, url: []const u8) !void {
        const os_tag = @import("builtin").os.tag;

        const command = switch (os_tag) {
            .linux => "xdg-open",
            .macos => "open",
            .windows => "start",
            else => return error.UnsupportedPlatform,
        };

        // On Windows, we need to use cmd.exe /c start
        if (os_tag == .windows) {
            var child = std.process.Child.init(&[_][]const u8{ "cmd.exe", "/c", "start", url }, allocator);
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;

            _ = try child.spawnAndWait();
        } else {
            // Linux/macOS
            var child = std.process.Child.init(&[_][]const u8{ command, url }, allocator);
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;

            _ = try child.spawnAndWait();
        }
    }

    /// Open URL with fallback to manual instruction
    pub fn openWithFallback(allocator: std.mem.Allocator, url: []const u8) void {
        open(allocator, url) catch {
            // Fallback: print URL for manual opening
            std.debug.print(
                \\
                \\⚠️  Could not automatically open browser.
                \\Please open this URL manually:
                \\
                \\  {s}
                \\
                \\
            , .{url});
        };
    }
};

// === Tests ===

test "browser opener compile" {
    // Just ensure the code compiles
    const allocator = std.testing.allocator;
    _ = allocator;
}
