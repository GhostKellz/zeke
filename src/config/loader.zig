const std = @import("std");
const Config = @import("mod.zig").Config;
const toml_loader = @import("toml_loader.zig");

/// Hierarchical configuration loader
/// Priority (highest to lowest): CLI flags → Project → User → System → Defaults
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return .{ .allocator = allocator };
    }

    /// Load configuration with hierarchical merging
    /// 1. Start with defaults
    /// 2. Load system config (/etc/zeke/config.toml)
    /// 3. Load user config (~/.config/zeke/config.toml)
    /// 4. Load project config (./zeke.toml or ./.zeke/config.toml)
    /// 5. Apply CLI overrides
    pub fn load(self: *ConfigLoader, project_root: ?[]const u8) !Config {
        var config = try self.loadDefaults();
        errdefer config.deinit(self.allocator);

        // System config (lowest priority)
        if (self.tryLoadSystemConfig()) |system_config| {
            try self.merge(&config, system_config);
            system_config.deinit(self.allocator);
        }

        // User config
        if (try self.tryLoadUserConfig()) |user_config| {
            try self.merge(&config, user_config);
            user_config.deinit(self.allocator);
        }

        // Project config (highest priority)
        if (project_root) |root| {
            if (try self.tryLoadProjectConfig(root)) |project_config| {
                try self.merge(&config, project_config);
                project_config.deinit(self.allocator);
            }
        }

        return config;
    }

    /// Load default configuration
    fn loadDefaults(self: *ConfigLoader) !Config {
        return Config{
            .allocator = self.allocator,
            .default_model = try self.allocator.dupe(u8, "qwen2.5-coder:7b"), // Default to Ollama
            .models = std.ArrayList(@import("mod.zig").ModelConfig).init(self.allocator),
            .keybindings = .{},
            .providers = .{
                .default_provider = try self.allocator.dupe(u8, "ollama"), // Default to local Ollama
                .endpoints = .{},
                .enabled_providers = try self.createDefaultProviders(),
            },
            .ui = .{},
            .lsp = .{},
            .debug_mode = false,
            .log_file = null,
            .cache_dir = null,
            .mcp_servers = std.ArrayList(@import("mod.zig").McpServerConfig).init(self.allocator),
        };
    }

    fn createDefaultProviders(self: *ConfigLoader) ![]const []const u8 {
        const providers = [_][]const u8{ "ollama", "openai", "anthropic", "google", "xai" };
        const result = try self.allocator.alloc([]const u8, providers.len);
        for (providers, 0..) |provider, i| {
            result[i] = try self.allocator.dupe(u8, provider);
        }
        return result;
    }

    /// Try to load system config from /etc/zeke/config.toml
    fn tryLoadSystemConfig(self: *ConfigLoader) ?Config {
        const path = "/etc/zeke/config.toml";
        return self.tryLoadFromPath(path);
    }

    /// Try to load user config from ~/.config/zeke/config.toml
    fn tryLoadUserConfig(self: *ConfigLoader) !?Config {
        const home = std.posix.getenv("HOME") orelse return null;

        const config_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ home, ".config", "zeke", "config.toml" },
        );
        defer self.allocator.free(config_path);

        return self.tryLoadFromPath(config_path);
    }

    /// Try to load project config from {project_root}/.zeke/config.toml or {project_root}/zeke.toml
    fn tryLoadProjectConfig(self: *ConfigLoader, project_root: []const u8) !?Config {
        // Try .zeke/config.toml first
        const zeke_config = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ project_root, ".zeke", "config.toml" },
        );
        defer self.allocator.free(zeke_config);

        if (self.tryLoadFromPath(zeke_config)) |config| {
            return config;
        }

        // Try zeke.toml
        const root_config = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ project_root, "zeke.toml" },
        );
        defer self.allocator.free(root_config);

        return self.tryLoadFromPath(root_config);
    }

    /// Try to load config from a specific path
    fn tryLoadFromPath(self: *ConfigLoader, path: []const u8) ?Config {
        const config = toml_loader.loadFromFile(self.allocator, path) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("⚠️  Warning: Failed to load config from {s}: {}\n", .{ path, err });
            }
            return null;
        };
        std.debug.print("✅ Loaded config from: {s}\n", .{path});
        return config;
    }

    /// Merge source config into target (source takes priority)
    fn merge(self: *ConfigLoader, target: *Config, source: Config) !void {
        // Merge default_model if source has one
        if (source.default_model.len > 0) {
            self.allocator.free(target.default_model);
            target.default_model = try self.allocator.dupe(u8, source.default_model);
        }

        // Merge default_provider if source has one
        if (source.providers.default_provider.len > 0) {
            self.allocator.free(target.providers.default_provider);
            target.providers.default_provider = try self.allocator.dupe(u8, source.providers.default_provider);
        }

        // Merge enabled_providers
        if (source.providers.enabled_providers.len > 0) {
            // Free old providers
            for (target.providers.enabled_providers) |provider| {
                self.allocator.free(provider);
            }
            self.allocator.free(target.providers.enabled_providers);

            // Copy new providers
            const providers = try self.allocator.alloc([]const u8, source.providers.enabled_providers.len);
            for (source.providers.enabled_providers, 0..) |provider, i| {
                providers[i] = try self.allocator.dupe(u8, provider);
            }
            target.providers.enabled_providers = providers;
        }

        // Merge endpoint URLs (source overrides)
        inline for (@typeInfo(@TypeOf(source.providers.endpoints)).Struct.fields) |field| {
            const source_val = @field(source.providers.endpoints, field.name);
            if (field.type == []const u8 and source_val.len > 0) {
                const target_ptr = &@field(target.providers.endpoints, field.name);
                self.allocator.free(target_ptr.*);
                target_ptr.* = try self.allocator.dupe(u8, source_val);
            }
        }

        // Merge debug mode
        target.debug_mode = source.debug_mode;

        // Merge log_file if specified
        if (source.log_file) |log_file| {
            if (target.log_file) |old_log| {
                self.allocator.free(old_log);
            }
            target.log_file = try self.allocator.dupe(u8, log_file);
        }

        // Merge cache_dir if specified
        if (source.cache_dir) |cache_dir| {
            if (target.cache_dir) |old_cache| {
                self.allocator.free(old_cache);
            }
            target.cache_dir = try self.allocator.dupe(u8, cache_dir);
        }

        // Merge models
        for (source.models.items) |model| {
            try target.models.append(.{
                .name = try self.allocator.dupe(u8, model.name),
                .provider = try self.allocator.dupe(u8, model.provider),
                .temperature = model.temperature,
                .max_tokens = model.max_tokens,
                .top_p = model.top_p,
                .frequency_penalty = model.frequency_penalty,
                .presence_penalty = model.presence_penalty,
            });
        }

        // Merge MCP servers
        for (source.mcp_servers.items) |server| {
            try target.mcp_servers.append(.{
                .name = try self.allocator.dupe(u8, server.name),
                .transport = server.transport, // TODO: Deep copy transport
            });
        }
    }

    /// Get config value with environment variable override
    /// Example: ZEKE_DEFAULT_PROVIDER overrides config.providers.default_provider
    pub fn getWithEnvOverride(self: *ConfigLoader, comptime field_name: []const u8, default_value: []const u8) ![]const u8 {
        _ = self;

        // Convert field_name to env var name (e.g., "default_provider" → "ZEKE_DEFAULT_PROVIDER")
        var env_name_buf: [128]u8 = undefined;
        const env_name = try std.fmt.bufPrint(&env_name_buf, "ZEKE_{s}", .{field_name});

        // Convert to uppercase
        for (env_name) |*c| {
            if (c.* >= 'a' and c.* <= 'z') {
                c.* -= 32;
            } else if (c.* == '.') {
                c.* = '_';
            }
        }

        if (std.posix.getenv(env_name)) |env_val| {
            std.debug.print("🔧 Environment override: {s}={s}\n", .{ env_name, env_val });
            return env_val;
        }

        return default_value;
    }
};

// === Tests ===

test "config loader init" {
    const allocator = std.testing.allocator;
    const loader = ConfigLoader.init(allocator);
    _ = loader;
}

test "load defaults" {
    const allocator = std.testing.allocator;
    var loader = ConfigLoader.init(allocator);

    var config = try loader.loadDefaults();
    defer config.deinit(allocator);

    try std.testing.expectEqualStrings("qwen2.5-coder:7b", config.default_model);
    try std.testing.expectEqualStrings("ollama", config.providers.default_provider);
    try std.testing.expect(config.providers.enabled_providers.len == 5);
}

test "environment override" {
    const allocator = std.testing.allocator;
    var loader = ConfigLoader.init(allocator);

    // Without env var
    const default = try loader.getWithEnvOverride("default_provider", "ollama");
    try std.testing.expectEqualStrings("ollama", default);
}
