const std = @import("std");
const Keyring = @import("keyring.zig").Keyring;
const AnthropicOAuth = @import("anthropic_oauth.zig").AnthropicOAuth;
const OAuthTokens = @import("anthropic_oauth.zig").OAuthTokens;

/// Token metadata stored alongside access token
pub const TokenMetadata = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8,
    expires_at: i64, // Unix timestamp
    token_type: []const u8,

    pub fn deinit(self: *TokenMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        if (self.refresh_token) |rt| allocator.free(rt);
        allocator.free(self.token_type);
    }

    pub fn isExpired(self: *const TokenMetadata) bool {
        const now = std.time.timestamp();
        // Consider expired if within 5 minutes of expiry (buffer for refresh)
        return now >= (self.expires_at - 300);
    }
};

/// Authentication manager for API keys and OAuth tokens
/// Supports environment variables, keyring, and OAuth flows
pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    keys: std.StringHashMap([]const u8),
    tokens: std.StringHashMap(TokenMetadata),
    keyring: Keyring,

    pub fn init(allocator: std.mem.Allocator) AuthManager {
        return .{
            .allocator = allocator,
            .keys = std.StringHashMap([]const u8).init(allocator),
            .tokens = std.StringHashMap(TokenMetadata).init(allocator),
            .keyring = Keyring.init(allocator),
        };
    }

    pub fn deinit(self: *AuthManager) void {
        // Clean up API keys
        var iter = self.keys.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Zero out sensitive data before freeing
            self.zeroMemory(entry.value_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.keys.deinit();

        // Clean up OAuth tokens
        var token_iter = self.tokens.iterator();
        while (token_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var metadata = entry.value_ptr.*;
            metadata.deinit(self.allocator);
        }
        self.tokens.deinit();
    }

    /// Get API key for a provider
    /// Priority: 1. Cached key, 2. Environment variable
    pub fn getApiKey(self: *AuthManager, provider: []const u8) !?[]const u8 {
        // Check cached keys first
        if (self.keys.get(provider)) |key| {
            return key;
        }

        // Try environment variable
        const env_var = try self.getEnvVarName(provider);
        defer self.allocator.free(env_var);

        if (std.posix.getenv(env_var)) |key| {
            // Cache the key
            try self.setApiKey(provider, key);
            return key;
        }

        return null;
    }

    /// Set API key for a provider (caches in memory)
    pub fn setApiKey(self: *AuthManager, provider: []const u8, api_key: []const u8) !void {
        const owned_provider = try self.allocator.dupe(u8, provider);
        errdefer self.allocator.free(owned_provider);

        const owned_key = try self.allocator.dupe(u8, api_key);
        errdefer self.allocator.free(owned_key);

        // Remove old key if exists
        if (self.keys.fetchRemove(provider)) |old_kv| {
            self.allocator.free(old_kv.key);
            self.zeroMemory(old_kv.value);
            self.allocator.free(old_kv.value);
        }

        try self.keys.put(owned_provider, owned_key);
    }

    /// Check if API key exists for provider
    pub fn hasApiKey(self: *AuthManager, provider: []const u8) !bool {
        const key = try self.getApiKey(provider);
        return key != null;
    }

    /// Load all API keys from environment
    pub fn loadFromEnvironment(self: *AuthManager) !void {
        const providers = [_][]const u8{
            "openai",
            "anthropic",
            "google",
            "xai",
            "azure",
        };

        for (providers) |provider| {
            _ = try self.getApiKey(provider);
        }

        std.debug.print("✅ Loaded API keys from environment\n", .{});
    }

    /// Get environment variable name for provider
    /// Examples: "openai" → "OPENAI_API_KEY", "anthropic" → "ANTHROPIC_API_KEY"
    fn getEnvVarName(self: *AuthManager, provider: []const u8) ![]const u8 {
        var upper = try self.allocator.alloc(u8, provider.len);
        errdefer self.allocator.free(upper);

        for (provider, 0..) |c, i| {
            upper[i] = std.ascii.toUpper(c);
        }

        const env_var = try std.fmt.allocPrint(
            self.allocator,
            "{s}_API_KEY",
            .{upper},
        );
        self.allocator.free(upper);

        return env_var;
    }

    /// Zero out memory containing sensitive data
    fn zeroMemory(self: *AuthManager, data: []const u8) void {
        _ = self;
        @memset(@constCast(data), 0);
    }

    // === OAuth Token Management ===

    /// Perform OAuth login for Anthropic Claude
    pub fn loginAnthropic(self: *AuthManager) !void {
        var oauth = AnthropicOAuth.init(self.allocator);
        var tokens = try oauth.authorize();
        defer tokens.deinit(self.allocator);
        try self.storeOAuthTokens("anthropic", tokens);
    }

    /// Store OAuth tokens in keyring and memory
    fn storeOAuthTokens(self: *AuthManager, provider: []const u8, tokens: OAuthTokens) !void {
        const now = std.time.timestamp();
        const expires_at = now + tokens.expires_in;

        // Store in keyring
        try self.keyring.set("zeke", provider, tokens.access_token);

        if (tokens.refresh_token) |rt| {
            const refresh_key = try std.fmt.allocPrint(self.allocator, "{s}_refresh", .{provider});
            defer self.allocator.free(refresh_key);
            try self.keyring.set("zeke", refresh_key, rt);
        }

        // Cache in memory
        const metadata = TokenMetadata{
            .access_token = try self.allocator.dupe(u8, tokens.access_token),
            .refresh_token = if (tokens.refresh_token) |rt|
                try self.allocator.dupe(u8, rt)
            else
                null,
            .expires_at = expires_at,
            .token_type = try self.allocator.dupe(u8, tokens.token_type),
        };

        const owned_provider = try self.allocator.dupe(u8, provider);
        errdefer self.allocator.free(owned_provider);

        // Remove old token if exists
        if (self.tokens.fetchRemove(provider)) |old_kv| {
            self.allocator.free(old_kv.key);
            var old_metadata = old_kv.value;
            old_metadata.deinit(self.allocator);
        }

        try self.tokens.put(owned_provider, metadata);

        std.debug.print("✅ OAuth tokens stored for {s}\n", .{provider});
    }

    /// Get OAuth access token for provider (auto-refresh if expired)
    pub fn getOAuthToken(self: *AuthManager, provider: []const u8) !?[]const u8 {
        // Check cached token first
        if (self.tokens.get(provider)) |metadata| {
            if (!metadata.isExpired()) {
                return metadata.access_token;
            }

            // Token expired, try to refresh
            if (metadata.refresh_token) |rt| {
                std.debug.print("🔄 Refreshing expired {s} token...\n", .{provider});
                self.refreshOAuthToken(provider, rt) catch |err| {
                    std.debug.print("❌ Failed to refresh token: {}\n", .{err});
                    return null;
                };

                // Get refreshed token
                if (self.tokens.get(provider)) |new_metadata| {
                    return new_metadata.access_token;
                }
            }
        }

        // Try loading from keyring
        if (try self.keyring.get("zeke", provider)) |token| {
            defer self.allocator.free(token);
            // Token from keyring doesn't have expiry info, so return it but warn
            std.debug.print("⚠️  Using token from keyring (no expiry info)\n", .{});
            return try self.allocator.dupe(u8, token);
        }

        return null;
    }

    /// Refresh OAuth token
    fn refreshOAuthToken(self: *AuthManager, provider: []const u8, refresh_token: []const u8) !void {
        if (std.mem.eql(u8, provider, "anthropic")) {
            var oauth = AnthropicOAuth.init(self.allocator);
            var tokens = try oauth.refreshToken(refresh_token);
            defer tokens.deinit(self.allocator);
            try self.storeOAuthTokens(provider, tokens);
        } else {
            return error.UnsupportedProvider;
        }
    }

    /// Logout (remove OAuth tokens)
    pub fn logout(self: *AuthManager, provider: []const u8) !void {
        // Remove from keyring
        self.keyring.delete("zeke", provider) catch {};

        const refresh_key = try std.fmt.allocPrint(self.allocator, "{s}_refresh", .{provider});
        defer self.allocator.free(refresh_key);
        self.keyring.delete("zeke", refresh_key) catch {};

        // Remove from memory
        if (self.tokens.fetchRemove(provider)) |kv| {
            self.allocator.free(kv.key);
            var metadata = kv.value;
            metadata.deinit(self.allocator);
        }

        std.debug.print("✅ Logged out of {s}\n", .{provider});
    }

    /// Get list of providers with configured API keys
    pub fn listConfiguredProviders(self: *AuthManager) ![]const []const u8 {
        var providers = std.ArrayList([]const u8).init(self.allocator);
        errdefer providers.deinit();

        var iter = self.keys.iterator();
        while (iter.next()) |entry| {
            try providers.append(entry.key_ptr.*);
        }

        return providers.toOwnedSlice();
    }

    /// Print authentication status
    pub fn printStatus(self: *AuthManager) !void {
        const providers = [_][]const u8{
            "openai",
            "anthropic",
            "google",
            "xai",
            "azure",
            "ollama", // Always available (local)
        };

        std.debug.print("\n🔐 Authentication Status:\n\n", .{});

        for (providers) |provider| {
            if (std.mem.eql(u8, provider, "ollama")) {
                std.debug.print("  ✅ {s:<12} Local (no API key needed)\n", .{provider});
                continue;
            }

            // Check OAuth first (for anthropic)
            if (std.mem.eql(u8, provider, "anthropic")) {
                if (try self.getOAuthToken(provider)) |token| {
                    defer self.allocator.free(token);

                    if (self.tokens.get(provider)) |metadata| {
                        const now = std.time.timestamp();
                        const remaining = metadata.expires_at - now;
                        const hours = @divTrunc(remaining, 3600);

                        if (metadata.isExpired()) {
                            std.debug.print("  ⚠️  {s:<12} OAuth (expired, will auto-refresh)\n", .{provider});
                        } else {
                            std.debug.print("  ✅ {s:<12} OAuth (expires in ~{d}h)\n", .{ provider, hours });
                        }
                        continue;
                    } else {
                        std.debug.print("  ✅ {s:<12} OAuth (from keyring)\n", .{provider});
                        continue;
                    }
                }
            }

            // Check API key
            const has_key = try self.hasApiKey(provider);
            if (has_key) {
                std.debug.print("  ✅ {s:<12} API Key configured\n", .{provider});
            } else {
                const env_var = try self.getEnvVarName(provider);
                defer self.allocator.free(env_var);
                if (std.mem.eql(u8, provider, "anthropic")) {
                    std.debug.print("  ❌ {s:<12} Not configured (run 'zeke auth claude' or set {s})\n", .{ provider, env_var });
                } else {
                    std.debug.print("  ❌ {s:<12} Not configured (set {s})\n", .{ provider, env_var });
                }
            }
        }

        std.debug.print("\n", .{});
    }
};

// === Tests ===

test "auth manager init/deinit" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator);
    defer auth.deinit();
}

test "auth manager set/get API key" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator);
    defer auth.deinit();

    // Set API key
    try auth.setApiKey("test_provider", "test_api_key_12345");

    // Get API key
    const key = try auth.getApiKey("test_provider");
    try std.testing.expect(key != null);
    try std.testing.expectEqualStrings("test_api_key_12345", key.?);
}

test "auth manager has API key" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator);
    defer auth.deinit();

    // Should not have key initially
    try std.testing.expect(!try auth.hasApiKey("test_provider"));

    // Set API key
    try auth.setApiKey("test_provider", "test_key");

    // Should have key now
    try std.testing.expect(try auth.hasApiKey("test_provider"));
}

test "auth manager env var name" {
    const allocator = std.testing.allocator;

    var auth = AuthManager.init(allocator);
    defer auth.deinit();

    const env_var = try auth.getEnvVarName("openai");
    defer allocator.free(env_var);

    try std.testing.expectEqualStrings("OPENAI_API_KEY", env_var);
}
