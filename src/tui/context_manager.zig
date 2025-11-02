const std = @import("std");

/// Context item type
pub const ContextType = enum {
    file,
    directory,
    url,
    text,
};

/// Single context item
pub const ContextItem = struct {
    type: ContextType,
    path: []const u8,
    content: ?[]const u8 = null,
    token_count: u32 = 0,
    timestamp: i64,

    pub fn deinit(self: *ContextItem, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.content) |content| {
            allocator.free(content);
        }
    }
};

/// Context management for AI conversations
pub const ContextManager = struct {
    allocator: std.mem.Allocator,
    items: std.array_list.AlignedManaged(ContextItem, null),
    max_tokens: u32,
    current_tokens: u32,
    auto_suggest: bool,

    pub fn init(allocator: std.mem.Allocator, max_tokens: u32) ContextManager {
        return .{
            .allocator = allocator,
            .items = std.array_list.AlignedManaged(ContextItem, null).init(allocator),
            .max_tokens = max_tokens,
            .current_tokens = 0,
            .auto_suggest = true,
        };
    }

    pub fn deinit(self: *ContextManager) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit();
    }

    /// Add a file to context
    pub fn addFile(self: *ContextManager, file_path: []const u8) !void {
        // Check if already in context
        for (self.items.items) |item| {
            if (item.type == .file and std.mem.eql(u8, item.path, file_path)) {
                return error.AlreadyInContext;
            }
        }

        // Read file content
        const content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024, // 10MB max
        );
        errdefer self.allocator.free(content);

        // Estimate token count (rough: 1 token per 4 chars)
        const tokens = @as(u32, @intCast(content.len / 4));

        // Check token limit
        if (self.current_tokens + tokens > self.max_tokens) {
            self.allocator.free(content);
            return error.ContextTokenLimitExceeded;
        }

        const item = ContextItem{
            .type = .file,
            .path = try self.allocator.dupe(u8, file_path),
            .content = content,
            .token_count = tokens,
            .timestamp = std.time.timestamp(),
        };

        try self.items.append(item);
        self.current_tokens += tokens;
    }

    /// Add a directory to context (recursively)
    pub fn addDirectory(self: *ContextManager, dir_path: []const u8, max_depth: usize) !void {
        // Check if already in context
        for (self.items.items) |item| {
            if (item.type == .directory and std.mem.eql(u8, item.path, dir_path)) {
                return error.AlreadyInContext;
            }
        }

        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        var file_count: usize = 0;
        const total_tokens: u32 = 0;

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (walker.stack.items.len > max_depth) continue;

            // Skip common ignore patterns
            if (self.shouldIgnore(entry.path)) continue;

            // Build full path
            const full_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ dir_path, entry.path },
            );
            defer self.allocator.free(full_path);

            // Try to add file
            self.addFile(full_path) catch |err| {
                if (err == error.ContextTokenLimitExceeded) {
                    break;
                }
                continue; // Skip files we can't read
            };

            file_count += 1;
            if (file_count > 100) break; // Safety limit
        }

        // Add directory marker
        const item = ContextItem{
            .type = .directory,
            .path = try self.allocator.dupe(u8, dir_path),
            .content = null,
            .token_count = total_tokens,
            .timestamp = std.time.timestamp(),
        };

        try self.items.append(item);
    }

    /// Add text snippet to context
    pub fn addText(self: *ContextManager, name: []const u8, text: []const u8) !void {
        const tokens = @as(u32, @intCast(text.len / 4));

        if (self.current_tokens + tokens > self.max_tokens) {
            return error.ContextTokenLimitExceeded;
        }

        const item = ContextItem{
            .type = .text,
            .path = try self.allocator.dupe(u8, name),
            .content = try self.allocator.dupe(u8, text),
            .token_count = tokens,
            .timestamp = std.time.timestamp(),
        };

        try self.items.append(item);
        self.current_tokens += tokens;
    }

    /// Remove item from context
    pub fn remove(self: *ContextManager, path: []const u8) !void {
        for (self.items.items, 0..) |*item, i| {
            if (std.mem.eql(u8, item.path, path)) {
                self.current_tokens -= item.token_count;
                item.deinit(self.allocator);
                _ = self.items.orderedRemove(i);
                return;
            }
        }
        return error.NotInContext;
    }

    /// Clear all context
    pub fn clear(self: *ContextManager) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();
        self.current_tokens = 0;
    }

    /// Get context items list
    pub fn list(self: *const ContextManager) []const ContextItem {
        return self.items.items;
    }

    /// Get formatted context for AI prompt
    pub fn formatForPrompt(self: *ContextManager) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        try output.appendSlice("# Context Files\n\n");

        for (self.items.items) |item| {
            switch (item.type) {
                .file => {
                    try output.appendSlice("## File: ");
                    try output.appendSlice(item.path);
                    try output.appendSlice("\n```\n");
                    if (item.content) |content| {
                        try output.appendSlice(content);
                    }
                    try output.appendSlice("\n```\n\n");
                },
                .text => {
                    try output.appendSlice("## ");
                    try output.appendSlice(item.path);
                    try output.appendSlice("\n");
                    if (item.content) |content| {
                        try output.appendSlice(content);
                    }
                    try output.appendSlice("\n\n");
                },
                .directory => {
                    try output.appendSlice("## Directory: ");
                    try output.appendSlice(item.path);
                    try output.appendSlice("\n\n");
                },
                .url => {
                    try output.appendSlice("## URL: ");
                    try output.appendSlice(item.path);
                    try output.appendSlice("\n\n");
                },
            }
        }

        return try output.toOwnedSlice();
    }

    /// Suggest relevant files based on current conversation
    pub fn suggestFiles(self: *ContextManager, query: []const u8) ![]const []const u8 {
        _ = self;
        _ = query;
        // TODO: Implement intelligent file suggestion based on:
        // - Recent edits
        // - Import statements in existing context
        // - Git changes
        // - Keyword matching
        return &[_][]const u8{};
    }

    /// Check if file should be ignored
    fn shouldIgnore(self: *ContextManager, path: []const u8) bool {
        _ = self;

        const ignore_patterns = [_][]const u8{
            ".git/",
            "node_modules/",
            ".zig-cache/",
            "zig-out/",
            ".zeke_backups/",
            "target/",
            "build/",
            "dist/",
            ".DS_Store",
            "*.pyc",
            "*.o",
            "*.so",
            "*.dylib",
        };

        for (ignore_patterns) |pattern| {
            if (std.mem.indexOf(u8, path, pattern) != null) {
                return true;
            }
        }

        return false;
    }

    /// Get token usage stats
    pub fn getStats(self: *const ContextManager) struct {
        items: usize,
        tokens: u32,
        max_tokens: u32,
        usage_percent: f32,
    } {
        return .{
            .items = self.items.items.len,
            .tokens = self.current_tokens,
            .max_tokens = self.max_tokens,
            .usage_percent = @as(f32, @floatFromInt(self.current_tokens)) / @as(f32, @floatFromInt(self.max_tokens)) * 100.0,
        };
    }
};

