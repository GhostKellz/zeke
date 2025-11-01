const std = @import("std");
const HttpClient = @import("../api/http_client.zig").HttpClient;
const HttpResponse = @import("../api/http_client.zig").HttpResponse;

/// GitHub Copilot provider - uses OpenAI-compatible API
/// Requires GitHub Copilot Pro subscription ($10/month)
/// Provides access to multiple models: GPT-4, Claude, Gemini, etc.
pub const GitHubCopilotProvider = struct {
    http_client: HttpClient,
    access_token: []const u8,
    base_url: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,

    /// Initialize GitHub Copilot provider with OAuth token
    pub fn init(allocator: std.mem.Allocator, access_token: []const u8) GitHubCopilotProvider {
        return .{
            .http_client = HttpClient.init(allocator),
            .access_token = access_token,
            .base_url = "https://api.githubcopilot.com",
            .model = "gpt-4o", // Default model
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GitHubCopilotProvider) void {
        self.http_client.deinit();
    }

    /// Set the model to use for requests
    pub fn setModel(self: *GitHubCopilotProvider, model: []const u8) void {
        self.model = model;
    }

    /// Chat completion using OpenAI-compatible format
    pub fn chatCompletion(
        self: *GitHubCopilotProvider,
        messages: []const ChatMessage,
        conversation_id: []const u8,
    ) !ChatCompletionResponse {
        _ = conversation_id;

        // Create request payload (OpenAI format)
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const writer = payload.writer();
        try writer.print("{{\"model\":\"{s}\",\"messages\":[", .{self.model});

        for (messages, 0..) |message, i| {
            if (i > 0) try writer.print(",", .{});
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.print("}}", .{});
        }

        try writer.print("],\"stream\":false}}", .{});

        // Create headers with OAuth bearer token
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // GitHub Copilot uses Bearer token authentication
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.access_token});
        defer self.allocator.free(auth_header);

        try headers.put("Authorization", auth_header);
        try headers.put("Content-Type", "application/json");
        try headers.put("Editor-Plugin-Version", "zeke/0.3.1");
        try headers.put("Editor-Version", "zeke/0.3.1");
        try headers.put("OpenAI-Intent", "conversation-panel");

        // Make HTTP request to chat completions endpoint
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/chat/completions",
            .{self.base_url},
        );
        defer self.allocator.free(url);

        var response = self.http_client.post(url, payload.items, headers) catch |err| {
            std.log.err("GitHub Copilot HTTP request failed: {}", .{err});
            return ChatCompletionError.NetworkError;
        };
        defer response.deinit();

        if (!response.isSuccess()) {
            std.log.err("GitHub Copilot API error: status {}, body: {s}", .{ response.status, response.body });
            return switch (response.status) {
                401 => ChatCompletionError.AuthenticationFailed,
                403 => ChatCompletionError.AuthenticationFailed, // No active subscription
                429 => ChatCompletionError.RateLimited,
                400...499 => ChatCompletionError.BadRequest,
                500...599 => ChatCompletionError.ServerError,
                else => ChatCompletionError.NetworkError,
            };
        }

        // Parse OpenAI-compatible response
        const parsed = std.json.parseFromSlice(
            OpenAIResponse,
            self.allocator,
            response.body,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            std.log.err("Failed to parse Copilot response: {}, body: {s}", .{ err, response.body });
            return ChatCompletionError.InvalidResponse;
        };
        defer parsed.deinit();

        const openai_response = parsed.value;

        // Extract content from first choice
        if (openai_response.choices.len == 0) {
            return ChatCompletionError.InvalidResponse;
        }

        const content = try self.allocator.dupe(u8, openai_response.choices[0].message.content);

        return ChatCompletionResponse{
            .content = content,
            .model = try self.allocator.dupe(u8, openai_response.model),
            .usage = .{
                .prompt_tokens = openai_response.usage.prompt_tokens,
                .completion_tokens = openai_response.usage.completion_tokens,
                .total_tokens = openai_response.usage.total_tokens,
            },
        };
    }

    /// Streaming chat completion
    pub fn chatCompletionStream(
        self: *GitHubCopilotProvider,
        messages: []const ChatMessage,
        conversation_id: []const u8,
        callback: *const fn (chunk: []const u8) void,
    ) !ChatCompletionResponse {
        _ = conversation_id;
        _ = callback;

        // Create request payload with streaming enabled
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        const writer = payload.writer();
        try writer.print("{{\"model\":\"{s}\",\"messages\":[", .{self.model});

        for (messages, 0..) |message, i| {
            if (i > 0) try writer.print(",", .{});
            try writer.print("{{\"role\":\"{s}\",\"content\":", .{message.role});
            try std.json.stringify(message.content, .{}, writer);
            try writer.print("}}", .{});
        }

        try writer.print("],\"stream\":true}}", .{});

        // TODO: Implement streaming response handling
        // For now, return non-streaming completion
        return self.chatCompletion(messages, "");
    }
};

