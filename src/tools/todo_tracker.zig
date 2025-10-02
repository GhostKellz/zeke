//! TODO Tracker - Advanced TODO Comment Management
//!
//! Extracts, categorizes, and tracks TODO comments across the codebase
//! with priority levels, assignees, and context.

const std = @import("std");
const zeke = @import("zeke");

/// TODO priority levels
pub const TodoPriority = enum {
    critical, // FIXME, XXX, HACK
    high, // TODO with !!!
    medium, // TODO with !!
    low, // TODO with !
    normal, // Regular TODO

    pub fn fromMarker(marker: []const u8) TodoPriority {
        if (std.mem.indexOf(u8, marker, "FIXME") != null or
            std.mem.indexOf(u8, marker, "XXX") != null or
            std.mem.indexOf(u8, marker, "HACK") != null)
        {
            return .critical;
        }

        const exclamation_count = std.mem.count(u8, marker, "!");
        if (exclamation_count >= 3) return .high;
        if (exclamation_count == 2) return .medium;
        if (exclamation_count == 1) return .low;

        return .normal;
    }
};

/// TODO category
pub const TodoCategory = enum {
    bug_fix, // FIXME, BUG
    refactor, // REFACTOR, CLEANUP
    optimization, // OPTIMIZE, PERF
    documentation, // DOC, DOCS
    feature, // TODO, FEATURE
    security, // SECURITY, XXX
    @"test", // TEST, TESTING
    hack, // HACK, WORKAROUND
    unknown,

    pub fn fromMarker(marker: []const u8) TodoCategory {
        if (std.mem.indexOf(u8, marker, "FIXME") != null or
            std.mem.indexOf(u8, marker, "BUG") != null) return .bug_fix;
        if (std.mem.indexOf(u8, marker, "REFACTOR") != null or
            std.mem.indexOf(u8, marker, "CLEANUP") != null) return .refactor;
        if (std.mem.indexOf(u8, marker, "OPTIMIZE") != null or
            std.mem.indexOf(u8, marker, "PERF") != null) return .optimization;
        if (std.mem.indexOf(u8, marker, "DOC") != null) return .documentation;
        if (std.mem.indexOf(u8, marker, "SECURITY") != null or
            std.mem.indexOf(u8, marker, "XXX") != null) return .security;
        if (std.mem.indexOf(u8, marker, "TEST") != null) return .@"test";
        if (std.mem.indexOf(u8, marker, "HACK") != null or
            std.mem.indexOf(u8, marker, "WORKAROUND") != null) return .hack;
        if (std.mem.indexOf(u8, marker, "TODO") != null or
            std.mem.indexOf(u8, marker, "FEATURE") != null) return .feature;

        return .unknown;
    }
};

/// Extracted TODO item
pub const TodoItem = struct {
    file_path: []const u8,
    line: usize,
    column: usize,
    marker: []const u8, // TODO, FIXME, XXX, etc.
    message: []const u8,
    context: []const u8, // Surrounding code context
    priority: TodoPriority,
    category: TodoCategory,
    assignee: ?[]const u8, // Extracted from TODO(@username)
    issue_ref: ?[]const u8, // Extracted from TODO(#123)
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TodoItem) void {
        self.allocator.free(self.file_path);
        self.allocator.free(self.marker);
        self.allocator.free(self.message);
        self.allocator.free(self.context);
        if (self.assignee) |a| self.allocator.free(a);
        if (self.issue_ref) |r| self.allocator.free(r);
    }

    /// Format TODO as string for display
    pub fn format(
        self: TodoItem,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const priority_icon = switch (self.priority) {
            .critical => "🔴",
            .high => "🟠",
            .medium => "🟡",
            .low => "🔵",
            .normal => "⚪",
        };

        const category_icon = switch (self.category) {
            .bug_fix => "🐛",
            .refactor => "♻️ ",
            .optimization => "⚡",
            .documentation => "📚",
            .feature => "✨",
            .security => "🔒",
            .@"test" => "🧪",
            .hack => "⚠️ ",
            .unknown => "❓",
        };

        try writer.print("{s}{s} {s}:{d}:{d} [{s}] {s}", .{
            priority_icon,
            category_icon,
            self.file_path,
            self.line,
            self.column,
            self.marker,
            self.message,
        });

        if (self.assignee) |assignee| {
            try writer.print(" (@{s})", .{assignee});
        }

        if (self.issue_ref) |issue| {
            try writer.print(" (#{s})", .{issue});
        }
    }
};

