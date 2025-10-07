const std = @import("std");
const http_client = @import("../api/http_client.zig");

/// Ollama API response structures
pub const OllamaModel = struct {
    name: []const u8,
    model: []const u8,
    modified_at: []const u8,
    size: u64,
    digest: []const u8,
    details: struct {
        parent_model: []const u8,
        format: []const u8,
        family: []const u8,
        families: [][]const u8,
        parameter_size: []const u8,
        quantization_level: []const u8,
    },
};

pub const OllamaTagsResponse = struct {
    models: []OllamaModel,
};

pub const OllamaChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const OllamaChatRequest = struct {
    model: []const u8,
    messages: []OllamaChatMessage,
    stream: bool = false,
    options: ?struct {
        temperature: ?f32 = null,
        top_p: ?f32 = null,
        top_k: ?u32 = null,
    } = null,
};

pub const OllamaChatResponse = struct {
    model: []const u8,
    created_at: []const u8,
    message: OllamaChatMessage,
    done: bool,
    total_duration: ?u64 = null,
    load_duration: ?u64 = null,
    prompt_eval_count: ?u32 = null,
    eval_count: ?u32 = null,
    eval_duration: ?u64 = null,
};

pub const OllamaGenerateRequest = struct {
    model: []const u8,
    prompt: []const u8,
    stream: bool = false,
    system: ?[]const u8 = null,
    options: ?struct {
        temperature: ?f32 = null,
        top_p: ?f32 = null,
        top_k: ?u32 = null,
    } = null,
};

pub const OllamaGenerateResponse = struct {
    model: []const u8,
    created_at: []const u8,
    response: []const u8,
    done: bool,
    context: ?[]i32 = null,
    total_duration: ?u64 = null,
    load_duration: ?u64 = null,
    prompt_eval_count: ?u32 = null,
    eval_count: ?u32 = null,
    eval_duration: ?u64 = null,
};

/// Ollama provider client
pub const OllamaProvider = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    timeout_ms: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, timeout_ms: u32) !Self {
        return Self{
            .allocator = allocator,
            .base_url = try allocator.dupe(u8, base_url),
            .timeout_ms = timeout_ms,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.base_url);
    }

    /// List available models
    pub fn listModels(self: *Self) !OllamaTagsResponse {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/tags", .{self.base_url});
        defer self.allocator.free(url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        const response_data = blk: {
            errdefer {
                const slice = allocating_writer.toOwnedSlice() catch &[_]u8{};
                self.allocator.free(slice);
            }

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .method = .GET,
                .response_writer = &allocating_writer.writer,
            });

            if (result.status != .ok) {
                std.log.err("Ollama API error: {}", .{result.status});
                return error.OllamaApiError;
            }

            break :blk try allocating_writer.toOwnedSlice();
        };
        defer self.allocator.free(response_data);

        const parsed = try std.json.parseFromSlice(
            OllamaTagsResponse,
            self.allocator,
            response_data,
            .{ .allocate = .alloc_always },
        );

        return parsed.value;
    }

    /// Chat completion
    pub fn chat(self: *Self, request: OllamaChatRequest) !OllamaChatResponse {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/chat", .{self.base_url});
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

            const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = request_json,
            .response_writer = &allocating_writer.writer,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "application/json" },
            },
        });

        if (result.status != .ok) {
            std.log.err("Ollama chat API error: {}", .{result.status});
            return error.OllamaChatError;
        }

        break :blk try allocating_writer.toOwnedSlice();
    };
    defer self.allocator.free(response_data);

    const parsed = try std.json.parseFromSlice(
        OllamaChatResponse,
        self.allocator,
        response_data,
        .{ .allocate = .alloc_always },
    );

    return parsed.value;
    }

    /// Generate completion (simpler API)
    pub fn generate(self: *Self, request: OllamaGenerateRequest) !OllamaGenerateResponse {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/generate", .{self.base_url});
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

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .method = .POST,
                .payload = request_json,
                .response_writer = &allocating_writer.writer,
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "application/json" },
                    .{ .name = "Accept", .value = "application/json" },
                },
            });

            if (result.status != .ok) {
                std.log.err("Ollama generate API error: {}", .{result.status});
                return error.OllamaGenerateError;
            }

            break :blk try allocating_writer.toOwnedSlice();
        };
        defer self.allocator.free(response_data);

        const parsed = try std.json.parseFromSlice(
            OllamaGenerateResponse,
            self.allocator,
            response_data,
            .{ .allocate = .alloc_always },
        );

        return parsed.value;
    }

    /// Health check - ping the Ollama server
    pub fn health(self: *Self) !bool {
        // Simplified health check - try to list models
        // If that works, Ollama is healthy
        _ = self.listModels() catch return false;
        return true;
    }

    /// Get version info
    pub fn version(self: *Self) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/version", .{self.base_url});
        defer self.allocator.free(url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer {
            const slice = allocating_writer.toOwnedSlice() catch &[_]u8{};
            self.allocator.free(slice);
        }

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            return error.OllamaVersionError;
        }

        return try allocating_writer.toOwnedSlice();
    }
};

/// Helper function to create Ollama provider from environment
pub fn fromEnv(allocator: std.mem.Allocator) !OllamaProvider {
    const ollama_host = std.posix.getenv("OLLAMA_HOST") orelse "http://localhost:11434";
    return OllamaProvider.init(allocator, ollama_host, 60000); // 60s timeout
}

/// Test function
pub fn testOllama() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var provider = try fromEnv(allocator);
    defer provider.deinit();

    // Test health
    const is_healthy = try provider.health();
    std.debug.print("Ollama healthy: {}\n", .{is_healthy});

    if (!is_healthy) return;

    // Test list models
    const models_response = try provider.listModels();
    std.debug.print("Found {} models\n", .{models_response.models.len});

    for (models_response.models) |model| {
        std.debug.print("  - {s} ({s}, {s})\n", .{
            model.name,
            model.details.parameter_size,
            model.details.quantization_level,
        });
    }
}
