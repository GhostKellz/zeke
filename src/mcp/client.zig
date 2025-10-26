const std = @import("std");
const config = @import("../config/mod.zig");

/// MCP (Model Context Protocol) Client
/// Communicates with MCP servers like Glyph for file operations and tools
pub const McpClient = struct {
    allocator: std.mem.Allocator,
    transport: Transport,
    next_request_id: std.atomic.Value(u64),

    const Self = @This();

    /// Transport layer for MCP communication
    pub const Transport = union(enum) {
        stdio: StdioTransport,
        websocket: WebSocketTransport,

        pub fn deinit(self: *Transport) void {
            switch (self.*) {
                .stdio => |*stdio| stdio.deinit(),
                .websocket => |*ws| ws.deinit(),
            }
        }
    };

    /// Stdio transport spawns a child process and communicates via stdin/stdout
    pub const StdioTransport = struct {
        allocator: std.mem.Allocator,
        process: std.process.Child,
        stdin: std.fs.File,
        stdout: std.fs.File,
        read_buffer: std.ArrayList(u8),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, command: []const u8, args: []const []const u8) !StdioTransport {
            // Build argv with command + args
            const ArgList = std.ArrayList([]const u8);
            var argv = ArgList.empty;
            defer argv.deinit(allocator);

            try argv.append(allocator, command);
            for (args) |arg| {
                try argv.append(allocator, arg);
            }

            var process = std.process.Child.init(argv.items, allocator);
            process.stdin_behavior = .Pipe;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;

            try process.spawn();

            return StdioTransport{
                .allocator = allocator,
                .process = process,
                .stdin = process.stdin.?,
                .stdout = process.stdout.?,
                .read_buffer = std.ArrayList(u8).empty,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *StdioTransport) void {
            self.read_buffer.deinit(self.allocator);
            _ = self.process.kill() catch {};
        }

        pub fn send(self: *StdioTransport, message: []const u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Write JSON-RPC message with newline delimiter
            try self.stdin.writeAll(message);
            try self.stdin.writeAll("\n");
        }

        pub fn receive(self: *StdioTransport) ![]const u8 {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Read until newline
            self.read_buffer.clearRetainingCapacity();

            // Read byte by byte until newline
            var byte: [1]u8 = undefined;
            while (true) {
                const n = try self.stdout.read(&byte);
                if (n == 0) return error.EndOfStream;
                if (byte[0] == '\n') break;
                try self.read_buffer.append(self.allocator, byte[0]);
            }

            return self.read_buffer.items;
        }
    };

    /// WebSocket transport for persistent MCP connections
    pub const WebSocketTransport = struct {
        allocator: std.mem.Allocator,
        url: []const u8,
        stream: ?std.net.Stream = null,
        http_client: std.http.Client,
        read_buffer: std.ArrayList(u8),
        write_buffer: std.ArrayList(u8),
        mutex: std.Thread.Mutex,
        connected: bool = false,

        pub fn init(allocator: std.mem.Allocator, url: []const u8) !WebSocketTransport {
            return WebSocketTransport{
                .allocator = allocator,
                .url = try allocator.dupe(u8, url),
                .http_client = std.http.Client{ .allocator = allocator },
                .read_buffer = std.ArrayList(u8).empty,
                .write_buffer = std.ArrayList(u8).empty,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *WebSocketTransport) void {
            self.disconnect();
            self.http_client.deinit();
            self.read_buffer.deinit(self.allocator);
            self.write_buffer.deinit(self.allocator);
            self.allocator.free(self.url);
        }

        pub fn connect(self: *WebSocketTransport) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.connected) return;

            // Parse URL to extract host and path
            const uri = try std.Uri.parse(self.url);
            const host_component = uri.host orelse return error.InvalidUrl;
            const port = uri.port orelse (if (std.mem.startsWith(u8, self.url, "wss://")) @as(u16, 443) else @as(u16, 80));

            // Extract host string from Component union
            const host: []const u8 = switch (host_component) {
                .raw => |h| h,
                .percent_encoded => |h| h,
            };

            // Get path from URI
            const path: []const u8 = switch (uri.path) {
                .raw => |p| if (p.len > 0) p else "/",
                .percent_encoded => |p| if (p.len > 0) p else "/",
            };

            // Connect TCP socket
            const address = try std.net.Address.parseIp(host, port);
            self.stream = try std.net.tcpConnectToAddress(address);

            // Send WebSocket upgrade request
            const upgrade_request = try std.fmt.allocPrint(
                self.allocator,
                "GET {s} HTTP/1.1\r\n" ++
                    "Host: {s}:{d}\r\n" ++
                    "Upgrade: websocket\r\n" ++
                    "Connection: Upgrade\r\n" ++
                    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
                    "Sec-WebSocket-Version: 13\r\n" ++
                    "\r\n",
                .{ path, host, port },
            );
            defer self.allocator.free(upgrade_request);

            try self.stream.?.writeAll(upgrade_request);

            // Read upgrade response (simplified - should validate properly)
            var response_buf: [1024]u8 = undefined;
            const n = try self.stream.?.read(&response_buf);
            if (n == 0) return error.ConnectionClosed;

            // Check for 101 Switching Protocols
            if (!std.mem.containsAtLeast(u8, response_buf[0..n], 1, "101")) {
                return error.WebSocketUpgradeFailed;
            }

            self.connected = true;
            std.log.info("WebSocket connected to {s}", .{self.url});
        }

        pub fn disconnect(self: *WebSocketTransport) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.stream) |stream| {
                stream.close();
                self.stream = null;
            }
            self.connected = false;
        }

        pub fn send(self: *WebSocketTransport, message: []const u8) !void {
            if (!self.connected) try self.connect();

            self.mutex.lock();
            defer self.mutex.unlock();

            // Build WebSocket frame
            self.write_buffer.clearRetainingCapacity();

            // FIN + text frame (0x81)
            try self.write_buffer.append(self.allocator, 0x81);

            // Payload length with masking bit
            if (message.len < 126) {
                try self.write_buffer.append(self.allocator, @as(u8, @intCast(message.len)) | 0x80);
            } else if (message.len < 65536) {
                try self.write_buffer.append(self.allocator, 126 | 0x80);
                try self.write_buffer.append(self.allocator, @as(u8, @intCast(message.len >> 8)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast(message.len & 0xFF)));
            } else {
                try self.write_buffer.append(self.allocator, 127 | 0x80);
                const len = message.len;
                try self.write_buffer.append(self.allocator, @as(u8, @intCast(len >> 56)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 48) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 40) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 32) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 24) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 16) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast((len >> 8) & 0xFF)));
                try self.write_buffer.append(self.allocator, @as(u8, @intCast(len & 0xFF)));
            }

            // Masking key (random 4 bytes)
            var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
            const mask_key = [4]u8{
                rng.random().int(u8),
                rng.random().int(u8),
                rng.random().int(u8),
                rng.random().int(u8),
            };
            try self.write_buffer.appendSlice(self.allocator, &mask_key);

            // Masked payload
            for (message, 0..) |byte, i| {
                try self.write_buffer.append(self.allocator, byte ^ mask_key[i % 4]);
            }

            // Send frame
            try self.stream.?.writeAll(self.write_buffer.items);
        }

        pub fn receive(self: *WebSocketTransport) ![]const u8 {
            if (!self.connected) return error.NotConnected;

            self.mutex.lock();
            defer self.mutex.unlock();

            self.read_buffer.clearRetainingCapacity();

            // Read WebSocket frame header
            var header: [2]u8 = undefined;
            const n = try self.stream.?.readAtLeast(&header, 2);
            if (n < 2) return error.ConnectionClosed;

            const fin = (header[0] & 0x80) != 0;
            const opcode = header[0] & 0x0F;
            const masked = (header[1] & 0x80) != 0;
            var payload_len: u64 = header[1] & 0x7F;

            // Handle extended payload length
            if (payload_len == 126) {
                var len_bytes: [2]u8 = undefined;
                _ = try self.stream.?.readAtLeast(&len_bytes, 2);
                payload_len = (@as(u64, len_bytes[0]) << 8) | @as(u64, len_bytes[1]);
            } else if (payload_len == 127) {
                var len_bytes: [8]u8 = undefined;
                _ = try self.stream.?.readAtLeast(&len_bytes, 8);
                payload_len = (@as(u64, len_bytes[0]) << 56) |
                    (@as(u64, len_bytes[1]) << 48) |
                    (@as(u64, len_bytes[2]) << 40) |
                    (@as(u64, len_bytes[3]) << 32) |
                    (@as(u64, len_bytes[4]) << 24) |
                    (@as(u64, len_bytes[5]) << 16) |
                    (@as(u64, len_bytes[6]) << 8) |
                    @as(u64, len_bytes[7]);
            }

            // Read masking key if present
            var mask_key: [4]u8 = undefined;
            if (masked) {
                _ = try self.stream.?.readAtLeast(&mask_key, 4);
            }

            // Read payload
            const payload = try self.allocator.alloc(u8, @intCast(payload_len));
            defer self.allocator.free(payload);
            _ = try self.stream.?.readAtLeast(payload, @intCast(payload_len));

            // Unmask if needed
            if (masked) {
                for (payload, 0..) |*byte, i| {
                    byte.* ^= mask_key[i % 4];
                }
            }

            // Handle different frame types
            switch (opcode) {
                0x1 => { // Text frame
                    if (fin) {
                        try self.read_buffer.appendSlice(self.allocator, payload);
                        return self.read_buffer.items;
                    } else {
                        // TODO: Handle fragmented messages
                        try self.read_buffer.appendSlice(self.allocator, payload);
                        return self.receive(); // Read next frame
                    }
                },
                0x8 => { // Close frame
                    self.disconnect();
                    return error.ConnectionClosed;
                },
                0x9 => { // Ping frame
                    // Send pong
                    try self.sendPong(payload);
                    return self.receive(); // Read next frame
                },
                0xA => { // Pong frame
                    return self.receive(); // Ignore pong, read next frame
                },
                else => {
                    std.log.warn("Unknown WebSocket opcode: 0x{x}", .{opcode});
                    return error.UnknownOpcode;
                },
            }
        }

        fn sendPong(self: *WebSocketTransport, payload: []const u8) !void {
            self.write_buffer.clearRetainingCapacity();

            // FIN + pong frame (0x8A)
            try self.write_buffer.append(self.allocator, 0x8A);
            try self.write_buffer.append(self.allocator, @as(u8, @intCast(payload.len)) | 0x80);

            // Masking key
            var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
            const mask_key = [4]u8{
                rng.random().int(u8),
                rng.random().int(u8),
                rng.random().int(u8),
                rng.random().int(u8),
            };
            try self.write_buffer.appendSlice(self.allocator, &mask_key);

            // Masked payload
            for (payload, 0..) |byte, i| {
                try self.write_buffer.append(self.allocator, byte ^ mask_key[i % 4]);
            }

            try self.stream.?.writeAll(self.write_buffer.items);
        }
    };

    /// JSON-RPC request structure
    pub const JsonRpcRequest = struct {
        jsonrpc: []const u8 = "2.0",
        id: u64,
        method: []const u8,
        params: ?std.json.Value = null,
    };

    /// JSON-RPC response structure
    pub const JsonRpcResponse = struct {
        jsonrpc: []const u8,
        id: u64,
        result: ?std.json.Value = null,
        @"error": ?JsonRpcError = null,
    };

    pub const JsonRpcError = struct {
        code: i32,
        message: []const u8,
        data: ?std.json.Value = null,
    };

    /// Tool call result
    pub const ToolResult = struct {
        allocator: std.mem.Allocator,
        content: []const u8,
        is_error: bool = false,

        pub fn deinit(self: ToolResult) void {
            self.allocator.free(self.content);
        }
    };

    /// Initialize MCP client from configuration
    pub fn initFromConfig(allocator: std.mem.Allocator, cfg: config.ServiceConfig.GlyphConfig) !Self {
        const transport = switch (cfg.mcp) {
            .stdio => |stdio_cfg| Transport{
                .stdio = try StdioTransport.init(allocator, stdio_cfg.command, stdio_cfg.args),
            },
            .websocket => |ws_cfg| Transport{
                .websocket = try WebSocketTransport.init(allocator, ws_cfg.url),
            },
            .docker => |_| {
                std.log.err("Docker transport not yet implemented", .{});
                return error.DockerTransportNotImplemented;
            },
        };

        return Self{
            .allocator = allocator,
            .transport = transport,
            .next_request_id = std.atomic.Value(u64).init(1),
        };
    }

    pub fn deinit(self: *Self) void {
        self.transport.deinit();
    }

    /// Call a tool on the MCP server
    pub fn callTool(self: *Self, _: []const u8, arguments: std.json.Value) !ToolResult {
        const request_id = self.next_request_id.fetchAdd(1, .monotonic);

        // Build JSON-RPC request
        const request = JsonRpcRequest{
            .id = request_id,
            .method = "tools/call",
            .params = arguments,
        };

        const request_json = try std.json.Stringify.valueAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        // Send request
        switch (self.transport) {
            .stdio => |*stdio| try stdio.send(request_json),
            .websocket => |*ws| try ws.send(request_json),
        }

        // Receive response
        const response_json = switch (self.transport) {
            .stdio => |*stdio| try stdio.receive(),
            .websocket => |*ws| try ws.receive(),
        };

        // Parse response
        const parsed = try std.json.parseFromSlice(JsonRpcResponse, self.allocator, response_json, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const response = parsed.value;

        // Check for errors
        if (response.@"error") |err| {
            std.log.err("MCP tool call error: {s}", .{err.message});
            return ToolResult{
                .allocator = self.allocator,
                .content = try self.allocator.dupe(u8, err.message),
                .is_error = true,
            };
        }

        // Extract result
        if (response.result) |result| {
            const result_str = try std.json.Stringify.valueAlloc(self.allocator, result, .{});
            return ToolResult{
                .allocator = self.allocator,
                .content = result_str,
                .is_error = false,
            };
        }

        return error.MissingResult;
    }

    /// Helper: Read file via Glyph
    pub fn readFile(self: *Self, path: []const u8) !ToolResult {
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        try params.put("name", .{ .string = "fs.read" });

        var arguments = std.json.ObjectMap.init(self.allocator);
        defer arguments.deinit();
        try arguments.put("path", .{ .string = path });

        try params.put("arguments", .{ .object = arguments });

        return try self.callTool("fs.read", .{ .object = params });
    }

    /// Helper: Write file via Glyph
    pub fn writeFile(self: *Self, path: []const u8, content: []const u8) !ToolResult {
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        try params.put("name", .{ .string = "fs.write" });

        var arguments = std.json.ObjectMap.init(self.allocator);
        defer arguments.deinit();
        try arguments.put("path", .{ .string = path });
        try arguments.put("content", .{ .string = content });

        try params.put("arguments", .{ .object = arguments });

        return try self.callTool("fs.write", .{ .object = params });
    }

    /// Helper: List directory via Glyph
    pub fn listDirectory(self: *Self, path: []const u8) !ToolResult {
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        try params.put("name", .{ .string = "fs.list" });

        var arguments = std.json.ObjectMap.init(self.allocator);
        defer arguments.deinit();
        try arguments.put("path", .{ .string = path });

        try params.put("arguments", .{ .object = arguments });

        return try self.callTool("fs.list", .{ .object = params });
    }

    /// Helper: Apply diff via Glyph
    pub fn applyDiff(self: *Self, path: []const u8, diff: []const u8) !ToolResult {
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        try params.put("name", .{ .string = "diff.apply" });

        var arguments = std.json.ObjectMap.init(self.allocator);
        defer arguments.deinit();
        try arguments.put("path", .{ .string = path });
        try arguments.put("diff", .{ .string = diff });

        try params.put("arguments", .{ .object = arguments });

        return try self.callTool("diff.apply", .{ .object = params });
    }

    /// Helper: Generate diff via Glyph
    pub fn generateDiff(self: *Self, old_content: []const u8, new_content: []const u8) !ToolResult {
        var params = std.json.ObjectMap.init(self.allocator);
        defer params.deinit();

        try params.put("name", .{ .string = "diff.generate" });

        var arguments = std.json.ObjectMap.init(self.allocator);
        defer arguments.deinit();
        try arguments.put("old", .{ .string = old_content });
        try arguments.put("new", .{ .string = new_content });

        try params.put("arguments", .{ .object = arguments });

        return try self.callTool("diff.generate", .{ .object = params });
    }
};

/// Health check for MCP services
pub fn checkHealth(allocator: std.mem.Allocator, cfg: config.ServiceConfig.GlyphConfig) !bool {
    var client = try McpClient.initFromConfig(allocator, cfg);
    defer client.deinit();

    // Try to call a simple tool to verify connection
    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("name", .{ .string = "ping" });
    try params.put("arguments", .{ .object = std.json.ObjectMap.init(allocator) });

    const result = client.callTool("ping", .{ .object = params }) catch |err| {
        std.log.warn("MCP health check failed: {}", .{err});
        return false;
    };
    defer result.deinit();

    return !result.is_error;
}