/// TODO Tracker
pub const TodoTracker = struct {
    allocator: std.mem.Allocator,
    todos: std.ArrayList(TodoItem),

    pub fn init(allocator: std.mem.Allocator) TodoTracker {
        return .{
            .allocator = allocator,
            .todos = .{},
        };
    }

    pub fn deinit(self: *TodoTracker) void {
        for (self.todos.items) |*todo| {
            todo.deinit();
        }
        self.todos.deinit(self.allocator);
    }

    /// Extract all TODO comments from source code
    pub fn extractTodos(
        self: *TodoTracker,
        file_path: []const u8,
        source: []const u8,
    ) !void {
        const markers = [_][]const u8{
            "TODO", "FIXME", "XXX", "HACK", "BUG",
            "OPTIMIZE", "REFACTOR", "NOTE", "REVIEW",
        };

        var line_iter = std.mem.splitScalar(u8, source, '\n');
        var line_no: usize = 1;
        while (line_iter.next()) |line| : (line_no += 1) {
            // Check each marker
            for (markers) |marker| {
                if (std.mem.indexOf(u8, line, marker)) |col| {
                    // Extract the TODO comment
                    const todo_start = col;
                    const comment_start = std.mem.lastIndexOfScalar(u8, line[0..col], '/') orelse col;

                    // Get the message (everything after the marker)
                    const after_marker = line[todo_start + marker.len ..];
                    const message = std.mem.trim(u8, after_marker, " :()");

                    // Extract assignee if present: TODO(@username)
                    var assignee: ?[]const u8 = null;
                    if (std.mem.indexOf(u8, message, "@")) |at_pos| {
                        const assignee_start = at_pos + 1;
                        const assignee_end = std.mem.indexOfAny(u8, message[assignee_start..], " ):,") orelse message.len - assignee_start;
                        assignee = try self.allocator.dupe(u8, message[assignee_start .. assignee_start + assignee_end]);
                    }

                    // Extract issue reference if present: TODO(#123)
                    var issue_ref: ?[]const u8 = null;
                    if (std.mem.indexOf(u8, message, "#")) |hash_pos| {
                        const ref_start = hash_pos + 1;
                        const ref_end = std.mem.indexOfAny(u8, message[ref_start..], " ):,") orelse message.len - ref_start;
                        issue_ref = try self.allocator.dupe(u8, message[ref_start .. ref_start + ref_end]);
                    }

                    // Get surrounding context (3 lines)
                    const context = try self.getContext(source, line_no, 3);

                    const priority = TodoPriority.fromMarker(marker);
                    const category = TodoCategory.fromMarker(marker);

                    const todo = TodoItem{
                        .file_path = try self.allocator.dupe(u8, file_path),
                        .line = line_no,
                        .column = comment_start,
                        .marker = try self.allocator.dupe(u8, marker),
                        .message = try self.allocator.dupe(u8, message),
                        .context = context,
                        .priority = priority,
                        .category = category,
                        .assignee = assignee,
                        .issue_ref = issue_ref,
                        .allocator = self.allocator,
                    };

                    try self.todos.append(self.allocator, todo);
                    break; // Only match first marker per line
                }
            }
        }
    }

    /// Get surrounding code context for a line
    fn getContext(
        self: *TodoTracker,
        source: []const u8,
        target_line: usize,
        context_lines: usize,
    ) ![]const u8 {
        var line_iter = std.mem.splitScalar(u8, source, '\n');
        var line_no: usize = 1;
        var context: std.ArrayList(u8) = .{};
        defer context.deinit(self.allocator);

        const start_line = if (target_line > context_lines) target_line - context_lines else 1;
        const end_line = target_line + context_lines;

        while (line_iter.next()) |line| : (line_no += 1) {
            if (line_no >= start_line and line_no <= end_line) {
                const marker = if (line_no == target_line) ">" else " ";
                const line_str = try std.fmt.allocPrint(self.allocator, "{s} {d}: {s}\n", .{ marker, line_no, line });
                defer self.allocator.free(line_str);
                try context.appendSlice(self.allocator, line_str);
            }
            if (line_no > end_line) break;
        }

        return try context.toOwnedSlice(self.allocator);
    }

    /// Get TODOs sorted by priority
    pub fn getByPriority(self: *TodoTracker) []TodoItem {
        // Sort by priority (critical -> high -> medium -> low -> normal)
        std.mem.sort(TodoItem, self.todos.items, {}, struct {
            fn lessThan(_: void, a: TodoItem, b: TodoItem) bool {
                return @intFromEnum(a.priority) < @intFromEnum(b.priority);
            }
        }.lessThan);

        return self.todos.items;
    }

    /// Get TODOs by category
    pub fn getByCategory(self: *TodoTracker, category: TodoCategory) ![]TodoItem {
        var filtered: std.ArrayList(TodoItem) = .{};
        defer filtered.deinit(self.allocator);

        for (self.todos.items) |todo| {
            if (todo.category == category) {
                try filtered.append(self.allocator, todo);
            }
        }

        return try filtered.toOwnedSlice(self.allocator);
    }

    /// Print summary statistics
    pub fn printSummary(self: *TodoTracker) void {
        std.log.info("\n📋 TODO Summary:", .{});
        std.log.info("  Total: {d}", .{self.todos.items.len});

        // Count by priority
        var critical: usize = 0;
        var high: usize = 0;
        var medium: usize = 0;
        var low: usize = 0;
        var normal: usize = 0;

        for (self.todos.items) |todo| {
            switch (todo.priority) {
                .critical => critical += 1,
                .high => high += 1,
                .medium => medium += 1,
                .low => low += 1,
                .normal => normal += 1,
            }
        }

        std.log.info("\n  By Priority:", .{});
        if (critical > 0) std.log.info("    🔴 Critical: {d}", .{critical});
        if (high > 0) std.log.info("    🟠 High: {d}", .{high});
        if (medium > 0) std.log.info("    🟡 Medium: {d}", .{medium});
        if (low > 0) std.log.info("    🔵 Low: {d}", .{low});
        if (normal > 0) std.log.info("    ⚪ Normal: {d}", .{normal});
    }
};

