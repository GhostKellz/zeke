const std = @import("std");

/// Simple markdown renderer for terminal output
pub const MarkdownRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MarkdownRenderer {
        return MarkdownRenderer{ .allocator = allocator };
    }

    /// Render markdown to ANSI-colored terminal output
    pub fn render(self: *MarkdownRenderer, markdown: []const u8) ![]const u8 {
        var buf = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer buf.deinit();

        var lines = std.mem.splitScalar(u8, markdown, '\n');
        var in_code_block = false;

        while (lines.next()) |line| {
            // Code blocks
            if (std.mem.startsWith(u8, line, "```")) {
                in_code_block = !in_code_block;
                if (in_code_block) {
                    try buf.appendSlice("\x1b[90m"); // Dim gray
                } else {
                    try buf.appendSlice("\x1b[0m"); // Reset
                }
                try buf.appendSlice("\r\n");
                continue;
            }

            if (in_code_block) {
                try buf.appendSlice("  ");
                try buf.appendSlice(line);
                try buf.appendSlice("\r\n");
                continue;
            }

            // Headers
            if (std.mem.startsWith(u8, line, "# ")) {
                try buf.appendSlice("\x1b[1;34m"); // Bold blue
                try buf.appendSlice(line[2..]);
                try buf.appendSlice("\x1b[0m\r\n");
                continue;
            }

            if (std.mem.startsWith(u8, line, "## ")) {
                try buf.appendSlice("\x1b[1;36m"); // Bold cyan
                try buf.appendSlice(line[3..]);
                try buf.appendSlice("\x1b[0m\r\n");
                continue;
            }

            // Bold **text**
            const bold_rendered = try self.renderBold(line);
            defer self.allocator.free(bold_rendered);

            // Italic *text*
            const italic_rendered = try self.renderItalic(bold_rendered);
            defer self.allocator.free(italic_rendered);

            // Inline code `code`
            const code_rendered = try self.renderInlineCode(italic_rendered);
            defer self.allocator.free(code_rendered);

            try buf.appendSlice(code_rendered);
            try buf.appendSlice("\r\n");
        }

        return try buf.toOwnedSlice();
    }

    fn renderBold(self: *MarkdownRenderer, text: []const u8) ![]const u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
                // Find closing **
                var j = i + 2;
                while (j + 1 < text.len) : (j += 1) {
                    if (text[j] == '*' and text[j + 1] == '*') {
                        try result.appendSlice("\x1b[1m"); // Bold
                        try result.appendSlice(text[i + 2 .. j]);
                        try result.appendSlice("\x1b[0m"); // Reset
                        i = j + 2;
                        break;
                    }
                } else {
                    try result.append(text[i]);
                    i += 1;
                }
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice();
    }

    fn renderItalic(self: *MarkdownRenderer, text: []const u8) ![]const u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '*' and (i == 0 or text[i - 1] != '*')) {
                // Find closing *
                var j = i + 1;
                while (j < text.len) : (j += 1) {
                    if (text[j] == '*' and (j + 1 >= text.len or text[j + 1] != '*')) {
                        try result.appendSlice("\x1b[3m"); // Italic
                        try result.appendSlice(text[i + 1 .. j]);
                        try result.appendSlice("\x1b[0m"); // Reset
                        i = j + 1;
                        break;
                    }
                } else {
                    try result.append(text[i]);
                    i += 1;
                }
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice();
    }

    fn renderInlineCode(self: *MarkdownRenderer, text: []const u8) ![]const u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '`') {
                // Find closing `
                var j = i + 1;
                while (j < text.len) : (j += 1) {
                    if (text[j] == '`') {
                        try result.appendSlice("\x1b[90m"); // Gray
                        try result.appendSlice(text[i + 1 .. j]);
                        try result.appendSlice("\x1b[0m"); // Reset
                        i = j + 1;
                        break;
                    }
                } else {
                    try result.append(text[i]);
                    i += 1;
                }
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice();
    }
};

// Tests
test "markdown headers" {
    const allocator = std.testing.allocator;

    var renderer = MarkdownRenderer.init(allocator);
    const markdown = "# Header 1\n## Header 2\nRegular text";

    const result = try renderer.render(markdown);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "Header 1") != null);
}

test "markdown code blocks" {
    const allocator = std.testing.allocator;

    var renderer = MarkdownRenderer.init(allocator);
    const markdown = "```\ncode here\n```";

    const result = try renderer.render(markdown);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "markdown bold" {
    const allocator = std.testing.allocator;

    var renderer = MarkdownRenderer.init(allocator);
    const result = try renderer.renderBold("This is **bold** text");
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "bold") != null);
}

test "markdown inline code" {
    const allocator = std.testing.allocator;

    var renderer = MarkdownRenderer.init(allocator);
    const result = try renderer.renderInlineCode("This is `code` text");
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "code") != null);
}
