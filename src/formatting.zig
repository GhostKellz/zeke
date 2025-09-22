const std = @import("std");

pub const OutputFormat = enum {
    plain,
    json,
    markdown,
};

pub const Formatter = struct {
    format: OutputFormat,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, format: OutputFormat) Formatter {
        return Formatter{
            .format = format,
            .allocator = allocator,
        };
    }
    
    pub fn formatResponse(self: *Formatter, response: []const u8) ![]const u8 {
        switch (self.format) {
            .plain => return self.formatPlain(response),
            .json => return self.formatJson(response),
            .markdown => return self.formatMarkdown(response),
        }
    }
    
    pub fn formatError(self: *Formatter, error_msg: []const u8) ![]const u8 {
        switch (self.format) {
            .plain => return self.formatPlainError(error_msg),
            .json => return self.formatJsonError(error_msg),
            .markdown => return self.formatMarkdownError(error_msg),
        }
    }
    
    fn formatPlain(self: *Formatter, response: []const u8) ![]const u8 {
        // Add nice formatting for plain text
        const formatted = try std.fmt.allocPrint(self.allocator,
            "┌─────────────────────────────────────────────────────────────────────────────────┐\n" ++
            "│ Zeke AI Response                                                                │\n" ++
            "├─────────────────────────────────────────────────────────────────────────────────┤\n" ++
            "{s}\n" ++
            "└─────────────────────────────────────────────────────────────────────────────────┘\n",
            .{response}
        );
        return formatted;
    }
    
    fn formatJson(self: *Formatter, response: []const u8) ![]const u8 {
        // Escape quotes in response for JSON
        const escaped = try self.escapeJsonString(response);
        defer self.allocator.free(escaped);
        
        const formatted = try std.fmt.allocPrint(self.allocator,
            "{{\"success\": true, \"result\": \"{s}\"}}\n",
            .{escaped}
        );
        return formatted;
    }
    
    fn formatMarkdown(self: *Formatter, response: []const u8) ![]const u8 {
        const formatted = try std.fmt.allocPrint(self.allocator,
            "# Zeke AI Response\n\n{s}\n\n",
            .{response}
        );
        return formatted;
    }
    
    fn formatPlainError(self: *Formatter, error_msg: []const u8) ![]const u8 {
        const formatted = try std.fmt.allocPrint(self.allocator,
            "┌─────────────────────────────────────────────────────────────────────────────────┐\n" ++
            "│ ❌ Error                                                                        │\n" ++
            "├─────────────────────────────────────────────────────────────────────────────────┤\n" ++
            "{s}\n" ++
            "└─────────────────────────────────────────────────────────────────────────────────┘\n",
            .{error_msg}
        );
        return formatted;
    }
    
    fn formatJsonError(self: *Formatter, error_msg: []const u8) ![]const u8 {
        const escaped = try self.escapeJsonString(error_msg);
        defer self.allocator.free(escaped);
        
        const formatted = try std.fmt.allocPrint(self.allocator,
            "{{\"success\": false, \"error\": \"{s}\"}}\n",
            .{escaped}
        );
        return formatted;
    }
    
    fn formatMarkdownError(self: *Formatter, error_msg: []const u8) ![]const u8 {
        const formatted = try std.fmt.allocPrint(self.allocator,
            "# ❌ Error\n\n{s}\n\n",
            .{error_msg}
        );
        return formatted;
    }
    
    fn escapeJsonString(self: *Formatter, input: []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        defer result.deinit(self.allocator);
        
        for (input) |char| {
            switch (char) {
                '"' => try result.appendSlice(self.allocator, "\\\""),
                '\\' => try result.appendSlice(self.allocator, "\\\\"),
                '\n' => try result.appendSlice(self.allocator, "\\n"),
                '\r' => try result.appendSlice(self.allocator, "\\r"),
                '\t' => try result.appendSlice(self.allocator, "\\t"),
                else => try result.append(self.allocator, char),
            }
        }
        
        return result.toOwnedSlice(self.allocator);
    }
    
    pub fn formatCodeBlock(self: *Formatter, code: []const u8, language: ?[]const u8) ![]const u8 {
        switch (self.format) {
            .plain => {
                const formatted = try std.fmt.allocPrint(self.allocator,
                    "┌─ Code {s} ─────────────────────────────────────────────────────────────────────┐\n" ++
                    "{s}\n" ++
                    "└─────────────────────────────────────────────────────────────────────────────────┘\n",
                    .{ language orelse "", code }
                );
                return formatted;
            },
            .json => {
                const escaped_code = try self.escapeJsonString(code);
                defer self.allocator.free(escaped_code);
                
                const formatted = try std.fmt.allocPrint(self.allocator,
                    "{{\"code\": \"{s}\", \"language\": \"{s}\"}}\n",
                    .{ escaped_code, language orelse "text" }
                );
                return formatted;
            },
            .markdown => {
                const formatted = try std.fmt.allocPrint(self.allocator,
                    "```{s}\n{s}\n```\n",
                    .{ language orelse "", code }
                );
                return formatted;
            },
        }
    }
};

pub fn detectFormat(args: [][]const u8) OutputFormat {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            return .json;
        } else if (std.mem.eql(u8, arg, "--markdown")) {
            return .markdown;
        }
    }
    return .plain;
}