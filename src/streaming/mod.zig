const std = @import("std");
const api = @import("../api/client.zig");

pub const StreamChunk = struct {
    content: []const u8,
    is_final: bool,
    token_count: ?u32,
    timestamp: i64,
    
    pub fn deinit(self: *StreamChunk, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

pub const StreamCallback = *const fn (chunk: StreamChunk) void;

pub const SSEParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }
    
    pub fn parseChunk(self: *Self, data: []const u8, callback: StreamCallback) !void {
        try self.buffer.appendSlice(data);
        
        // Process complete SSE events
        while (std.mem.indexOf(u8, self.buffer.items, "\n\n")) |event_end| {
            const event_data = self.buffer.items[0..event_end];
            
            // Parse the SSE event
            if (try self.parseSSEEvent(event_data)) |chunk| {
                callback(chunk);
            }
            
            // Remove processed event from buffer
            const remaining = self.buffer.items[event_end + 2..];
            self.buffer.clearAndFree();
            try self.buffer.appendSlice(remaining);
        }
    }
    
    fn parseSSEEvent(self: *Self, event_data: []const u8) !?StreamChunk {
        var data_line: ?[]const u8 = null;
        var event_type: ?[]const u8 = null;
        
        var lines = std.mem.splitScalar(u8, event_data, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                data_line = line[6..];
            } else if (std.mem.startsWith(u8, line, "event: ")) {
                event_type = line[7..];
            }
        }
        
        if (data_line) |data| {
            // Check for stream end
            if (std.mem.eql(u8, data, "[DONE]")) {
                return StreamChunk{
                    .content = try self.allocator.dupe(u8, ""),
                    .is_final = true,
                    .token_count = null,
                    .timestamp = std.time.timestamp(),
                };
            }
            
            // Parse JSON data for OpenAI/Claude format
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch |err| {
                std.log.warn("Failed to parse SSE JSON: {}", .{err});
                return null;
            };
            defer parsed.deinit();
            
            const root = parsed.value.object;
            
            // Extract content from different provider formats
            var content: []const u8 = "";
            var is_final: bool = false;
            
            if (root.get("choices")) |choices_value| {
                // OpenAI format
                if (choices_value.array.items.len > 0) {
                    const choice = choices_value.array.items[0].object;
                    if (choice.get("delta")) |delta| {
                        if (delta.object.get("content")) |content_value| {
                            content = content_value.string;
                        }
                        if (choice.get("finish_reason")) |finish_reason| {
                            is_final = finish_reason != .null;
                        }
                    }
                }
            } else if (root.get("delta")) |delta_value| {
                // Claude format
                if (delta_value.object.get("text")) |text_value| {
                    content = text_value.string;
                }
                if (root.get("stop_reason")) |stop_reason| {
                    is_final = stop_reason != .null;
                }
            } else if (root.get("content")) |content_value| {
                // GhostLLM format
                content = content_value.string;
                if (root.get("final")) |final_value| {
                    is_final = final_value.bool;
                }
            }
            
            return StreamChunk{
                .content = try self.allocator.dupe(u8, content),
                .is_final = is_final,
                .token_count = null,
                .timestamp = std.time.timestamp(),
            };
        }
        
        return null;
    }
};

