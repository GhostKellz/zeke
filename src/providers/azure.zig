const std = @import("std");
const HttpClient = @import("../api/http_client.zig").HttpClient;
const HttpResponse = @import("../api/http_client.zig").HttpResponse;

/// Azure OpenAI provider
/// Documentation: https://learn.microsoft.com/en-us/azure/ai-services/openai/
pub const AzureProvider = struct {
    http_client: HttpClient,
    api_key: []const u8,
    resource_name: []const u8, // e.g., "my-resource"
    deployment_name: []const u8, // Your model deployment name
    api_version: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        resource_name: []const u8,
        deployment_name: []const u8,
    ) AzureProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .api_key = api_key,
            .resource_name = resource_name,
            .deployment_name = deployment_name,
            .api_version = "2024-02-15-preview", // Latest stable API version
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AzureProvider) void {
        self.http_client.deinit();
    }

    pub fn setDeployment(self: *AzureProvider, deployment_name: []const u8) void {
        self.deployment_name = deployment_name;
    }

    pub fn setApiVersion(self: *AzureProvider, api_version: []const u8) void {
        self.api_version = api_version;
    }

    fn getBaseUrl(self: *AzureProvider) ![]const u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "https://{s}.openai.azure.com",
            .{self.resource_name},
        );
    }

    pub fn chatCompletion(self: *AzureProvider, messages: []const ChatMessage, conversation_id: []const u8) !ChatCompletionResponse {
        _ = conversation_id;

        // Create request payload
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const writer = payload.writer();
        try writer.writeAll("{\"messages\":[");

        for (messages, 0..) |message, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.writeAll("}");
        }

        try writer.writeAll("],\"temperature\":0.7,\"max_tokens\":4000}");

        // Azure uses api-key header instead of Bearer
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("api-key", self.api_key);
        try headers.put("Content-Type", "application/json");

        // Build Azure-specific endpoint URL
        const base_url = try self.getBaseUrl();
        defer self.allocator.free(base_url);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/openai/deployments/{s}/chat/completions?api-version={s}",
            .{ base_url, self.deployment_name, self.api_version },
        );
        defer self.allocator.free(url);

        var response = self.http_client.post(url, payload.items, headers) catch {
            return ChatCompletionError.NetworkError;
        };
        defer response.deinit();

        if (!response.isSuccess()) {
            std.log.err("Azure OpenAI API error: status {}, body: {s}", .{ response.status, response.body });
            return switch (response.status) {
                401 => ChatCompletionError.AuthenticationFailed,
                429 => ChatCompletionError.RateLimited,
                400...499 => ChatCompletionError.BadRequest,
                500...599 => ChatCompletionError.ServerError,
                else => ChatCompletionError.NetworkError,
            };
        }

        // Parse response (same as OpenAI format)
        const parsed = std.json.parseFromSlice(AzureResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse Azure response: {}", .{err});
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

    pub fn codeCompletion(self: *AzureProvider, prompt: []const u8, language: ?[]const u8, context: ?[]const u8) !CodeCompletionResponse {
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

    /// Stream chat completion (simulated for now)
    pub fn streamChatCompletion(
        self: *AzureProvider,
        messages: []const ChatMessage,
        callback: *const fn ([]const u8) void,
    ) !void {
        // Simulate streaming
        const response = try self.chatCompletion(messages, "stream");
        defer self.allocator.free(response.content);
        defer self.allocator.free(response.model);

        // Chunk and stream
        const chunk_size = 50;
        var i: usize = 0;
        while (i < response.content.len) {
            const end = @min(i + chunk_size, response.content.len);
            callback(response.content[i..end]);
            i = end;
            std.time.sleep(50 * std.time.ns_per_ms);
        }
    }
};

// Response types (OpenAI-compatible)
pub const ChatMessage = struct {
    role: []const u8,
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
const AzureResponse = struct {
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
