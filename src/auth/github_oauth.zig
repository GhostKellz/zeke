const std = @import("std");
const BrowserOpener = @import("browser.zig").BrowserOpener;

/// GitHub Copilot OAuth using Device Flow
/// Based on VS Code's approach and OpenCode implementation
pub const GitHubOAuth = struct {
    /// VS Code's public OAuth client ID (publicly known, can be reused)
    pub const CLIENT_ID = "Iv1.b507a08c87ecfe98";

    /// GitHub Device Authorization endpoint
    pub const DEVICE_CODE_URL = "https://github.com/login/device/code";

    /// GitHub OAuth token endpoint
    pub const TOKEN_URL = "https://github.com/login/oauth/access_token";

    /// GitHub Copilot token exchange endpoint
    pub const COPILOT_TOKEN_URL = "https://api.github.com/copilot_internal/v2/token";

    /// Required scopes for GitHub Copilot
    pub const SCOPES = "read:user";

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GitHubOAuth {
        return .{ .allocator = allocator };
    }

    /// Perform GitHub Device Flow OAuth and return GitHub access token
    pub fn authorize(self: *GitHubOAuth) !OAuthTokens {
        std.debug.print("\n🔐 Starting GitHub Device Flow authentication...\n\n", .{});

        // 1. Request device code
        const device_code_response = try self.requestDeviceCode();
        defer device_code_response.deinit(self.allocator);

        std.debug.print("✓ Device code received\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("  GitHub Authentication\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Visit: \x1b[94m\x1b[4m{s}\x1b[0m\n", .{device_code_response.verification_uri});
        std.debug.print("Enter code: \x1b[1m\x1b[93m{s}\x1b[0m\n", .{device_code_response.user_code});
        std.debug.print("\n", .{});

        // 2. Optionally open browser to verification page
        const verification_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}",
            .{device_code_response.verification_uri},
        );
        defer self.allocator.free(verification_url);

        BrowserOpener.openWithFallback(self.allocator, verification_url);

        // 3. Poll for authorization
        std.debug.print("⏳ Waiting for authorization...\n", .{});

        const github_token = try self.pollForToken(
            device_code_response.device_code,
            device_code_response.interval,
        );

        std.debug.print("\n✅ GitHub authentication successful!\n", .{});

        return OAuthTokens{
            .access_token = github_token,
            .token_type = try self.allocator.dupe(u8, "Bearer"),
            .scope = try self.allocator.dupe(u8, SCOPES),
        };
    }

    /// Request device code from GitHub
    fn requestDeviceCode(self: *GitHubOAuth) !DeviceCodeResponse {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Build request body
        const body = try std.fmt.allocPrint(
            self.allocator,
            "client_id={s}&scope={s}",
            .{ CLIENT_ID, SCOPES },
        );
        defer self.allocator.free(body);

        // Parse URL
        const uri = try std.Uri.parse(DEVICE_CODE_URL);

        // Create request
        const extra_headers = [_]std.http.Header{
            .{ .name = "Accept", .value = "application/json" },
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
            std.debug.print("❌ Device code request failed with status: {}\n", .{response.head.status});
            return error.DeviceCodeRequestFailed;
        }

        // Read response body
        var response_body: [4096]u8 = undefined;
        const response_reader = response.reader(&response_body);
        const body_data = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(body_data);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            DeviceCodeResponseJson,
            self.allocator,
            body_data,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const dc = parsed.value;

        return DeviceCodeResponse{
            .device_code = try self.allocator.dupe(u8, dc.device_code),
            .user_code = try self.allocator.dupe(u8, dc.user_code),
            .verification_uri = try self.allocator.dupe(u8, dc.verification_uri),
            .expires_in = dc.expires_in,
            .interval = dc.interval orelse 5,
        };
    }

    /// Poll GitHub for authorization
    fn pollForToken(self: *GitHubOAuth, device_code: []const u8, interval: i64) ![]const u8 {
        const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        var spinner_idx: usize = 0;

        const max_attempts = 120; // 10 minutes at 5 second intervals
        const poll_interval_ns = @as(u64, @intCast(interval)) * std.time.ns_per_s;

        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            // Wait before polling
            std.Thread.sleep(poll_interval_ns);

            // Show spinner
            const elapsed_seconds: i64 = @intCast(attempt * @as(usize, @intCast(interval)));
            std.debug.print("\r{s} Waiting for authorization... ({d}s)", .{
                spinner_chars[spinner_idx],
                elapsed_seconds,
            });
            spinner_idx = (spinner_idx + 1) % spinner_chars.len;

            var client = std.http.Client{ .allocator = self.allocator };
            defer client.deinit();

            // Build request body
            const body = try std.fmt.allocPrint(
                self.allocator,
                "client_id={s}&device_code={s}&grant_type=urn:ietf:params:oauth:grant-type:device_code",
                .{ CLIENT_ID, device_code },
            );
            defer self.allocator.free(body);

            // Parse URL
            const uri = try std.Uri.parse(TOKEN_URL);

            // Create request
            const extra_headers = [_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
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

            // Read response body
            var response_body: [4096]u8 = undefined;
            const response_reader = response.reader(&response_body);
            const body_data = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
            defer self.allocator.free(body_data);

            // Check if response is successful
            if (response.head.status == .ok) {
                // Parse JSON response
                const parsed = try std.json.parseFromSlice(
                    TokenResponseJson,
                    self.allocator,
                    body_data,
                    .{ .ignore_unknown_fields = true },
                );
                defer parsed.deinit();

                if (parsed.value.access_token) |token| {
                    std.debug.print("\r✓ Authorization successful!         \n", .{});
                    return try self.allocator.dupe(u8, token);
                }

                if (parsed.value.@"error") |err| {
                    if (std.mem.eql(u8, err, "authorization_pending")) {
                        // Continue polling
                        continue;
                    } else if (std.mem.eql(u8, err, "slow_down")) {
                        // Slow down polling
                        std.Thread.sleep(5 * std.time.ns_per_s);
                        continue;
                    } else {
                        std.debug.print("\n❌ Authorization failed: {s}\n", .{err});
                        return error.AuthorizationFailed;
                    }
                }
            }
        }

        std.debug.print("\n❌ Authorization timeout\n", .{});
        return error.AuthorizationTimeout;
    }

    /// Get Copilot-specific token from GitHub token
    pub fn getCopilotToken(self: *GitHubOAuth, github_token: []const u8) !CopilotTokens {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Parse URL
        const uri = try std.Uri.parse(COPILOT_TOKEN_URL);

        // Create request
        const auth_header_value = try std.fmt.allocPrint(
            self.allocator,
            "Bearer {s}",
            .{github_token},
        );
        defer self.allocator.free(auth_header_value);

        const extra_headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = auth_header_value },
            .{ .name = "Accept", .value = "application/json" },
        };

        var request = try client.request(.GET, uri, .{
            .extra_headers = &extra_headers,
        });
        defer request.deinit();

        // Send request
        try request.send();
        try request.finish();

        // Receive response headers
        var redirect_buf: [4096]u8 = undefined;
        var response = try request.receiveHead(&redirect_buf);

        // Check status
        if (response.head.status != .ok) {
            std.debug.print("❌ Copilot token request failed with status: {}\n", .{response.head.status});
            return error.CopilotTokenRequestFailed;
        }

        // Read response body
        var response_body: [4096]u8 = undefined;
        const response_reader = response.reader(&response_body);
        const body_data = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(body_data);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            CopilotTokensJson,
            self.allocator,
            body_data,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const ct = parsed.value;

        return CopilotTokens{
            .token = try self.allocator.dupe(u8, ct.token),
            .expires_at = ct.expires_at,
        };
    }
};

