const std = @import("std");
const zeke = @import("zeke");
const router = zeke.routing;
const ZhttpServer = zeke.rpc.ZhttpServer;
const ollama = zeke.providers.ollama;
const omen = zeke.providers.omen;
const routing_db = zeke.db;

pub const ServeOptions = struct {
    port: u16 = 7878,
    host: []const u8 = "127.0.0.1",
    verbose: bool = false,
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var options = ServeOptions{};

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            if (i + 1 < args.len) {
                i += 1;
                options.port = try std.fmt.parseInt(u16, args[i], 10);
            }
        } else if (std.mem.eql(u8, arg, "--host") or std.mem.eql(u8, arg, "-h")) {
            if (i + 1 < args.len) {
                i += 1;
                options.host = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        }
    }

    std.log.info("🚀 Starting Zeke RPC Server...", .{});
    if (options.verbose) {
        std.log.info("  Host: {s}", .{options.host});
        std.log.info("  Port: {}", .{options.port});
    }

    // Initialize providers
    var ollama_provider = ollama.fromEnv(allocator) catch |err| {
        std.log.warn("⚠️  Failed to initialize Ollama: {}", .{err});
        std.log.warn("  Continuing without local Ollama support", .{});
        return error.OllamaInitFailed;
    };
    defer ollama_provider.deinit();

    var omen_client = omen.fromEnv(allocator) catch |err| {
        std.log.warn("⚠️  Failed to initialize OMEN: {}", .{err});
        std.log.warn("  Continuing without OMEN cloud routing", .{});
        return error.OmenInitFailed;
    };
    defer omen_client.deinit();

    // Initialize routing database
    const db_path = try getDbPath(allocator);
    defer allocator.free(db_path);

    var db = try routing_db.RoutingDB.init(allocator, db_path);
    defer db.deinit();

    if (options.verbose) {
        std.log.info("  Database: {s}", .{db_path});
    }

    // Create smart router
    var smart_router = router.SmartRouter.init(
        allocator,
        &ollama_provider,
        &omen_client,
        &db,
        router.RoutingConfig{},
    );

    // Create and start server
    var server = ZhttpServer.init(allocator, &smart_router, .{
        .port = options.port,
        .host = options.host,
    });
    defer server.deinit();

    std.log.info("✅ Zeke RPC Server ready", .{});
    std.log.info("", .{});
    std.log.info("  Endpoints:", .{});
    std.log.info("    • Health:   http://{s}:{}/health", .{ options.host, options.port });
    std.log.info("    • Chat:     http://{s}:{}/api/chat", .{ options.host, options.port });
    std.log.info("    • Complete: http://{s}:{}/api/complete", .{ options.host, options.port });
    std.log.info("    • Explain:  http://{s}:{}/api/explain", .{ options.host, options.port });
    std.log.info("    • Edit:     http://{s}:{}/api/edit", .{ options.host, options.port });
    std.log.info("    • Status:   http://{s}:{}/api/status", .{ options.host, options.port });
    std.log.info("", .{});
    std.log.info("Press Ctrl+C to stop", .{});
    std.log.info("", .{});

    try server.start();
}

fn getDbPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const db_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/zeke", .{home});
    defer allocator.free(db_dir);

    // Ensure directory exists
    std.fs.makeDirAbsolute(db_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    return try std.fmt.allocPrint(allocator, "{s}/routing.db", .{db_dir});
}
