const std = @import("std");
const HttpClient = @import("../api/http_client.zig").HttpClient;
const HttpResponse = @import("../api/http_client.zig").HttpResponse;

/// xAI/Grok provider - OpenAI-compatible API
/// Documentation: https://docs.x.ai/api
pub const XAIProvider = struct {
    http_client: HttpClient,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,

    /// Available Grok models
    pub const Model = enum {
        grok_2_latest, // Latest Grok-2 model
        grok_2_1212, // Grok-2 December 2024 release
        grok_2_vision_1212, // Grok-2 with vision capabilities
        grok_beta, // Beta model with latest features

        pub fn toString(self: Model) []const u8 {
            return switch (self) {
                .grok_2_latest => "grok-2-latest",
                .grok_2_1212 => "grok-2-1212",
                .grok_2_vision_1212 => "grok-2-vision-1212",
                .grok_beta => "grok-beta",
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) XAIProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .api_key = api_key,
            .base_url = "https://api.x.ai/v1",
            .model = Model.grok_2_latest.toString(), // Default to latest
            .allocator = allocator,
        };
    }

    pub fn initWithModel(allocator: std.mem.Allocator, api_key: []const u8, model: Model) XAIProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .api_key = api_key,
            .base_url = "https://api.x.ai/v1",
            .model = model.toString(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *XAIProvider) void {
        self.http_client.deinit();
    }

    pub fn setModel(self: *XAIProvider, model: Model) void {
        self.model = model.toString();
    }

    pub fn chatCompletion(self: *XAIProvider, messages: []const ChatMessage, conversation_id: []const u8) !ChatCompletionResponse {
        _ = conversation_id;

        // Create request payload (OpenAI-compatible)
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const writer = payload.writer();
        try writer.print("{{\"model\":\"{s}\",\"messages\":[", .{self.model});

        for (messages, 0..) |message, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.writeAll("}");
        }

        try writer.writeAll("],\"temperature\":0.7,\"max_tokens\":4000}");

        // Create authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("Authorization", auth_header);
        try headers.put("Content-Type", "application/json");

        // Make HTTP request to xAI API
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);

        var response = self.http_client.post(url, payload.items, headers) catch {
            return ChatCompletionError.NetworkError;
        };
        defer response.deinit();

        if (!response.isSuccess()) {
            std.log.err("xAI API error: status {}, body: {s}", .{ response.status, response.body });
            return switch (response.status) {
                401 => ChatCompletionError.AuthenticationFailed,
                429 => ChatCompletionError.RateLimited,
                400...499 => ChatCompletionError.BadRequest,
                500...599 => ChatCompletionError.ServerError,
                else => ChatCompletionError.NetworkError,
            };
        }

        // Parse response (OpenAI-compatible format)
        const parsed = std.json.parseFromSlice(XAIResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse xAI response: {}", .{err});
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

    pub fn codeCompletion(self: *XAIProvider, prompt: []const u8, language: ?[]const u8, context: ?[]const u8) !CodeCompletionResponse {
        var messages = std.ArrayList(ChatMessage).init(self.allocator);
        defer messages.deinit();

        // System message for code completion
        const system_msg = try std.fmt.allocPrint(
            self.allocator,
            "You are an expert programmer. Provide concise, well-structured code completions for {s}. Only output code, no explanations unless requested.",
            .{language orelse "the requested language"},
        );
        defer self.allocator.free(system_msg);

        try messages.append(.{
            .role = "system",
            .content = system_msg,
        });

        // Add context if provided
        if (context) |ctx| {
            const context_msg = try std.fmt.allocPrint(
                self.allocator,
                "Context:\n{s}",
                .{ctx},
            );
            defer self.allocator.free(context_msg);

            try messages.append(.{
                .role = "user",
                .content = context_msg,
            });
        }

        // Add the prompt
        try messages.append(.{
            .role = "user",
            .content = prompt,
        });

        // Use chat completion for code
        const response = try self.chatCompletion(messages.items, "code-completion");

        return CodeCompletionResponse{
            .code = response.content,
            .language = if (language) |lang| try self.allocator.dupe(u8, lang) else null,
            .model = response.model,
        };
    }

    /// Stream chat completion (simulated for now, actual streaming TBD)
    pub fn streamChatCompletion(
        self: *XAIProvider,
        messages: []const ChatMessage,
        callback: *const fn ([]const u8) void,
    ) !void {
        // For now, simulate streaming by chunking the response
        const response = try self.chatCompletion(messages, "stream");
        defer self.allocator.free(response.content);
        defer self.allocator.free(response.model);

        // Simulate streaming with 50-char chunks
        const chunk_size = 50;
        var i: usize = 0;
        while (i < response.content.len) {
            const end = @min(i + chunk_size, response.content.len);
            callback(response.content[i..end]);
            i = end;
            std.time.sleep(50 * std.time.ns_per_ms); // 50ms delay
        }
    }
};

// Response types (OpenAI-compatible)
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
    code: []const u8,
    language: ?[]const u8,
    model: []const u8,
};

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

pub const ChatCompletionError = error{
    NetworkError,
    AuthenticationFailed,
    RateLimited,
    BadRequest,
    ServerError,
    InvalidResponse,
    OutOfMemory,
};

// Internal response parsing structures
const XAIResponse = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []Choice,
    usage: UsageData,

    const Choice = struct {
        index: u32,
        message: Message,
        finish_reason: []const u8,

        const Message = struct {
            role: []const u8,
            content: []const u8,
        };
    };

    const UsageData = struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    };
};
