const std = @import("std");

/// Authentication manager for API keys
/// Supports environment variables and future keyring integration
pub const AuthManager = struct {
    allocator: std.mem.Allocator,
    keys: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) AuthManager {
        return .{
            .allocator = allocator,
            .keys = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AuthManager) void {
        var iter = self.keys.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Zero out sensitive data before freeing
            self.zeroMemory(entry.value_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.keys.deinit();
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

        std.debug.print("\n🔐 Authentication Status:\n", .{});

        for (providers) |provider| {
            if (std.mem.eql(u8, provider, "ollama")) {
                std.debug.print("  ✅ {s}: Local (no API key needed)\n", .{provider});
                continue;
            }

            const has_key = try self.hasApiKey(provider);
            if (has_key) {
                std.debug.print("  ✅ {s}: Configured\n", .{provider});
            } else {
                const env_var = try self.getEnvVarName(provider);
                defer self.allocator.free(env_var);
                std.debug.print("  ❌ {s}: Not configured (set {s})\n", .{ provider, env_var });
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
