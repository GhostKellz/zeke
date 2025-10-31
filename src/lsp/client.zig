// LSP Client - Manages connection to language servers

const std = @import("std");
const types = @import("types.zig");
const jsonrpc = @import("jsonrpc.zig");

pub const LspClient = struct {
    allocator: std.mem.Allocator,
    process: ?std.process.Child,
    server_config: types.ServerConfig,
    next_request_id: i64,
    initialized: bool,
    capabilities: ?types.ServerCapabilities,
    root_uri: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: types.ServerConfig, root_path: []const u8) !LspClient {
        const root_uri = try std.fmt.allocPrint(allocator, "file://{s}", .{root_path});

        return LspClient{
            .allocator = allocator,
            .process = null,
            .server_config = config,
            .next_request_id = 1,
            .initialized = false,
            .capabilities = null,
            .root_uri = root_uri,
        };
    }

    pub fn deinit(self: *LspClient) void {
        if (self.process) |*proc| {
            _ = proc.kill() catch {};
        }
        self.allocator.free(self.root_uri);
        if (self.capabilities) |_| {
            // Capabilities are stack-allocated, no cleanup needed
        }
    }

    /// Start the LSP server process
    pub fn start(self: *LspClient) !void {
        std.debug.print("Starting LSP server: {s}\n", .{self.server_config.command});

        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);

        try argv.append(self.allocator, self.server_config.command);
        for (self.server_config.args) |arg| {
            try argv.append(self.allocator, arg);
        }

        var process = std.process.Child.init(argv.items, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        try process.spawn();
        self.process = process;

        std.debug.print("LSP server started (PID: {})\n", .{process.id});
    }

    /// Initialize the LSP server
    pub fn initialize(self: *LspClient) !types.InitializeResult {
        if (self.initialized) return error.AlreadyInitialized;

        std.debug.print("Initializing LSP server...\n", .{});

        // Create initialize request params
        var params_obj = std.json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();

        try params_obj.put("processId", .{ .integer = @intCast(std.os.linux.getpid()) });
        try params_obj.put("rootUri", .{ .string = self.root_uri });

        // Client capabilities
        var capabilities = std.json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();

        var textDocument = std.json.ObjectMap.init(self.allocator);
        defer textDocument.deinit();

        try textDocument.put("synchronization", .{ .object = std.json.ObjectMap.init(self.allocator) });
        try textDocument.put("completion", .{ .object = std.json.ObjectMap.init(self.allocator) });
        try textDocument.put("hover", .{ .object = std.json.ObjectMap.init(self.allocator) });
        try textDocument.put("diagnostic", .{ .object = std.json.ObjectMap.init(self.allocator) });

        try capabilities.put("textDocument", .{ .object = textDocument });
        try params_obj.put("capabilities", .{ .object = capabilities });

        const params = std.json.Value{ .object = params_obj };

        // Send initialize request and get raw JSON response
        const response_json = try self.sendRequestRaw("initialize", params);
        defer self.allocator.free(response_json);

        // Parse the JSON response directly
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_json, .{});
        defer parsed.deinit();

        const response_obj = parsed.value.object;
        if (response_obj.get("result")) |result| {
            const result_obj = result.object;
            if (result_obj.get("capabilities")) |caps| {
                self.capabilities = try parseServerCapabilities(caps);
                self.initialized = true;

                std.debug.print("LSP server initialized successfully\n", .{});

                // Send initialized notification
                try self.sendNotification("initialized", .{ .object = std.json.ObjectMap.init(self.allocator) });

                return types.InitializeResult{
                    .capabilities = self.capabilities.?,
                    .serverInfo = null,
                };
            }
        }

        return error.InitializationFailed;
    }

    /// Shutdown the LSP server
    pub fn shutdown(self: *LspClient) !void {
        if (!self.initialized) return;

        std.debug.print("Shutting down LSP server...\n", .{});

        const response = try self.sendRequest("shutdown", null);
        defer {
            var mut_response = response;
            mut_response.deinit(self.allocator);
        }

        try self.sendNotification("exit", null);

        if (self.process) |*proc| {
            _ = try proc.wait();
            self.process = null;
        }

        self.initialized = false;
        std.debug.print("LSP server shutdown complete\n", .{});
    }

    /// Get diagnostics for a file
    /// TODO: Implement full diagnostics with didOpen + publishDiagnostics notifications
    /// For now, this is a placeholder that returns empty diagnostics
    pub fn getDiagnostics(self: *LspClient, file_uri: []const u8) ![]types.Diagnostic {
        if (!self.initialized) return error.NotInitialized;

        _ = file_uri;

        // TODO: Full implementation requires:
        // 1. Send textDocument/didOpen notification with file content
        // 2. Read publishDiagnostics notifications from server
        // 3. Parse and return diagnostics
        // This is best done in daemon mode with persistent connections

        std.debug.print("Note: Full diagnostics require daemon mode with notification handling.\n", .{});
        return &[_]types.Diagnostic{};
    }

    /// Get hover information at position
    pub fn getHover(self: *LspClient, file_uri: []const u8, line: u32, character: u32) !?types.Hover {
        if (!self.initialized) return error.NotInitialized;

        var params_obj = std.json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();

        var textDocument = std.json.ObjectMap.init(self.allocator);
        defer textDocument.deinit();
        try textDocument.put("uri", .{ .string = file_uri });

        var position = std.json.ObjectMap.init(self.allocator);
        defer position.deinit();
        try position.put("line", .{ .integer = @intCast(line) });
        try position.put("character", .{ .integer = @intCast(character) });

        try params_obj.put("textDocument", .{ .object = textDocument });
        try params_obj.put("position", .{ .object = position });

        const params = std.json.Value{ .object = params_obj };

        const response = try self.sendRequest("textDocument/hover", params);
        defer {
            var mut_response = response;
            mut_response.deinit(self.allocator);
        }

        if (response.result) |result| {
            if (result == .null) return null;
            return try parseHover(self.allocator, result);
        }

        return null;
    }

    /// Get definition location for a symbol at a position
    pub fn getDefinition(self: *LspClient, file_uri: []const u8, line: u32, character: u32) !?[]types.Location {
        if (!self.initialized) return error.NotInitialized;

        var params_obj = std.json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();

        var textDocument = std.json.ObjectMap.init(self.allocator);
        defer textDocument.deinit();
        try textDocument.put("uri", .{ .string = file_uri });

        var position = std.json.ObjectMap.init(self.allocator);
        defer position.deinit();
        try position.put("line", .{ .integer = @intCast(line) });
        try position.put("character", .{ .integer = @intCast(character) });

        try params_obj.put("textDocument", .{ .object = textDocument });
        try params_obj.put("position", .{ .object = position });

        const params = std.json.Value{ .object = params_obj };

        const response = try self.sendRequest("textDocument/definition", params);
        defer {
            var mut_response = response;
            mut_response.deinit(self.allocator);
        }

        if (response.result) |result| {
            if (result == .null) return null;
            return try parseLocations(self.allocator, result);
        }

        return null;
    }

    /// Find all references to a symbol at a position
    pub fn findReferences(self: *LspClient, file_uri: []const u8, line: u32, character: u32, include_declaration: bool) !?[]types.Location {
        if (!self.initialized) return error.NotInitialized;

        var params_obj = std.json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();

        var textDocument = std.json.ObjectMap.init(self.allocator);
        defer textDocument.deinit();
        try textDocument.put("uri", .{ .string = file_uri });

        var position = std.json.ObjectMap.init(self.allocator);
        defer position.deinit();
        try position.put("line", .{ .integer = @intCast(line) });
        try position.put("character", .{ .integer = @intCast(character) });

        var context = std.json.ObjectMap.init(self.allocator);
        defer context.deinit();
        try context.put("includeDeclaration", .{ .bool = include_declaration });

        try params_obj.put("textDocument", .{ .object = textDocument });
        try params_obj.put("position", .{ .object = position });
        try params_obj.put("context", .{ .object = context });

        const params = std.json.Value{ .object = params_obj };

        const response = try self.sendRequest("textDocument/references", params);
        defer {
            var mut_response = response;
            mut_response.deinit(self.allocator);
        }

        if (response.result) |result| {
            if (result == .null) return null;
            return try parseLocations(self.allocator, result);
        }

        return null;
    }

    /// Send request and wait for raw JSON response
    fn sendRequestRaw(self: *LspClient, method: []const u8, params: ?std.json.Value) ![]const u8 {
        const id = self.next_request_id;
        self.next_request_id += 1;

        const request_json = try jsonrpc.createRequest(self.allocator, id, method, params);
        defer self.allocator.free(request_json);

        const encoded = try jsonrpc.encodeMessage(self.allocator, request_json);
        defer self.allocator.free(encoded);

        // Send to server
        if (self.process) |*proc| {
            if (proc.stdin) |stdin| {
                try stdin.writeAll(encoded);
            }
        }

        // Read response and return raw JSON
        return try self.readResponseRaw();
    }

    /// Send request and wait for response
    fn sendRequest(self: *LspClient, method: []const u8, params: ?std.json.Value) !jsonrpc.Response {
        const id = self.next_request_id;
        self.next_request_id += 1;

        const request_json = try jsonrpc.createRequest(self.allocator, id, method, params);
        defer self.allocator.free(request_json);

        const encoded = try jsonrpc.encodeMessage(self.allocator, request_json);
        defer self.allocator.free(encoded);

        // Send to server
        if (self.process) |*proc| {
            if (proc.stdin) |stdin| {
                try stdin.writeAll(encoded);
            }
        }

        // Read response
        return try self.readResponse();
    }

    /// Store diagnostics for a file URI
    pub fn storeDiagnostics(self: *LspClient, file_uri: []const u8, diagnostics: []types.Diagnostic) !void {
        _ = self;
        _ = file_uri;
        _ = diagnostics;
        // TODO: Store diagnostics in a HashMap for later retrieval
        // This will be wired into the event bus
    }

    /// Send notification (no response expected)
    fn sendNotification(self: *LspClient, method: []const u8, params: ?std.json.Value) !void {
        const notif_json = try jsonrpc.createNotification(self.allocator, method, params);
        defer self.allocator.free(notif_json);

        const encoded = try jsonrpc.encodeMessage(self.allocator, notif_json);
        defer self.allocator.free(encoded);

        if (self.process) |*proc| {
            if (proc.stdin) |stdin| {
                try stdin.writeAll(encoded);
            }
        }
    }

    /// Read raw JSON response from server, skipping notifications
    /// Returns the raw JSON string that must be freed by caller
    fn readResponseRaw(self: *LspClient) ![]const u8 {
        if (self.process) |*proc| {
            if (proc.stdout) |stdout| {
                // Keep reading until we get a response (skip notifications)
                while (true) {
                    var buf: [65536]u8 = undefined;
                    const n = try stdout.read(&buf);
                    if (n == 0) return error.ServerDisconnected;

                    std.debug.print("Read {} bytes from LSP server\n", .{n});

                    // Process potentially multiple messages in the buffer
                    var offset: usize = 0;
                    while (offset < n) {
                        // Find Content-Length header
                        const header_start = std.mem.indexOf(u8, buf[offset..n], "Content-Length:") orelse break;
                        offset += header_start;

                        const header_end = std.mem.indexOf(u8, buf[offset..n], "\r\n\r\n") orelse break;
                        const headers = buf[offset .. offset + header_end];

                        // Parse Content-Length
                        var content_length: usize = 0;
                        var lines = std.mem.tokenizeScalar(u8, headers, '\n');
                        while (lines.next()) |line| {
                            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
                            if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                                const value_str = std.mem.trim(u8, trimmed[15..], &std.ascii.whitespace);
                                content_length = try std.fmt.parseInt(usize, value_str, 10);
                                break;
                            }
                        }

                        if (content_length == 0) break;

                        const json_start = offset + header_end + 4;
                        if (json_start + content_length > n) break;  // Incomplete message

                        const json_data = buf[json_start .. json_start + content_length];
                        std.debug.print("Decoded JSON: {s}\n", .{json_data});

                        const message = try jsonrpc.parseMessage(self.allocator, json_data);

                        switch (message) {
                            .response => {
                                std.debug.print("Got response!\n", .{});
                                // Clean up the message
                                var mut_msg = message;
                                mut_msg.deinit(self.allocator);
                                // Return a copy of the raw JSON
                                return try self.allocator.dupe(u8, json_data);
                            },
                            .notification => |notif| {
                                std.debug.print("Got notification: {s}, skipping...\n", .{notif.method});
                                // Clean up this message
                                var mut_msg = message;
                                mut_msg.deinit(self.allocator);
                                // Move to next message
                                offset = json_start + content_length;
                                continue;
                            },
                            .request => {
                                std.debug.print("Got request from server (unexpected)\n", .{});
                                var mut_msg = message;
                                mut_msg.deinit(self.allocator);
                                return error.UnexpectedMessage;
                            },
                        }
                    }
                }
            }
        }

        return error.NoProcess;
    }

    /// Read notification from server with timeout (in milliseconds)
    /// Returns raw JSON string or error on timeout
    fn readNotificationWithTimeout(self: *LspClient, timeout_ms: u64) ![]const u8 {
        if (self.process) |*proc| {
            if (proc.stdout) |stdout| {
                // Set up for non-blocking read with timeout
                const start_time = std.time.milliTimestamp();

                while (std.time.milliTimestamp() - start_time < timeout_ms) {
                    // Try to read with a small buffer first
                    var peek_buf: [16]u8 = undefined;
                    const peek_n = stdout.read(&peek_buf) catch |err| {
                        if (err == error.WouldBlock) {
                            std.time.sleep(10 * std.time.ns_per_ms);
                            continue;
                        }
                        return err;
                    };

                    if (peek_n == 0) {
                        std.time.sleep(10 * std.time.ns_per_ms);
                        continue;
                    }

                    // We got some data, read the full message
                    var buf: [65536]u8 = undefined;
                    @memcpy(buf[0..peek_n], peek_buf[0..peek_n]);
                    const rest_n = try stdout.read(buf[peek_n..]);
                    const n = peek_n + rest_n;

                    // Parse the first message
                    const header_start = std.mem.indexOf(u8, buf[0..n], "Content-Length:") orelse continue;
                    const header_end = std.mem.indexOf(u8, buf[header_start..n], "\r\n\r\n") orelse continue;
                    const headers = buf[header_start .. header_start + header_end];

                    var content_length: usize = 0;
                    var lines = std.mem.tokenizeScalar(u8, headers, '\n');
                    while (lines.next()) |line| {
                        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
                        if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                            const value_str = std.mem.trim(u8, trimmed[15..], &std.ascii.whitespace);
                            content_length = try std.fmt.parseInt(usize, value_str, 10);
                            break;
                        }
                    }

                    if (content_length == 0) continue;

                    const json_start = header_start + header_end + 4;
                    if (json_start + content_length > n) continue;

                    const json_data = buf[json_start .. json_start + content_length];
                    return try self.allocator.dupe(u8, json_data);
                }

                return error.Timeout;
            }
        }

        return error.NoProcess;
    }

    /// Read response from server, skipping notifications
    /// This function handles multiple messages in a single buffer
    fn readResponse(self: *LspClient) !jsonrpc.Response {
        if (self.process) |*proc| {
            if (proc.stdout) |stdout| {
                // Keep reading until we get a response (skip notifications)
                while (true) {
                    var buf: [65536]u8 = undefined;  // Larger buffer for multiple messages
                    const n = try stdout.read(&buf);
                    if (n == 0) return error.ServerDisconnected;

                    std.debug.print("Read {} bytes from LSP server\n", .{n});

                    // Process potentially multiple messages in the buffer
                    var offset: usize = 0;
                    while (offset < n) {
                        // Find Content-Length header
                        const header_start = std.mem.indexOf(u8, buf[offset..n], "Content-Length:") orelse break;
                        offset += header_start;

                        const header_end = std.mem.indexOf(u8, buf[offset..n], "\r\n\r\n") orelse break;
                        const headers = buf[offset .. offset + header_end];

                        // Parse Content-Length
                        var content_length: usize = 0;
                        var lines = std.mem.tokenizeScalar(u8, headers, '\n');
                        while (lines.next()) |line| {
                            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
                            if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                                const value_str = std.mem.trim(u8, trimmed[15..], &std.ascii.whitespace);
                                content_length = try std.fmt.parseInt(usize, value_str, 10);
                                break;
                            }
                        }

                        if (content_length == 0) break;

                        const json_start = offset + header_end + 4;
                        if (json_start + content_length > n) break;  // Incomplete message

                        const json_data = buf[json_start .. json_start + content_length];
                        std.debug.print("Decoded JSON: {s}\n", .{json_data});

                        const message = try jsonrpc.parseMessage(self.allocator, json_data);

                        switch (message) {
                            .response => |res| {
                                std.debug.print("Got response!\n", .{});
                                // TODO: This leaks the message memory because the response contains
                                // pointers into the parsed JSON. We need a better architecture.
                                // For now, don't deinit - caller will use the response data.
                                return res;
                            },
                            .notification => |notif| {
                                std.debug.print("Got notification: {s}, skipping...\n", .{notif.method});
                                // Clean up this message
                                var mut_msg = message;
                                mut_msg.deinit(self.allocator);
                                // Move to next message
                                offset = json_start + content_length;
                                continue;
                            },
                            .request => {
                                std.debug.print("Got request from server (unexpected)\n", .{});
                                var mut_msg = message;
                                mut_msg.deinit(self.allocator);
                                return error.UnexpectedMessage;
                            },
                        }
                    }
                }
            }
        }

        return error.NoProcess;
    }
};

