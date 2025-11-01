const std = @import("std");

/// OAuth callback server for handling redirect URIs
/// Listens on localhost for one OAuth authorization callback
pub const CallbackServer = struct {
    allocator: std.mem.Allocator,
    server: std.net.Server,
    port: u16,
    authorization_code: ?[]const u8,
    error_message: ?[]const u8,

    /// Initialize callback server on random available port
    pub fn init(allocator: std.mem.Allocator) !CallbackServer {
        const address = try std.net.Address.parseIp("127.0.0.1", 0);
        var server = try address.listen(.{
            .reuse_address = true,
        });

        const actual_port = server.listen_address.getPort();

        return .{
            .allocator = allocator,
            .server = server,
            .port = actual_port,
            .authorization_code = null,
            .error_message = null,
        };
    }

    pub fn deinit(self: *CallbackServer) void {
        if (self.authorization_code) |code| {
            self.allocator.free(code);
        }
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        self.server.deinit();
    }

    /// Get the callback URL for OAuth redirect
    pub fn getCallbackUrl(self: *CallbackServer) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "http://localhost:{d}/callback",
            .{self.port},
        );
    }

    /// Wait for OAuth callback (blocking)
    /// Accepts one HTTP connection, parses the authorization code, and sends response
    pub fn waitForCallback(self: *CallbackServer, timeout_seconds: u64) !void {
        const timeout_ns = timeout_seconds * std.time.ns_per_s;
        const deadline = std.time.nanoTimestamp() + @as(i128, timeout_ns);

        while (std.time.nanoTimestamp() < deadline) {
            // Try to accept connection with short timeout
            const connection = self.server.accept() catch |err| switch (err) {
                error.WouldBlock => {
                    std.Thread.sleep(100 * std.time.ns_per_ms);
                    continue;
                },
                else => return err,
            };

            defer connection.stream.close();

            // Handle the request
            try self.handleRequest(connection.stream);

            // We only need one callback
            return;
        }

        return error.CallbackTimeout;
    }

    /// Handle incoming HTTP request
    fn handleRequest(self: *CallbackServer, stream: std.net.Stream) !void {
        var buffer: [4096]u8 = undefined;
        const bytes_read = try stream.read(&buffer);

        if (bytes_read == 0) {
            return error.EmptyRequest;
        }

        const request = buffer[0..bytes_read];

        // Parse HTTP request line (e.g., "GET /callback?code=xxx HTTP/1.1")
        var lines = std.mem.splitScalar(u8, request, '\n');
        const request_line = lines.next() orelse return error.InvalidRequest;

        // Extract path and query string
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        _ = parts.next(); // Skip method (GET)
        const path_and_query = parts.next() orelse return error.InvalidRequest;

        // Parse query parameters
        if (std.mem.indexOf(u8, path_and_query, "?")) |query_start| {
            const query = path_and_query[query_start + 1 ..];
            try self.parseQueryParams(query);
        } else {
            return error.NoQueryParams;
        }

        // Send response to browser
        if (self.error_message) |_| {
            try self.sendErrorResponse(stream);
        } else if (self.authorization_code) |_| {
            try self.sendSuccessResponse(stream);
        } else {
            try self.sendErrorResponse(stream);
        }
    }

    /// Parse OAuth query parameters (code, state, error)
    fn parseQueryParams(self: *CallbackServer, query: []const u8) !void {
        var params = std.mem.splitScalar(u8, query, '&');

        while (params.next()) |param| {
            // Remove any trailing \r\n or whitespace
            const clean_param = std.mem.trim(u8, param, &std.ascii.whitespace);

            if (std.mem.indexOf(u8, clean_param, "=")) |eq_pos| {
                const key = clean_param[0..eq_pos];
                const value = clean_param[eq_pos + 1 ..];

                if (std.mem.eql(u8, key, "code")) {
                    // URL decode and store authorization code
                    const decoded = try self.urlDecode(value);
                    self.authorization_code = decoded;
                } else if (std.mem.eql(u8, key, "error")) {
                    const decoded = try self.urlDecode(value);
                    self.error_message = decoded;
                } else if (std.mem.eql(u8, key, "error_description")) {
                    // If we already have an error, append description
                    const decoded = try self.urlDecode(value);
                    if (self.error_message) |old_msg| {
                        const combined = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}: {s}",
                            .{ old_msg, decoded },
                        );
                        self.allocator.free(old_msg);
                        self.allocator.free(decoded);
                        self.error_message = combined;
                    } else {
                        self.error_message = decoded;
                    }
                }
                // Ignore other params like 'state' for now
            }
        }
    }

    /// URL decode a string (handles %XX encoded characters)
    fn urlDecode(self: *CallbackServer, encoded: []const u8) ![]const u8 {
        var decoded = std.ArrayList(u8){};
        try decoded.ensureTotalCapacity(self.allocator, encoded.len);
        errdefer decoded.deinit(self.allocator);

        var i: usize = 0;
        while (i < encoded.len) {
            if (encoded[i] == '%' and i + 2 < encoded.len) {
                // Decode %XX
                const hex = encoded[i + 1 .. i + 3];
                const byte = try std.fmt.parseInt(u8, hex, 16);
                try decoded.append(self.allocator, byte);
                i += 3;
            } else if (encoded[i] == '+') {
                // Convert + to space
                try decoded.append(self.allocator, ' ');
                i += 1;
            } else {
                try decoded.append(self.allocator, encoded[i]);
                i += 1;
            }
        }

        return decoded.toOwnedSlice(self.allocator);
    }

    /// Send success HTML response
    fn sendSuccessResponse(self: *CallbackServer, stream: std.net.Stream) !void {
        _ = self;

        const html =
            \\HTTP/1.1 200 OK
            \\Content-Type: text/html; charset=utf-8
            \\Connection: close
            \\
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <meta charset="utf-8">
            \\  <title>Zeke Authentication</title>
            \\  <style>
            \\    body {
            \\      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            \\      display: flex;
            \\      align-items: center;
            \\      justify-content: center;
            \\      height: 100vh;
            \\      margin: 0;
            \\      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            \\    }
            \\    .container {
            \\      text-align: center;
            \\      background: white;
            \\      padding: 3rem;
            \\      border-radius: 1rem;
            \\      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            \\      max-width: 500px;
            \\    }
            \\    h1 { color: #2d3748; margin: 0 0 1rem 0; }
            \\    p { color: #4a5568; margin: 0 0 2rem 0; }
            \\    .success { color: #38a169; font-size: 4rem; margin-bottom: 1rem; }
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="container">
            \\    <div class="success">✓</div>
            \\    <h1>Authentication Successful!</h1>
            \\    <p>You can now close this window and return to your terminal.</p>
            \\  </div>
            \\</body>
            \\</html>
        ;

        try stream.writeAll(html);
    }

    /// Send error HTML response
    fn sendErrorResponse(self: *CallbackServer, stream: std.net.Stream) !void {
        const error_msg = self.error_message orelse "Unknown error occurred";

        const html = try std.fmt.allocPrint(
            self.allocator,
            \\HTTP/1.1 400 Bad Request
            \\Content-Type: text/html; charset=utf-8
            \\Connection: close
            \\
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <meta charset="utf-8">
            \\  <title>Zeke Authentication Error</title>
            \\  <style>
            \\    body {{
            \\      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            \\      display: flex;
            \\      align-items: center;
            \\      justify-content: center;
            \\      height: 100vh;
            \\      margin: 0;
            \\      background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            \\    }}
            \\    .container {{
            \\      text-align: center;
            \\      background: white;
            \\      padding: 3rem;
            \\      border-radius: 1rem;
            \\      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            \\      max-width: 500px;
            \\    }}
            \\    h1 {{ color: #2d3748; margin: 0 0 1rem 0; }}
            \\    p {{ color: #4a5568; margin: 0 0 2rem 0; }}
            \\    .error {{ color: #e53e3e; font-size: 4rem; margin-bottom: 1rem; }}
            \\    code {{ background: #f7fafc; padding: 0.5rem; border-radius: 0.25rem; }}
            \\  </style>
            \\</head>
            \\<body>
            \\  <div class="container">
            \\    <div class="error">✗</div>
            \\    <h1>Authentication Failed</h1>
            \\    <p><code>{s}</code></p>
            \\    <p>Please close this window and try again.</p>
            \\  </div>
            \\</body>
            \\</html>
        ,
            .{error_msg},
        );
        defer self.allocator.free(html);

        try stream.writeAll(html);
    }
};

// === Tests ===

test "callback server init and deinit" {
    const allocator = std.testing.allocator;

    var server = try CallbackServer.init(allocator);
    defer server.deinit();

    // Port should be assigned
    try std.testing.expect(server.port > 0);

    // Should be able to get callback URL
    const url = try server.getCallbackUrl();
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "http://localhost:") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "/callback") != null);
}

test "url decode" {
    const allocator = std.testing.allocator;

    var server = try CallbackServer.init(allocator);
    defer server.deinit();

    // Test basic decoding
    const decoded1 = try server.urlDecode("hello+world");
    defer allocator.free(decoded1);
    try std.testing.expectEqualStrings("hello world", decoded1);

    // Test percent encoding
    const decoded2 = try server.urlDecode("hello%20world");
    defer allocator.free(decoded2);
    try std.testing.expectEqualStrings("hello world", decoded2);

    // Test complex encoding
    const decoded3 = try server.urlDecode("foo%3Dbar%26baz");
    defer allocator.free(decoded3);
    try std.testing.expectEqualStrings("foo=bar&baz", decoded3);
}

test "parse query params success" {
    const allocator = std.testing.allocator;

    var server = try CallbackServer.init(allocator);
    defer server.deinit();

    // Simulate OAuth success callback
    try server.parseQueryParams("code=abc123&state=xyz");

    try std.testing.expect(server.authorization_code != null);
    try std.testing.expectEqualStrings("abc123", server.authorization_code.?);
}

test "parse query params error" {
    const allocator = std.testing.allocator;

    var server = try CallbackServer.init(allocator);
    defer server.deinit();

    // Simulate OAuth error callback
    try server.parseQueryParams("error=access_denied&error_description=User+cancelled");

    try std.testing.expect(server.error_message != null);
    try std.testing.expect(std.mem.indexOf(u8, server.error_message.?, "access_denied") != null);
}
