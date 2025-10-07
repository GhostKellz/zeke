const std = @import("std");
const flash = @import("flash");
const zhttp = @import("zhttp");

/// Authentication provider types
pub const AuthProvider = enum {
    google, // For Claude via Google Identity, OpenAI via Google
    github, // For GitHub Copilot
    openai, // OpenAI (OAuth via Google or direct API key)
    anthropic, // Direct Anthropic/Claude API key
    azure, // Azure OpenAI API key
    local, // Local providers (Ollama, etc.) - no auth needed
};

/// Stored credential
pub const Credential = struct {
    provider: AuthProvider,
    access_token: ?[]const u8 = null,
    refresh_token: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    expires_at: ?i64 = null,
};

/// Credentials file format
const CredentialsFile = struct {
    credentials: []Credential = &.{},
};

/// Authentication manager
pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    credentials_path: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
        const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/zeke", .{home});
        defer allocator.free(config_dir);

        // Ensure config directory exists
        std.fs.makeDirAbsolute(config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const credentials_path = try std.fmt.allocPrint(allocator, "{s}/credentials.json", .{config_dir});

        return Self{
            .allocator = allocator,
            .credentials_path = credentials_path,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.credentials_path);
    }

    /// Start Google OAuth flow for Claude Max/ChatGPT Pro
    pub fn authorizeGoogle(self: *Self) !Credential {
        const client_id = std.posix.getenv("ZEKE_GOOGLE_CLIENT_ID") orelse {
            std.log.err("ZEKE_GOOGLE_CLIENT_ID not set.", .{});
            std.log.err("", .{});
            std.log.err("To get Google OAuth credentials:", .{});
            std.log.err("1. Go to https://console.cloud.google.com/apis/credentials", .{});
            std.log.err("2. Create OAuth 2.0 Client ID", .{});
            std.log.err("3. Add http://localhost:8765/callback as redirect URI", .{});
            std.log.err("4. Set ZEKE_GOOGLE_CLIENT_ID and ZEKE_GOOGLE_CLIENT_SECRET", .{});
            return error.MissingGoogleClientId;
        };

        const client_secret = std.posix.getenv("ZEKE_GOOGLE_CLIENT_SECRET") orelse {
            std.log.err("ZEKE_GOOGLE_CLIENT_SECRET not set.", .{});
            return error.MissingGoogleClientSecret;
        };

        std.log.info("🔐 Starting Google OAuth for Claude Max + ChatGPT Pro...", .{});
        std.log.info("", .{});

        // Start OAuth flow
        const oauth_result = try self.runGoogleOAuth(client_id, client_secret);

        std.log.info("✅ Google OAuth successful!", .{});
        std.log.info("  You can now use Claude Max and ChatGPT Pro via Google", .{});

        return oauth_result;
    }

    fn runGoogleOAuth(self: *Self, client_id: []const u8, client_secret: []const u8) !Credential {
        const redirect_uri = "http://localhost:8765/callback";
        const scope = "openid email profile";

        // Build authorization URL
        const auth_url = try std.fmt.allocPrint(
            self.allocator,
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={s}&redirect_uri={s}&response_type=code&scope={s}&access_type=offline",
            .{ client_id, redirect_uri, scope },
        );
        defer self.allocator.free(auth_url);

        std.log.info("Opening browser for Google Sign-in...", .{});
        std.log.info("URL: {s}", .{auth_url});
        std.log.info("", .{});

        // Open browser (platform-specific)
        const open_cmd = if (@import("builtin").os.tag == .linux)
            "xdg-open"
        else if (@import("builtin").os.tag == .macos)
            "open"
        else
            "start";

        var child = std.process.Child.init(&[_][]const u8{ open_cmd, auth_url }, self.allocator);
        _ = child.spawnAndWait() catch {
            std.log.warn("Could not open browser automatically. Please open manually:", .{});
            std.log.warn("{s}", .{auth_url});
        };

        // Start callback server
        std.log.info("Waiting for OAuth callback on http://localhost:8765/callback...", .{});
        const auth_code = try self.waitForOAuthCallback();

        std.log.info("Exchanging authorization code for tokens...", .{});

        // Exchange code for tokens
        const tokens = try self.exchangeCodeForTokens(client_id, client_secret, auth_code, redirect_uri);

        return Credential{
            .provider = .google,
            .access_token = tokens.access_token,
            .refresh_token = tokens.refresh_token,
            .expires_at = tokens.expires_at,
        };
    }

    const OAuthTokens = struct {
        access_token: []const u8,
        refresh_token: ?[]const u8,
        expires_at: ?i64,
    };

    // Global OAuth callback state (thread-safe via mutex)
    var oauth_callback_state: ?struct {
        mutex: std.Thread.Mutex,
        code: ?[]const u8,
        done: bool,
        allocator: std.mem.Allocator,
    } = null;

    fn oauthCallbackHandler(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        if (!std.mem.startsWith(u8, req.path, "/callback")) {
            res.setStatus(404);
            try res.send("Not Found");
            return;
        }

        // Parse query parameters from URL
        if (std.mem.indexOf(u8, req.path, "?code=")) |idx| {
            const query_start = idx + 6; // Skip "?code="
            const code_end = std.mem.indexOfScalarPos(u8, req.path, query_start, '&') orelse req.path.len;
            const code = req.path[query_start..code_end];

            // Store code in global state
            if (oauth_callback_state) |*state| {
                state.mutex.lock();
                defer state.mutex.unlock();

                state.code = try state.allocator.dupe(u8, code);
                state.done = true;
            }

            // Send success page
            res.setStatus(200);
            try res.setHeader("Content-Type", "text/html");
            const success_html =
                \\<!DOCTYPE html>
                \\<html>
                \\<head><title>Authentication Successful</title></head>
                \\<body style="font-family: Arial, sans-serif; text-align: center; padding: 50px;">
                \\  <h1>✅ Authentication Successful!</h1>
                \\  <p>You can close this window and return to the terminal.</p>
                \\</body>
                \\</html>
            ;
            try res.send(success_html);
        } else {
            // No code found - show error
            res.setStatus(400);
            try res.setHeader("Content-Type", "text/html");
            const error_html =
                \\<!DOCTYPE html>
                \\<html>
                \\<head><title>Authentication Failed</title></head>
                \\<body style="font-family: Arial, sans-serif; text-align: center; padding: 50px;">
                \\  <h1>❌ Authentication Failed</h1>
                \\  <p>No authorization code received. Please try again.</p>
                \\</body>
                \\</html>
            ;
            try res.send(error_html);

            if (oauth_callback_state) |*state| {
                state.mutex.lock();
                defer state.mutex.unlock();
                state.done = true;
            }
        }
    }

    fn waitForOAuthCallback(self: *Self) ![]const u8 {
        // Initialize global state
        oauth_callback_state = .{
            .mutex = .{},
            .code = null,
            .done = false,
            .allocator = self.allocator,
        };
        defer oauth_callback_state = null;

        // Start server on port 8765
        var server = zhttp.Server.init(self.allocator, .{
            .host = "127.0.0.1",
            .port = 8765,
        }, oauthCallbackHandler);
        defer server.deinit();

        std.log.info("OAuth callback server listening on http://127.0.0.1:8765/callback", .{});

        // Start server in background
        var server_error: ?anyerror = null;
        const listen_thread = try std.Thread.spawn(.{}, struct {
            fn run(srv: *zhttp.Server, err: *?anyerror) void {
                srv.listen() catch |e| {
                    err.* = e;
                    if (oauth_callback_state) |*state| {
                        state.mutex.lock();
                        defer state.mutex.unlock();
                        state.done = true;
                    }
                    return;
                };
            }
        }.run, .{ &server, &server_error });

        // Wait for callback (with timeout)
        const timeout_ns = 5 * 60 * std.time.ns_per_s; // 5 minutes
        const start_time = std.time.nanoTimestamp();

        while (true) {
            std.Thread.sleep(100 * std.time.ns_per_ms);

            var done = false;
            if (oauth_callback_state) |*state| {
                state.mutex.lock();
                done = state.done;
                state.mutex.unlock();
            }

            if (done) break;

            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed > timeout_ns) {
                std.log.err("OAuth callback timeout after 5 minutes", .{});
                return error.OAuthTimeout;
            }
        }

        listen_thread.join();

        if (server_error) |err| {
            return err;
        }

        if (oauth_callback_state) |*state| {
            state.mutex.lock();
            defer state.mutex.unlock();

            if (state.code) |code| {
                return code;
            }
        }

        return error.NoAuthCode;
    }

    fn exchangeCodeForTokens(self: *Self, client_id: []const u8, client_secret: []const u8, code: []const u8, redirect_uri: []const u8) !OAuthTokens {
        // Build POST body
        const post_body = try std.fmt.allocPrint(
            self.allocator,
            "code={s}&client_id={s}&client_secret={s}&redirect_uri={s}&grant_type=authorization_code",
            .{ code, client_id, client_secret, redirect_uri },
        );
        defer self.allocator.free(post_body);

        // Make HTTP POST request to Google's token endpoint
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse("https://oauth2.googleapis.com/token");

        var req = try client.request(.POST, uri, .{
            .headers = .{
                .content_type = .{ .override = "application/x-www-form-urlencoded" },
            },
        });
        defer req.deinit();

        // Send the body
        try req.sendBodyComplete(post_body);

        // Receive response headers
        var redirect_buffer: [4096]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        // Check status
        if (response.head.status != .ok) {
            std.log.err("Token exchange failed with status: {}", .{response.head.status});
            return error.TokenExchangeFailed;
        }

        // Read response body
        var response_buffer: [4096]u8 = undefined;
        const response_reader = response.reader(&response_buffer);
        const response_body = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(response_body);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            struct {
                access_token: []const u8,
                refresh_token: ?[]const u8 = null,
                expires_in: ?i64 = null,
                token_type: []const u8,
            },
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const expires_at = if (parsed.value.expires_in) |expires_in|
            std.time.timestamp() + expires_in
        else
            null;

        return OAuthTokens{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = if (parsed.value.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                null,
            .expires_at = expires_at,
        };
    }

    /// Start GitHub OAuth flow for Copilot Pro
    pub fn authorizeGitHub(self: *Self) !Credential {
        const client_id = std.posix.getenv("ZEKE_GITHUB_CLIENT_ID") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_ID not set.", .{});
            std.log.err("", .{});
            std.log.err("To get GitHub OAuth credentials:", .{});
            std.log.err("1. Go to https://github.com/settings/developers", .{});
            std.log.err("2. Create a new OAuth App", .{});
            std.log.err("3. Set callback URL to http://localhost:8765/callback", .{});
            std.log.err("4. Set ZEKE_GITHUB_CLIENT_ID and ZEKE_GITHUB_CLIENT_SECRET", .{});
            return error.MissingGitHubClientId;
        };

        const client_secret = std.posix.getenv("ZEKE_GITHUB_CLIENT_SECRET") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_SECRET not set.", .{});
            return error.MissingGitHubClientSecret;
        };

        std.log.info("🔐 Starting GitHub OAuth for Copilot Pro...", .{});
        std.log.info("", .{});

        // Start OAuth flow
        const oauth_result = try self.runGitHubOAuth(client_id, client_secret);

        std.log.info("✅ GitHub OAuth successful!", .{});
        std.log.info("  You can now use GitHub Copilot Pro", .{});

        return oauth_result;
    }

    fn runGitHubOAuth(self: *Self, client_id: []const u8, client_secret: []const u8) !Credential {
        const redirect_uri = "http://localhost:8765/callback";
        const scope = "read:user user:email";

        // Build authorization URL
        const auth_url = try std.fmt.allocPrint(
            self.allocator,
            "https://github.com/login/oauth/authorize?client_id={s}&redirect_uri={s}&scope={s}",
            .{ client_id, redirect_uri, scope },
        );
        defer self.allocator.free(auth_url);

        std.log.info("Opening browser for GitHub Sign-in...", .{});
        std.log.info("URL: {s}", .{auth_url});
        std.log.info("", .{});

        // Open browser (platform-specific)
        const open_cmd = if (@import("builtin").os.tag == .linux)
            "xdg-open"
        else if (@import("builtin").os.tag == .macos)
            "open"
        else
            "start";

        var child = std.process.Child.init(&[_][]const u8{ open_cmd, auth_url }, self.allocator);
        _ = child.spawnAndWait() catch {
            std.log.warn("Could not open browser automatically. Please open manually:", .{});
            std.log.warn("{s}", .{auth_url});
        };

        // Start callback server
        std.log.info("Waiting for OAuth callback on http://localhost:8765/callback...", .{});
        const auth_code = try self.waitForOAuthCallback();

        std.log.info("Exchanging authorization code for tokens...", .{});

        // Exchange code for tokens
        const tokens = try self.exchangeGitHubCodeForTokens(client_id, client_secret, auth_code, redirect_uri);

        return Credential{
            .provider = .github,
            .access_token = tokens.access_token,
            .refresh_token = tokens.refresh_token,
            .expires_at = tokens.expires_at,
        };
    }

    fn exchangeGitHubCodeForTokens(self: *Self, client_id: []const u8, client_secret: []const u8, code: []const u8, redirect_uri: []const u8) !OAuthTokens {
        // Build POST body
        const post_body = try std.fmt.allocPrint(
            self.allocator,
            "client_id={s}&client_secret={s}&code={s}&redirect_uri={s}",
            .{ client_id, client_secret, code, redirect_uri },
        );
        defer self.allocator.free(post_body);

        // Make HTTP POST request to GitHub's token endpoint
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try std.Uri.parse("https://github.com/login/oauth/access_token");

        const accept_header = [_]std.http.Header{
            .{ .name = "Accept", .value = "application/json" },
        };

        var req = try client.request(.POST, uri, .{
            .headers = .{
                .content_type = .{ .override = "application/x-www-form-urlencoded" },
            },
            .extra_headers = &accept_header,
        });
        defer req.deinit();

        // Send the body
        try req.sendBodyComplete(post_body);

        // Receive response headers
        var redirect_buffer: [4096]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        // Check status
        if (response.head.status != .ok) {
            std.log.err("Token exchange failed with status: {}", .{response.head.status});
            return error.TokenExchangeFailed;
        }

        // Read response body
        var response_buffer: [4096]u8 = undefined;
        const response_reader = response.reader(&response_buffer);
        const response_body = try response_reader.*.allocRemaining(self.allocator, @enumFromInt(1024 * 1024));
        defer self.allocator.free(response_body);

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(
            struct {
                access_token: []const u8,
                refresh_token: ?[]const u8 = null,
                expires_in: ?i64 = null,
                token_type: []const u8,
            },
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const expires_at = if (parsed.value.expires_in) |expires_in|
            std.time.timestamp() + expires_in
        else
            null;

        return OAuthTokens{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = if (parsed.value.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                null,
            .expires_at = expires_at,
        };
    }

    /// Set API key for a provider
    pub fn setApiKey(self: *Self, provider: AuthProvider, api_key: []const u8) !void {
        const credential = Credential{
            .provider = provider,
            .api_key = api_key,
        };

        try self.upsertCredential(credential);

        const provider_name = @tagName(provider);
        std.log.info("✅ API key saved for {s}", .{provider_name});
    }

    /// Get token string for a provider (returns access_token or api_key)
    pub fn getToken(self: *Self, provider: AuthProvider) !?[]const u8 {
        const cred = try self.getCredential(provider) orelse return null;

        // Prefer access_token (OAuth), fall back to api_key
        if (cred.access_token) |token| {
            return try self.allocator.dupe(u8, token);
        } else if (cred.api_key) |key| {
            return try self.allocator.dupe(u8, key);
        }

        return null;
    }

    /// Get credential for a provider
    pub fn getCredential(self: *Self, provider: AuthProvider) !?Credential {
        const creds = try self.loadCredentials();
        defer self.freeCredentials(creds);

        for (creds.credentials) |cred| {
            if (cred.provider == provider) {
                // Duplicate strings for caller
                return Credential{
                    .provider = cred.provider,
                    .access_token = if (cred.access_token) |t| try self.allocator.dupe(u8, t) else null,
                    .refresh_token = if (cred.refresh_token) |t| try self.allocator.dupe(u8, t) else null,
                    .api_key = if (cred.api_key) |k| try self.allocator.dupe(u8, k) else null,
                    .expires_at = cred.expires_at,
                };
            }
        }

        return null;
    }

    /// Load credentials from file
    fn loadCredentials(self: *Self) !CredentialsFile {
        const content = std.fs.cwd().readFileAlloc(
            self.credentials_path,
            self.allocator,
            @enumFromInt(1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => return CredentialsFile{},
            else => return err,
        };
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(
            CredentialsFile,
            self.allocator,
            content,
            .{ .ignore_unknown_fields = true },
        );

        return parsed.value;
    }

    /// Free credentials loaded from file
    fn freeCredentials(self: *Self, creds: CredentialsFile) void {
        for (creds.credentials) |cred| {
            if (cred.access_token) |t| self.allocator.free(t);
            if (cred.refresh_token) |t| self.allocator.free(t);
            if (cred.api_key) |k| self.allocator.free(k);
        }
        self.allocator.free(creds.credentials);
    }

    /// Upsert credential (update or insert)
    pub fn upsertCredential(self: *Self, credential: Credential) !void {
        const creds = try self.loadCredentials();
        defer self.freeCredentials(creds);

        // Find existing credential for this provider
        var idx: ?usize = null;
        for (creds.credentials, 0..) |c, i| {
            if (c.provider == credential.provider) {
                idx = i;
                break;
            }
        }

        var list = std.array_list.AlignedManaged(Credential, null).init(self.allocator);
        defer list.deinit();

        // Copy all credentials except the one we're updating
        for (creds.credentials, 0..) |c, i| {
            if (idx == null or i != idx.?) {
                try list.append(.{
                    .provider = c.provider,
                    .access_token = if (c.access_token) |t| try self.allocator.dupe(u8, t) else null,
                    .refresh_token = if (c.refresh_token) |t| try self.allocator.dupe(u8, t) else null,
                    .api_key = if (c.api_key) |k| try self.allocator.dupe(u8, k) else null,
                    .expires_at = c.expires_at,
                });
            }
        }

        // Add new/updated credential
        try list.append(.{
            .provider = credential.provider,
            .access_token = if (credential.access_token) |t| try self.allocator.dupe(u8, t) else null,
            .refresh_token = if (credential.refresh_token) |t| try self.allocator.dupe(u8, t) else null,
            .api_key = if (credential.api_key) |k| try self.allocator.dupe(u8, k) else null,
            .expires_at = credential.expires_at,
        });

        const new_creds = CredentialsFile{
            .credentials = try list.toOwnedSlice(),
        };
        defer {
            for (new_creds.credentials) |c| {
                if (c.access_token) |t| self.allocator.free(t);
                if (c.refresh_token) |t| self.allocator.free(t);
                if (c.api_key) |k| self.allocator.free(k);
            }
            self.allocator.free(new_creds.credentials);
        }

        // Write to file
        const json = try std.json.Stringify.valueAlloc(self.allocator, new_creds, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json);

        const tmp_file = try std.fs.createFileAbsolute(self.credentials_path, .{ .truncate = true });
        defer tmp_file.close();

        try tmp_file.writeAll(json);

        // Set file permissions to user-only (Linux/macOS)
        if (@import("builtin").os.tag != .windows) {
            try std.posix.fchmod(tmp_file.handle, 0o600);
        }
    }
};