test "TodoPriority.fromMarker" {
    try std.testing.expectEqual(TodoPriority.critical, TodoPriority.fromMarker("FIXME: critical bug"));
    try std.testing.expectEqual(TodoPriority.high, TodoPriority.fromMarker("TODO!!! urgent"));
    try std.testing.expectEqual(TodoPriority.medium, TodoPriority.fromMarker("TODO!! important"));
    try std.testing.expectEqual(TodoPriority.low, TodoPriority.fromMarker("TODO! minor"));
    try std.testing.expectEqual(TodoPriority.normal, TodoPriority.fromMarker("TODO: regular"));
}

test "TodoCategory.fromMarker" {
    try std.testing.expectEqual(TodoCategory.bug_fix, TodoCategory.fromMarker("FIXME: bug"));
    try std.testing.expectEqual(TodoCategory.refactor, TodoCategory.fromMarker("REFACTOR: cleanup"));
    try std.testing.expectEqual(TodoCategory.optimization, TodoCategory.fromMarker("OPTIMIZE: perf"));
    try std.testing.expectEqual(TodoCategory.security, TodoCategory.fromMarker("XXX: security issue"));
    try std.testing.expectEqual(TodoCategory.feature, TodoCategory.fromMarker("TODO: new feature"));
}

test "TodoTracker.extractTodos" {
    const allocator = std.testing.allocator;
    var tracker = TodoTracker.init(allocator);
    defer tracker.deinit();

    const source =
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    // TODO: implement main function
        \\    // FIXME(@john): critical bug here
        \\    // TODO(#123): linked to issue
        \\    std.debug.print("Hello\n", .{});
        \\}
    ;

    try tracker.extractTodos("test.zig", source);
    try std.testing.expectEqual(@as(usize, 3), tracker.todos.items.len);

    const first = tracker.todos.items[0];
    try std.testing.expectEqualStrings("TODO", first.marker);
    try std.testing.expectEqual(@as(usize, 4), first.line);

    const second = tracker.todos.items[1];
    try std.testing.expectEqualStrings("FIXME", second.marker);
    try std.testing.expect(second.assignee != null);
    try std.testing.expectEqualStrings("john", second.assignee.?);

    const third = tracker.todos.items[2];
    try std.testing.expect(third.issue_ref != null);
    try std.testing.expectEqualStrings("123", third.issue_ref.?);
}
