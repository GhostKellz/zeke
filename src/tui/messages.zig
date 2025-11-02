const std = @import("std");
const session = @import("session.zig");

/// Message display entry
pub const MessageDisplay = struct {
    role: session.MessageRole,
    content: []const u8,
    wrapped_lines: std.array_list.AlignedManaged([]const u8, null),

    pub fn deinit(self: *MessageDisplay, allocator: std.mem.Allocator) void {
        for (self.wrapped_lines.items) |line| {
            allocator.free(line);
        }
        self.wrapped_lines.deinit();
    }
};

/// Message renderer with scrolling support
pub const MessageRenderer = struct {
    allocator: std.mem.Allocator,
    messages: std.array_list.AlignedManaged(MessageDisplay, null),
    scroll_offset: usize,
    max_visible_lines: usize,

    pub fn init(allocator: std.mem.Allocator, max_visible_lines: usize) MessageRenderer {
        return MessageRenderer{
            .allocator = allocator,
            .messages = std.array_list.AlignedManaged(MessageDisplay, null).init(allocator),
            .scroll_offset = 0,
            .max_visible_lines = max_visible_lines,
        };
    }

    pub fn deinit(self: *MessageRenderer) void {
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit();
    }

    /// Add a message with word wrapping
    pub fn addMessage(self: *MessageRenderer, role: session.MessageRole, content: []const u8, width: usize) !void {
        var wrapped_lines = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);

        // Simple word wrapping
        var start: usize = 0;
        while (start < content.len) {
            const remaining = content[start..];
            const chunk_len = @min(remaining.len, width);
            const chunk = remaining[0..chunk_len];

            const owned_line = try self.allocator.dupe(u8, chunk);
            try wrapped_lines.append(owned_line);

            start += chunk_len;
        }

        const display = MessageDisplay{
            .role = role,
            .content = content,
            .wrapped_lines = wrapped_lines,
        };

        try self.messages.append(display);

        // Auto-scroll to bottom
        self.scrollToBottom();
    }

    /// Scroll up by N lines
    pub fn scrollUp(self: *MessageRenderer, lines: usize) void {
        if (self.scroll_offset >= lines) {
            self.scroll_offset -= lines;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Scroll down by N lines
    pub fn scrollDown(self: *MessageRenderer, lines: usize) void {
        const total_lines = self.getTotalLines();
        const max_scroll = if (total_lines > self.max_visible_lines)
            total_lines - self.max_visible_lines
        else
            0;

        self.scroll_offset = @min(self.scroll_offset + lines, max_scroll);
    }

    /// Scroll to bottom (most recent messages)
    pub fn scrollToBottom(self: *MessageRenderer) void {
        const total_lines = self.getTotalLines();
        self.scroll_offset = if (total_lines > self.max_visible_lines)
            total_lines - self.max_visible_lines
        else
            0;
    }

    /// Get total number of wrapped lines across all messages
    fn getTotalLines(self: *const MessageRenderer) usize {
        var total: usize = 0;
        for (self.messages.items) |msg| {
            total += msg.wrapped_lines.items.len + 1; // +1 for role header
        }
        return total;
    }

    /// Render visible messages
    pub fn render(self: *const MessageRenderer, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.array_list.AlignedManaged(u8, null).init(allocator);
        defer buf.deinit();

        var line_count: usize = 0;
        var lines_to_skip = self.scroll_offset;

        for (self.messages.items) |msg| {
            // Render role header
            const role_str = switch (msg.role) {
                .user => "💬 You:",
                .assistant => "🤖 AI:",
                .system => "⚙️  System:",
            };

            if (lines_to_skip > 0) {
                lines_to_skip -= 1;
            } else if (line_count < self.max_visible_lines) {
                try buf.appendSlice(role_str);
                try buf.appendSlice("\r\n");
                line_count += 1;
            }

            // Render wrapped content lines
            for (msg.wrapped_lines.items) |line| {
                if (lines_to_skip > 0) {
                    lines_to_skip -= 1;
                } else if (line_count < self.max_visible_lines) {
                    try buf.appendSlice(line);
                    try buf.appendSlice("\r\n");
                    line_count += 1;
                } else {
                    break;
                }
            }

            if (line_count >= self.max_visible_lines) break;
        }

        return try buf.toOwnedSlice();
    }
};

// Tests
test "message renderer basic" {
    const allocator = std.testing.allocator;

    var renderer = MessageRenderer.init(allocator, 10);
    defer renderer.deinit();

    try renderer.addMessage(.user, "Hello world", 80);
    try renderer.addMessage(.assistant, "Hi there!", 80);

    try std.testing.expectEqual(@as(usize, 2), renderer.messages.items.len);
}

test "message word wrapping" {
    const allocator = std.testing.allocator;

    var renderer = MessageRenderer.init(allocator, 10);
    defer renderer.deinit();

    try renderer.addMessage(.user, "This is a very long message that should wrap", 10);

    // Should create multiple wrapped lines
    try std.testing.expect(renderer.messages.items[0].wrapped_lines.items.len > 1);
}

test "message scrolling" {
    const allocator = std.testing.allocator;

    var renderer = MessageRenderer.init(allocator, 5);
    defer renderer.deinit();

    try renderer.addMessage(.user, "1", 80);
    try renderer.addMessage(.user, "2", 80);
    try renderer.addMessage(.user, "3", 80);

    try std.testing.expectEqual(@as(usize, 3), renderer.messages.items.len);

    renderer.scrollUp(1);
    try std.testing.expect(renderer.scroll_offset < 10);
}