/// Device code response JSON structure
const DeviceCodeResponseJson = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: i64,
    interval: ?i64 = null,
};

/// Device code response
pub const DeviceCodeResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: i64,
    interval: i64,

    pub fn deinit(self: *const DeviceCodeResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.device_code);
        allocator.free(self.user_code);
        allocator.free(self.verification_uri);
    }
};

/// Token response JSON structure
const TokenResponseJson = struct {
    access_token: ?[]const u8 = null,
    token_type: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
    error_description: ?[]const u8 = null,
};

/// OAuth tokens returned to caller
pub const OAuthTokens = struct {
    access_token: []const u8,
    token_type: []const u8,
    scope: []const u8,

    pub fn deinit(self: *OAuthTokens, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        allocator.free(self.token_type);
        allocator.free(self.scope);
    }
};

/// Copilot token response JSON structure
const CopilotTokensJson = struct {
    token: []const u8,
    expires_at: i64,
};

/// Copilot-specific tokens
pub const CopilotTokens = struct {
    token: []const u8,
    expires_at: i64,

    pub fn deinit(self: *CopilotTokens, allocator: std.mem.Allocator) void {
        allocator.free(self.token);
    }
};

// === Tests ===

test "github oauth compile" {
    const allocator = std.testing.allocator;
    const oauth = GitHubOAuth.init(allocator);
    _ = oauth;
}
