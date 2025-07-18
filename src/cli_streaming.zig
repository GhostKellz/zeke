const std = @import("std");
const zeke = @import("zeke");
const streaming = zeke.streaming;
const formatting = @import("formatting.zig");

pub const CLIStreamHandler = struct {
    allocator: std.mem.Allocator,
    formatter: formatting.Formatter,
    buffer: std.ArrayList(u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .formatter = formatting.Formatter.init(allocator, .plain),
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
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
            try self.buffer.appendSlice(chunk.content);
            
            // Print the chunk immediately for real-time effect
            try self.printWithFlush(chunk.content);
        }
        
        if (chunk.is_final) {
            try self.finishStreaming();
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
    var stream_handler = CLIStreamHandler.init(allocator);
    defer stream_handler.deinit();
    
    try stream_handler.startStreaming("chat");
    
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
        
        try stream_handler.handleStreamError(error_msg);
        
        // Fallback to regular chat
        std.debug.print("\n🔄 Falling back to regular chat...\n\n", .{});
        
        const response = zeke_instance.chat(message) catch |chat_err| {
            const chat_error_msg = try std.fmt.allocPrint(allocator, "Chat also failed: {}", .{chat_err});
            defer allocator.free(chat_error_msg);
            
            try stream_handler.handleStreamError(chat_error_msg);
            return;
        };
        defer allocator.free(response);
        
        var formatter = formatting.Formatter.init(allocator, .plain);
        const formatted_response = try formatter.formatResponse(response);
        defer allocator.free(formatted_response);
        
        std.debug.print("{s}", .{formatted_response});
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
        std.time.sleep(50 * std.time.ns_per_ms);
        
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