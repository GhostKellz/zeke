const std = @import("std");
const zeke = @import("zeke");
const streaming = zeke.streaming;
const formatting = @import("formatting.zig");

pub const CLIStreamHandler = struct {
    allocator: std.mem.Allocator,
    formatter: formatting.Formatter,
    buffer: std.ArrayList(u8),
    json_mode: bool = false, // Enable JSON output for nvim integration
    start_time: i64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .formatter = formatting.Formatter.init(allocator, .plain),
            .buffer = std.ArrayList(u8){},
            .json_mode = false,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn initWithJsonMode(allocator: std.mem.Allocator, json_mode: bool) Self {
        return Self{
            .allocator = allocator,
            .formatter = formatting.Formatter.init(allocator, .plain),
            .buffer = std.ArrayList(u8){},
            .json_mode = json_mode,
            .start_time = std.time.timestamp(),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }
    
    pub fn startStreaming(self: *Self, task_type: []const u8) !void {
        // Clear any previous content
        self.buffer.clearRetainingCapacity();
        
        // Print streaming header
        const header = try std.fmt.allocPrint(self.allocator,
            "┌─────────────────────────────────────────────────────────────────────────────────┐\n" ++
            "│ 🚀 Zeke AI Streaming Response ({s})                                    │\n" ++
            "├─────────────────────────────────────────────────────────────────────────────────┤\n",
            .{task_type}
        );
        defer self.allocator.free(header);
        
        try self.printWithFlush(header);
        
        // Show progress indicator
        var progress = try streaming.ProgressIndicator.init(self.allocator, task_type);
        defer progress.deinit();
        
        if (progress.nextStage()) |stage| {
            try self.printWithFlush(stage);
            try self.printWithFlush(" ");
        }
    }
    
    pub fn handleStreamChunk(self: *Self, chunk: streaming.StreamChunk) !void {
        if (chunk.content.len > 0) {
            // Add chunk to buffer
            try self.buffer.appendSlice(self.allocator, chunk.content);

            if (self.json_mode) {
                // Output JSON format for nvim
                const json_chunk = try std.fmt.allocPrint(self.allocator,
                    "{{\"type\":\"chunk\",\"content\":{s},\"is_final\":{}}}\n",
                    .{ try escapeJson(self.allocator, chunk.content), chunk.is_final }
                );
                defer self.allocator.free(json_chunk);
                try self.printWithFlush(json_chunk);
            } else {
                // Print the chunk immediately for real-time effect
                try self.printWithFlush(chunk.content);
            }
        }

        if (chunk.is_final and !self.json_mode) {
            try self.finishStreaming();
        }
    }

    /// Output final metadata chunk (only in JSON mode)
    pub fn outputMetadata(self: *Self, provider: []const u8, model: []const u8, usage: ?zeke.api.Usage) !void {
        if (!self.json_mode) return;

        const elapsed_ms = (std.time.timestamp() - self.start_time) * 1000;

        if (usage) |u| {
            const meta = try std.fmt.allocPrint(self.allocator,
                "{{\"type\":\"metadata\",\"provider\":\"{s}\",\"model\":\"{s}\",\"tokens\":{{\"prompt\":{d},\"completion\":{d},\"total\":{d}}},\"response_time_ms\":{d}}}\n",
                .{ provider, model, u.prompt_tokens, u.completion_tokens, u.total_tokens, elapsed_ms }
            );
            defer self.allocator.free(meta);
            try self.printWithFlush(meta);
        } else {
            const meta = try std.fmt.allocPrint(self.allocator,
                "{{\"type\":\"metadata\",\"provider\":\"{s}\",\"model\":\"{s}\",\"response_time_ms\":{d}}}\n",
                .{ provider, model, elapsed_ms }
            );
            defer self.allocator.free(meta);
            try self.printWithFlush(meta);
        }
    }
    
    pub fn finishStreaming(self: *Self) !void {
        // Print footer
        const footer = 
            "\n└─────────────────────────────────────────────────────────────────────────────────┘\n";
        
        try self.printWithFlush(footer);
        
        // Print final stats if available
        const stats = try std.fmt.allocPrint(self.allocator,
            "📊 Response complete • {} characters • {} ms\n",
            .{ self.buffer.items.len, std.time.timestamp() }
        );
        defer self.allocator.free(stats);
        
        try self.printWithFlush(stats);
    }
    
    pub fn handleStreamError(self: *Self, error_msg: []const u8) !void {
        const formatted_error = try self.formatter.formatError(error_msg);
        defer self.allocator.free(formatted_error);
        
        try self.printWithFlush(formatted_error);
    }
    
    fn printWithFlush(self: *Self, content: []const u8) !void {
        _ = self;
        std.debug.print("{s}", .{content});
    }
    
    pub fn getFullResponse(self: *const Self) []const u8 {
        return self.buffer.items;
    }
};

pub fn handleStreamingChat(
    zeke_instance: anytype,
    allocator: std.mem.Allocator,
    message: []const u8
) !void {
    try handleStreamingChatWithMode(zeke_instance, allocator, message, false);
}

pub fn handleStreamingChatJson(
    zeke_instance: anytype,
    allocator: std.mem.Allocator,
    message: []const u8
) !void {
    try handleStreamingChatWithMode(zeke_instance, allocator, message, true);
}

fn handleStreamingChatWithMode(
    zeke_instance: anytype,
    allocator: std.mem.Allocator,
    message: []const u8,
    json_mode: bool
) !void {
    var stream_handler = CLIStreamHandler.initWithJsonMode(allocator, json_mode);
    defer stream_handler.deinit();

    if (!json_mode) {
        try stream_handler.startStreaming("chat");
    }

    // Define streaming callback
    const StreamHandler = struct {
        fn callback(chunk: streaming.StreamChunk) void {
            // Since we can't capture the handler in the callback, we'll use a global or static approach
            // For now, just print directly to simulate streaming
            std.debug.print("{s}", .{chunk.content});
            if (chunk.is_final) {
                std.debug.print("\n✅ Stream complete!\n", .{});
            }
        }
    };

    // Try to start streaming
    zeke_instance.streamChat(message, StreamHandler.callback) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Streaming failed: {}", .{err});
        defer allocator.free(error_msg);

        if (json_mode) {
            const error_json = try std.fmt.allocPrint(allocator,
                "{{\"type\":\"error\",\"message\":\"{s}\"}}\n",
                .{error_msg}
            );
            defer allocator.free(error_json);
            std.debug.print("{s}", .{error_json});
            return;
        }

        try stream_handler.handleStreamError(error_msg);

        // Fallback to regular chat
        std.debug.print("\n🔄 Falling back to regular chat...\n\n", .{});

        const response = zeke_instance.chatWithUsage(message) catch |chat_err| {
            const chat_error_msg = try std.fmt.allocPrint(allocator, "Chat also failed: {}", .{chat_err});
            defer allocator.free(chat_error_msg);

            try stream_handler.handleStreamError(chat_error_msg);
            return;
        };
        defer allocator.free(response.content);
        defer allocator.free(response.model);

        var formatter = formatting.Formatter.init(allocator, .plain);
        const formatted_response = try formatter.formatResponse(response.content);
        defer allocator.free(formatted_response);

        std.debug.print("{s}", .{formatted_response});

        // Output metadata for fallback response
        if (response.usage) |usage| {
            const provider_name = @tagName(zeke_instance.current_provider);
            try stream_handler.outputMetadata(provider_name, response.model, usage);
        }
    };
}

