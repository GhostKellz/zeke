const std = @import("std");
const api = @import("../api/client.zig");

pub const ProviderCapability = enum {
    chat_completion,
    code_completion,
    code_analysis,
    code_explanation,
    code_refactoring,
    test_generation,
    project_context,
    commit_generation,
    security_scanning,
    streaming,
};

pub const ProviderHealth = struct {
    provider: api.ApiProvider,
    is_healthy: bool,
    last_check: i64,
    response_time_ms: u64,
    error_rate: f32,
    
    pub fn isStale(self: *const ProviderHealth) bool {
        const now = std.time.timestamp();
        return (now - self.last_check) > 300; // 5 minutes
    }
};

pub const ProviderConfig = struct {
    provider: api.ApiProvider,
    priority: u8, // 1-10, higher is better
    capabilities: []const ProviderCapability,
    max_requests_per_minute: u32,
    timeout_ms: u32,
    fallback_providers: []const api.ApiProvider,
    
    pub fn hasCapability(self: *const ProviderConfig, capability: ProviderCapability) bool {
        for (self.capabilities) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }
};

pub const ProviderManager = struct {
    allocator: std.mem.Allocator,
    provider_configs: std.AutoHashMap(api.ApiProvider, ProviderConfig),
    provider_health: std.AutoHashMap(api.ApiProvider, ProviderHealth),
    client_instances: std.AutoHashMap(api.ApiProvider, *api.ApiClient),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        var manager = Self{
            .allocator = allocator,
            .provider_configs = std.AutoHashMap(api.ApiProvider, ProviderConfig).init(allocator),
            .provider_health = std.AutoHashMap(api.ApiProvider, ProviderHealth).init(allocator),
            .client_instances = std.AutoHashMap(api.ApiProvider, *api.ApiClient).init(allocator),
        };
        
        try manager.setupDefaultConfigs();
        return manager;
    }
    
    pub fn deinit(self: *Self) void {
        // Cleanup client instances
        var client_iter = self.client_instances.iterator();
        while (client_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        
        // Cleanup HashMaps
        var config_iter = self.provider_configs.iterator();
        while (config_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.capabilities);
            self.allocator.free(entry.value_ptr.fallback_providers);
        }
        
        self.provider_configs.deinit();
        self.provider_health.deinit();
        self.client_instances.deinit();
    }
    
    fn setupDefaultConfigs(self: *Self) !void {
        // OpenAI configuration
        const openai_caps = try self.allocator.dupe(ProviderCapability, &[_]ProviderCapability{
            .chat_completion, .code_completion, .code_explanation, .streaming
        });
        const openai_fallbacks = try self.allocator.dupe(api.ApiProvider, &[_]api.ApiProvider{.claude, .ollama});
        
        try self.provider_configs.put(.openai, ProviderConfig{
            .provider = .openai,
            .priority = 8,
            .capabilities = openai_caps,
            .max_requests_per_minute = 60,
            .timeout_ms = 30000,
            .fallback_providers = openai_fallbacks,
        });
        
        // Claude configuration
        const claude_caps = try self.allocator.dupe(ProviderCapability, &[_]ProviderCapability{
            .chat_completion, .code_completion, .code_analysis, .code_explanation, .streaming
        });
        const claude_fallbacks = try self.allocator.dupe(api.ApiProvider, &[_]api.ApiProvider{.openai, .ollama});
        
        try self.provider_configs.put(.claude, ProviderConfig{
            .provider = .claude,
            .priority = 9,
            .capabilities = claude_caps,
            .max_requests_per_minute = 50,
            .timeout_ms = 45000,
            .fallback_providers = claude_fallbacks,
        });
        
        // GitHub Copilot configuration
        const copilot_caps = try self.allocator.dupe(ProviderCapability, &[_]ProviderCapability{
            .code_completion, .code_explanation
        });
        const copilot_fallbacks = try self.allocator.dupe(api.ApiProvider, &[_]api.ApiProvider{.openai, .claude});
        
        try self.provider_configs.put(.copilot, ProviderConfig{
            .provider = .copilot,
            .priority = 7,
            .capabilities = copilot_caps,
            .max_requests_per_minute = 100,
            .timeout_ms = 15000,
            .fallback_providers = copilot_fallbacks,
        });
        
        // GhostLLM configuration (highest priority with all capabilities)
        const ghostllm_caps = try self.allocator.dupe(ProviderCapability, &[_]ProviderCapability{
            .chat_completion, .code_completion, .code_analysis, .code_explanation, 
            .code_refactoring, .test_generation, .project_context, .commit_generation, 
            .security_scanning, .streaming
        });
        const ghostllm_fallbacks = try self.allocator.dupe(api.ApiProvider, &[_]api.ApiProvider{.claude, .openai});
        
        try self.provider_configs.put(.ghostllm, ProviderConfig{
            .provider = .ghostllm,
            .priority = 10,
            .capabilities = ghostllm_caps,
            .max_requests_per_minute = 200,
            .timeout_ms = 5000, // Fast GPU responses
            .fallback_providers = ghostllm_fallbacks,
        });
        
        // Ollama configuration (local fallback)
        const ollama_caps = try self.allocator.dupe(ProviderCapability, &[_]ProviderCapability{
            .chat_completion, .code_completion, .code_explanation
        });
        const ollama_fallbacks = try self.allocator.dupe(api.ApiProvider, &[_]api.ApiProvider{});
        
        try self.provider_configs.put(.ollama, ProviderConfig{
            .provider = .ollama,
            .priority = 5,
            .capabilities = ollama_caps,
            .max_requests_per_minute = 1000, // Local, no real limit
            .timeout_ms = 60000, // Local inference can be slow
            .fallback_providers = ollama_fallbacks,
        });
    }
    
    pub fn selectBestProvider(self: *Self, capability: ProviderCapability) !?api.ApiProvider {
        var best_provider: ?api.ApiProvider = null;
        var best_score: f32 = 0.0;
        
        var config_iter = self.provider_configs.iterator();
        while (config_iter.next()) |entry| {
            const provider = entry.key_ptr.*;
            const config = entry.value_ptr.*;
            
            // Check if provider has the required capability
            if (!config.hasCapability(capability)) continue;
            
            // Calculate provider score
            var score: f32 = @floatFromInt(config.priority);
            
            // Factor in health status
            if (self.provider_health.get(provider)) |health| {
                if (!health.is_healthy) {
                    score *= 0.1; // Heavily penalize unhealthy providers
                }
                
                // Factor in response time (lower is better)
                if (health.response_time_ms > 0) {
                    const response_factor = 1000.0 / @as(f32, @floatFromInt(health.response_time_ms));
                    score *= response_factor;
                }
                
                // Factor in error rate (lower is better)
                score *= (1.0 - health.error_rate);
            }
            
            if (score > best_score) {
                best_score = score;
                best_provider = provider;
            }
        }
        
        return best_provider;
    }
    
    pub fn selectProvidersWithFallback(self: *Self, capability: ProviderCapability, allocator: std.mem.Allocator) ![]api.ApiProvider {
        var providers = std.ArrayList(api.ApiProvider).init(allocator);
        
        // Get the best provider
        if (try self.selectBestProvider(capability)) |primary| {
            try providers.append(primary);
            
            // Add fallback providers
            if (self.provider_configs.get(primary)) |config| {
                for (config.fallback_providers) |fallback| {
                    // Only add fallback if it has the required capability
                    if (self.provider_configs.get(fallback)) |fallback_config| {
                        if (fallback_config.hasCapability(capability)) {
                            try providers.append(fallback);
                        }
                    }
                }
            }
        }
        
        return providers.toOwnedSlice();
    }
    
    pub fn getOrCreateClient(self: *Self, provider: api.ApiProvider) !*api.ApiClient {
        if (self.client_instances.get(provider)) |client| {
            return client;
        }
        
        // Create new client instance
        const client = try self.allocator.create(api.ApiClient);
        client.* = try api.ApiClient.init(self.allocator, provider);
        
        try self.client_instances.put(provider, client);
        return client;
    }
    
    pub fn updateHealth(self: *Self, provider: api.ApiProvider, is_healthy: bool, response_time_ms: u64) !void {
        const now = std.time.timestamp();
        
        var health = self.provider_health.get(provider) orelse ProviderHealth{
            .provider = provider,
            .is_healthy = true,
            .last_check = now,
            .response_time_ms = 0,
            .error_rate = 0.0,
        };
        
        // Update health metrics
        health.is_healthy = is_healthy;
        health.last_check = now;
        health.response_time_ms = response_time_ms;
        
        // Update error rate with exponential moving average
        const error_value: f32 = if (is_healthy) 0.0 else 1.0;
        health.error_rate = health.error_rate * 0.9 + error_value * 0.1;
        
        try self.provider_health.put(provider, health);
    }
    
    pub fn healthCheck(self: *Self, provider: api.ApiProvider) !bool {
        const client = try self.getOrCreateClient(provider);
        const start_time = std.time.milliTimestamp();
        
        // Simple health check with a basic chat completion
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = "ping" },
        };
        
        const is_healthy = blk: {
            _ = client.chatCompletion(&messages, "health-check") catch break :blk false;
            break :blk true;
        };
        
        const end_time = std.time.milliTimestamp();
        const response_time: u64 = @intCast(end_time - start_time);
        
        try self.updateHealth(provider, is_healthy, response_time);
        return is_healthy;
    }
    
    pub fn performHealthChecks(self: *Self) !void {
        var config_iter = self.provider_configs.iterator();
        while (config_iter.next()) |entry| {
            const provider = entry.key_ptr.*;
            
            // Only check stale health status
            if (self.provider_health.get(provider)) |health| {
                if (!health.isStale()) continue;
            }
            
            _ = self.healthCheck(provider) catch |err| {
                std.log.warn("Health check failed for provider {s}: {}", .{ @tagName(provider), err });
                try self.updateHealth(provider, false, 30000); // Mark as unhealthy with high response time
            };
        }
    }
    
    pub fn getProviderConfig(self: *Self, provider: api.ApiProvider) ?ProviderConfig {
        return self.provider_configs.get(provider);
    }
    
    pub fn getProviderHealth(self: *Self, provider: api.ApiProvider) ?ProviderHealth {
        return self.provider_health.get(provider);
    }
    
    pub fn listHealthyProviders(self: *Self, capability: ProviderCapability, allocator: std.mem.Allocator) ![]api.ApiProvider {
        var healthy_providers = std.ArrayList(api.ApiProvider).init(allocator);
        
        var config_iter = self.provider_configs.iterator();
        while (config_iter.next()) |entry| {
            const provider = entry.key_ptr.*;
            const config = entry.value_ptr.*;
            
            // Check capability
            if (!config.hasCapability(capability)) continue;
            
            // Check health
            if (self.provider_health.get(provider)) |health| {
                if (health.is_healthy) {
                    try healthy_providers.append(provider);
                }
            } else {
                // If no health data, assume healthy for now
                try healthy_providers.append(provider);
            }
        }
        
        return healthy_providers.toOwnedSlice();
    }
};