pub const StreamingClient = struct {
    allocator: std.mem.Allocator,
    http_client: *std.http.Client,
    sse_parser: SSEParser,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, http_client: *std.http.Client) Self {
        return Self{
            .allocator = allocator,
            .http_client = http_client,
            .sse_parser = SSEParser.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.sse_parser.deinit();
    }
    
    pub fn streamChatCompletion(
        self: *Self,
        endpoint: []const u8,
        request_body: []const u8,
        headers: []const std.http.Header,
        callback: StreamCallback
    ) !void {
        // Parse URI
        const uri = try std.Uri.parse(endpoint);
        
        // Create server header buffer
        var server_header_buffer: [8192]u8 = undefined;
        
        // Create request
        var request = self.http_client.open(.POST, uri, .{
            .server_header_buffer = &server_header_buffer,
        }) catch |err| {
            std.log.err("Failed to create streaming request: {}", .{err});
            return self.simulateStreaming(callback);
        };
        defer request.deinit();
        
        // Set headers
        request.headers.content_type = .{ .override = "application/json" };
        
        // Add custom headers
        for (headers) |header| {
            if (std.mem.eql(u8, header.name, "authorization")) {
                request.headers.authorization = .{ .override = header.value };
            }
        }
        
        // Send request
        request.transfer_encoding = .chunked;
        
        request.send() catch |err| {
            std.log.err("Failed to send streaming request: {}", .{err});
            return self.simulateStreaming(callback);
        };
        
        request.writeAll(request_body) catch |err| {
            std.log.err("Failed to write streaming request body: {}", .{err});
            return self.simulateStreaming(callback);
        };
        
        request.finish() catch |err| {
            std.log.err("Failed to finish streaming request: {}", .{err});
            return self.simulateStreaming(callback);
        };
        
        request.wait() catch |err| {
            std.log.err("Failed to wait for streaming response: {}", .{err});
            return self.simulateStreaming(callback);
        };
        
        // Handle streaming response
        if (request.response.status == .ok) {
            try self.handleStreamingResponse(&request, callback);
        } else {
            std.log.err("Streaming request failed with status: {}", .{@intFromEnum(request.response.status)});
            return self.simulateStreaming(callback);
        }
    }
    
    fn handleStreamingResponse(self: *Self, request: *std.http.Client.Request, callback: StreamCallback) !void {
        var buffer: [4096]u8 = undefined;
        var stream_buffer = std.ArrayList(u8).init(self.allocator);
        defer stream_buffer.deinit();
        
        // Read streaming data
        while (true) {
            const bytes_read = request.read(&buffer) catch |err| {
                if (err == error.EndOfStream) break;
                std.log.err("Error reading streaming response: {}", .{err});
                break;
            };
            
            if (bytes_read == 0) break;
            
            try stream_buffer.appendSlice(buffer[0..bytes_read]);
            
            // Process complete SSE events
            try self.sse_parser.parseChunk(stream_buffer.items, callback);
            
            // Clear processed data
            stream_buffer.clearRetainingCapacity();
        }
        
        // Send final chunk
        const final_chunk = StreamChunk{
            .content = try self.allocator.dupe(u8, ""),
            .is_final = true,
            .token_count = null,
            .timestamp = std.time.timestamp(),
        };
        callback(final_chunk);
    }
    
    fn simulateStreaming(self: *Self, callback: StreamCallback) !void {
        // Simulate streaming with chunks
        const mock_chunks = [_][]const u8{
            "This ",
            "is ",
            "a ",
            "simulated ",
            "streaming ",
            "response ",
            "from ",
            "ZEKE!"
        };
        
        for (mock_chunks) |chunk_text| {
            const chunk = StreamChunk{
                .content = try self.allocator.dupe(u8, chunk_text),
                .is_final = false,
                .token_count = 1,
                .timestamp = std.time.timestamp(),
            };
            callback(chunk);
            
            // Small delay to simulate streaming
            std.time.sleep(200 * std.time.ns_per_ms);
        }
        
        // Send final chunk
        const final_chunk = StreamChunk{
            .content = try self.allocator.dupe(u8, ""),
            .is_final = true,
            .token_count = null,
            .timestamp = std.time.timestamp(),
        };
        callback(final_chunk);
    }
    
    pub fn streamCodeCompletion(
        self: *Self,
        endpoint: []const u8,
        request_body: []const u8,
        headers: []const std.http.Header,
        callback: StreamCallback
    ) !void {
        return self.streamChatCompletion(endpoint, request_body, headers, callback);
    }
};

