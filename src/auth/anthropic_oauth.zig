const std = @import("std");
const PKCE = @import("pkce.zig").PKCE;
const CallbackServer = @import("callback_server.zig").CallbackServer;
const BrowserOpener = @import("browser.zig").BrowserOpener;

/// Anthropic OAuth configuration
/// Based on OpenCode implementation: https://github.com/stackblitz/opencode
pub const AnthropicOAuth = struct {
    /// Anthropic's public OAuth client ID (same as used by OpenCode)
    pub const CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";

    /// OAuth authorization endpoint
    pub const AUTH_URL = "https://console.anthropic.com/oauth/authorize";

    /// Token exchange endpoint (v1 API!)
    pub const TOKEN_URL = "https://console.anthropic.com/v1/oauth/token";

    /// OAuth redirect URI (must match Anthropic's registered callback)
    pub const REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";

    /// OAuth scopes required (from OpenCode implementation)
    pub const SCOPES = "org:create_api_key user:profile user:inference";

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnthropicOAuth {
        return .{ .allocator = allocator };
    }

    /// Perform OAuth flow and return access token
    /// Uses Anthropic's callback URL and manual code entry (like OpenCode)
    pub fn authorize(self: *AnthropicOAuth) !OAuthTokens {
        std.debug.print("\n🔐 Starting Anthropic OAuth authentication...\n\n", .{});

        // 1. Generate PKCE challenge
        var pkce = try PKCE.init(self.allocator);
        defer pkce.deinit();

        std.debug.print("✓ Generated PKCE challenge\n", .{});

        // 2. Build authorization URL (uses Anthropic's redirect URI, not localhost)
        const auth_url = try self.buildAuthUrl(pkce.code_challenge, pkce.code_verifier);
        defer self.allocator.free(auth_url);

        // 3. Display instructions to user
        std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("  Anthropic Claude Max Authentication\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});
        std.debug.print("Opening browser for authentication...\n", .{});
        std.debug.print("URL: \x1b[94m{s}\x1b[0m\n\n", .{auth_url});

        // 4. Open browser
        BrowserOpener.openWithFallback(self.allocator, auth_url);

        // 5. Wait for user to paste authorization code
        std.debug.print("After logging in, you'll be redirected to a page with an authorization code.\n", .{});
        std.debug.print("Paste the authorization code here: ", .{});

        // Read authorization code from stdin
        const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
        var input_buffer: [512]u8 = undefined;
        const bytes_read = try stdin_file.read(&input_buffer);
        if (bytes_read == 0) return error.NoInput;

        const auth_code = std.mem.trim(u8, input_buffer[0..bytes_read], &std.ascii.whitespace);

        if (auth_code.len == 0) {
            std.debug.print("\n❌ No authorization code provided\n", .{});
            return error.NoAuthCode;
        }

        std.debug.print("\n✓ Received authorization code\n", .{});

        // 6. Exchange code for tokens
        std.debug.print("🔄 Exchanging code for access token...\n", .{});

        const tokens = try self.exchangeCodeForTokens(auth_code, pkce.code_verifier);

        std.debug.print("\n✅ Authentication successful!\n", .{});
        std.debug.print("   Access token expires in: {d} seconds\n", .{tokens.expires_in});

        return tokens;
    }

    /// Build OAuth authorization URL with PKCE
    /// Matches OpenCode's implementation
    fn buildAuthUrl(self: *AnthropicOAuth, code_challenge: []const u8, code_verifier: []const u8) ![]const u8 {
        // Note: OpenCode uses code_verifier as the state parameter
        return std.fmt.allocPrint(
            self.allocator,
            "{s}?code=true&client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}",
            .{
                AUTH_URL,
                CLIENT_ID,
                REDIRECT_URI,
                SCOPES,
                code_challenge,
                code_verifier,
            },
        );
    }

    /// Exchange authorization code for access/refresh tokens
    /// Matches OpenCode implementation - uses JSON POST and splits code#state
    fn exchangeCodeForTokens(
        self: *AnthropicOAuth,
        code_with_state: []const u8,
        code_verifier: []const u8,
    ) !OAuthTokens {
        // IMPORTANT: Disable automatic compression in HTTP client
        var client = std.http.Client{
            .allocator = self.allocator,
            // Disable automatic decompression - we'll handle raw response
        };
        defer client.deinit();

        // Split code into code and state (format: "code#state")
        var split_iter = std.mem.splitScalar(u8, code_with_state, '#');
        const code = split_iter.next() orelse return error.InvalidCodeFormat;
        const state = split_iter.next() orelse return error.InvalidCodeFormat;

        // Build JSON request body (OpenCode uses JSON, not form data!)
        const body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"code":"{s}","state":"{s}","grant_type":"authorization_code","client_id":"{s}","redirect_uri":"{s}","code_verifier":"{s}"}}
            ,
            .{
                code,
                state,
                CLIENT_ID,
                REDIRECT_URI,
                code_verifier,
            },
        );
        defer self.allocator.free(body);

        // Parse URL
        const uri = try std.Uri.parse(TOKEN_URL);

        // Create request using JSON content type
        // IMPORTANT: Disable gzip compression by setting Accept-Encoding to identity
        const extra_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept-Encoding", .value = "identity" },
        };

        var request = try client.request(.POST, uri, .{
            .extra_headers = &extra_headers,
        });
        defer request.deinit();

        // Send request body
        try request.sendBodyComplete(body);

        // Receive response headers
        var redirect_buf: [4096]u8 = undefined;
        var response = try request.receiveHead(&redirect_buf);

        // Check status
        if (response.head.status != .ok) {
            std.debug.print("❌ Token exchange failed with status: {}\n", .{response.head.status});
            return error.TokenExchangeFailed;
        }

        // Read response body
        var response_body: [4096]u8 = undefined;
        const response_reader = response.reader(&response_body);
        const compressed_data = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(compressed_data);

        // Check if response is gzip compressed (magic bytes: 0x1f 0x8b)
        const is_gzipped = compressed_data.len >= 2 and compressed_data[0] == 0x1f and compressed_data[1] == 0x8b;

        // Decompress if needed using external gunzip command
        const body_data = if (is_gzipped) blk: {
            // Write compressed data to temp file
            const tmp_path = "/tmp/zeke_oauth_response.gz";
            const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{});
            defer tmp_file.close();
            try tmp_file.writeAll(compressed_data);

            // Decompress using gunzip
            const result = try std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "gunzip", "-c", tmp_path },
            });
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                std.debug.print("❌ gunzip failed: {s}\n", .{result.stderr});
                return error.DecompressionFailed;
            }

            break :blk try self.allocator.dupe(u8, result.stdout);
        } else blk: {
            break :blk try self.allocator.dupe(u8, compressed_data);
        };
        defer self.allocator.free(body_data);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            TokenResponse,
            self.allocator,
            body_data,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const token_response = parsed.value;

        // Extract tokens
        return OAuthTokens{
            .access_token = try self.allocator.dupe(u8, token_response.access_token),
            .refresh_token = if (token_response.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                null,
            .token_type = try self.allocator.dupe(u8, token_response.token_type),
            .expires_in = token_response.expires_in,
            .scope = if (token_response.scope) |s|
                try self.allocator.dupe(u8, s)
            else
                null,
        };
    }

    /// Refresh an expired access token
    pub fn refreshToken(self: *AnthropicOAuth, refresh_token: []const u8) !OAuthTokens {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Build request body
        const body = try std.fmt.allocPrint(
            self.allocator,
            "grant_type=refresh_token&refresh_token={s}&client_id={s}",
            .{
                refresh_token,
                CLIENT_ID,
            },
        );
        defer self.allocator.free(body);

        // Parse URL
        const uri = try std.Uri.parse(TOKEN_URL);

        // Create request using the new API
        const extra_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        };

        var request = try client.request(.POST, uri, .{
            .extra_headers = &extra_headers,
        });
        defer request.deinit();

        // Send request body
        try request.sendBodyComplete(body);

        // Receive response headers
        var redirect_buf: [4096]u8 = undefined;
        var response = try request.receiveHead(&redirect_buf);

        // Check status
        if (response.head.status != .ok) {
            return error.TokenRefreshFailed;
        }

        // Read response body
        var response_body: [4096]u8 = undefined;
        const response_reader = response.reader(&response_body);
        const body_data = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(body_data);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            TokenResponse,
            self.allocator,
            body_data,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const token_response = parsed.value;

        // Extract tokens
        return OAuthTokens{
            .access_token = try self.allocator.dupe(u8, token_response.access_token),
            .refresh_token = if (token_response.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                try self.allocator.dupe(u8, refresh_token), // Keep old refresh token
            .token_type = try self.allocator.dupe(u8, token_response.token_type),
            .expires_in = token_response.expires_in,
            .scope = if (token_response.scope) |s|
                try self.allocator.dupe(u8, s)
            else
                null,
        };
    }
};

/// OAuth token response from Anthropic
const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    token_type: []const u8,
    expires_in: i64,
    scope: ?[]const u8 = null,
};

/// OAuth tokens returned to caller
pub const OAuthTokens = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8,
    token_type: []const u8,
    expires_in: i64,
    scope: ?[]const u8,

    pub fn deinit(self: *OAuthTokens, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |rt| allocator.free(rt);
        allocator.free(self.token_type);
        if (self.scope) |s| allocator.free(s);
    }
};

// === Tests ===

test "anthropic oauth compile" {
    const allocator = std.testing.allocator;
    const oauth = AnthropicOAuth.init(allocator);
    _ = oauth;
}

test "build auth url" {
    const allocator = std.testing.allocator;
    var oauth = AnthropicOAuth.init(allocator);

    const url = try oauth.buildAuthUrl("http://localhost:8080/callback", "challenge123");
    defer allocator.free(url);

    // Verify URL contains required components
    try std.testing.expect(std.mem.indexOf(u8, url, AnthropicOAuth.AUTH_URL) != null);
    try std.testing.expect(std.mem.indexOf(u8, url, AnthropicOAuth.CLIENT_ID) != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=") != null);
}