// Tests
test "context manager init" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 100000);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.items.items.len);
    try std.testing.expectEqual(@as(u32, 0), ctx.current_tokens);
}

test "add text to context" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 100000);
    defer ctx.deinit();

    try ctx.addText("note", "This is a test note");

    try std.testing.expectEqual(@as(usize, 1), ctx.items.items.len);
    try std.testing.expect(ctx.current_tokens > 0);
}

test "remove from context" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 100000);
    defer ctx.deinit();

    try ctx.addText("note1", "First note");
    try ctx.addText("note2", "Second note");

    try std.testing.expectEqual(@as(usize, 2), ctx.items.items.len);

    try ctx.remove("note1");
    try std.testing.expectEqual(@as(usize, 1), ctx.items.items.len);
}

test "clear context" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 100000);
    defer ctx.deinit();

    try ctx.addText("note1", "First note");
    try ctx.addText("note2", "Second note");

    ctx.clear();
    try std.testing.expectEqual(@as(usize, 0), ctx.items.items.len);
    try std.testing.expectEqual(@as(u32, 0), ctx.current_tokens);
}

test "token limit enforcement" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 10); // Very small limit
    defer ctx.deinit();

    const large_text = "a" ** 100; // Should exceed limit

    try std.testing.expectError(
        error.ContextTokenLimitExceeded,
        ctx.addText("large", large_text),
    );
}

test "get stats" {
    const allocator = std.testing.allocator;

    var ctx = ContextManager.init(allocator, 1000);
    defer ctx.deinit();

    try ctx.addText("note", "Test");

    const stats = ctx.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.items);
    try std.testing.expect(stats.tokens > 0);
    try std.testing.expect(stats.usage_percent < 100.0);
}
