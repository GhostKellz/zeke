const std = @import("std");
const tokyo = @import("tokyo_night.zig");

/// Status bar component showing session info
pub const StatusBar = struct {
    provider: []const u8,
    model: []const u8,
    thinking_mode: bool,
    total_tokens: u32,
    estimated_cost: f32,
    message_count: usize,

    pub fn init(
        provider: []const u8,
        model: []const u8,
        thinking_mode: bool,
        total_tokens: u32,
        estimated_cost: f32,
        message_count: usize,
    ) StatusBar {
        return StatusBar{
            .provider = provider,
            .model = model,
            .thinking_mode = thinking_mode,
            .total_tokens = total_tokens,
            .estimated_cost = estimated_cost,
            .message_count = message_count,
        };
    }

    /// Render status bar to a string
    pub fn render(self: *const StatusBar, allocator: std.mem.Allocator, width: usize) ![]const u8 {
        // Prepare status components
        const thinking_indicator = if (self.thinking_mode) "🧠 ON" else "🧠 OFF";

        const status_text = try std.fmt.allocPrint(
            allocator,
            "{s}:{s} | {s} | {d} msgs | {d} tokens | ${d:.4}",
            .{
                self.provider,
                self.model,
                thinking_indicator,
                self.message_count,
                self.total_tokens,
                self.estimated_cost,
            },
        );
        defer allocator.free(status_text);

        // Pad or truncate to fit width
        var buf = try allocator.alloc(u8, width);
        @memset(buf, ' ');

        const copy_len = @min(status_text.len, width);
        @memcpy(buf[0..copy_len], status_text[0..copy_len]);

        return buf;
    }

    /// Render with Tokyo Night colors
    pub fn renderColored(self: *const StatusBar, allocator: std.mem.Allocator, width: usize) ![]const u8 {
        const plain = try self.render(allocator, width);
        defer allocator.free(plain);

        // Add Tokyo Night blue background
        return try std.fmt.allocPrint(
            allocator,
            "\x1b[48;2;{d};{d};{d}m\x1b[38;2;{d};{d};{d}m{s}\x1b[0m",
            .{
                tokyo.TokyoNight.blue.r,
                tokyo.TokyoNight.blue.g,
                tokyo.TokyoNight.blue.b,
                tokyo.TokyoNight.bg.r,
                tokyo.TokyoNight.bg.g,
                tokyo.TokyoNight.bg.b,
                plain,
            },
        );
    }

    /// Write status bar to stdout
    pub fn write(self: *const StatusBar, stdout: std.posix.fd_t, width: usize) !void {
        const colored = try self.renderColored(std.heap.page_allocator, width);
        defer std.heap.page_allocator.free(colored);

        _ = try std.posix.write(stdout, colored);
        _ = try std.posix.write(stdout, "\r\n");
    }
};

/// Input history for arrow up/down navigation
pub const InputHistory = struct {
    allocator: std.mem.Allocator,
    items: std.array_list.AlignedManaged([]const u8, null),
    current_index: ?usize, // null when not navigating
    max_size: usize,

    pub fn init(allocator: std.mem.Allocator, max_size: usize) InputHistory {
        return InputHistory{
            .allocator = allocator,
            .items = std.array_list.AlignedManaged([]const u8, null).init(allocator),
            .current_index = null,
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *InputHistory) void {
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.deinit();
    }

    /// Add a new entry to history
    pub fn add(self: *InputHistory, text: []const u8) !void {
        // Don't add empty or duplicate entries
        if (text.len == 0) return;
        if (self.items.items.len > 0) {
            if (std.mem.eql(u8, self.items.items[self.items.items.len - 1], text)) {
                return;
            }
        }

        const owned = try self.allocator.dupe(u8, text);

        // Add to history
        try self.items.append(owned);

        // Limit size
        while (self.items.items.len > self.max_size) {
            const removed = self.items.orderedRemove(0);
            self.allocator.free(removed);
        }

        // Reset navigation
        self.current_index = null;
    }

    /// Navigate to previous entry (arrow up)
    pub fn navigatePrevious(self: *InputHistory) ?[]const u8 {
        if (self.items.items.len == 0) return null;

        if (self.current_index) |idx| {
            if (idx > 0) {
                self.current_index = idx - 1;
            }
        } else {
            // Start from most recent
            self.current_index = self.items.items.len - 1;
        }

        return self.items.items[self.current_index.?];
    }

    /// Navigate to next entry (arrow down)
    pub fn navigateNext(self: *InputHistory) ?[]const u8 {
        if (self.current_index) |idx| {
            if (idx < self.items.items.len - 1) {
                self.current_index = idx + 1;
                return self.items.items[self.current_index.?];
            } else {
                // Reached end, clear navigation
                self.current_index = null;
                return null; // Return to empty input
            }
        }
        return null;
    }

    /// Reset navigation state
    pub fn resetNavigation(self: *InputHistory) void {
        self.current_index = null;
    }
};

// Tests
test "status bar render" {
    const allocator = std.testing.allocator;

    const bar = StatusBar.init("ollama", "llama3.2:3b", true, 1000, 0.01, 5);
    const rendered = try bar.render(allocator, 80);
    defer allocator.free(rendered);

    try std.testing.expectEqual(@as(usize, 80), rendered.len);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "ollama") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "llama3.2:3b") != null);
}

test "input history" {
    const allocator = std.testing.allocator;

    var history = InputHistory.init(allocator, 10);
    defer history.deinit();

    try history.add("first");
    try history.add("second");
    try history.add("third");

    try std.testing.expectEqual(@as(usize, 3), history.items.items.len);

    // Navigate back
    const prev1 = history.navigatePrevious();
    try std.testing.expectEqualStrings("third", prev1.?);

    const prev2 = history.navigatePrevious();
    try std.testing.expectEqualStrings("second", prev2.?);

    // Navigate forward
    const next1 = history.navigateNext();
    try std.testing.expectEqualStrings("third", next1.?);

    const next2 = history.navigateNext();
    try std.testing.expect(next2 == null); // Back to empty
}

test "input history max size" {
    const allocator = std.testing.allocator;

    var history = InputHistory.init(allocator, 3);
    defer history.deinit();

    try history.add("1");
    try history.add("2");
    try history.add("3");
    try history.add("4");

    // Should only keep last 3
    try std.testing.expectEqual(@as(usize, 3), history.items.items.len);
    try std.testing.expectEqualStrings("2", history.items.items[0]);
    try std.testing.expectEqualStrings("4", history.items.items[2]);
}