pub fn simulateStreamingResponse(allocator: std.mem.Allocator, response: []const u8) !void {
    var stream_handler = CLIStreamHandler.init(allocator);
    defer stream_handler.deinit();
    
    try stream_handler.startStreaming("chat");
    
    // Split response into chunks and stream them
    const chunk_size = 3; // Small chunks for typing effect
    var i: usize = 0;
    
    while (i < response.len) {
        const end = @min(i + chunk_size, response.len);
        const chunk_content = response[i..end];
        
        const chunk = streaming.StreamChunk{
            .content = chunk_content,
            .is_final = (end == response.len),
            .token_count = null,
            .timestamp = std.time.timestamp(),
        };
        
        try stream_handler.handleStreamChunk(chunk);
        
        // Add small delay for typing effect
        std.Thread.sleep(50 * std.time.ns_per_ms);
        
        i = end;
    }
}

pub fn createStreamingProgress(allocator: std.mem.Allocator, task_type: []const u8) !void {
    var progress = try streaming.ProgressIndicator.init(allocator, task_type);
    defer progress.deinit();

    while (progress.nextStage()) |stage| {
        std.debug.print("\r{s}", .{stage});
        try std.io.getStdOut().flush();

        // Simulate processing time
        std.time.sleep(800 * std.time.ns_per_ms);
    }

    std.debug.print("\n");
}

/// Escape string for JSON output
fn escapeJson(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.append(allocator, '"');

    for (str) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => {
                if (c < 32) {
                    // Control characters
                    const escaped = try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{c});
                    defer allocator.free(escaped);
                    try result.appendSlice(allocator, escaped);
                } else {
                    try result.append(allocator, c);
                }
            },
        }
    }

    try result.append(allocator, '"');
    return try result.toOwnedSlice(allocator);
}