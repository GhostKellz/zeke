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
    /// Get redirect URI with provider-specific override support
    fn getRedirectUri(provider: []const u8) []const u8 {
        // Check provider-specific override first
        if (std.mem.eql(u8, provider, "google")) {
            if (std.posix.getenv("ZEKE_GOOGLE_REDIRECT_URI")) |uri| return uri;
        } else if (std.mem.eql(u8, provider, "github")) {
            if (std.posix.getenv("ZEKE_GITHUB_REDIRECT_URI")) |uri| return uri;
        } else if (std.mem.eql(u8, provider, "azure")) {
            if (std.posix.getenv("ZEKE_AZURE_REDIRECT_URI")) |uri| return uri;
        }

        // Fall back to general redirect URI
        if (std.posix.getenv("ZEKE_OAUTH_REDIRECT_URI")) |uri| return uri;

        // Default to localhost
        return "http://localhost:8765/callback";
    }

    pub fn authorizeGoogle(self: *Self) !Credential {
        const broker_url = std.posix.getenv("ZEKE_OAUTH_BROKER_URL") orelse "https://auth.cktech.org";

        std.log.info("🔐 Starting Google OAuth...", .{});
        std.log.info("  Using OAuth broker: {s}", .{broker_url});
        std.log.info("", .{});

        // Start OAuth flow via broker
        const oauth_result = try self.runBrokerOAuth(broker_url, "google");

        std.log.info("✅ Google OAuth successful!", .{});
        std.log.info("  Identity: {s}", .{oauth_result.access_token orelse "unknown"});

        return oauth_result;
    }

    fn runGoogleOAuth(self: *Self, client_id: []const u8, client_secret: []const u8) !Credential {
        const redirect_uri = getRedirectUri("google");
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
        const callback_result = try self.waitForOAuthCallback();

        const tokens = switch (callback_result) {
            .tokens => |t| blk: {
                std.log.info("✅ Received tokens directly from OAuth proxy", .{});
                break :blk t;
            },
            .code => |auth_code| blk: {
                defer self.allocator.free(auth_code);
                std.log.info("Exchanging authorization code for tokens...", .{});
                break :blk try self.exchangeCodeForTokens(client_id, client_secret, auth_code, redirect_uri);
            },
        };

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
        tokens: ?OAuthTokens,
        done: bool,
        allocator: std.mem.Allocator,
    } = null;

    fn oauthCallbackHandler(req: *zhttp.ServerRequest, res: *zhttp.ServerResponse) !void {
        if (!std.mem.startsWith(u8, req.path, "/callback")) {
            res.setStatus(404);
            try res.send("Not Found");
            return;
        }

        // Check if this is a POST request with tokens (from OAuth proxy like Shade)
        if (req.method == .POST) {
            // Parse JSON body with tokens
            if (req.body.len == 0) {
                res.setStatus(400);
                try res.send("Missing request body");
                return;
            }
            const body = req.body;

            const parsed = std.json.parseFromSlice(
                struct {
                    access_token: []const u8,
                    refresh_token: ?[]const u8 = null,
                    expires_in: ?i64 = null,
                },
                if (oauth_callback_state) |*state| state.allocator else return error.NoCallbackState,
                body,
                .{ .ignore_unknown_fields = true },
            ) catch {
                res.setStatus(400);
                try res.send("Invalid JSON body");
                return;
            };
            defer parsed.deinit();

            const expires_at = if (parsed.value.expires_in) |expires_in|
                std.time.timestamp() + expires_in
            else
                null;

            // Store tokens in global state
            if (oauth_callback_state) |*state| {
                state.mutex.lock();
                defer state.mutex.unlock();

                state.tokens = OAuthTokens{
                    .access_token = try state.allocator.dupe(u8, parsed.value.access_token),
                    .refresh_token = if (parsed.value.refresh_token) |rt|
                        try state.allocator.dupe(u8, rt)
                    else
                        null,
                    .expires_at = expires_at,
                };
                state.done = true;
            }

            // Send success response
            res.setStatus(200);
            try res.setHeader("Content-Type", "application/json");
            try res.send("{\"status\":\"success\"}");
            return;
        }

        // Parse query parameters from URL (direct OAuth callback)
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

    const OAuthCallbackResult = union(enum) {
        code: []const u8,
        tokens: OAuthTokens,
    };

    fn waitForOAuthCallback(self: *Self) !OAuthCallbackResult {
        // Initialize global state
        oauth_callback_state = .{
            .mutex = .{},
            .code = null,
            .tokens = null,
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
        var joined = false;
        defer if (!joined) {
            if (@hasDecl(@TypeOf(server), "stop")) {
                server.stop();
            }
            listen_thread.join();
        };

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

        if (@hasDecl(@TypeOf(server), "stop")) {
            server.stop();
        }
        listen_thread.join();
        joined = true;

        if (server_error) |err| {
            return err;
        }

        if (oauth_callback_state) |*state| {
            state.mutex.lock();
            defer state.mutex.unlock();

            // Check if we received tokens directly from OAuth proxy
            if (state.tokens) |tokens| {
                return OAuthCallbackResult{ .tokens = tokens };
            }

            // Check if we received an authorization code
            if (state.code) |code| {
                return OAuthCallbackResult{ .code = code };
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

    /// Broker-based OAuth flow (Shade)
    fn runBrokerOAuth(self: *Self, broker_url: []const u8, provider: []const u8) !Credential {
        // Step 1: Call /oauth/start
        const start_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/oauth/start?provider={s}",
            .{ broker_url, provider },
        );
        defer self.allocator.free(start_url);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        const response_data = blk: {
            errdefer {
                const slice = allocating_writer.toOwnedSlice() catch &[_]u8{};
                self.allocator.free(slice);
            }

            const result = try client.fetch(.{
                .location = .{ .url = start_url },
                .method = .GET,
                .response_writer = &allocating_writer.writer,
            });

            if (result.status != .ok) {
                std.log.err("Failed to start OAuth flow: {}", .{result.status});
                return error.OAuthStartFailed;
            }

            break :blk try allocating_writer.toOwnedSlice();
        };
        defer self.allocator.free(response_data);

        const OAuthStartResponse = struct {
            state: []const u8,
            authorize_url: []const u8,
        };

        const parsed = try std.json.parseFromSlice(
            OAuthStartResponse,
            self.allocator,
            response_data,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();

        const state = parsed.value.state;
        const authorize_url = parsed.value.authorize_url;

        // Step 2: Print URL (clickable in most terminals)
        std.log.info("", .{});
        std.debug.print("To authenticate, open this link:\n\n  \x1b[94m\x1b[4m{s}\x1b[0m\n\n", .{authorize_url});

        // Step 3: Poll for completion
        std.log.info("Waiting for authentication...", .{});
        return try self.pollBroker(broker_url, state);
    }

    fn pollBroker(self: *Self, broker_url: []const u8, state: []const u8) !Credential {
        const poll_url_template = "{s}/cli/poll?state={s}";
        const max_attempts = 60; // 5 minutes at 5 second intervals
        const poll_interval_ns = 5 * std.time.ns_per_s;

        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            std.Thread.sleep(poll_interval_ns);

            const poll_url = try std.fmt.allocPrint(
                self.allocator,
                poll_url_template,
                .{ broker_url, state },
            );
            defer self.allocator.free(poll_url);

            var client = std.http.Client{ .allocator = self.allocator };

            var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
            const response_body = blk: {
                errdefer {
                    const slice = allocating_writer.toOwnedSlice() catch &[_]u8{};
                    self.allocator.free(slice);
                }

                const result = client.fetch(.{
                    .location = .{ .url = poll_url },
                    .method = .GET,
                    .response_writer = &allocating_writer.writer,
                }) catch continue;

                if (result.status != .ok) continue;

                break :blk allocating_writer.toOwnedSlice() catch {
                    client.deinit();
                    continue;
                };
            };
            defer {
                self.allocator.free(response_body);
                client.deinit();
            }

            const PollResponse = struct {
                status: []const u8,
                access_token: ?[]const u8 = null,
                refresh_token: ?[]const u8 = null,
                id_token: ?[]const u8 = null,
                user_email: ?[]const u8 = null,
                message: ?[]const u8 = null,
            };

            const parsed = try std.json.parseFromSlice(
                PollResponse,
                self.allocator,
                response_body,
                .{ .ignore_unknown_fields = true },
            );
            defer parsed.deinit();

            if (std.mem.eql(u8, parsed.value.status, "success")) {
                std.log.info("✅ Authentication complete for: {s}", .{parsed.value.user_email orelse "unknown"});
                return Credential{
                    .provider = .google,
                    .access_token = if (parsed.value.access_token) |t| try self.allocator.dupe(u8, t) else null,
                    .refresh_token = if (parsed.value.refresh_token) |t| try self.allocator.dupe(u8, t) else null,
                    .expires_at = null,
                };
            } else if (std.mem.eql(u8, parsed.value.status, "error")) {
                std.log.err("OAuth error: {s}", .{parsed.value.message orelse "unknown"});
                return error.OAuthFailed;
            }
            // else status == "pending", continue polling
        }

        std.log.err("OAuth timeout after 5 minutes", .{});
        return error.OAuthTimeout;
    }

    /// Start GitHub OAuth flow for Copilot Pro
    pub fn authorizeGitHub(self: *Self) !Credential {
        const redirect_uri = getRedirectUri("github");

        const client_id = std.posix.getenv("ZEKE_GITHUB_CLIENT_ID") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_ID not set.", .{});
            std.log.err("", .{});
            std.log.err("To get GitHub OAuth credentials:", .{});
            std.log.err("1. Go to https://github.com/settings/developers", .{});
            std.log.err("2. Create a new OAuth App", .{});
            std.log.err("3. Set callback URL to: {s}", .{redirect_uri});
            std.log.err("4. Set ZEKE_GITHUB_CLIENT_ID and ZEKE_GITHUB_CLIENT_SECRET", .{});
            std.log.err("", .{});
            std.log.err("Optional: Set ZEKE_GITHUB_REDIRECT_URI or ZEKE_OAUTH_REDIRECT_URI to use a custom OAuth proxy", .{});
            return error.MissingGitHubClientId;
        };

        const client_secret = std.posix.getenv("ZEKE_GITHUB_CLIENT_SECRET") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_SECRET not set.", .{});
            return error.MissingGitHubClientSecret;
        };

        std.log.info("🔐 Starting GitHub OAuth for Copilot Pro...", .{});
        std.log.info("  Redirect URI: {s}", .{redirect_uri});
        std.log.info("", .{});

        // Start OAuth flow
        const oauth_result = try self.runGitHubOAuth(client_id, client_secret);

        std.log.info("✅ GitHub OAuth successful!", .{});
        std.log.info("  You can now use GitHub Copilot Pro", .{});

        return oauth_result;
    }

    pub fn authenticateGoogle(self: *Self, auth_code: []const u8) !void {
        const client_id = std.posix.getenv("ZEKE_GOOGLE_CLIENT_ID") orelse {
            std.log.err("ZEKE_GOOGLE_CLIENT_ID not set.", .{});
            return error.MissingGoogleClientId;
        };

        const client_secret = std.posix.getenv("ZEKE_GOOGLE_CLIENT_SECRET") orelse {
            std.log.err("ZEKE_GOOGLE_CLIENT_SECRET not set.", .{});
            return error.MissingGoogleClientSecret;
        };

        const redirect_uri = getRedirectUri("google");

        const tokens = try self.exchangeCodeForTokens(client_id, client_secret, auth_code, redirect_uri);
        const credential = Credential{
            .provider = .google,
            .access_token = tokens.access_token,
            .refresh_token = tokens.refresh_token,
            .expires_at = tokens.expires_at,
        };
        defer self.freeCredential(credential);

        try self.upsertCredential(credential);

        std.log.info("✅ Google OAuth tokens saved", .{});
    }

    pub fn authenticateGitHub(self: *Self, code: []const u8) !void {
        const client_id = std.posix.getenv("ZEKE_GITHUB_CLIENT_ID") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_ID not set.", .{});
            return error.MissingGitHubClientId;
        };

        const client_secret = std.posix.getenv("ZEKE_GITHUB_CLIENT_SECRET") orelse {
            std.log.err("ZEKE_GITHUB_CLIENT_SECRET not set.", .{});
            return error.MissingGitHubClientSecret;
        };

        const redirect_uri = getRedirectUri("github");

        const tokens = try self.exchangeGitHubCodeForTokens(client_id, client_secret, code, redirect_uri);
        const credential = Credential{
            .provider = .github,
            .access_token = tokens.access_token,
            .refresh_token = tokens.refresh_token,
            .expires_at = tokens.expires_at,
        };
        defer self.freeCredential(credential);

        try self.upsertCredential(credential);

        std.log.info("✅ GitHub OAuth tokens saved", .{});
    }

    pub fn setOpenAIToken(self: *Self, token: []const u8) !void {
        try self.setApiKey(.openai, token);
    }

    pub fn freeCredential(self: *Self, credential: Credential) void {
        if (credential.access_token) |token| {
            self.allocator.free(token);
        }
        if (credential.refresh_token) |token| {
            self.allocator.free(token);
        }
        if (credential.api_key) |key| {
            self.allocator.free(key);
        }
    }

    fn runGitHubOAuth(self: *Self, client_id: []const u8, client_secret: []const u8) !Credential {
        const redirect_uri = getRedirectUri("github");
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
        const callback_result = try self.waitForOAuthCallback();

        const tokens = switch (callback_result) {
            .tokens => |t| blk: {
                std.log.info("✅ Received tokens directly from OAuth proxy", .{});
                break :blk t;
            },
            .code => |auth_code| blk: {
                defer self.allocator.free(auth_code);
                std.log.info("Exchanging authorization code for tokens...", .{});
                break :blk try self.exchangeGitHubCodeForTokens(client_id, client_secret, auth_code, redirect_uri);
            },
        };

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
        defer parsed.deinit();

        // Duplicate the credentials so we own them after parsed is freed
        var owned_creds = std.array_list.AlignedManaged(Credential, null).init(self.allocator);
        errdefer owned_creds.deinit();

        for (parsed.value.credentials) |cred| {
            try owned_creds.append(.{
                .provider = cred.provider,
                .access_token = if (cred.access_token) |t| try self.allocator.dupe(u8, t) else null,
                .refresh_token = if (cred.refresh_token) |t| try self.allocator.dupe(u8, t) else null,
                .api_key = if (cred.api_key) |k| try self.allocator.dupe(u8, k) else null,
                .expires_at = cred.expires_at,
            });
        }

        return .{ .credentials = try owned_creds.toOwnedSlice() };
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