// === Response Types (OpenAI-compatible) ===

const OpenAIResponse = struct {
    id: []const u8,
    object: []const u8,
    created: i64,
    model: []const u8,
    choices: []Choice,
    usage: Usage,

    const Choice = struct {
        index: i32,
        message: Message,
        finish_reason: ?[]const u8 = null,

        const Message = struct {
            role: []const u8,
            content: []const u8,
        };
    };

    const Usage = struct {
        prompt_tokens: i32,
        completion_tokens: i32,
        total_tokens: i32,
    };
};

// === Common Types ===

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const ChatCompletionResponse = struct {
    content: []const u8,
    model: []const u8,
    usage: struct {
        prompt_tokens: i32,
        completion_tokens: i32,
        total_tokens: i32,
    },

    pub fn deinit(self: *ChatCompletionResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        allocator.free(self.model);
    }
};

pub const ChatCompletionError = error{
    NetworkError,
    AuthenticationFailed,
    RateLimited,
    BadRequest,
    ServerError,
    InvalidResponse,
};

// === Available Models via GitHub Copilot Pro ===

pub const AVAILABLE_MODELS = [_][]const u8{
    // GPT Models
    "gpt-4o",
    "gpt-4.1",
    "gpt-5",
    "gpt-5-mini",
    "gpt-5-codex",

    // Claude Models (via Copilot)
    "claude-3.5-sonnet",
    "claude-3.7-sonnet",
    "claude-3.7-sonnet-thought",
    "claude-haiku-4.5",
    "claude-opus-4",
    "claude-opus-41",
    "claude-sonnet-4",
    "claude-sonnet-4.5",

    // Gemini Models (via Copilot)
    "gemini-2.0-flash-001",
    "gemini-2.5-pro",

    // O-series Models
    "o3-mini",
    "o3",
    "o4-mini",

    // Grok
    "grok-code-fast-1",
};

/// Get recommended model for specific task
pub fn getRecommendedModel(task: TaskType) []const u8 {
    return switch (task) {
        .code_completion => "gpt-5-codex",
        .chat => "gpt-4o",
        .reasoning => "claude-opus-4",
        .fast_response => "gpt-5-mini",
        .code_review => "claude-3.5-sonnet",
    };
}

pub const TaskType = enum {
    code_completion,
    chat,
    reasoning,
    fast_response,
    code_review,
};

// === Tests ===

test "github copilot provider init" {
    const allocator = std.testing.allocator;
    const provider = GitHubCopilotProvider.init(allocator, "test-token");
    var provider_mut = provider;
    defer provider_mut.deinit();

    try std.testing.expectEqualStrings("https://api.githubcopilot.com", provider.base_url);
    try std.testing.expectEqualStrings("gpt-4o", provider.model);
}

test "model selection" {
    try std.testing.expectEqualStrings("gpt-5-codex", getRecommendedModel(.code_completion));
    try std.testing.expectEqualStrings("claude-opus-4", getRecommendedModel(.reasoning));
    try std.testing.expectEqualStrings("gpt-5-mini", getRecommendedModel(.fast_response));
}
