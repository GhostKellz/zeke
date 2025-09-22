const std = @import("std");
const api = @import("../api/client.zig");
const streaming = @import("../streaming/mod.zig");
const ghost_rpc = @import("ghost_rpc.zig");

const Zeke = @import("../root.zig").Zeke;

/// HTTP Server wrapper for GhostRPC - REST API for Zion integration
pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    ghost_rpc: ghost_rpc.GhostRPC,
    server: std.http.Server,
    port: u16,
    running: std.atomic.Value(bool),
    
    const Self = @This();
    
    pub const HttpRequest = struct {
        method: []const u8,
        path: []const u8,
        body: ?[]const u8 = null,
        headers: std.StringHashMap([]const u8),
    };
    
    pub const HttpResponse = struct {
        status: u16 = 200,
        body: []const u8,
        content_type: []const u8 = "application/json",
    };
    
    pub fn init(allocator: std.mem.Allocator, zeke_instance: *Zeke, port: u16) !Self {
        const ghost_rpc_instance = try ghost_rpc.GhostRPC.init(allocator, zeke_instance);
        
        return Self{
            .allocator = allocator,
            .ghost_rpc = ghost_rpc_instance,
            .server = std.http.Server.init(allocator, .{ .reuse_address = true }),
            .port = port,
            .running = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.ghost_rpc.deinit();
        self.server.deinit();
    }
    
    pub fn start(self: *Self) !void {
        const address = std.net.Address.initIp4([_]u8{127, 0, 0, 1}, self.port);
        try self.server.listen(address);
        
        self.running.store(true, .release);
        std.log.info("🌐 HTTP Server started on http://127.0.0.1:{}", .{self.port});
        
        while (self.running.load(.acquire)) {
            const connection = self.server.accept() catch |err| {
                std.log.err("Failed to accept connection: {}", .{err});
                continue;
            };
            
            // Handle request in a separate function
            self.handleConnection(connection) catch |err| {
                std.log.err("Error handling connection: {}", .{err});
            };
        }
    }
    
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
        std.log.info("🌐 HTTP Server stopped");
    }
    
    fn handleConnection(self: *Self, connection: std.http.Server.Connection) !void {
        defer connection.stream.close();
        
        var read_buffer: [8192]u8 = undefined;
        var server = std.http.Server.init(self.allocator, .{});
        defer server.deinit();
        
        var request = server.receiveHead(connection, &read_buffer) catch |err| {
            std.log.err("Failed to receive request head: {}", .{err});
            return;
        };
        
        // Read request body if present
        const body = if (request.head.content_length) |length| blk: {
            if (length > 0 and length < 1024 * 1024) { // 1MB limit
                const body_buffer = try self.allocator.alloc(u8, length);
                _ = try request.reader().readAll(body_buffer);
                break :blk body_buffer;
            }
            break :blk null;
        } else null;
        defer if (body) |b| self.allocator.free(b);
        
        // Route the request
        const response = try self.routeRequest(request.head.method, request.head.target, body);
        defer self.allocator.free(response.body);
        
        // Send response
        try request.respond(response.body, .{
            .status = @enumFromInt(response.status),
            .extra_headers = &[_]std.http.Header{
                .{ .name = "content-type", .value = response.content_type },
                .{ .name = "access-control-allow-origin", .value = "*" },
                .{ .name = "access-control-allow-methods", .value = "GET, POST, OPTIONS" },
                .{ .name = "access-control-allow-headers", .value = "Content-Type" },
            },
        });
    }
    
    fn routeRequest(self: *Self, method: std.http.Method, path: []const u8, body: ?[]const u8) !HttpResponse {
        // Handle CORS preflight
        if (method == .OPTIONS) {
            return HttpResponse{
                .status = 200,
                .body = try self.allocator.dupe(u8, ""),
                .content_type = "text/plain",
            };
        }
        
        // API routes
        if (std.mem.startsWith(u8, path, "/api/")) {
            return try self.handleApiRequest(method, path[5..], body);
        }
        
        // Default 404
        return HttpResponse{
            .status = 404,
            .body = try self.allocator.dupe(u8, "{\"error\":\"Not found\"}"),
        };
    }
    
    fn handleApiRequest(self: *Self, method: std.http.Method, path: []const u8, body: ?[]const u8) !HttpResponse {
        if (method != .POST) {
            return HttpResponse{
                .status = 405,
                .body = try self.allocator.dupe(u8, "{\"error\":\"Method not allowed\"}"),
            };
        }
        
        const request_body = body orelse return HttpResponse{
            .status = 400,
            .body = try self.allocator.dupe(u8, "{\"error\":\"Request body required\"}"),
        };
        
        // Convert HTTP request to JSON-RPC request
        const rpc_request = try self.httpToRpcRequest(path, request_body);
        defer self.allocator.free(rpc_request);
        
        // Process via existing RPC handler
        const rpc_response = try self.processRpcRequest(rpc_request);
        defer self.allocator.free(rpc_response);
        
        // Convert RPC response to HTTP response
        return try self.rpcToHttpResponse(rpc_response);
    }
    
    fn httpToRpcRequest(self: *Self, path: []const u8, body: []const u8) ![]u8 {
        // Parse JSON body
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
        defer parsed.deinit();
        
        // Create JSON-RPC request
        var rpc_request = std.json.ObjectMap.init(self.allocator);
        defer rpc_request.deinit();
        
        try rpc_request.put("jsonrpc", std.json.Value{ .string = "2.0" });
        try rpc_request.put("method", std.json.Value{ .string = path });
        try rpc_request.put("params", parsed.value);
        try rpc_request.put("id", std.json.Value{ .integer = 1 });
        
        return try std.json.stringifyAlloc(self.allocator, std.json.Value{ .object = rpc_request }, .{});
    }
    
    fn processRpcRequest(self: *Self, request: []const u8) ![]u8 {
        // Parse the JSON-RPC request
        const parsed = try std.json.parseFromSlice(ghost_rpc.GhostRPC.Request, self.allocator, request, .{});
        defer parsed.deinit();
        
        // Create a mock response for now - in full implementation this would 
        // call the actual RPC handler methods
        var response = std.json.ObjectMap.init(self.allocator);
        defer response.deinit();
        
        try response.put("jsonrpc", std.json.Value{ .string = "2.0" });
        try response.put("id", std.json.Value{ .integer = 1 });
        
        if (std.mem.eql(u8, parsed.value.method, "chat")) {
            try response.put("result", std.json.Value{ .string = "HTTP chat response" });
        } else if (std.mem.eql(u8, parsed.value.method, "project_analyze")) {
            var result = std.json.ObjectMap.init(self.allocator);
            try result.put("dependencies", std.json.Value{ .array = std.json.Array.init(self.allocator) });
            try result.put("build_config", std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) });
            try response.put("result", std.json.Value{ .object = result });
        } else {
            try response.put("result", std.json.Value{ .string = "HTTP API response" });
        }
        
        return try std.json.stringifyAlloc(self.allocator, std.json.Value{ .object = response }, .{});
    }
    
    fn rpcToHttpResponse(self: *Self, rpc_response: []const u8) !HttpResponse {
        // Parse JSON-RPC response
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, rpc_response, .{});
        defer parsed.deinit();
        
        if (parsed.value == .object and parsed.value.object.get("error")) |error_value| {
            return HttpResponse{
                .status = 400,
                .body = try std.json.stringifyAlloc(self.allocator, error_value, .{}),
            };
        }
        
        if (parsed.value == .object and parsed.value.object.get("result")) |result| {
            return HttpResponse{
                .status = 200,
                .body = try std.json.stringifyAlloc(self.allocator, result, .{}),
            };
        }
        
        return HttpResponse{
            .status = 500,
            .body = try self.allocator.dupe(u8, "{\"error\":\"Invalid RPC response\"}"),
        };
    }
};