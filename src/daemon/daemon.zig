// Zeke Daemon - Background service for fast LSP/index queries
// Uses Unix domain sockets for IPC

const std = @import("std");
const lsp = @import("../lsp/lsp.zig");
const index = @import("../index/index.zig");
const lifecycle = @import("lifecycle.zig");

pub const SOCKET_PATH = "/tmp/zeke.sock";
pub const PID_FILE_PATH = "/tmp/zeke.pid";

/// Daemon state
pub const Daemon = struct {
    allocator: std.mem.Allocator,
    lsp_manager: *lsp.LspManager,
    socket_path: []const u8,
    lifecycle_manager: lifecycle.LifecycleManager,

    pub fn init(allocator: std.mem.Allocator) !*Daemon {
        const daemon = try allocator.create(Daemon);

        const lsp_mgr = try allocator.create(lsp.LspManager);
        lsp_mgr.* = try lsp.LspManager.init(allocator);

        daemon.* = .{
            .allocator = allocator,
            .lsp_manager = lsp_mgr,
            .socket_path = SOCKET_PATH,
            .lifecycle_manager = try lifecycle.LifecycleManager.init(allocator, PID_FILE_PATH),
        };

        return daemon;
    }

    pub fn deinit(self: *Daemon) void {
        if (!self.lifecycle_manager.shouldShutdown()) {
            self.stop() catch {};
        }
        self.lsp_manager.deinit();
        self.allocator.destroy(self.lsp_manager);
        self.lifecycle_manager.deinit();
        self.allocator.destroy(self);
    }

    /// Start the daemon server
    pub fn start(self: *Daemon) !void {
        // Start lifecycle manager (creates PID file, checks for existing daemon)
        try self.lifecycle_manager.start();

        std.debug.print("🚀 Starting Zeke daemon on {s}\n", .{self.socket_path});

        // Remove old socket if exists
        std.fs.cwd().deleteFile(self.socket_path) catch {};

        // Create Unix domain socket
        const address = try std.net.Address.initUnix(self.socket_path);
        var server = try address.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        std.debug.print("✓ Daemon listening on {s}\n", .{self.socket_path});
        std.debug.print("  Use 'zeke daemon stop' to shut down\n\n", .{});

        // Accept connections
        while (!self.lifecycle_manager.shouldShutdown()) {
            const connection = server.accept() catch |err| {
                std.debug.print("Accept error: {}\n", .{err});
                continue;
            };

            // Handle connection in a new thread
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, connection });
            thread.detach();
        }
    }

    /// Stop the daemon
    pub fn stop(self: *Daemon) !void {
        std.debug.print("Stopping daemon...\n", .{});
        self.lifecycle_manager.requestShutdown();

        // Shutdown all LSP servers
        try self.lsp_manager.shutdownAll();

        // Stop lifecycle manager (removes PID file)
        try self.lifecycle_manager.stop();

        // Clean up socket
        std.fs.cwd().deleteFile(self.socket_path) catch {};
    }

    /// Get daemon health status
    pub fn getHealthStatus(self: *Daemon) !lifecycle.LifecycleManager.HealthStatus {
        return try self.lifecycle_manager.getHealthStatus();
    }

    /// Handle a client connection
    fn handleConnection(self: *Daemon, connection: std.net.Server.Connection) void {
        defer connection.stream.close();

        var buf: [8192]u8 = undefined;
        const n = connection.stream.read(&buf) catch |err| {
            std.debug.print("Read error: {}\n", .{err});
            return;
        };

        if (n == 0) return;

        const request = buf[0..n];

        // Parse request JSON
        const response = self.handleRequest(request) catch |err| {
            std.debug.print("Handle error: {}\n", .{err});
            return;
        };
        defer self.allocator.free(response);

        // Send response
        _ = connection.stream.write(response) catch |err| {
            std.debug.print("Write error: {}\n", .{err});
            return;
        };
    }

    /// Handle a request and return response JSON
    fn handleRequest(self: *Daemon, request: []const u8) ![]const u8 {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, request, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        const method = obj.get("method") orelse return error.MissingMethod;

        if (method != .string) return error.InvalidMethod;

        // Route to appropriate handler
        if (std.mem.eql(u8, method.string, "lsp/diagnostics")) {
            return try self.handleLspDiagnostics(obj);
        } else if (std.mem.eql(u8, method.string, "lsp/hover")) {
            return try self.handleLspHover(obj);
        } else if (std.mem.eql(u8, method.string, "lsp/definition")) {
            return try self.handleLspDefinition(obj);
        } else if (std.mem.eql(u8, method.string, "lsp/references")) {
            return try self.handleLspReferences(obj);
        } else if (std.mem.eql(u8, method.string, "index/search")) {
            return try self.handleIndexSearch(obj);
        } else if (std.mem.eql(u8, method.string, "health")) {
            return try self.handleHealth();
        } else if (std.mem.eql(u8, method.string, "ping")) {
            return try self.handlePing();
        } else if (std.mem.eql(u8, method.string, "shutdown")) {
            return try self.handleShutdown();
        }

        return error.UnknownMethod;
    }

    fn handleLspDiagnostics(self: *Daemon, params: std.json.ObjectMap) ![]const u8 {
        const file_uri = params.get("file_uri") orelse return error.MissingFileUri;
        const root_path = params.get("root_path") orelse return error.MissingRootPath;

        if (file_uri != .string or root_path != .string) return error.InvalidParams;

        const diagnostics = try self.lsp_manager.getDiagnosticsForFile(
            file_uri.string,
            root_path.string,
        );
        defer self.allocator.free(diagnostics);

        // Serialize diagnostics to JSON
        return try serializeDiagnostics(self.allocator, diagnostics);
    }

    fn handleLspHover(self: *Daemon, params: std.json.ObjectMap) ![]const u8 {
        const file_uri = params.get("file_uri") orelse return error.MissingFileUri;
        const root_path = params.get("root_path") orelse return error.MissingRootPath;
        const line = params.get("line") orelse return error.MissingLine;
        const character = params.get("character") orelse return error.MissingCharacter;

        if (file_uri != .string or root_path != .string) return error.InvalidParams;
        if (line != .integer or character != .integer) return error.InvalidParams;

        const hover = try self.lsp_manager.getHoverForPosition(
            file_uri.string,
            root_path.string,
            @intCast(line.integer),
            @intCast(character.integer),
        );

        if (hover) |h| {
            defer {
                var mut_h = h;
                mut_h.deinit(self.allocator);
            }
            return try serializeHover(self.allocator, h);
        }

        return try self.allocator.dupe(u8, "{\"result\":null}");
    }

    fn handleLspDefinition(self: *Daemon, params: std.json.ObjectMap) ![]const u8 {
        const file_uri = params.get("file_uri") orelse return error.MissingFileUri;
        const root_path = params.get("root_path") orelse return error.MissingRootPath;
        const line = params.get("line") orelse return error.MissingLine;
        const character = params.get("character") orelse return error.MissingCharacter;

        if (file_uri != .string or root_path != .string) return error.InvalidParams;
        if (line != .integer or character != .integer) return error.InvalidParams;

        const locations = try self.lsp_manager.getDefinitionForPosition(
            file_uri.string,
            root_path.string,
            @intCast(line.integer),
            @intCast(character.integer),
        );

        if (locations) |locs| {
            defer {
                for (locs) |loc| {
                    self.allocator.free(loc.uri);
                }
                self.allocator.free(locs);
            }
            return try serializeLocations(self.allocator, locs);
        }

        return try self.allocator.dupe(u8, "{\"result\":null}");
    }

    fn handleLspReferences(self: *Daemon, params: std.json.ObjectMap) ![]const u8 {
        const file_uri = params.get("file_uri") orelse return error.MissingFileUri;
        const root_path = params.get("root_path") orelse return error.MissingRootPath;
        const line = params.get("line") orelse return error.MissingLine;
        const character = params.get("character") orelse return error.MissingCharacter;

        if (file_uri != .string or root_path != .string) return error.InvalidParams;
        if (line != .integer or character != .integer) return error.InvalidParams;

        const include_declaration = if (params.get("includeDeclaration")) |v|
            if (v == .bool) v.bool else false
        else
            false;

        const locations = try self.lsp_manager.getReferencesForPosition(
            file_uri.string,
            root_path.string,
            @intCast(line.integer),
            @intCast(character.integer),
            include_declaration,
        );

        if (locations) |locs| {
            defer {
                for (locs) |loc| {
                    self.allocator.free(loc.uri);
                }
                self.allocator.free(locs);
            }
            return try serializeLocations(self.allocator, locs);
        }

        return try self.allocator.dupe(u8, "{\"result\":null}");
    }

    fn handleIndexSearch(self: *Daemon, params: std.json.ObjectMap) ![]const u8 {
        _ = params;
        // TODO: Implement index search
        return try self.allocator.dupe(u8, "{\"result\":[]}");
    }

    fn handleHealth(self: *Daemon) ![]const u8 {
        const status = try self.getHealthStatus();
        return try status.toJson(self.allocator);
    }

    fn handlePing(self: *Daemon) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{{\"result\":\"pong\"}}", .{});
    }

    fn handleShutdown(self: *Daemon) ![]const u8 {
        self.lifecycle_manager.requestShutdown();
        return try std.fmt.allocPrint(self.allocator, "{{\"result\":\"shutting down\"}}", .{});
    }
};

