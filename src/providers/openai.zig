const std = @import("std");
const HttpClient = @import("../api/http_client.zig").HttpClient;
const HttpResponse = @import("../api/http_client.zig").HttpResponse;

pub const OpenAIProvider = struct {
    http_client: HttpClient,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) OpenAIProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .api_key = api_key,
            .base_url = "https://api.openai.com/v1",
            .model = "gpt-4",
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *OpenAIProvider) void {
        self.http_client.deinit();
    }
    
    pub fn chatCompletion(self: *OpenAIProvider, messages: []const ChatMessage, conversation_id: []const u8) !ChatCompletionResponse {
        _ = conversation_id;
        
        // Create request payload
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();
        
        const writer = payload.writer();
        try writer.print("{{\"model\":\"{s}\",\"messages\":[", .{self.model});
        
        for (messages, 0..) |message, i| {
            if (i > 0) try writer.print(",");
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.print("}}");
        }
        
        try writer.print("],\"temperature\":0.7,\"max_tokens\":4000}}");
        
        // Create authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("Authorization", auth_header);
        try headers.put("Content-Type", "application/json");
        
        // Make HTTP request
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);
        
        var response = self.http_client.post(url, payload.items, headers) catch {
            return ChatCompletionError.NetworkError;
        };
        defer response.deinit();
        
        if (!response.isSuccess()) {
            std.log.err("OpenAI API error: status {}, body: {s}", .{ response.status, response.body });
            return switch (response.status) {
                401 => ChatCompletionError.AuthenticationFailed,
                429 => ChatCompletionError.RateLimited,
                400...499 => ChatCompletionError.BadRequest,
                500...599 => ChatCompletionError.ServerError,
                else => ChatCompletionError.NetworkError,
            };
        }
        
        // Parse response
        const parsed = std.json.parseFromSlice(OpenAIResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse OpenAI response: {}", .{err});
            return ChatCompletionError.InvalidResponse;
        };
        defer parsed.deinit();
        
        if (parsed.value.choices.len == 0) {
            return ChatCompletionError.InvalidResponse;
        }
        
        const choice = parsed.value.choices[0];
        const content = try self.allocator.dupe(u8, choice.message.content);
        
        return ChatCompletionResponse{
            .content = content,
            .model = try self.allocator.dupe(u8, parsed.value.model),
            .usage = Usage{
                .prompt_tokens = parsed.value.usage.prompt_tokens,
                .completion_tokens = parsed.value.usage.completion_tokens,
                .total_tokens = parsed.value.usage.total_tokens,
            },
        };
    }
    
    pub fn codeCompletion(self: *OpenAIProvider, prompt: []const u8, language: ?[]const u8, context: ?[]const u8) !CodeCompletionResponse {
        var messages = std.ArrayList(ChatMessage).init(self.allocator);
        defer messages.deinit();
        
        // System message for code completion
        const system_prompt = if (language) |lang|
            try std.fmt.allocPrint(self.allocator, 
                "You are an expert {s} programmer. Complete the following code. Return only the completion without explanation.", 
                .{lang})
        else
            "You are an expert programmer. Complete the following code. Return only the completion without explanation.";
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
            .confidence = 0.8, // OpenAI typically has high confidence
        };
    }
    
    pub fn streamChatCompletion(self: *OpenAIProvider, messages: []const ChatMessage, callback: StreamCallback) !void {
        // For now, simulate streaming by calling the regular completion and invoking callback
        const response = try self.chatCompletion(messages, "stream");
        defer self.allocator.free(response.content);
        defer self.allocator.free(response.model);
        
        // Split content into chunks and stream
        const chunk_size = 10;
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
            std.time.sleep(50 * std.time.ns_per_ms);
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

// Internal OpenAI API response structures
const OpenAIResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    usage: ApiUsage,
    
    const Choice = struct {
        index: u32,
        message: Message,
        finish_reason: []const u8,
        
        const Message = struct {
            role: []const u8,
            content: []const u8,
        };
    };
    
    const ApiUsage = struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    };
};