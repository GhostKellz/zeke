const std = @import("std");
const zhttp = @import("zhttp");
const router = @import("../routing/router.zig");
const ollama = @import("../providers/ollama.zig");
const omen = @import("../providers/omen.zig");
const routing_db = @import("../db/routing.zig");

/// Request/Response JSON structures
pub const ChatRequest = struct {
    message: []const u8,
    model: ?[]const u8 = null,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    intent: ?[]const u8 = null,
    language: ?[]const u8 = null,
    complexity: ?[]const u8 = null,
    project: ?[]const u8 = null,
};

pub const ChatResponse = struct {
    response: []const u8,
    model: []const u8,
    provider: []const u8,
    tokens_in: u32,
    tokens_out: u32,
    latency_ms: u32,
};

pub const CompleteRequest = struct {
    prompt: []const u8,
    model: ?[]const u8 = null,
    max_tokens: ?u32 = null,
    language: ?[]const u8 = null,
};

pub const CompleteResponse = struct {
    completion: []const u8,
    model: []const u8,
    provider: []const u8,
};

pub const ExplainRequest = struct {
    code: []const u8,
    language: ?[]const u8 = null,
};

pub const ExplainResponse = struct {
    explanation: []const u8,
    model: []const u8,
    provider: []const u8,
};

pub const EditRequest = struct {
    code: ?[]const u8 = null, // Optional: provide code directly
    file: ?[]const u8 = null, // Optional: provide file path (uses MCP fs.read)
    instruction: []const u8,
    prompt: ?[]const u8 = null, // Alias for instruction
    language: ?[]const u8 = null,
    dry_run: ?bool = null, // If true, generate diff but don't apply
};

pub const EditResponse = struct {
    edited_code: []const u8,
    diff: ?[]const u8 = null,
    model: []const u8,
    provider: []const u8,
};

pub const ErrorResponse = struct {
    @"error": []const u8,
    code: ?[]const u8 = null,
};

/// Global server instance for handler access
/// This is a workaround for zhttp's handler signature limitation
var global_server: ?*ZhttpServer = null;
var global_mutex: std.Thread.Mutex = .{};