/// Serialize diagnostics to JSON
fn serializeDiagnostics(allocator: std.mem.Allocator, diagnostics: []const lsp.Diagnostic) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{ .writer = &out.writer };

    try stringify.beginObject();
    try stringify.objectField("result");
    try stringify.beginArray();

    for (diagnostics) |diag| {
        try stringify.beginObject();

        try stringify.objectField("range");
        try stringify.beginObject();
        try stringify.objectField("start");
        try stringify.beginObject();
        try stringify.objectField("line");
        try stringify.write(diag.range.start.line);
        try stringify.objectField("character");
        try stringify.write(diag.range.start.character);
        try stringify.endObject();

        try stringify.objectField("end");
        try stringify.beginObject();
        try stringify.objectField("line");
        try stringify.write(diag.range.end.line);
        try stringify.objectField("character");
        try stringify.write(diag.range.end.character);
        try stringify.endObject();
        try stringify.endObject();

        if (diag.severity) |sev| {
            try stringify.objectField("severity");
            try stringify.write(@intFromEnum(sev));
        }

        try stringify.objectField("message");
        try stringify.write(diag.message);

        if (diag.source) |src| {
            try stringify.objectField("source");
            try stringify.write(src);
        }

        try stringify.endObject();
    }

    try stringify.endArray();
    try stringify.endObject();

    return allocator.dupe(u8, out.written());
}