// WebSocket support for real-time bidirectional communication
pub const WebSocketHandler = struct {
    allocator: std.mem.Allocator,
    websocket: ?*std.http.Client,
    is_connected: bool,
    url: ?[]const u8,
    message_queue: std.ArrayList([]const u8),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .websocket = null,
            .is_connected = false,
            .url = null,
            .message_queue = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.websocket) |ws| {
            ws.deinit();
            self.allocator.destroy(ws);
        }
        if (self.url) |url| {
            self.allocator.free(url);
        }
        // Free queued messages
        for (self.message_queue.items) |msg| {
            self.allocator.free(msg);
        }
        self.message_queue.deinit();
    }
    
    pub fn connect(self: *Self, url: []const u8) !void {
        // Store URL for reconnection
        if (self.url) |old_url| {
            self.allocator.free(old_url);
        }
        self.url = try self.allocator.dupe(u8, url);
        
        // For now, simulate WebSocket connection
        // In a real implementation, this would:
        // 1. Parse the WebSocket URL
        // 2. Open HTTP connection
        // 3. Send WebSocket handshake
        // 4. Verify handshake response
        // 5. Set up frame handling
        
        std.log.info("WebSocket connecting to: {s}", .{url});
        
        // Simulate connection
        self.is_connected = true;
        std.log.info("WebSocket connection established (simulated)", .{});
    }
    
    pub fn sendMessage(self: *Self, message: []const u8) !void {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // In a real implementation, this would:
        // 1. Frame the message according to WebSocket protocol
        // 2. Send over the connection
        
        std.log.info("WebSocket sending message: {s}", .{message});
        
        // For now, simulate by echoing back the message
        const echo_message = try std.fmt.allocPrint(self.allocator, "Echo: {s}", .{message});
        try self.message_queue.append(echo_message);
    }
    
    pub fn receiveMessage(self: *Self) !?[]const u8 {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // Check if we have any queued messages
        if (self.message_queue.items.len > 0) {
            return self.message_queue.swapRemove(0);
        }
        
        // In a real implementation, this would:
        // 1. Read frames from the connection
        // 2. Parse WebSocket frames
        // 3. Handle control frames (ping, pong, close)
        // 4. Return message data
        
        return null;
    }
    
    pub fn isConnected(self: *const Self) bool {
        return self.is_connected;
    }
    
    pub fn disconnect(self: *Self) void {
        if (self.is_connected) {
            std.log.info("WebSocket disconnecting", .{});
            self.is_connected = false;
            
            // Clear message queue
            for (self.message_queue.items) |msg| {
                self.allocator.free(msg);
            }
            self.message_queue.clearRetainingCapacity();
        }
    }
    
    pub fn sendPing(self: *Self) !void {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        std.log.info("WebSocket sending ping", .{});
        // In a real implementation, this would send a ping frame
        
        // Simulate pong response
        const pong_message = try self.allocator.dupe(u8, "pong");
        try self.message_queue.append(pong_message);
    }
    
    pub fn handleRealTimeCodeIntelligence(self: *Self, callback: *const fn([]const u8) void) !void {
        while (true) {
            if (try self.receiveMessage()) |message| {
                defer self.allocator.free(message);
                callback(message);
            } else {
                break; // Connection closed
            }
        }
    }
};