/// zhttp-based RPC server for Neovim and editor integrations
/// Provides REST API endpoints for AI operations with smart routing
pub const ZhttpServer = struct {
    allocator: std.mem.Allocator,
    server: zhttp.Server,
    smart_router: *router.SmartRouter,
    port: u16,
    running: std.atomic.Value(bool),

    const Self = @This();

    pub const Config = struct {
        port: u16 = 7878,
        host: []const u8 = "127.0.0.1",
        enable_cors: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, smart_router: *router.SmartRouter, config: Config) Self {
        const server = zhttp.Server.init(allocator, .{
            .host = config.host,
            .port = config.port,
        }, handleRequest);

        return Self{
            .allocator = allocator,
            .server = server,
            .smart_router = smart_router,
            .port = config.port,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }

    pub fn start(self: *Self) !void {
        // Register as global server for handlers
        global_mutex.lock();
        global_server = self;
        global_mutex.unlock();
        defer {
            global_mutex.lock();
            global_server = null;
            global_mutex.unlock();
        }

        self.running.store(true, .release);
        std.log.info("🌐 Zeke RPC Server starting on http://127.0.0.1:{}", .{self.port});

        try self.server.listen();
    }

    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        std.log.info("🌐 Zeke RPC Server stopped", .{});
    }

    fn handleRequest(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        // CORS headers
        try res.setHeader("Access-Control-Allow-Origin", "*");
        try res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        try res.setHeader("Access-Control-Allow-Headers", "Content-Type");

        // Handle OPTIONS preflight
        if (req.method == .OPTIONS) {
            res.setStatus(204);
            try res.send("");
            return;
        }

        // Route endpoints
        if (std.mem.eql(u8, req.path, "/health")) {
            try handleHealth(req, res);
        } else if (std.mem.startsWith(u8, req.path, "/api/chat")) {
            try handleChat(req, res);
        } else if (std.mem.startsWith(u8, req.path, "/api/complete")) {
            try handleComplete(req, res);
        } else if (std.mem.startsWith(u8, req.path, "/api/explain")) {
            try handleExplain(req, res);
        } else if (std.mem.startsWith(u8, req.path, "/api/edit")) {
            try handleEdit(req, res);
        } else if (std.mem.startsWith(u8, req.path, "/api/status")) {
            try handleStatus(req, res);
        } else {
            res.setStatus(404);
            try res.sendJson("{\"error\":\"Not Found\"}");
        }
    }

    fn handleHealth(_: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        try res.sendJson("{\"status\":\"ok\",\"server\":\"zeke-rpc\",\"version\":\"0.2.8\"}");
    }

    fn handleChat(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        const allocator = req.allocator;

        // Parse JSON request
        const chat_req = std.json.parseFromSlice(
            ChatRequest,
            allocator,
            req.body,
            .{ .allocate = .alloc_always },
        ) catch {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Invalid JSON request",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(400);
            try res.sendJson(err_json);
            return;
        };
        defer chat_req.deinit();

        // Get server instance
        global_mutex.lock();
        const server = global_server;
        global_mutex.unlock();

        if (server == null) {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Server not initialized",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        }

        // Build completion request
        const completion_req = router.CompletionRequest{
            .prompt = chat_req.value.message,
            .model = chat_req.value.model,
            .temperature = chat_req.value.temperature,
            .max_tokens = chat_req.value.max_tokens,
            .intent = chat_req.value.intent,
            .language = chat_req.value.language,
            .complexity = chat_req.value.complexity,
            .project = chat_req.value.project,
        };

        // Route and execute
        const completion_res = server.?.smart_router.complete(completion_req) catch |err| {
            std.log.err("Completion failed: {}", .{err});
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Completion request failed",
                .code = @errorName(err),
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        };

        // Build response
        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .response = completion_res.content,
            .model = completion_res.model,
            .provider = completion_res.provider,
            .tokens_in = completion_res.tokens_in,
            .tokens_out = completion_res.tokens_out,
            .latency_ms = completion_res.latency_ms,
        }, .{});
        defer allocator.free(response_json);

        try res.sendJson(response_json);
    }

    fn handleComplete(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        const allocator = req.allocator;

        const complete_req = std.json.parseFromSlice(
            CompleteRequest,
            allocator,
            req.body,
            .{ .allocate = .alloc_always },
        ) catch {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Invalid JSON request",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(400);
            try res.sendJson(err_json);
            return;
        };
        defer complete_req.deinit();

        // Get server instance
        global_mutex.lock();
        const server = global_server;
        global_mutex.unlock();

        if (server == null) {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Server not initialized",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        }

        // Build completion request
        const completion_request = router.CompletionRequest{
            .prompt = complete_req.value.prompt,
            .model = complete_req.value.model,
            .max_tokens = complete_req.value.max_tokens,
            .intent = "completion",
            .language = complete_req.value.language,
        };

        // Route and execute
        const completion_res = server.?.smart_router.complete(completion_request) catch |err| {
            std.log.err("Completion failed: {}", .{err});
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Completion request failed",
                .code = @errorName(err),
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        };

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .completion = completion_res.content,
            .model = completion_res.model,
            .provider = completion_res.provider,
        }, .{});
        defer allocator.free(response_json);

        try res.sendJson(response_json);
    }

    fn handleExplain(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        const allocator = req.allocator;

        const explain_req = std.json.parseFromSlice(
            ExplainRequest,
            allocator,
            req.body,
            .{ .allocate = .alloc_always },
        ) catch {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Invalid JSON request",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(400);
            try res.sendJson(err_json);
            return;
        };
        defer explain_req.deinit();

        // Get server instance
        global_mutex.lock();
        const server = global_server;
        global_mutex.unlock();

        if (server == null) {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Server not initialized",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        }

        // Build prompt for code explanation
        const prompt = try std.fmt.allocPrint(
            allocator,
            "Explain this code:\n\n{s}",
            .{explain_req.value.code},
        );
        defer allocator.free(prompt);

        // Build completion request
        const completion_request = router.CompletionRequest{
            .prompt = prompt,
            .intent = "explain",
            .language = explain_req.value.language,
            .complexity = "simple",
        };

        // Route and execute
        const completion_res = server.?.smart_router.complete(completion_request) catch |err| {
            std.log.err("Explanation failed: {}", .{err});
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Explanation request failed",
                .code = @errorName(err),
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        };

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .explanation = completion_res.content,
            .model = completion_res.model,
            .provider = completion_res.provider,
        }, .{});
        defer allocator.free(response_json);

        try res.sendJson(response_json);
    }

    fn handleEdit(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        const allocator = req.allocator;

        const edit_req = std.json.parseFromSlice(
            EditRequest,
            allocator,
            req.body,
            .{ .allocate = .alloc_always },
        ) catch {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Invalid JSON request",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(400);
            try res.sendJson(err_json);
            return;
        };
        defer edit_req.deinit();

        // Get server instance
        global_mutex.lock();
        const server = global_server;
        global_mutex.unlock();

        if (server == null) {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Server not initialized",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        }

        // Get instruction (supports both "instruction" and "prompt" fields)
        const instruction = edit_req.value.prompt orelse edit_req.value.instruction;

        // Determine if we're using MCP (file-based) or direct code
        const use_mcp = edit_req.value.file != null;
        const dry_run = edit_req.value.dry_run orelse false;

        // Get original code (either from MCP or request body)
        var original_code: []const u8 = undefined;
        var code_from_mcp = false;
        var mcp_read_start: i64 = 0;

        if (use_mcp and server.?.smart_router.mcp_client != null) {
            // Use MCP to read file
            const file_path = edit_req.value.file.?;
            mcp_read_start = std.time.milliTimestamp();

            const mcp_result = server.?.smart_router.mcp_client.?.readFile(file_path) catch |err| {
                std.log.err("MCP fs.read failed: {}", .{err});
                const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                    .@"error" = "Failed to read file via MCP",
                    .code = @errorName(err),
                }, .{});
                defer allocator.free(err_json);
                res.setStatus(500);
                try res.sendJson(err_json);
                return;
            };
            defer mcp_result.deinit();

            if (mcp_result.is_error) {
                const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                    .@"error" = "MCP tool returned error",
                    .code = mcp_result.content,
                }, .{});
                defer allocator.free(err_json);
                res.setStatus(500);
                try res.sendJson(err_json);
                return;
            }

            original_code = try allocator.dupe(u8, mcp_result.content);
            code_from_mcp = true;

            // Record MCP tool call
            const mcp_read_end = std.time.milliTimestamp();
            if (server.?.smart_router.db) |db| {
                db.recordToolCall(.{
                    .tool_name = "fs.read",
                    .service = "glyph",
                    .latency_ms = @intCast(mcp_read_end - mcp_read_start),
                    .success = true,
                    .created_at = std.time.timestamp(),
                }) catch |err| {
                    std.log.warn("Failed to record tool call: {}", .{err});
                };
            }
        } else if (edit_req.value.code) |code| {
            original_code = code;
        } else {
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Must provide either 'code' or 'file'",
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(400);
            try res.sendJson(err_json);
            return;
        }
        defer if (code_from_mcp) allocator.free(original_code);

        // Build prompt for code editing
        const prompt = try std.fmt.allocPrint(
            allocator,
            "Edit this code according to the instruction.\n\nOriginal code:\n```\n{s}\n```\n\nInstruction: {s}\n\nProvide only the edited code without explanations.",
            .{ original_code, instruction },
        );
        defer allocator.free(prompt);

        // Build completion request
        const completion_request = router.CompletionRequest{
            .prompt = prompt,
            .intent = "refactor",
            .language = edit_req.value.language,
            .complexity = "medium",
        };

        // Route and execute
        const completion_res = server.?.smart_router.complete(completion_request) catch |err| {
            std.log.err("Edit failed: {}", .{err});
            const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                .@"error" = "Edit request failed",
                .code = @errorName(err),
            }, .{});
            defer allocator.free(err_json);
            res.setStatus(500);
            try res.sendJson(err_json);
            return;
        };

        // Generate diff using MCP if available
        var diff_content: ?[]const u8 = null;
        if (server.?.smart_router.mcp_client) |mcp_client| {
            const diff_gen_start = std.time.milliTimestamp();

            if (mcp_client.generateDiff(original_code, completion_res.content)) |diff_result| {
                defer diff_result.deinit();

                if (!diff_result.is_error) {
                    diff_content = try allocator.dupe(u8, diff_result.content);

                    // Record tool call
                    const diff_gen_end = std.time.milliTimestamp();
                    if (server.?.smart_router.db) |db| {
                        db.recordToolCall(.{
                            .tool_name = "diff.generate",
                            .service = "glyph",
                            .latency_ms = @intCast(diff_gen_end - diff_gen_start),
                            .success = true,
                            .created_at = std.time.timestamp(),
                        }) catch |err| {
                            std.log.warn("Failed to record tool call: {}", .{err});
                        };
                    }
                }
            } else |err| {
                std.log.warn("MCP diff.generate failed: {}", .{err});
            }
        }
        defer if (diff_content) |dc| allocator.free(dc);

        // Apply diff if not dry_run and file path provided
        if (use_mcp and !dry_run and edit_req.value.file != null and diff_content != null) {
            if (server.?.smart_router.mcp_client) |mcp_client| {
                const apply_start = std.time.milliTimestamp();

                const apply_result = mcp_client.applyDiff(edit_req.value.file.?, diff_content.?) catch |err| {
                    std.log.err("MCP diff.apply failed: {}", .{err});
                    const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                        .@"error" = "Failed to apply diff",
                        .code = @errorName(err),
                    }, .{});
                    defer allocator.free(err_json);
                    res.setStatus(500);
                    try res.sendJson(err_json);
                    return;
                };
                defer apply_result.deinit();

                if (apply_result.is_error) {
                    const err_json = try std.json.Stringify.valueAlloc(allocator, .{
                        .@"error" = "MCP diff.apply returned error",
                        .code = apply_result.content,
                    }, .{});
                    defer allocator.free(err_json);
                    res.setStatus(500);
                    try res.sendJson(err_json);
                    return;
                }

                // Record tool call
                const apply_end = std.time.milliTimestamp();
                if (server.?.smart_router.db) |db| {
                    db.recordToolCall(.{
                        .tool_name = "diff.apply",
                        .service = "glyph",
                        .latency_ms = @intCast(apply_end - apply_start),
                        .success = true,
                        .created_at = std.time.timestamp(),
                    }) catch |err| {
                        std.log.warn("Failed to record tool call: {}", .{err});
                    };
                }
            }
        }

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .edited_code = completion_res.content,
            .diff = diff_content,
            .model = completion_res.model,
            .provider = completion_res.provider,
        }, .{});
        defer allocator.free(response_json);

        try res.sendJson(response_json);
    }

    fn handleStatus(_: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        // Simple status for now - TODO: integrate with router health checks
        const status_json =
            \\{
            \\  "status": "ok",
            \\  "providers": {
            \\    "ollama": "unknown",
            \\    "omen": "unknown"
            \\  },
            \\  "routing": {
            \\    "local_available": false,
            \\    "cloud_available": false
            \\  }
            \\}
        ;

        try res.sendJson(status_json);
    }
};

/// Test server initialization
pub fn testServer() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize providers
    var ollama_provider = try ollama.fromEnv(allocator);
    defer ollama_provider.deinit();

    var omen_client = try omen.fromEnv(allocator);
    defer omen_client.deinit();

    // Create smart router
    var smart_router = router.SmartRouter.init(
        allocator,
        &ollama_provider,
        &omen_client,
        null, // No DB for test
        router.defaultConfig(),
    );

    // Create server
    var server = try ZhttpServer.init(allocator, &smart_router, .{});
    defer server.deinit();

    std.debug.print("✅ Zhttp RPC server initialized successfully\n", .{});
}
