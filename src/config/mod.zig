const std = @import("std");

// Export TOML loader and hierarchical config loader
pub const toml_loader = @import("toml_loader.zig");
pub const loader = @import("loader.zig");
pub const ConfigLoader = loader.ConfigLoader;

pub const ModelConfig = struct {
    name: []const u8,
    provider: []const u8,
    temperature: f32 = 0.7,
    max_tokens: u32 = 1000,
    top_p: f32 = 1.0,
    frequency_penalty: f32 = 0.0,
    presence_penalty: f32 = 0.0,
};

pub const KeybindingConfig = struct {
    open_panel: []const u8 = "<leader>ac",
    accept_suggestion: []const u8 = "<C-g>",
    next_suggestion: []const u8 = "<C-]>",
    prev_suggestion: []const u8 = "<C-[>",
    dismiss: []const u8 = "<C-\\>",
    ai_palette: []const u8 = "<leader>ai",
    toggle_inline: []const u8 = "<leader>at",
};

pub const ProviderEndpointConfig = struct {
    claude: []const u8 = "https://api.anthropic.com",
    openai: []const u8 = "https://api.openai.com",
    xai: []const u8 = "https://api.x.ai",
    google: []const u8 = "https://generativelanguage.googleapis.com",
    azure: []const u8 = "https://YOUR_RESOURCE.openai.azure.com", // User must set via env or config
    ollama: []const u8 = "http://localhost:11434",

    // Azure-specific settings
    azure_resource_name: ?[]const u8 = null,
    azure_deployment_name: ?[]const u8 = null,
    azure_api_version: []const u8 = "2024-02-15-preview",
};

/// MCP transport type for Glyph
pub const McpTransport = union(enum) {
    stdio: StdioTransport,
    websocket: WebSocketTransport,
    docker: DockerTransport,

    pub const StdioTransport = struct {
        command: []const u8,
        args: []const []const u8 = &.{},
    };

    pub const WebSocketTransport = struct {
        url: []const u8,
    };

    pub const DockerTransport = struct {
        container_name: []const u8,
        command: []const u8 = "/app/mcp-server",
        args: []const []const u8 = &.{},
        // Optional: specific network, volumes, etc.
        network: ?[]const u8 = null,
        volumes: []const []const u8 = &.{},
    };
};

/// Service configuration for external tools and services
pub const ServiceConfig = struct {
    /// Glyph MCP server configuration
    glyph: ?GlyphConfig = null,

    pub const GlyphConfig = struct {
        enabled: bool = true,
        mcp: McpTransport,
        health_check_interval_s: u32 = 30,
        timeout_ms: u32 = 5000,
    };
};

/// Model alias configuration for simple model selection
pub const ModelAliasConfig = struct {
    fast: []const u8 = "llama3.2:3b", // Fast local model
    smart: []const u8 = "claude-opus-4-1-20250805", // Most capable
    balanced: []const u8 = "claude-sonnet-4-5-20250929", // Best balance (Sonnet 4.5)
    local: []const u8 = "qwen2.5-coder:7b", // Local via Ollama
};

// OAuth removed - using API keys only

pub const StreamingConfig = struct {
    enabled: bool = true,
    chunk_size: u32 = 4096,
    timeout_ms: u32 = 30000,
    enable_websocket: bool = true,
    websocket_port: u16 = 8081,
};

pub const RealTimeConfig = struct {
    enabled: bool = false,
    typing_assistance: bool = true,
    code_analysis: bool = true,
    auto_suggestions: bool = true,
    debounce_ms: u32 = 300,
};

