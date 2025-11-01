const std = @import("std");

/// Model capability and specification information
pub const ModelInfo = struct {
    name: []const u8,
    provider: []const u8,
    release_date: ?[]const u8 = null,
    context_limit: ?u32 = null,
    output_limit: ?u32 = null,
    supports_vision: bool = false,
    supports_reasoning: bool = false,
    supports_tool_calls: bool = false,
    status: ModelStatus = .active,

    pub const ModelStatus = enum {
        active,
        deprecated,
        beta,
    };

    pub fn deinit(self: *ModelInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.provider);
        if (self.release_date) |date| allocator.free(date);
    }
};

/// Model database - hardcoded for now, can be loaded from TOML files later
pub const ModelDatabase = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ModelDatabase {
        return .{ .allocator = allocator };
    }

    /// Get model info by name
    pub fn getModel(self: *ModelDatabase, model_name: []const u8) ?ModelInfo {
        _ = self;

        // Hardcoded database for now
        // TODO: Load from archive/models.dev TOML files

        if (std.mem.eql(u8, model_name, "gpt-4o")) {
            return ModelInfo{
                .name = "GPT-4o",
                .provider = "openai",
                .context_limit = 128000,
                .output_limit = 16384,
                .supports_vision = true,
                .supports_tool_calls = true,
            };
        } else if (std.mem.eql(u8, model_name, "claude-sonnet-4.5")) {
            return ModelInfo{
                .name = "Claude Sonnet 4.5",
                .provider = "anthropic",
                .context_limit = 200000,
                .output_limit = 8192,
                .supports_vision = true,
                .supports_tool_calls = true,
            };
        } else if (std.mem.eql(u8, model_name, "claude-opus-4")) {
            return ModelInfo{
                .name = "Claude Opus 4",
                .provider = "anthropic",
                .context_limit = 80000,
                .output_limit = 16000,
                .supports_reasoning = true,
                .status = .deprecated,
            };
        } else if (std.mem.eql(u8, model_name, "gpt-5-codex")) {
            return ModelInfo{
                .name = "GPT-5 Codex",
                .provider = "github_copilot",
                .context_limit = 128000,
                .output_limit = 32000,
                .supports_tool_calls = true,
            };
        } else if (std.mem.eql(u8, model_name, "gemini-2.5-pro")) {
            return ModelInfo{
                .name = "Gemini 2.5 Pro",
                .provider = "google",
                .context_limit = 1000000,
                .output_limit = 8192,
                .supports_vision = true,
                .supports_tool_calls = true,
            };
        }

        return null;
    }

    /// Get all models for a provider
    pub fn getModelsForProvider(self: *ModelDatabase, provider: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
        _ = self;

        if (std.mem.eql(u8, provider, "github_copilot")) {
            const models = try allocator.alloc([]const u8, 19);
            models[0] = "gpt-4o";
            models[1] = "gpt-4.1";
            models[2] = "gpt-5";
            models[3] = "gpt-5-mini";
            models[4] = "gpt-5-codex";
            models[5] = "claude-3.5-sonnet";
            models[6] = "claude-3.7-sonnet";
            models[7] = "claude-haiku-4.5";
            models[8] = "claude-opus-4";
            models[9] = "claude-sonnet-4";
            models[10] = "claude-sonnet-4.5";
            models[11] = "gemini-2.0-flash-001";
            models[12] = "gemini-2.5-pro";
            models[13] = "o3-mini";
            models[14] = "o3";
            models[15] = "o4-mini";
            models[16] = "grok-code-fast-1";
            models[17] = "gpt-5-pro";
            models[18] = "gpt-5-nano";
            return models;
        } else if (std.mem.eql(u8, provider, "anthropic") or std.mem.eql(u8, provider, "claude")) {
            const models = try allocator.alloc([]const u8, 5);
            models[0] = "claude-sonnet-4.5";
            models[1] = "claude-opus-4";
            models[2] = "claude-3.5-sonnet";
            models[3] = "claude-3.7-sonnet";
            models[4] = "claude-haiku-4.5";
            return models;
        } else if (std.mem.eql(u8, provider, "openai")) {
            const models = try allocator.alloc([]const u8, 5);
            models[0] = "gpt-4o";
            models[1] = "gpt-4.1";
            models[2] = "gpt-4-turbo";
            models[3] = "gpt-3.5-turbo";
            models[4] = "o3-mini";
            return models;
        } else if (std.mem.eql(u8, provider, "google")) {
            const models = try allocator.alloc([]const u8, 3);
            models[0] = "gemini-2.5-pro";
            models[1] = "gemini-2.0-flash-001";
            models[2] = "gemini-1.5-pro";
            return models;
        }

        return &[_][]const u8{};
    }

    /// Recommend a model for a specific task type
    pub fn recommendModel(self: *ModelDatabase, task_type: TaskType, provider: ?[]const u8) []const u8 {
        _ = self;

        // If provider specified, use provider-specific recommendations
        if (provider) |prov| {
            if (std.mem.eql(u8, prov, "github_copilot")) {
                return switch (task_type) {
                    .code_completion => "gpt-5-codex",
                    .chat => "gpt-4o",
                    .reasoning => "claude-opus-4",
                    .fast_response => "gpt-5-mini",
                    .code_review => "claude-3.5-sonnet",
                };
            } else if (std.mem.eql(u8, prov, "anthropic") or std.mem.eql(u8, prov, "claude")) {
                return switch (task_type) {
                    .code_completion, .code_review => "claude-sonnet-4.5",
                    .chat => "claude-3.5-sonnet",
                    .reasoning => "claude-opus-4",
                    .fast_response => "claude-haiku-4.5",
                };
            } else if (std.mem.eql(u8, prov, "openai")) {
                return switch (task_type) {
                    .code_completion, .chat => "gpt-4o",
                    .reasoning => "o3-mini",
                    .fast_response => "gpt-3.5-turbo",
                    .code_review => "gpt-4.1",
                };
            }
        }

        // Default recommendations across all providers
        return switch (task_type) {
            .code_completion => "gpt-5-codex", // From Copilot
            .chat => "gpt-4o",
            .reasoning => "claude-opus-4",
            .fast_response => "gpt-3.5-turbo",
            .code_review => "claude-sonnet-4.5",
        };
    }
};

pub const TaskType = enum {
    code_completion,
    chat,
    reasoning,
    fast_response,
    code_review,
};
