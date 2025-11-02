const std = @import("std");
const tokyo = @import("tokyo_night.zig");

/// Diff viewer with syntax highlighting for terminal
pub const DiffViewer = struct {
    allocator: std.mem.Allocator,

    const colors = struct {
        const added = "\x1b[32m"; // Green
        const removed = "\x1b[31m"; // Red
        const context = "\x1b[90m"; // Gray
        const header = "\x1b[1;36m"; // Bold cyan
        const line_num = "\x1b[33m"; // Yellow
        const reset = "\x1b[0m";
    };

    pub fn init(allocator: std.mem.Allocator) DiffViewer {
        return .{ .allocator = allocator };
    }

    /// Render diff with colors
    pub fn render(self: *DiffViewer, diff: []const u8, width: usize) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        var lines = std.mem.splitScalar(u8, diff, '\n');

        while (lines.next()) |line| {
            if (line.len == 0) {
                try output.appendSlice("\r\n");
                continue;
            }

            // Colorize based on first character
            if (std.mem.startsWith(u8, line, "---") or std.mem.startsWith(u8, line, "+++")) {
                // File headers
                try output.appendSlice(colors.header);
                try output.appendSlice(line);
                try output.appendSlice(colors.reset);
            } else if (std.mem.startsWith(u8, line, "@@")) {
                // Hunk headers
                try output.appendSlice(colors.line_num);
                try output.appendSlice(line);
                try output.appendSlice(colors.reset);
            } else if (std.mem.startsWith(u8, line, "+")) {
                // Addition
                try output.appendSlice(colors.added);
                try output.appendSlice(line);
                try output.appendSlice(colors.reset);
            } else if (std.mem.startsWith(u8, line, "-")) {
                // Deletion
                try output.appendSlice(colors.removed);
                try output.appendSlice(line);
                try output.appendSlice(colors.reset);
            } else {
                // Context
                try output.appendSlice(colors.context);
                try output.appendSlice(line);
                try output.appendSlice(colors.reset);
            }

            try output.appendSlice("\r\n");
        }

        return try output.toOwnedSlice();
    }

    /// Render side-by-side diff
    pub fn renderSideBySide(self: *DiffViewer, diff: []const u8, width: usize) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        const half_width = width / 2 - 2;

        var lines = std.mem.splitScalar(u8, diff, '\n');

        try output.appendSlice("╭");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("┬");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("╮\r\n");

        try output.appendSlice("│ ");
        try output.appendSlice(colors.header);
        try output.appendSlice("OLD");
        try output.appendSlice(colors.reset);
        for (0..half_width - 4) |_| try output.appendSlice(" ");
        try output.appendSlice(" │ ");
        try output.appendSlice(colors.header);
        try output.appendSlice("NEW");
        try output.appendSlice(colors.reset);
        for (0..half_width - 4) |_| try output.appendSlice(" ");
        try output.appendSlice(" │\r\n");

        try output.appendSlice("├");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("┼");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("┤\r\n");

        var old_line: ?[]const u8 = null;
        var new_line: ?[]const u8 = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            if (std.mem.startsWith(u8, line, "-")) {
                old_line = line[1..];
            } else if (std.mem.startsWith(u8, line, "+")) {
                new_line = line[1..];

                // Render the pair
                if (old_line != null or new_line != null) {
                    try self.renderSideBySideLine(&output, old_line, new_line, half_width);
                    old_line = null;
                    new_line = null;
                }
            } else if (std.mem.startsWith(u8, line, " ")) {
                // Context line (same on both sides)
                try self.renderSideBySideLine(&output, line[1..], line[1..], half_width);
            }
        }

        // Handle remaining old line
        if (old_line) |old| {
            try self.renderSideBySideLine(&output, old, null, half_width);
        }

        try output.appendSlice("╰");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("┴");
        for (0..half_width) |_| try output.appendSlice("─");
        try output.appendSlice("╯\r\n");

        return try output.toOwnedSlice();
    }

    fn renderSideBySideLine(
        self: *DiffViewer,
        output: *std.ArrayList(u8),
        old: ?[]const u8,
        new: ?[]const u8,
        half_width: usize,
    ) !void {
        _ = self;

        // Left side (old)
        try output.appendSlice("│ ");
        if (old) |old_text| {
            try output.appendSlice(colors.removed);
            const truncated = if (old_text.len > half_width - 2) old_text[0..half_width - 2] else old_text;
            try output.appendSlice(truncated);
            try output.appendSlice(colors.reset);
            for (truncated.len..half_width - 2) |_| try output.appendSlice(" ");
        } else {
            for (0..half_width - 2) |_| try output.appendSlice(" ");
        }

        // Separator
        try output.appendSlice(" │ ");

        // Right side (new)
        if (new) |new_text| {
            try output.appendSlice(colors.added);
            const truncated = if (new_text.len > half_width - 2) new_text[0..half_width - 2] else new_text;
            try output.appendSlice(truncated);
            try output.appendSlice(colors.reset);
            for (truncated.len..half_width - 2) |_| try output.appendSlice(" ");
        } else {
            for (0..half_width - 2) |_| try output.appendSlice(" ");
        }

        try output.appendSlice(" │\r\n");
    }

    /// Create a compact diff summary
    pub fn summary(self: *DiffViewer, diff: []const u8) ![]const u8 {
        var additions: usize = 0;
        var deletions: usize = 0;
        var files: usize = 0;

        var lines = std.mem.splitScalar(u8, diff, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "+++")) {
                files += 1;
            } else if (std.mem.startsWith(u8, line, "+") and !std.mem.startsWith(u8, line, "+++")) {
                additions += 1;
            } else if (std.mem.startsWith(u8, line, "-") and !std.mem.startsWith(u8, line, "---")) {
                deletions += 1;
            }
        }

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}{d} file(s){s}, {s}+{d}{s}, {s}-{d}{s}",
            .{
                colors.header, files,      colors.reset,
                colors.added,  additions,  colors.reset,
                colors.removed, deletions, colors.reset,
            },
        );
    }
};

// Tests
test "diff viewer render" {
    const allocator = std.testing.allocator;

    var viewer = DiffViewer.init(allocator);

    const diff =
        \\--- test.txt
        \\+++ test.txt
        \\-old line
        \\+new line
    ;

    const rendered = try viewer.render(diff, 80);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "old line") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "new line") != null);
}

test "diff summary" {
    const allocator = std.testing.allocator;

    var viewer = DiffViewer.init(allocator);

    const diff =
        \\--- test.txt
        \\+++ test.txt
        \\-line1
        \\-line2
        \\+line3
        \\+line4
        \\+line5
    ;

    const summary_text = try viewer.summary(diff);
    defer allocator.free(summary_text);

    // Should show 1 file, +3, -2
    try std.testing.expect(std.mem.indexOf(u8, summary_text, "1 file") != null);
}