pub const ProviderPreferencesConfig = struct {
    default_provider: []const u8 = "ollama", // Ollama works out of the box
    fallback_enabled: bool = true,
    health_check_interval_s: u32 = 300,
    auto_switch_on_failure: bool = true,
    enabled_providers: []const []const u8 = &[_][]const u8{ "ollama", "openai", "anthropic", "google", "xai" },
    endpoints: ProviderEndpointConfig = ProviderEndpointConfig{},
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    
    // Model settings
    default_model: []const u8 = "gpt-4",
    models: std.ArrayList(ModelConfig),
    
    // API endpoints
    endpoints: ProviderEndpointConfig = ProviderEndpointConfig{},
    
    // Authentication (API keys only - managed by auth module)
    // These are loaded from auth manager, not stored here
    anthropic_api_key: ?[]const u8 = null,
    openai_api_key: ?[]const u8 = null,
    xai_api_key: ?[]const u8 = null,
    azure_api_key: ?[]const u8 = null,
    
    // Storage settings
    enable_storage: bool = true,
    storage_encryption_key: ?[]const u8 = null,
    storage_path: []const u8 = "zeke_data.db",
    
    // Provider preferences
    providers: ProviderPreferencesConfig = ProviderPreferencesConfig{},

    // External services (Glyph MCP)
    services: ServiceConfig = ServiceConfig{},

    // Model aliases for simplified selection
    model_aliases: ModelAliasConfig = ModelAliasConfig{},

    // Streaming configuration
    streaming: StreamingConfig = StreamingConfig{},

    // Real-time features
    realtime: RealTimeConfig = RealTimeConfig{},

    // Keybindings
    keybindings: KeybindingConfig = KeybindingConfig{},
    
    // Features
    auto_complete: bool = true,
    chat_enabled: bool = true,
    inline_suggestions: bool = true,
    context_lines: u32 = 50,
    smart_routing: bool = true,
    
    // Performance
    request_timeout_ms: u32 = 30000,
    max_concurrent_requests: u32 = 5,
    rate_limit_requests_per_minute: u32 = 100,
    
    // Logging
    log_level: std.log.Level = .info,
    log_file: ?[]const u8 = null,
    log_requests: bool = false,
    
    // Security
    store_tokens_encrypted: bool = true,
    telemetry_enabled: bool = false,
    validate_ssl: bool = true,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .models = std.ArrayList(ModelConfig){},
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.models.deinit(self.allocator);

        // Free provider config strings
        self.allocator.free(self.providers.default_provider);
        self.allocator.free(self.default_model);

        if (self.anthropic_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.openai_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.xai_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.azure_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.log_file) |file| {
            self.allocator.free(file);
        }
    }
    
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Self {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Create default config if file doesn't exist
                var config = Self.init(allocator);
                try config.addDefaultModels();
                return config;
            },
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const contents = try allocator.alloc(u8, file_size);
        defer allocator.free(contents);
        
        _ = try file.readAll(contents);
        
        // Determine file type based on extension
        if (std.mem.endsWith(u8, file_path, ".toml")) {
            return try parseToml(allocator, contents);
        } else if (std.mem.endsWith(u8, file_path, ".json")) {
            return try parseJson(allocator, contents);
        } else if (std.mem.endsWith(u8, file_path, ".yaml") or std.mem.endsWith(u8, file_path, ".yml")) {
            return try parseYaml(allocator, contents);
        } else {
            return error.UnsupportedConfigFormat;
        }
    }
    
    pub fn saveToFile(self: *Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        if (std.mem.endsWith(u8, file_path, ".toml")) {
            try self.writeToml(file.writer());
        } else if (std.mem.endsWith(u8, file_path, ".json")) {
            try self.writeJson(file.writer());
        } else {
            return error.UnsupportedConfigFormat;
        }
    }
    
    pub fn loadFromEnv(self: *Self) !void {
        // API Keys (loaded from env, but auth manager is primary source)
        if (std.process.getEnvVarOwned(self.allocator, "ANTHROPIC_API_KEY")) |key| {
            self.anthropic_api_key = key;
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "OPENAI_API_KEY")) |key| {
            self.openai_api_key = key;
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "XAI_API_KEY")) |key| {
            self.xai_api_key = key;
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "AZURE_OPENAI_API_KEY")) |key| {
            self.azure_api_key = key;
        } else |_| {}

        // Provider Endpoints
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_OLLAMA_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.ollama = try self.allocator.dupe(u8, endpoint);
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_CLAUDE_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.claude = try self.allocator.dupe(u8, endpoint);
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_OPENAI_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.openai = try self.allocator.dupe(u8, endpoint);
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_XAI_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.xai = try self.allocator.dupe(u8, endpoint);
        } else |_| {}

        // Azure-specific configuration
        if (std.process.getEnvVarOwned(self.allocator, "AZURE_OPENAI_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.azure = try self.allocator.dupe(u8, endpoint);
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "AZURE_OPENAI_RESOURCE_NAME")) |name| {
            self.endpoints.azure_resource_name = name;
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "AZURE_OPENAI_DEPLOYMENT_NAME")) |name| {
            self.endpoints.azure_deployment_name = name;
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "AZURE_OPENAI_API_VERSION")) |version| {
            defer self.allocator.free(version);
            self.endpoints.azure_api_version = try self.allocator.dupe(u8, version);
        } else |_| {}

        // MCP Configuration
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_MCP_COMMAND")) |command| {
            const cmd_owned = try self.allocator.dupe(u8, command);
            self.services.glyph = ServiceConfig.GlyphConfig{
                .mcp = .{ .stdio = .{ .command = cmd_owned } },
            };
        } else |_| {}

        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_MCP_WS")) |ws_url| {
            const url_owned = try self.allocator.dupe(u8, ws_url);
            self.services.glyph = ServiceConfig.GlyphConfig{
                .mcp = .{ .websocket = .{ .url = url_owned } },
            };
        } else |_| {}

        // Docker MCP Configuration
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_MCP_DOCKER_CONTAINER")) |container| {
            const container_owned = try self.allocator.dupe(u8, container);
            self.services.glyph = ServiceConfig.GlyphConfig{
                .mcp = .{ .docker = .{ .container_name = container_owned } },
            };
        } else |_| {}
        
        // Features
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_STREAMING_ENABLED")) |enabled| {
            defer self.allocator.free(enabled);
            self.streaming.enabled = std.mem.eql(u8, enabled, "true");
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_REALTIME_ENABLED")) |enabled| {
            defer self.allocator.free(enabled);
            self.realtime.enabled = std.mem.eql(u8, enabled, "true");
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_SMART_ROUTING")) |enabled| {
            defer self.allocator.free(enabled);
            self.smart_routing = std.mem.eql(u8, enabled, "true");
        } else |_| {}
        
        // Logging
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_LOG_LEVEL")) |level| {
            defer self.allocator.free(level);
            if (std.mem.eql(u8, level, "debug")) {
                self.log_level = .debug;
            } else if (std.mem.eql(u8, level, "info")) {
                self.log_level = .info;
            } else if (std.mem.eql(u8, level, "warn")) {
                self.log_level = .warn;
            } else if (std.mem.eql(u8, level, "err")) {
                self.log_level = .err;
            }
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_LOG_REQUESTS")) |enabled| {
            defer self.allocator.free(enabled);
            self.log_requests = std.mem.eql(u8, enabled, "true");
        } else |_| {}
    }
    
    pub fn addDefaultModels(self: *Self) !void {
        // Claude 4.x models (latest - actual model IDs)
        try self.models.append(self.allocator, ModelConfig{
            .name = "claude-sonnet-4-5-20250929",
            .provider = "claude",
            .temperature = 0.7,
            .max_tokens = 8000,
        });

        try self.models.append(self.allocator, ModelConfig{
            .name = "claude-opus-4-1-20250805",
            .provider = "claude",
            .temperature = 0.7,
            .max_tokens = 8000,
        });

        // OpenAI models
        try self.models.append(self.allocator, ModelConfig{
            .name = "gpt-4-turbo",
            .provider = "openai",
            .temperature = 0.7,
            .max_tokens = 4000,
        });

        try self.models.append(self.allocator, ModelConfig{
            .name = "gpt-3.5-turbo",
            .provider = "openai",
            .temperature = 0.7,
            .max_tokens = 4000,
        });

        // xAI/Grok models
        try self.models.append(self.allocator, ModelConfig{
            .name = "grok-2-latest",
            .provider = "xai",
            .temperature = 0.7,
            .max_tokens = 4000,
        });

        try self.models.append(self.allocator, ModelConfig{
            .name = "grok-beta",
            .provider = "xai",
            .temperature = 0.7,
            .max_tokens = 4000,
        });

        // Ollama models (local)
        try self.models.append(self.allocator, ModelConfig{
            .name = "llama3.2:3b",
            .provider = "ollama",
            .temperature = 0.7,
            .max_tokens = 2000,
        });

        try self.models.append(self.allocator, ModelConfig{
            .name = "qwen2.5-coder:7b",
            .provider = "ollama",
            .temperature = 0.7,
            .max_tokens = 2000,
        });
    }
    
    pub fn getModel(self: *Self, name: []const u8) ?ModelConfig {
        for (self.models.items) |model| {
            if (std.mem.eql(u8, model.name, name)) {
                return model;
            }
        }
        return null;
    }

    /// Resolve a model name, checking aliases first
    pub fn resolveModel(self: *Self, name: []const u8) []const u8 {
        // Check if it's an alias
        if (std.mem.eql(u8, name, "fast")) {
            return self.model_aliases.fast;
        } else if (std.mem.eql(u8, name, "smart")) {
            return self.model_aliases.smart;
        } else if (std.mem.eql(u8, name, "local")) {
            return self.model_aliases.local;
        } else if (std.mem.eql(u8, name, "balanced")) {
            return self.model_aliases.balanced;
        }
        // Return the name as-is if not an alias
        return name;
    }
    
    fn parseToml(allocator: std.mem.Allocator, contents: []const u8) !Self {
        // Use zontom for proper TOML parsing
        _ = contents;

        // For now, return a default config
        // The proper TOML loading is done via toml_loader.loadFromToml()
        var config = Self.init(allocator);
        try config.addDefaultModels();
        return config;
    }
    
    fn parseJson(allocator: std.mem.Allocator, contents: []const u8) !Self {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{});
        defer parsed.deinit();
        
        var config = Self.init(allocator);
        
        if (parsed.value.object.get("default_model")) |value| {
            config.default_model = try allocator.dupe(u8, value.string);
        }
        
        if (parsed.value.object.get("auto_complete")) |value| {
            config.auto_complete = value.bool;
        }
        
        if (parsed.value.object.get("chat_enabled")) |value| {
            config.chat_enabled = value.bool;
        }
        
        if (parsed.value.object.get("inline_suggestions")) |value| {
            config.inline_suggestions = value.bool;
        }
        
        if (parsed.value.object.get("context_lines")) |value| {
            config.context_lines = @intCast(value.integer);
        }
        
        return config;
    }
    
    fn parseYaml(allocator: std.mem.Allocator, contents: []const u8) !Self {
        // Simple YAML parser - in production, use a proper YAML library
        return try parseToml(allocator, contents); // Similar parsing for now
    }
    
    fn writeToml(self: *Self, writer: anytype) !void {
        try writer.print("# ZEKE Configuration\n");
        try writer.print("default_model = \"{s}\"\n", .{self.default_model});
        try writer.print("auto_complete = {}\n", .{self.auto_complete});
        try writer.print("chat_enabled = {}\n", .{self.chat_enabled});
        try writer.print("inline_suggestions = {}\n", .{self.inline_suggestions});
        try writer.print("context_lines = {}\n", .{self.context_lines});
        try writer.print("telemetry_enabled = {}\n", .{self.telemetry_enabled});
        
        try writer.print("\n[endpoints]\n");
        try writer.print("copilot = \"{s}\"\n", .{self.copilot_endpoint});
        try writer.print("claude = \"{s}\"\n", .{self.claude_endpoint});
        try writer.print("openai = \"{s}\"\n", .{self.openai_endpoint});
        try writer.print("ollama = \"{s}\"\n", .{self.ollama_endpoint});
        
        try writer.print("\n[keybindings]\n");
        try writer.print("open_panel = \"{s}\"\n", .{self.keybindings.open_panel});
        try writer.print("accept_suggestion = \"{s}\"\n", .{self.keybindings.accept_suggestion});
        try writer.print("next_suggestion = \"{s}\"\n", .{self.keybindings.next_suggestion});
        try writer.print("prev_suggestion = \"{s}\"\n", .{self.keybindings.prev_suggestion});
        try writer.print("dismiss = \"{s}\"\n", .{self.keybindings.dismiss});
        try writer.print("ai_palette = \"{s}\"\n", .{self.keybindings.ai_palette});
        try writer.print("toggle_inline = \"{s}\"\n", .{self.keybindings.toggle_inline});
    }
    
    fn writeJson(self: *Self, writer: anytype) !void {
        try writer.print("{{\n");
        try writer.print("  \"default_model\": \"{s}\",\n", .{self.default_model});
        try writer.print("  \"auto_complete\": {},\n", .{self.auto_complete});
        try writer.print("  \"chat_enabled\": {},\n", .{self.chat_enabled});
        try writer.print("  \"inline_suggestions\": {},\n", .{self.inline_suggestions});
        try writer.print("  \"context_lines\": {},\n", .{self.context_lines});
        try writer.print("  \"telemetry_enabled\": {}\n", .{self.telemetry_enabled});
        try writer.print("}}\n");
    }
};

pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.HomeNotFound,
        else => return err,
    };
    defer allocator.free(home);
    
    return try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "zeke", "zeke.toml" });
}

pub fn loadConfig(allocator: std.mem.Allocator) !Config {
    // Try to load from ~/.config/zeke/zeke.toml
    const config_path = getConfigPath(allocator) catch |err| switch (err) {
        error.HomeNotFound => {
            var config = Config.init(allocator);
            try config.addDefaultModels();
            return config;
        },
        else => return err,
    };
    defer allocator.free(config_path);

    // Use zontom TOML loader if file exists
    var config = toml_loader.loadFromToml(allocator, config_path) catch |err| switch (err) {
        error.FileNotFound => blk: {
            // Try loading from current directory
            break :blk toml_loader.loadFromToml(allocator, "zeke.toml") catch {
                // No config file found, use defaults
                var default_config = Config.init(allocator);
                try default_config.addDefaultModels();
                return default_config;
            };
        },
        else => return err,
    };

    try config.loadFromEnv();
    return config;
}