/// Parse server capabilities from JSON
fn parseServerCapabilities(value: std.json.Value) !types.ServerCapabilities {
    const obj = value.object;

    // textDocumentSync can be a number or an object
    var text_doc_sync: ?u8 = null;
    if (obj.get("textDocumentSync")) |v| {
        switch (v) {
            .integer => |i| text_doc_sync = @as(u8, @intCast(i)),
            .object => text_doc_sync = 2,  // Full sync as default
            else => {},
        }
    }

    return types.ServerCapabilities{
        .textDocumentSync = text_doc_sync,
        .completionProvider = obj.get("completionProvider") != null,
        .hoverProvider = if (obj.get("hoverProvider")) |v| v == .bool and v.bool else false,
        .definitionProvider = if (obj.get("definitionProvider")) |v| v == .bool and v.bool else false,
        .referencesProvider = if (obj.get("referencesProvider")) |v| v == .bool and v.bool else false,
        .documentSymbolProvider = if (obj.get("documentSymbolProvider")) |v| v == .bool and v.bool else false,
        .workspaceSymbolProvider = if (obj.get("workspaceSymbolProvider")) |v| v == .bool and v.bool else false,
        .diagnosticProvider = obj.get("diagnosticProvider") != null,
    };
}

/// Parse diagnostics from JSON
fn parseDiagnostics(allocator: std.mem.Allocator, value: std.json.Value) ![]types.Diagnostic {
    if (value != .array) return &[_]types.Diagnostic{};

    const array = value.array;
    var diagnostics = std.ArrayList(types.Diagnostic).empty;
    errdefer diagnostics.deinit(allocator);

    for (array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        // Parse range
        const range_val = obj.get("range") orelse continue;
        if (range_val != .object) continue;
        const range_obj = range_val.object;

        const start_val = range_obj.get("start") orelse continue;
        if (start_val != .object) continue;
        const start_obj = start_val.object;

        const end_val = range_obj.get("end") orelse continue;
        if (end_val != .object) continue;
        const end_obj = end_val.object;

        const range = types.Range{
            .start = .{
                .line = @intCast(start_obj.get("line").?.integer),
                .character = @intCast(start_obj.get("character").?.integer),
            },
            .end = .{
                .line = @intCast(end_obj.get("line").?.integer),
                .character = @intCast(end_obj.get("character").?.integer),
            },
        };

        // Parse severity (optional)
        var severity: ?types.DiagnosticSeverity = null;
        if (obj.get("severity")) |sev_val| {
            if (sev_val == .integer) {
                const sev_int: u8 = @intCast(sev_val.integer);
                severity = @enumFromInt(sev_int);
            }
        }

        // Parse message
        const message_val = obj.get("message") orelse continue;
        if (message_val != .string) continue;
        const message = try allocator.dupe(u8, message_val.string);

        // Parse code (optional)
        var code: ?[]const u8 = null;
        if (obj.get("code")) |code_val| {
            if (code_val == .string) {
                code = try allocator.dupe(u8, code_val.string);
            } else if (code_val == .integer) {
                code = try std.fmt.allocPrint(allocator, "{}", .{code_val.integer});
            }
        }

        // Parse source (optional)
        var source: ?[]const u8 = null;
        if (obj.get("source")) |source_val| {
            if (source_val == .string) {
                source = try allocator.dupe(u8, source_val.string);
            }
        }

        try diagnostics.append(allocator, .{
            .range = range,
            .severity = severity,
            .code = code,
            .source = source,
            .message = message,
            .relatedInformation = null,
        });
    }

    return diagnostics.toOwnedSlice(allocator);
}

