const std = @import("std");

/// Thinking indicator with animated spinner
pub const ThinkingIndicator = struct {
    frames: []const []const u8,
    current_frame: usize,
    last_update: i64,
    update_interval_ms: i64,
    prefix: []const u8,

    const default_frames = [_][]const u8{
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    };

    pub fn init(prefix: []const u8) ThinkingIndicator {
        return ThinkingIndicator{
            .frames = &default_frames,
            .current_frame = 0,
            .last_update = std.time.timestamp(),
            .update_interval_ms = 80,
            .prefix = prefix,
        };
    }

    /// Advance to next frame if enough time has passed
    pub fn tick(self: *ThinkingIndicator) bool {
        const now = std.time.timestamp();
        const elapsed_ms = (now - self.last_update) * 1000;

        if (elapsed_ms >= self.update_interval_ms) {
            self.current_frame = (self.current_frame + 1) % self.frames.len;
            self.last_update = now;
            return true;
        }
        return false;
    }

    /// Get current frame text
    pub fn getCurrentFrame(self: *const ThinkingIndicator) []const u8 {
        return self.frames[self.current_frame];
    }

    /// Render thinking indicator with prefix
    pub fn render(self: *ThinkingIndicator, allocator: std.mem.Allocator) ![]const u8 {
        const frame = self.getCurrentFrame();
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ frame, self.prefix });
    }

    /// Write thinking indicator directly to writer
    pub fn write(self: *ThinkingIndicator, stdout: std.posix.fd_t) !void {
        const frame = self.getCurrentFrame();

        // Move cursor to start of line, clear line
        _ = try std.posix.write(stdout, "\r\x1b[K");

        // Write spinner and prefix
        _ = try std.posix.write(stdout, frame);
        _ = try std.posix.write(stdout, " ");
        _ = try std.posix.write(stdout, self.prefix);
    }

    /// Clear the thinking indicator from screen
    pub fn clear(stdout: std.posix.fd_t) !void {
        _ = try std.posix.write(stdout, "\r\x1b[K");
    }
};

// Tests
test "thinking indicator init" {
    const indicator = ThinkingIndicator.init("Thinking...");
    try std.testing.expectEqual(@as(usize, 0), indicator.current_frame);
    try std.testing.expectEqualStrings("Thinking...", indicator.prefix);
}

test "thinking indicator frames" {
    var indicator = ThinkingIndicator.init("Test");
    const first_frame = indicator.getCurrentFrame();
    try std.testing.expectEqualStrings("⠋", first_frame);

    // Force tick
    indicator.last_update = 0;
    _ = indicator.tick();
    const second_frame = indicator.getCurrentFrame();
    try std.testing.expectEqualStrings("⠙", second_frame);
}

test "thinking indicator render" {
    const allocator = std.testing.allocator;
    var indicator = ThinkingIndicator.init("Loading");

    const rendered = try indicator.render(allocator);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "Loading") != null);
}
