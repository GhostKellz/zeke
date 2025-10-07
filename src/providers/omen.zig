const std = @import("std");

/// OMEN API client for smart routing
/// OMEN provides OpenAI-compatible API with intelligent model routing
pub const OmenClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: ?[]const u8,
    timeout_ms: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, api_key: ?[]const u8, timeout_ms: u32) !Self {
        return Self{
            .allocator = allocator,
            .base_url = try allocator.dupe(u8, base_url),
            .api_key = if (api_key) |key| try allocator.dupe(u8, key) else null,
            .timeout_ms = timeout_ms,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.base_url);
        if (self.api_key) |key| {
            self.allocator.free(key);
        }
    }

    /// OpenAI-compatible chat completion request
    pub fn chatCompletion(self: *Self, request: ChatCompletionRequest) !ChatCompletionResponse {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);

        const request_json = try std.json.Stringify.valueAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        const response_data = blk: {
            errdefer {
                const slice = allocating_writer.toOwnedSlice() catch &[_]u8{};
                self.allocator.free(slice);
            }

            var headers = std.ArrayList(std.http.Header).empty;
            defer headers.deinit(self.allocator);

            try headers.append(self.allocator, .{ .name = "Content-Type", .value = "application/json" });
            if (self.api_key) |key| {
                const auth_value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{key});
                defer self.allocator.free(auth_value);
                try headers.append(self.allocator, .{ .name = "Authorization", .value = auth_value });
            }

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .method = .POST,
                .payload = request_json,
                .response_writer = &allocating_writer.writer,
                .extra_headers = headers.items,
            });

            if (result.status != .ok) {
                std.log.err("OMEN API error: {} - {s}", .{ result.status, url });
                return error.OmenApiError;
            }

            break :blk try allocating_writer.toOwnedSlice();
        };
        defer self.allocator.free(response_data);

        const parsed = try std.json.parseFromSlice(
            ChatCompletionResponse,
            self.allocator,
            response_data,
            .{ .allocate = .alloc_always },
        );

        return parsed.value;
    }

    /// Health check for OMEN server
    pub fn health(self: *Self) !bool {
        const health_url = try std.fmt.allocPrint(self.allocator, "{s}/../health", .{self.base_url});
        defer self.allocator.free(health_url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = health_url },
            .method = .GET,
        }) catch return false;

        return result.status == .ok;
    }
};

/// Chat completion request (OpenAI-compatible)
pub const ChatCompletionRequest = struct {
    model: []const u8 = "auto", // Let OMEN choose optimal model
    messages: []Message,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    stream: bool = false,
    /// OMEN-specific routing tags
    tags: ?RoutingTags = null,
};

pub const Message = struct {
    role: []const u8, // "system", "user", "assistant"
    content: []const u8,
};

/// Routing metadata for OMEN decision engine
pub const RoutingTags = struct {
    /// Task intent: code, completion, refactor, tests, explain, reason, architecture
    intent: ?[]const u8 = null,
    /// Source application
    source: []const u8 = "zeke",
    /// Programming language
    language: ?[]const u8 = null,
    /// Task complexity: simple, medium, complex
    complexity: ?[]const u8 = null,
    /// Project identifier for cost tracking
    project: ?[]const u8 = null,
    /// Priority: low-latency, high-quality, cost-effective
    priority: ?[]const u8 = null,
};

/// OpenAI-compatible chat completion response
pub const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8, // "chat.completion"
    created: i64,
    model: []const u8, // Actual model used by OMEN
    choices: []Choice,
    usage: ?Usage = null,
    /// OMEN-specific routing metadata
    routing_metadata: ?RoutingMetadata = null,
};

pub const Choice = struct {
    index: u32,
    message: Message,
    finish_reason: []const u8, // "stop", "length", "content_filter"
};

pub const Usage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

/// OMEN routing decision metadata
pub const RoutingMetadata = struct {
    provider: []const u8, // "ollama", "anthropic", "openai"
    model_used: []const u8,
    latency_ms: u32,
    was_cached: bool = false,
    cost_usd: ?f64 = null,
    routing_reason: ?[]const u8 = null,
};

/// Helper to create OMEN client from environment
pub fn fromEnv(allocator: std.mem.Allocator) !OmenClient {
    const omen_base = std.posix.getenv("OMEN_BASE") orelse
        std.posix.getenv("ZEKE_API_BASE") orelse
        "http://localhost:8080/v1";

    const api_key = std.posix.getenv("OMEN_API_KEY") orelse
        std.posix.getenv("ZEKE_API_KEY");

    return OmenClient.init(allocator, omen_base, api_key, 60000); // 60s timeout
}

/// Test OMEN integration
pub fn testOmen() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try fromEnv(allocator);
    defer client.deinit();

    // Test health
    const is_healthy = try client.health();
    std.debug.print("OMEN healthy: {}\n", .{is_healthy});

    if (!is_healthy) {
        std.debug.print("OMEN is not available. Start it with: docker compose up -d omen\n", .{});
        return;
    }

    // Test chat completion
    var messages = [_]Message{
        .{ .role = "user", .content = "Write a hello world in Zig" },
    };

    const chat_request = ChatCompletionRequest{
        .model = "auto",
        .messages = &messages,
        .max_tokens = 512,
        .tags = .{
            .intent = "code",
            .language = "zig",
            .complexity = "simple",
            .priority = "low-latency",
        },
    };

    const response = try client.chatCompletion(chat_request);
    std.debug.print("\nModel used: {s}\n", .{response.model});
    std.debug.print("Response: {s}\n", .{response.choices[0].message.content});

    if (response.routing_metadata) |routing| {
        std.debug.print("\nRouting:\n", .{});
        std.debug.print("  Provider: {s}\n", .{routing.provider});
        std.debug.print("  Model: {s}\n", .{routing.model_used});
        std.debug.print("  Latency: {}ms\n", .{routing.latency_ms});
        std.debug.print("  Cached: {}\n", .{routing.was_cached});
        if (routing.cost_usd) |cost| {
            std.debug.print("  Cost: ${d:.4}\n", .{cost});
        }
    }

    if (response.usage) |usage| {
        std.debug.print("\nTokens:\n", .{});
        std.debug.print("  Prompt: {}\n", .{usage.prompt_tokens});
        std.debug.print("  Completion: {}\n", .{usage.completion_tokens});
        std.debug.print("  Total: {}\n", .{usage.total_tokens});
    }
}