/// Parse hover from JSON
/// Parse Location or Location[] from LSP response
fn parseLocations(allocator: std.mem.Allocator, value: std.json.Value) ![]types.Location {
    var locations = std.ArrayList(types.Location).empty;
    errdefer locations.deinit(allocator);

    if (value == .array) {
        // Multiple locations
        for (value.array.items) |item| {
            const loc = try parseLocation(allocator, item);
            try locations.append(allocator, loc);
        }
    } else if (value == .object) {
        // Single location
        const loc = try parseLocation(allocator, value);
        try locations.append(allocator, loc);
    }

    return locations.toOwnedSlice(allocator);
}

fn parseLocation(allocator: std.mem.Allocator, value: std.json.Value) !types.Location {
    const obj = value.object;

    const uri = if (obj.get("uri")) |u| try allocator.dupe(u8, u.string) else "";
    const range = if (obj.get("range")) |r| try parseRange(r) else types.Range{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    };

    return types.Location{
        .uri = uri,
        .range = range,
    };
}

fn parseRange(value: std.json.Value) !types.Range {
    const obj = value.object;

    const start = if (obj.get("start")) |s| types.Position{
        .line = @intCast(s.object.get("line").?.integer),
        .character = @intCast(s.object.get("character").?.integer),
    } else types.Position{ .line = 0, .character = 0 };

    const end = if (obj.get("end")) |e| types.Position{
        .line = @intCast(e.object.get("line").?.integer),
        .character = @intCast(e.object.get("character").?.integer),
    } else types.Position{ .line = 0, .character = 0 };

    return types.Range{
        .start = start,
        .end = end,
    };
}

fn parseHover(allocator: std.mem.Allocator, value: std.json.Value) !types.Hover {
    const obj = value.object;

    const contents = if (obj.get("contents")) |c| blk: {
        if (c == .string) {
            break :blk try allocator.dupe(u8, c.string);
        } else if (c == .object) {
            if (c.object.get("value")) |v| {
                break :blk try allocator.dupe(u8, v.string);
            }
        }
        break :blk try allocator.dupe(u8, "");
    } else try allocator.dupe(u8, "");

    return types.Hover{
        .contents = contents,
        .range = null,
    };
}

// Tests
test "LSP client initialization" {
    const allocator = std.testing.allocator;

    const config = types.ServerConfig{
        .name = "test",
        .command = "cat", // Use cat as a dummy command
        .args = &[_][]const u8{},
        .filetypes = &[_][]const u8{".test"},
        .rootPatterns = &[_][]const u8{},
    };

    var client = try LspClient.init(allocator, config, "/tmp");
    defer client.deinit();

    try std.testing.expect(!client.initialized);
    try std.testing.expect(client.next_request_id == 1);
}
