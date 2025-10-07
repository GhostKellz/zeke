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
    code: []const u8,
    instruction: []const u8,
    language: ?[]const u8 = null,
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

        // Get smart router from context (TODO: pass via context)
        // For now, this is a stub - we need to refactor to pass router via handler context
        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .response = "Chat handler with smart routing - implementation in progress",
            .model = "test-model",
            .provider = "test-provider",
            .tokens_in = 0,
            .tokens_out = 0,
            .latency_ms = 0,
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

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .completion = "Code completion via smart routing - implementation in progress",
            .model = "test-model",
            .provider = "test-provider",
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

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .explanation = "Code explanation via smart routing - implementation in progress",
            .model = "test-model",
            .provider = "test-provider",
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

        const response_json = try std.json.Stringify.valueAlloc(allocator, .{
            .edited_code = "Edited code via smart routing - implementation in progress",
            .diff = null,
            .model = "test-model",
            .provider = "test-provider",
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
