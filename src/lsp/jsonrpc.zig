// JSON-RPC 2.0 Protocol Implementation for LSP

const std = @import("std");

/// JSON-RPC message ID (can be number or string)
pub const MessageId = union(enum) {
    number: i64,
    string: []const u8,

    pub fn deinit(self: *MessageId, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .number => {},
        }
    }
};

/// JSON-RPC Request
pub const Request = struct {
    jsonrpc: []const u8 = "2.0",
    id: MessageId,
    method: []const u8,
    params: ?std.json.Value,

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        self.id.deinit(allocator);
        allocator.free(self.method);
        // params is just a value copy, no cleanup needed
        _ = self.params;
    }
};

/// JSON-RPC Response
pub const Response = struct {
    jsonrpc: []const u8 = "2.0",
    id: MessageId,
    result: ?std.json.Value,
    @"error": ?ResponseError,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        self.id.deinit(allocator);
        // result is just a value copy, no cleanup needed
        _ = self.result;
        if (self.@"error") |*err| {
            err.deinit(allocator);
        }
    }
};

/// JSON-RPC Notification (no id, no response expected)
pub const Notification = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?std.json.Value,

    pub fn deinit(self: *Notification, allocator: std.mem.Allocator) void {
        allocator.free(self.method);
        // params is just a value copy, no cleanup needed
        _ = self.params;
    }
};

/// JSON-RPC Error codes
pub const ErrorCode = enum(i32) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
    server_error_start = -32099,
    server_error_end = -32000,

    // LSP-specific error codes
    server_not_initialized = -32002,
    unknown_error_code = -32001,
    request_failed = -32803,
    server_cancelled = -32802,
    content_modified = -32801,
    request_cancelled = -32800,
};

/// JSON-RPC Response Error
pub const ResponseError = struct {
    code: i32,
    message: []const u8,
    data: ?std.json.Value,

    pub fn deinit(self: *ResponseError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        // data is just a value copy, no cleanup needed
        _ = self.data;
    }
};

/// JSON-RPC Message (can be request, response, or notification)
pub const Message = union(enum) {
    request: Request,
    response: Response,
    notification: Notification,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .request => |*req| req.deinit(allocator),
            .response => |*res| res.deinit(allocator),
            .notification => |*notif| notif.deinit(allocator),
        }
    }
};

/// Encode JSON-RPC message to wire format (Content-Length header + JSON)
pub fn encodeMessage(allocator: std.mem.Allocator, message: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);

    // Content-Length header
    const header = try std.fmt.allocPrint(allocator, "Content-Length: {}\r\n\r\n", .{message.len});
    defer allocator.free(header);

    try buf.appendSlice(allocator, header);
    try buf.appendSlice(allocator, message);

    return buf.toOwnedSlice(allocator);
}

/// Decode JSON-RPC message from wire format
pub fn decodeMessage(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    // Find Content-Length header
    const header_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse return error.InvalidMessage;
    const headers = data[0..header_end];

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

    if (content_length == 0) return error.MissingContentLength;

    // Extract JSON message
    const json_start = header_end + 4;
    if (json_start + content_length > data.len) return error.IncompleteMessage;

    const json_data = data[json_start .. json_start + content_length];
    return allocator.dupe(u8, json_data);
}

/// Create JSON-RPC request
pub fn createRequest(
    allocator: std.mem.Allocator,
    id: i64,
    method: []const u8,
    params: ?std.json.Value,
) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{ .writer = &out.writer };

    try stringify.beginObject();
    try stringify.objectField("jsonrpc");
    try stringify.write("2.0");
    try stringify.objectField("id");
    try stringify.write(id);
    try stringify.objectField("method");
    try stringify.write(method);

    if (params) |p| {
        try stringify.objectField("params");
        try stringify.write(p);
    }

    try stringify.endObject();

    return allocator.dupe(u8, out.written());
}

/// Create JSON-RPC notification
pub fn createNotification(
    allocator: std.mem.Allocator,
    method: []const u8,
    params: ?std.json.Value,
) ![]const u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{ .writer = &out.writer };

    try stringify.beginObject();
    try stringify.objectField("jsonrpc");
    try stringify.write("2.0");
    try stringify.objectField("method");
    try stringify.write(method);

    if (params) |p| {
        try stringify.objectField("params");
        try stringify.write(p);
    }

    try stringify.endObject();

    return allocator.dupe(u8, out.written());
}

/// Parse JSON-RPC message
/// Note: The returned Message owns the parsed JSON data.
/// You must call message.deinit() and parsed.deinit() to free memory.
pub fn parseMessage(allocator: std.mem.Allocator, json: []const u8) !Message {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    // Don't defer - caller must manage parsed lifetime
    defer parsed.deinit();

    const obj = parsed.value.object;

    // Check if it's a response (has result or error)
    if (obj.get("result") != null or obj.get("error") != null) {
        const id_value = obj.get("id") orelse return error.MissingId;
        const id = try parseMessageId(allocator, id_value);

        var result: ?std.json.Value = null;
        if (obj.get("result")) |r| {
            result = r;  // Just copy the value, it's already owned by parsed
        }

        var err: ?ResponseError = null;
        if (obj.get("error")) |e| {
            const err_obj = e.object;
            const code = @as(i32, @intCast(err_obj.get("code").?.integer));
            const message = try allocator.dupe(u8, err_obj.get("message").?.string);
            var data: ?std.json.Value = null;
            if (err_obj.get("data")) |d| {
                data = d;
            }
            err = .{ .code = code, .message = message, .data = data };
        }

        return Message{
            .response = .{
                .id = id,
                .result = result,
                .@"error" = err,
            },
        };
    }

    // Check if it's a notification (no id)
    if (obj.get("id") == null) {
        const method = try allocator.dupe(u8, obj.get("method").?.string);
        var params: ?std.json.Value = null;
        if (obj.get("params")) |p| {
            params = p;
        }

        return Message{
            .notification = .{
                .method = method,
                .params = params,
            },
        };
    }

    // It's a request
    const id_value = obj.get("id") orelse return error.MissingId;
    const id = try parseMessageId(allocator, id_value);
    const method = try allocator.dupe(u8, obj.get("method").?.string);
    var params: ?std.json.Value = null;
    if (obj.get("params")) |p| {
        params = p;
    }

    return Message{
        .request = .{
            .id = id,
            .method = method,
            .params = params,
        },
    };
}

fn parseMessageId(allocator: std.mem.Allocator, value: std.json.Value) !MessageId {
    return switch (value) {
        .integer => |i| MessageId{ .number = i },
        .string => |s| MessageId{ .string = try allocator.dupe(u8, s) },
        else => error.InvalidId,
    };
}

// Tests
test "encode/decode message" {
    const allocator = std.testing.allocator;

    const message = "test message";
    const encoded = try encodeMessage(allocator, message);
    defer allocator.free(encoded);

    const decoded = try decodeMessage(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(message, decoded);
}

test "create request" {
    const allocator = std.testing.allocator;

    const request = try createRequest(allocator, 1, "test/method", null);
    defer allocator.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"method\":\"test/method\"") != null);
}
