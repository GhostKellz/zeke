const std = @import("std");

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
    copilot: []const u8 = "https://api.githubcopilot.com",
    claude: []const u8 = "https://api.anthropic.com",
    openai: []const u8 = "https://api.openai.com",
    ollama: []const u8 = "http://localhost:11434",
    ghostllm: []const u8 = "http://localhost:8080",
};

pub const OAuthConfig = struct {
    google_client_id: ?[]const u8 = null,
    google_client_secret: ?[]const u8 = null,
    github_client_id: ?[]const u8 = null,
    github_client_secret: ?[]const u8 = null,
    redirect_uri: []const u8 = "http://localhost:8080/callback",
};

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
    default_provider: []const u8 = "ghostllm",
    fallback_enabled: bool = true,
    health_check_interval_s: u32 = 300,
    auto_switch_on_failure: bool = true,
    preferred_providers: []const []const u8 = &[_][]const u8{ "ghostllm", "claude", "openai" },
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    
    // Model settings
    default_model: []const u8 = "gpt-4",
    models: std.ArrayList(ModelConfig),
    
    // API endpoints
    endpoints: ProviderEndpointConfig = ProviderEndpointConfig{},
    
    // Authentication
    github_token: ?[]const u8 = null,
    openai_api_key: ?[]const u8 = null,
    claude_api_key: ?[]const u8 = null,
    ghostllm_api_key: ?[]const u8 = null,
    
    // GhostLLM settings
    enable_ghostllm: bool = true,
    ghostllm_gpu_enabled: bool = true,
    ghostllm_quic_enabled: bool = true,
    
    // Storage settings
    enable_storage: bool = true,
    storage_encryption_key: ?[]const u8 = null,
    storage_path: []const u8 = "zeke_data.db",
    
    // OAuth settings
    oauth: OAuthConfig = OAuthConfig{},
    
    // Provider preferences
    providers: ProviderPreferencesConfig = ProviderPreferencesConfig{},
    
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
        
        if (self.github_token) |token| {
            self.allocator.free(token);
        }
        if (self.openai_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.claude_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.ghostllm_api_key) |key| {
            self.allocator.free(key);
        }
        if (self.oauth.google_client_id) |id| {
            self.allocator.free(id);
        }
        if (self.oauth.google_client_secret) |secret| {
            self.allocator.free(secret);
        }
        if (self.oauth.github_client_id) |id| {
            self.allocator.free(id);
        }
        if (self.oauth.github_client_secret) |secret| {
            self.allocator.free(secret);
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
        // API Keys
        if (std.process.getEnvVarOwned(self.allocator, "GITHUB_TOKEN")) |token| {
            self.github_token = token;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "OPENAI_API_KEY")) |key| {
            self.openai_api_key = key;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "CLAUDE_API_KEY")) |key| {
            self.claude_api_key = key;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GHOSTLLM_API_KEY")) |key| {
            self.ghostllm_api_key = key;
        } else |_| {}
        
        // OAuth configuration
        if (std.process.getEnvVarOwned(self.allocator, "GOOGLE_CLIENT_ID")) |id| {
            self.oauth.google_client_id = id;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GOOGLE_CLIENT_SECRET")) |secret| {
            self.oauth.google_client_secret = secret;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GITHUB_CLIENT_ID")) |id| {
            self.oauth.github_client_id = id;
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "GITHUB_CLIENT_SECRET")) |secret| {
            self.oauth.github_client_secret = secret;
        } else |_| {}
        
        // Endpoints
        if (std.process.getEnvVarOwned(self.allocator, "GHOSTLLM_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.ghostllm = try self.allocator.dupe(u8, endpoint);
        } else |_| {}
        
        if (std.process.getEnvVarOwned(self.allocator, "OLLAMA_ENDPOINT")) |endpoint| {
            defer self.allocator.free(endpoint);
            self.endpoints.ollama = try self.allocator.dupe(u8, endpoint);
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
        try self.models.append(self.allocator, ModelConfig{
            .name = "gpt-4",
            .provider = "openai",
            .temperature = 0.7,
            .max_tokens = 1000,
        });
        
        try self.models.append(self.allocator, ModelConfig{
            .name = "gpt-3.5-turbo",
            .provider = "openai",
            .temperature = 0.7,
            .max_tokens = 1000,
        });
        
        try self.models.append(self.allocator, ModelConfig{
            .name = "claude-3-5-sonnet-20241022",
            .provider = "claude",
            .temperature = 0.7,
            .max_tokens = 1000,
        });
        
        try self.models.append(self.allocator, ModelConfig{
            .name = "copilot-codex",
            .provider = "copilot",
            .temperature = 0.3,
            .max_tokens = 500,
        });
        
        try self.models.append(self.allocator, ModelConfig{
            .name = "ghostllm-model",
            .provider = "ghostllm",
            .temperature = 0.7,
            .max_tokens = 1000,
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
    
    fn parseToml(allocator: std.mem.Allocator, contents: []const u8) !Self {
        // Simple TOML parser - in production, use a proper TOML library
        var config = Self.init(allocator);
        try config.addDefaultModels();
        
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 1..], " \t\"");
                
                if (std.mem.eql(u8, key, "default_model")) {
                    config.default_model = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "auto_complete")) {
                    config.auto_complete = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "chat_enabled")) {
                    config.chat_enabled = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "inline_suggestions")) {
                    config.inline_suggestions = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "context_lines")) {
                    config.context_lines = std.fmt.parseInt(u32, value, 10) catch 50;
                }
            }
        }
        
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
    const config_path = getConfigPath(allocator) catch |err| switch (err) {
        error.HomeNotFound => {
            var config = Config.init(allocator);
            try config.addDefaultModels();
            return config;
        },
        else => return err,
    };
    defer allocator.free(config_path);
    
    var config = Config.loadFromFile(allocator, config_path) catch |err| switch (err) {
        error.FileNotFound => {
            var default_config = Config.init(allocator);
            try default_config.addDefaultModels();
            return default_config;
        },
        else => return err,
    };
    
    try config.loadFromEnv();
    return config;
}