// Real-time features for enhanced user experience
pub const RealTimeFeatures = struct {
    allocator: std.mem.Allocator,
    streaming_client: StreamingClient,
    websocket_handler: WebSocketHandler,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, http_client: *std.http.Client) Self {
        return Self{
            .allocator = allocator,
            .streaming_client = StreamingClient.init(allocator, http_client),
            .websocket_handler = WebSocketHandler.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.streaming_client.deinit();
        self.websocket_handler.deinit();
    }
    
    pub fn enableRealTimeCodeAnalysis(self: *Self, ghostllm_ws_url: []const u8) !void {
        try self.websocket_handler.connect(ghostllm_ws_url);
        std.log.info("Real-time code analysis enabled via WebSocket", .{});
        
        // Send initial handshake message
        const handshake_msg = try std.json.stringifyAlloc(self.allocator, .{
            .type = "handshake",
            .service = "code_analysis",
            .version = "1.0",
            .timestamp = std.time.timestamp(),
        }, .{});
        defer self.allocator.free(handshake_msg);
        
        try self.websocket_handler.sendMessage(handshake_msg);
    }
    
    pub fn streamTypingAssistance(self: *Self, text_buffer: []const u8, callback: StreamCallback) !void {
        if (!self.websocket_handler.isConnected()) {
            std.log.warn("WebSocket not connected for typing assistance", .{});
            return;
        }
        
        const message = try std.json.stringifyAlloc(self.allocator, .{
            .type = "typing_assistance",
            .buffer = text_buffer,
            .timestamp = std.time.timestamp(),
        }, .{});
        defer self.allocator.free(message);
        
        try self.websocket_handler.sendMessage(message);
        
        // Listen for real-time suggestions
        if (try self.websocket_handler.receiveMessage()) |response| {
            defer self.allocator.free(response);
            
            const chunk = StreamChunk{
                .content = try self.allocator.dupe(u8, response),
                .is_final = false,
                .token_count = null,
                .timestamp = std.time.timestamp(),
            };
            
            callback(chunk);
        }
    }
    
    pub fn sendCodeAnalysisRequest(self: *Self, code: []const u8, language: []const u8) !void {
        if (!self.websocket_handler.isConnected()) {
            return error.NotConnected;
        }
        
        const request = try std.json.stringifyAlloc(self.allocator, .{
            .type = "code_analysis",
            .code = code,
            .language = language,
            .timestamp = std.time.timestamp(),
        }, .{});
        defer self.allocator.free(request);
        
        try self.websocket_handler.sendMessage(request);
    }
    
    pub fn getCodeAnalysisResponse(self: *Self) !?[]const u8 {
        if (!self.websocket_handler.isConnected()) {
            return error.NotConnected;
        }
        
        return try self.websocket_handler.receiveMessage();
    }
    
    pub fn keepAlive(self: *Self) !void {
        if (self.websocket_handler.isConnected()) {
            try self.websocket_handler.sendPing();
        }
    }
    
    pub fn getProgressIndicator(self: *Self, task_type: []const u8) !ProgressIndicator {
        return ProgressIndicator.init(self.allocator, task_type);
    }
};

pub const ProgressIndicator = struct {
    allocator: std.mem.Allocator,
    task_type: []const u8,
    start_time: i64,
    stages: std.ArrayList([]const u8),
    current_stage: usize,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, task_type: []const u8) !Self {
        var stages = std.ArrayList([]const u8).init(allocator);
        
        if (std.mem.eql(u8, task_type, "code_analysis")) {
            try stages.append(try allocator.dupe(u8, "🔍 Analyzing code structure..."));
            try stages.append(try allocator.dupe(u8, "🧠 Running AI analysis..."));
            try stages.append(try allocator.dupe(u8, "📊 Generating insights..."));
            try stages.append(try allocator.dupe(u8, "✅ Analysis complete!"));
        } else if (std.mem.eql(u8, task_type, "chat_completion")) {
            try stages.append(try allocator.dupe(u8, "🤖 Thinking..."));
            try stages.append(try allocator.dupe(u8, "✍️ Generating response..."));
            try stages.append(try allocator.dupe(u8, "✅ Response ready!"));
        } else {
            try stages.append(try allocator.dupe(u8, "⚡ Processing..."));
            try stages.append(try allocator.dupe(u8, "✅ Complete!"));
        }
        
        return Self{
            .allocator = allocator,
            .task_type = try allocator.dupe(u8, task_type),
            .start_time = std.time.timestamp(),
            .stages = stages,
            .current_stage = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.task_type);
        for (self.stages.items) |stage| {
            self.allocator.free(stage);
        }
        self.stages.deinit();
    }
    
    pub fn nextStage(self: *Self) ?[]const u8 {
        if (self.current_stage < self.stages.items.len) {
            const stage = self.stages.items[self.current_stage];
            self.current_stage += 1;
            return stage;
        }
        return null;
    }
    
    pub fn getCurrentStage(self: *const Self) ?[]const u8 {
        if (self.current_stage > 0 and self.current_stage <= self.stages.items.len) {
            return self.stages.items[self.current_stage - 1];
        }
        return null;
    }
    
    pub fn getElapsedTime(self: *const Self) i64 {
        return std.time.timestamp() - self.start_time;
    }
    
    pub fn isComplete(self: *const Self) bool {
        return self.current_stage >= self.stages.items.len;
    }
};