/// Serialize hover to JSON
fn serializeHover(allocator: std.mem.Allocator, hover: lsp.Hover) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{ .writer = &out.writer };

    try stringify.beginObject();
    try stringify.objectField("result");
    try stringify.beginObject();
    try stringify.objectField("contents");
    try stringify.write(hover.contents);
    try stringify.endObject();
    try stringify.endObject();

    return allocator.dupe(u8, out.written());
}

/// Serialize locations to JSON
fn serializeLocations(allocator: std.mem.Allocator, locations: []const lsp.Location) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{ .writer = &out.writer };

    try stringify.beginObject();
    try stringify.objectField("result");
    try stringify.beginArray();

    for (locations) |loc| {
        try stringify.beginObject();
        try stringify.objectField("uri");
        try stringify.write(loc.uri);

        try stringify.objectField("range");
        try stringify.beginObject();

        try stringify.objectField("start");
        try stringify.beginObject();
        try stringify.objectField("line");
        try stringify.write(loc.range.start.line);
        try stringify.objectField("character");
        try stringify.write(loc.range.start.character);
        try stringify.endObject();

        try stringify.objectField("end");
        try stringify.beginObject();
        try stringify.objectField("line");
        try stringify.write(loc.range.end.line);
        try stringify.objectField("character");
        try stringify.write(loc.range.end.character);
        try stringify.endObject();

        try stringify.endObject(); // range
        try stringify.endObject(); // location
    }

    try stringify.endArray();
    try stringify.endObject();

    return allocator.dupe(u8, out.written());
}
