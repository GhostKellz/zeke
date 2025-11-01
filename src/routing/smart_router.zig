const std = @import("std");
const api = @import("../api/client.zig");
const models = @import("../models/mod.zig");

/// Smart router for selecting the best model and provider for a task
pub const SmartRouter = struct {
    allocator: std.mem.Allocator,
    model_db: models.ModelDatabase,

    pub fn init(allocator: std.mem.Allocator) SmartRouter {
        return .{
            .allocator = allocator,
            .model_db = models.ModelDatabase.init(allocator),
        };
    }

    /// Route a request to the best provider and model
    pub fn route(self: *SmartRouter, task_type: models.TaskType, preferred_provider: ?api.ApiProvider) RoutingDecision {
        _ = self;

        // If user specified a provider, use it
        if (preferred_provider) |provider| {
            const model_name = self.model_db.recommendModel(task_type, @tagName(provider));
            return RoutingDecision{
                .provider = provider,
                .model = model_name,
                .reason = "User specified provider",
            };
        }

        // Smart selection based on task type
        const decision = switch (task_type) {
            .code_completion => RoutingDecision{
                .provider = .github_copilot,
                .model = "gpt-5-codex",
                .reason = "Optimized for code completion",
            },
            .code_review => RoutingDecision{
                .provider = .github_copilot,
                .model = "claude-sonnet-4.5",
                .reason = "Best for code analysis",
            },
            .reasoning => RoutingDecision{
                .provider = .github_copilot,
                .model = "claude-opus-4",
                .reason = "Strongest reasoning capabilities",
            },
            .chat => RoutingDecision{
                .provider = .openai,
                .model = "gpt-4o",
                .reason = "Best general chat model",
            },
            .fast_response => RoutingDecision{
                .provider = .ollama,
                .model = "qwen2.5-coder:7b",
                .reason = "Local and fast",
            },
        };

        return decision;
    }

    /// Get fallback providers if primary fails
    pub fn getFallbacks(self: *SmartRouter, primary: api.ApiProvider, allocator: std.mem.Allocator) ![]api.ApiProvider {
        _ = self;

        const fallbacks = switch (primary) {
            .github_copilot => &[_]api.ApiProvider{ .claude, .openai, .ollama },
            .claude => &[_]api.ApiProvider{ .github_copilot, .openai, .ollama },
            .openai => &[_]api.ApiProvider{ .github_copilot, .claude, .ollama },
            .google => &[_]api.ApiProvider{ .github_copilot, .openai, .ollama },
            .xai => &[_]api.ApiProvider{ .openai, .github_copilot, .ollama },
            .azure => &[_]api.ApiProvider{ .openai, .github_copilot, .ollama },
            .ollama => &[_]api.ApiProvider{}, // No fallback for local
        };

        return try allocator.dupe(api.ApiProvider, fallbacks);
    }
};

pub const RoutingDecision = struct {
    provider: api.ApiProvider,
    model: []const u8,
    reason: []const u8,

    pub fn print(self: *const RoutingDecision) void {
        std.debug.print("🎯 Routing: {s} via {s} ({s})\n", .{
            self.model,
            @tagName(self.provider),
            self.reason,
        });
    }
};
