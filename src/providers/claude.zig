const std = @import("std");
const HttpClient = @import("../api/http_client.zig").HttpClient;
const HttpResponse = @import("../api/http_client.zig").HttpResponse;

pub const ClaudeProvider = struct {
    http_client: HttpClient,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) ClaudeProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .api_key = api_key,
            .base_url = "https://api.anthropic.com/v1",
            .model = "claude-3-5-sonnet-20241022",
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ClaudeProvider) void {
        self.http_client.deinit();
    }
    
    pub fn chatCompletion(self: *ClaudeProvider, messages: []const ChatMessage, conversation_id: []const u8) !ChatCompletionResponse {
        _ = conversation_id;
        
        // Convert messages to Claude format (system message separate)
        var system_message: ?[]const u8 = null;
        var user_messages = std.ArrayList(ClaudeMessage).init(self.allocator);
        defer user_messages.deinit();
        
        for (messages) |message| {
            if (std.mem.eql(u8, message.role, "system")) {
                system_message = message.content;
            } else {
                try user_messages.append(.{
                    .role = message.role,
                    .content = message.content,
                });
            }
        }
        
        // Create request payload
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();
        
        const writer = payload.writer();
        try writer.print("{{\"model\":\"{s}\",\"max_tokens\":4000,\"messages\":[", .{self.model});
        
        for (user_messages.items, 0..) |message, i| {
            if (i > 0) try writer.print(",");
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.print("}}");
        }
        
        try writer.print("]");
        
        if (system_message) |sys_msg| {
            try writer.print(",\"system\":");
            try std.json.stringify(sys_msg, .{}, writer);
        }
        
        try writer.print("}}");
        
        // Create headers
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("x-api-key", self.api_key);
        try headers.put("Content-Type", "application/json");
        try headers.put("anthropic-version", "2023-06-01");
        
        // Make HTTP request
        const url = try std.fmt.allocPrint(self.allocator, "{s}/messages", .{self.base_url});
        defer self.allocator.free(url);
        
        var response = self.http_client.post(url, payload.items, headers) catch |err| {
            std.log.err("Claude HTTP request failed: {}", .{err});
            return ChatCompletionError.NetworkError;
        };
        defer response.deinit();
        
        if (!response.isSuccess()) {
            std.log.err("Claude API error: status {}, body: {s}", .{ response.status, response.body });
            return switch (response.status) {
                401 => ChatCompletionError.AuthenticationFailed,
                429 => ChatCompletionError.RateLimited,
                400...499 => ChatCompletionError.BadRequest,
                500...599 => ChatCompletionError.ServerError,
                else => ChatCompletionError.NetworkError,
            };
        }
        
        // Parse response
        const parsed = std.json.parseFromSlice(ClaudeResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse Claude response: {}, body: {s}", .{ err, response.body });
            return ChatCompletionError.InvalidResponse;
        };
        defer parsed.deinit();
        
        if (parsed.value.content.len == 0) {
            return ChatCompletionError.InvalidResponse;
        }
        
        // Find text content
        var text_content: ?[]const u8 = null;
        for (parsed.value.content) |content| {
            if (std.mem.eql(u8, content.type, "text")) {
                text_content = content.text;
                break;
            }
        }
        
        if (text_content == null) {
            return ChatCompletionError.InvalidResponse;
        }
        
        const content = try self.allocator.dupe(u8, text_content.?);
        
        return ChatCompletionResponse{
            .content = content,
            .model = try self.allocator.dupe(u8, parsed.value.model),
            .usage = Usage{
                .prompt_tokens = parsed.value.usage.input_tokens,
                .completion_tokens = parsed.value.usage.output_tokens,
                .total_tokens = parsed.value.usage.input_tokens + parsed.value.usage.output_tokens,
            },
        };
    }
    
    pub fn codeCompletion(self: *ClaudeProvider, prompt: []const u8, language: ?[]const u8, context: ?[]const u8) !CodeCompletionResponse {
        var messages = std.ArrayList(ChatMessage).init(self.allocator);
        defer messages.deinit();
        
        // System message for code completion
        const system_prompt = if (language) |lang|
            try std.fmt.allocPrint(self.allocator, 
                "You are an expert {s} programmer. Complete the following code. Return only the completion without explanation or markdown formatting.", 
                .{lang})
        else
            "You are an expert programmer. Complete the following code. Return only the completion without explanation or markdown formatting.";
        defer if (language != null) self.allocator.free(system_prompt);
        
        try messages.append(.{ .role = "system", .content = system_prompt });
        
        // Add context if provided
        if (context) |ctx| {
            const context_msg = try std.fmt.allocPrint(self.allocator, "Context:\n{s}\n\nComplete this code:", .{ctx});
            defer self.allocator.free(context_msg);
            try messages.append(.{ .role = "user", .content = context_msg });
        }
        
        try messages.append(.{ .role = "user", .content = prompt });
        
        const chat_response = try self.chatCompletion(messages.items, "code-completion");
        
        return CodeCompletionResponse{
            .completion = chat_response.content,
            .language = if (language) |lang| try self.allocator.dupe(u8, lang) else null,
            .confidence = 0.9, // Claude typically has very high confidence
        };
    }
    
    pub fn streamChatCompletion(self: *ClaudeProvider, messages: []const ChatMessage, callback: StreamCallback) !void {
        // For now, simulate streaming by calling the regular completion and invoking callback
        const response = try self.chatCompletion(messages, "stream");
        defer self.allocator.free(response.content);
        defer self.allocator.free(response.model);
        
        // Split content into chunks and stream
        const chunk_size = 15; // Slightly larger chunks for Claude
        var pos: usize = 0;
        
        while (pos < response.content.len) {
            const end = @min(pos + chunk_size, response.content.len);
            const chunk = response.content[pos..end];
            
            const stream_chunk = StreamChunk{
                .content = chunk,
                .done = end >= response.content.len,
                .model = response.model,
            };
            
            callback(stream_chunk);
            pos = end;
            
            // Small delay to simulate streaming
            std.time.sleep(30 * std.time.ns_per_ms);
        }
    }
};

pub const ChatMessage = struct {
    role: []const u8, // "system", "user", "assistant"
    content: []const u8,
};

pub const ChatCompletionResponse = struct {
    content: []const u8,
    model: []const u8,
    usage: Usage,
};

pub const CodeCompletionResponse = struct {
    completion: []const u8,
    language: ?[]const u8,
    confidence: f32,
};

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

pub const StreamChunk = struct {
    content: []const u8,
    done: bool,
    model: []const u8,
};

pub const StreamCallback = *const fn (chunk: StreamChunk) void;

pub const ChatCompletionError = error{
    NetworkError,
    InvalidResponse,
    AuthenticationFailed,
    RateLimited,
    ServerError,
    BadRequest,
} || std.mem.Allocator.Error;

// Internal Claude API response structures
const ClaudeMessage = struct {
    role: []const u8,
    content: []const u8,
};

const ClaudeResponse = struct {
    id: []const u8,
    type: []const u8,
    role: []const u8,
    model: []const u8,
    content: []ContentBlock,
    stop_reason: []const u8,
    stop_sequence: ?[]const u8,
    usage: ClaudeUsage,
    
    const ContentBlock = struct {
        type: []const u8, // "text"
        text: []const u8,
    };
    
    const ClaudeUsage = struct {
        input_tokens: u32,
        output_tokens: u32,
    };
};