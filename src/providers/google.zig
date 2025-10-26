const std = @import("std");
const api = @import("../api/client.zig");

/// Google Gemini API Provider
/// Supports Gemini Pro, Gemini Pro Vision, and other Google AI models
/// API Docs: https://ai.google.dev/api/rest
pub const GoogleClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8 = "https://generativelanguage.googleapis.com",
    model: []const u8 = "gemini-pro",
    temperature: f32 = 0.7,
    max_tokens: u32 = 2048,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !Self {
        return .{
            .allocator = allocator,
            .api_key = try allocator.dupe(u8, api_key),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
    }

    pub fn setModel(self: *Self, model: []const u8) !void {
        self.model = model;
    }

    /// Send a chat completion request to Google Gemini API
    pub fn chatCompletion(
        self: *Self,
        messages: []const api.Message,
        options: api.CompletionOptions,
    ) !api.CompletionResponse {
        const endpoint = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1beta/models/{s}:generateContent?key={s}",
            .{ self.base_url, self.model, self.api_key },
        );
        defer self.allocator.free(endpoint);

        // Convert messages to Gemini format
        const gemini_request = try self.buildGeminiRequest(messages, options);
        defer self.allocator.free(gemini_request);

        // Make HTTP request (simplified - needs proper HTTP client integration)
        const response = try self.makeRequest(endpoint, gemini_request);
        defer self.allocator.free(response);

        return try self.parseGeminiResponse(response);
    }

    /// Stream chat completion from Gemini API
    pub fn chatCompletionStream(
        self: *Self,
        messages: []const api.Message,
        options: api.CompletionOptions,
        callback: *const fn (chunk: []const u8) anyerror!void,
    ) !void {
        const endpoint = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1beta/models/{s}:streamGenerateContent?key={s}",
            .{ self.base_url, self.model, self.api_key },
        );
        defer self.allocator.free(endpoint);

        const gemini_request = try self.buildGeminiRequest(messages, options);
        defer self.allocator.free(gemini_request);

        try self.makeStreamRequest(endpoint, gemini_request, callback);
    }

    // ===== Private Implementation =====

    fn buildGeminiRequest(
        self: *Self,
        messages: []const api.Message,
        options: api.CompletionOptions,
    ) ![]const u8 {
        var request = std.ArrayList(u8).init(self.allocator);
        errdefer request.deinit();

        const writer = request.writer();

        try writer.writeAll("{\"contents\":[");

        // Convert messages to Gemini format
        for (messages, 0..) |msg, i| {
            if (i > 0) try writer.writeAll(",");

            const role = switch (msg.role) {
                .system => "user", // Gemini doesn't have system role, treat as user
                .user => "user",
                .assistant => "model",
            };

            try writer.print("{{\"role\":\"{s}\",\"parts\":[{{\"text\":", .{role});
            try std.json.encodeJsonString(msg.content, .{}, writer);
            try writer.writeAll("}]}");
        }

        try writer.writeAll("],\"generationConfig\":{");

        // Add generation config
        try writer.print("\"temperature\":{d},", .{options.temperature orelse self.temperature});
        try writer.print("\"maxOutputTokens\":{d}", .{options.max_tokens orelse self.max_tokens});

        if (options.stop_sequences) |sequences| {
            try writer.writeAll(",\"stopSequences\":[");
            for (sequences, 0..) |seq, i| {
                if (i > 0) try writer.writeAll(",");
                try std.json.encodeJsonString(seq, .{}, writer);
            }
            try writer.writeAll("]");
        }

        try writer.writeAll("}}");

        return request.toOwnedSlice();
    }

    fn parseGeminiResponse(self: *Self, response_json: []const u8) !api.CompletionResponse {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_json,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract content from Gemini response
        const candidates = root.get("candidates") orelse return error.InvalidResponse;
        if (candidates.array.items.len == 0) return error.NoContentGenerated;

        const first_candidate = candidates.array.items[0].object;
        const content = first_candidate.get("content") orelse return error.InvalidResponse;
        const parts = content.object.get("parts") orelse return error.InvalidResponse;

        if (parts.array.items.len == 0) return error.NoContentGenerated;

        const text_part = parts.array.items[0].object;
        const text = text_part.get("text") orelse return error.InvalidResponse;

        // Extract usage info
        var prompt_tokens: u32 = 0;
        var completion_tokens: u32 = 0;

        if (root.get("usageMetadata")) |usage| {
            if (usage.object.get("promptTokenCount")) |pt| {
                prompt_tokens = @intCast(pt.integer);
            }
            if (usage.object.get("candidatesTokenCount")) |ct| {
                completion_tokens = @intCast(ct.integer);
            }
        }

        return api.CompletionResponse{
            .content = try self.allocator.dupe(u8, text.string),
            .model = try self.allocator.dupe(u8, self.model),
            .finish_reason = .stop,
            .usage = .{
                .prompt_tokens = prompt_tokens,
                .completion_tokens = completion_tokens,
                .total_tokens = prompt_tokens + completion_tokens,
            },
        };
    }

    fn makeRequest(self: *Self, endpoint: []const u8, request_body: []const u8) ![]const u8 {
        _ = self;
        _ = endpoint;
        _ = request_body;
        // TODO: Integrate with zhttp or flash HTTP client
        return error.NotImplemented;
    }

    fn makeStreamRequest(
        self: *Self,
        endpoint: []const u8,
        request_body: []const u8,
        callback: *const fn (chunk: []const u8) anyerror!void,
    ) !void {
        _ = self;
        _ = endpoint;
        _ = request_body;
        _ = callback;
        // TODO: Integrate with zhttp streaming
        return error.NotImplemented;
    }
};

/// Gemini Model Variants
pub const GeminiModel = enum {
    gemini_pro,
    gemini_pro_vision,
    gemini_ultra,
    gemini_flash,

    pub fn toString(self: GeminiModel) []const u8 {
        return switch (self) {
            .gemini_pro => "gemini-pro",
            .gemini_pro_vision => "gemini-pro-vision",
            .gemini_ultra => "gemini-ultra",
            .gemini_flash => "gemini-1.5-flash",
        };
    }
};

test "GoogleClient - build request" {
    const allocator = std.testing.allocator;

    var client = try GoogleClient.init(allocator, "test-key");
    defer client.deinit();

    const messages = [_]api.Message{
        .{
            .role = .user,
            .content = "Hello, Gemini!",
        },
    };

    const options = api.CompletionOptions{
        .temperature = 0.8,
        .max_tokens = 1024,
    };

    const request = try client.buildGeminiRequest(&messages, options);
    defer allocator.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "gemini") != null or
        std.mem.indexOf(u8, request, "contents") != null);
}
