const std = @import("std");
const zhttp = @import("zhttp");

/// Server-Sent Events streaming client for real-time AI responses
pub const SSEClient = struct {
    allocator: std.mem.Allocator,
    http_client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) SSEClient {
        return .{
            .allocator = allocator,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *SSEClient) void {
        self.http_client.deinit();
    }

    /// Stream response from AI provider
    pub fn stream(
        self: *SSEClient,
        url: []const u8,
        headers: []const std.http.Header,
        body: []const u8,
        callbacks: StreamCallbacks,
    ) !void {
        var server_header_buffer: [16384]u8 = undefined;

        var req = try self.http_client.open(.POST, try std.Uri.parse(url), .{
            .server_header_buffer = &server_header_buffer,
            .headers = .{ .content_type = .{ .override = "application/json" } },
        });
        defer req.deinit();

        // Add custom headers
        for (headers) |header| {
            try req.headers.append(header.name, header.value);
        }

        req.transfer_encoding = .chunked;

        try req.send();
        try req.writeAll(body);
        try req.finish();
        try req.wait();

        // Read response as SSE stream
        var buffer: [8192]u8 = undefined;
        var event_buffer = std.ArrayList(u8).init(self.allocator);
        defer event_buffer.deinit();

        while (true) {
            const bytes_read = try req.reader().read(&buffer);
            if (bytes_read == 0) break; // End of stream

            try event_buffer.appendSlice(buffer[0..bytes_read]);

            // Parse SSE events
            while (std.mem.indexOf(u8, event_buffer.items, "\n\n")) |delimiter_pos| {
                const event_data = event_buffer.items[0..delimiter_pos];

                // Parse event
                try self.parseSSEEvent(event_data, callbacks);

                // Remove processed event from buffer
                const remaining = event_buffer.items[delimiter_pos + 2..];
                const remaining_copy = try self.allocator.dupe(u8, remaining);
                defer self.allocator.free(remaining_copy);

                event_buffer.clearRetainingCapacity();
                try event_buffer.appendSlice(remaining_copy);
            }
        }
    }

    fn parseSSEEvent(
        self: *SSEClient,
        event_data: []const u8,
        callbacks: StreamCallbacks,
    ) !void {
        var lines = std.mem.splitScalar(u8, event_data, '\n');

        var event_type: ?[]const u8 = null;
        var data_parts = std.ArrayList([]const u8).init(self.allocator);
        defer data_parts.deinit();

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "event:")) {
                event_type = std.mem.trim(u8, line[6..], &std.ascii.whitespace);
            } else if (std.mem.startsWith(u8, line, "data:")) {
                const data = std.mem.trim(u8, line[5..], &std.ascii.whitespace);
                try data_parts.append(data);
            }
        }

        if (data_parts.items.len == 0) return;

        // Join data parts
        var full_data = std.ArrayList(u8).init(self.allocator);
        defer full_data.deinit();

        for (data_parts.items) |part| {
            try full_data.appendSlice(part);
        }

        const data_str = try full_data.toOwnedSlice();
        defer self.allocator.free(data_str);

        // Parse JSON data
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            data_str,
            .{},
        );
        defer parsed.deinit();

        // Handle different event types
        if (event_type) |evt| {
            if (std.mem.eql(u8, evt, "content_block_delta")) {
                try self.handleContentDelta(parsed.value, callbacks);
            } else if (std.mem.eql(u8, evt, "tool_use")) {
                try self.handleToolUse(parsed.value, callbacks);
            } else if (std.mem.eql(u8, evt, "message_stop")) {
                if (callbacks.on_complete) |cb| {
                    cb();
                }
            }
        }
    }

    fn handleContentDelta(
        self: *SSEClient,
        value: std.json.Value,
        callbacks: StreamCallbacks,
    ) !void {
        if (value != .object) return;

        const delta = value.object.get("delta") orelse return;
        if (delta != .object) return;

        const text = delta.object.get("text") orelse return;
        if (text != .string) return;

        if (callbacks.on_chunk) |cb| {
            cb(text.string);
        }
    }

    fn handleToolUse(
        self: *SSEClient,
        value: std.json.Value,
        callbacks: StreamCallbacks,
    ) !void {
        _ = self;

        if (value != .object) return;

        const name = value.object.get("name") orelse return;
        const input = value.object.get("input") orelse return;

        if (name != .string) return;

        if (callbacks.on_tool) |cb| {
            const tool_call = ToolCall{
                .name = name.string,
                .input = input,
            };
            cb(tool_call);
        }
    }
};

/// Callbacks for streaming events
pub const StreamCallbacks = struct {
    on_chunk: ?*const fn ([]const u8) void = null,
    on_tool: ?*const fn (ToolCall) void = null,
    on_complete: ?*const fn () void = null,
    on_error: ?*const fn ([]const u8) void = null,
};

/// Tool call from AI
pub const ToolCall = struct {
    name: []const u8,
    input: std.json.Value,
};

// Tests
test "SSE client init" {
    const allocator = std.testing.allocator;
    var client = SSEClient.init(allocator);
    defer client.deinit();
}

test "parse SSE event" {
    const allocator = std.testing.allocator;
    var client = SSEClient.init(allocator);
    defer client.deinit();

    const event_data =
        \\event: content_block_delta
        \\data: {"delta": {"text": "Hello"}}
    ;

    var chunk_called = false;
    const callbacks = StreamCallbacks{
        .on_chunk = struct {
            fn callback(text: []const u8) void {
                _ = text;
            }
        }.callback,
    };

    // This will test parsing (callback verification would need more setup)
    try client.parseSSEEvent(event_data, callbacks);
}
