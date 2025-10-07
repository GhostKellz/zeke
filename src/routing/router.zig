const std = @import("std");
const ollama = @import("../providers/ollama.zig");
const omen = @import("../providers/omen.zig");
const routing_db = @import("../db/routing.zig");
const mcp = @import("../mcp/mod.zig");

/// Smart router that decides between local (Ollama) and cloud (OMEN) providers
pub const SmartRouter = struct {
    allocator: std.mem.Allocator,
    ollama_client: ?*ollama.OllamaProvider,
    omen_client: ?*omen.OmenClient,
    db: ?*routing_db.RoutingDB,
    mcp_client: ?*mcp.McpClient,
    config: RoutingConfig,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        ollama_client: ?*ollama.OllamaProvider,
        omen_client: ?*omen.OmenClient,
        db: ?*routing_db.RoutingDB,
        config: RoutingConfig,
    ) Self {
        return .{
            .allocator = allocator,
            .ollama_client = ollama_client,
            .omen_client = omen_client,
            .db = db,
            .mcp_client = null, // Set separately via setMcpClient
            .config = config,
        };
    }

    pub fn setMcpClient(self: *Self, client: *mcp.McpClient) void {
        self.mcp_client = client;
    }

    /// Route a completion request to the best provider
    pub fn complete(self: *Self, request: CompletionRequest) !CompletionResponse {
        const start_time = std.time.milliTimestamp();
        const request_id = try self.generateRequestId();
        defer self.allocator.free(request_id);

        // Decide routing strategy
        const decision = try self.makeRoutingDecision(request);

        std.log.info("Routing decision: {s} provider for intent '{s}', complexity '{s}'", .{
            @tagName(decision.provider),
            request.intent orelse "unknown",
            @tagName(decision.complexity),
        });

        var response: CompletionResponse = undefined;
        var routing_stats = routing_db.RoutingStats{
            .request_id = request_id,
            .project = request.project orelse "default",
            .alias = request.model,
            .model = "",
            .provider = "",
            .intent = request.intent orelse "code",
            .size_hint = @tagName(decision.complexity),
            .latency_ms = 0,
            .total_duration_ms = 0,
            .tokens_in = 0,
            .tokens_out = 0,
            .cost_cents = 0.0,
            .success = false,
            .error_code = null,
            .escalated = false,
            .created_at = std.time.timestamp(),
        };

        switch (decision.provider) {
            .local => {
                response = self.tryLocalOllama(request, &routing_stats) catch |err| blk: {
                    std.log.warn("Local Ollama failed: {}, escalating to cloud", .{err});

                    if (self.config.fallback_to_cloud and self.omen_client != null) {
                        routing_stats.escalated = true;
                        break :blk try self.useOmen(request, &routing_stats);
                    }

                    return err;
                };
            },
            .cloud => {
                response = try self.useOmen(request, &routing_stats);
            },
            .hybrid => {
                // Try local first, fallback to cloud on timeout
                response = self.tryLocalWithTimeout(request, &routing_stats, decision.timeout_ms) catch |err| blk: {
                    std.log.info("Local timeout/error: {}, escalating to cloud", .{err});
                    routing_stats.escalated = true;
                    break :blk try self.useOmen(request, &routing_stats);
                };
            },
        }

        const end_time = std.time.milliTimestamp();
        routing_stats.total_duration_ms = @intCast(end_time - start_time);
        routing_stats.success = true;

        // Record metrics
        if (self.db) |db| {
            db.recordStats(routing_stats) catch |err| {
                std.log.warn("Failed to record routing stats: {}", .{err});
            };
        }

        return response;
    }

    fn makeRoutingDecision(self: *Self, request: CompletionRequest) !RoutingDecision {
        const complexity = self.estimateComplexity(request);
        const intent = request.intent orelse "code";

        // Check if intent should prefer local
        const prefer_local = for (self.config.prefer_local_for) |local_intent| {
            if (std.mem.eql(u8, intent, local_intent)) break true;
        } else false;

        // Decide provider based on complexity and intent
        if (prefer_local and complexity == .simple) {
            return RoutingDecision{
                .provider = .local,
                .complexity = complexity,
                .timeout_ms = 2000, // 2s for simple local tasks
            };
        }

        if (complexity == .complex or !self.config.use_local) {
            return RoutingDecision{
                .provider = .cloud,
                .complexity = complexity,
                .timeout_ms = 30000, // 30s for complex cloud tasks
            };
        }

        // Hybrid: try local with timeout, fallback to cloud
        if (complexity == .medium and self.config.fallback_to_cloud) {
            return RoutingDecision{
                .provider = .hybrid,
                .complexity = complexity,
                .timeout_ms = self.config.first_token_timeout_ms,
            };
        }

        // Default to local if available
        if (self.ollama_client != null) {
            return RoutingDecision{
                .provider = .local,
                .complexity = complexity,
                .timeout_ms = 5000,
            };
        }

        // Fallback to cloud
        return RoutingDecision{
            .provider = .cloud,
            .complexity = complexity,
            .timeout_ms = 30000,
        };
    }

    fn estimateComplexity(self: *Self, request: CompletionRequest) Complexity {
        _ = self;

        // Heuristics for complexity estimation
        const prompt_len = request.prompt.len;
        const max_tokens = request.max_tokens orelse 512;

        // Check explicit complexity hint
        if (request.complexity) |hint| {
            if (std.mem.eql(u8, hint, "simple")) return .simple;
            if (std.mem.eql(u8, hint, "complex")) return .complex;
            return .medium;
        }

        // Intent-based complexity
        if (request.intent) |intent| {
            if (std.mem.eql(u8, intent, "completion")) return .simple;
            if (std.mem.eql(u8, intent, "architecture") or
                std.mem.eql(u8, intent, "reason")) return .complex;
        }

        // Size-based heuristics
        if (prompt_len < 200 and max_tokens <= 512) return .simple;
        if (prompt_len > 2000 or max_tokens > 2048) return .complex;

        return .medium;
    }

    fn tryLocalOllama(self: *Self, request: CompletionRequest, stats: *routing_db.RoutingStats) !CompletionResponse {
        if (self.ollama_client == null) return error.NoLocalProvider;

        const ollama_client = self.ollama_client.?;

        // Convert to Ollama generate request
        const ollama_request = ollama.OllamaGenerateRequest{
            .model = request.model orelse "deepseek-coder:33b",
            .prompt = request.prompt,
            .stream = false,
            .options = .{
                .temperature = request.temperature,
            },
        };

        const start = std.time.milliTimestamp();
        const ollama_response = try ollama_client.generate(ollama_request);
        const latency = std.time.milliTimestamp() - start;

        stats.provider = "ollama";
        stats.model = ollama_response.model;
        stats.latency_ms = @intCast(latency);
        stats.tokens_in = ollama_response.prompt_eval_count orelse 0;
        stats.tokens_out = ollama_response.eval_count orelse 0;
        stats.cost_cents = 0.0; // Local is free

        return CompletionResponse{
            .content = ollama_response.response,
            .model = ollama_response.model,
            .provider = "ollama",
            .tokens_in = ollama_response.prompt_eval_count orelse 0,
            .tokens_out = ollama_response.eval_count orelse 0,
            .latency_ms = @intCast(latency),
        };
    }

    fn tryLocalWithTimeout(self: *Self, request: CompletionRequest, stats: *routing_db.RoutingStats, timeout_ms: u32) !CompletionResponse {
        _ = timeout_ms; // TODO: Implement timeout mechanism
        return try self.tryLocalOllama(request, stats);
    }

    fn useOmen(self: *Self, request: CompletionRequest, stats: *routing_db.RoutingStats) !CompletionResponse {
        if (self.omen_client == null) return error.NoCloudProvider;

        const omen_client = self.omen_client.?;

        // Convert to OMEN chat completion request
        var messages = [_]omen.Message{
            .{ .role = "user", .content = request.prompt },
        };

        const omen_request = omen.ChatCompletionRequest{
            .model = request.model orelse "auto",
            .messages = &messages,
            .temperature = request.temperature,
            .max_tokens = request.max_tokens,
            .tags = .{
                .intent = request.intent,
                .language = request.language,
                .complexity = request.complexity,
                .project = request.project,
                .priority = request.priority,
            },
        };

        const start = std.time.milliTimestamp();
        const omen_response = try omen_client.chatCompletion(omen_request);
        const latency = std.time.milliTimestamp() - start;

        const content = if (omen_response.choices.len > 0)
            omen_response.choices[0].message.content
        else
            "";

        stats.provider = if (omen_response.routing_metadata) |rm| rm.provider else "omen";
        stats.model = omen_response.model;
        stats.latency_ms = @intCast(latency);
        if (omen_response.usage) |usage| {
            stats.tokens_in = usage.prompt_tokens;
            stats.tokens_out = usage.completion_tokens;
        }
        if (omen_response.routing_metadata) |rm| {
            if (rm.cost_usd) |cost| {
                stats.cost_cents = cost * 100.0;
            }
        }

        return CompletionResponse{
            .content = content,
            .model = omen_response.model,
            .provider = stats.provider,
            .tokens_in = stats.tokens_in,
            .tokens_out = stats.tokens_out,
            .latency_ms = @intCast(latency),
        };
    }

    fn generateRequestId(self: *Self) ![]const u8 {
        const timestamp = std.time.timestamp();
        var rng = std.Random.DefaultPrng.init(@intCast(timestamp));
        const random_bytes = rng.random().int(u32);

        return try std.fmt.allocPrint(self.allocator, "zeke-{x}-{x}", .{ timestamp, random_bytes });
    }
};

pub const RoutingConfig = struct {
    /// Prefer local Ollama for these intents
    prefer_local_for: []const []const u8 = &.{ "code", "completion", "refactor", "tests" },
    /// Use local Ollama if available
    use_local: bool = true,
    /// Fallback to cloud (OMEN) if local fails
    fallback_to_cloud: bool = true,
    /// Timeout before escalating to cloud (ms)
    first_token_timeout_ms: u32 = 2000,
    /// Maximum cost per request in cents (cloud only)
    max_cost_cents: ?u32 = 200,
};

pub const CompletionRequest = struct {
    prompt: []const u8,
    model: ?[]const u8 = null,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    /// Routing hints
    intent: ?[]const u8 = null, // code, completion, refactor, etc.
    language: ?[]const u8 = null,
    complexity: ?[]const u8 = null, // simple, medium, complex
    project: ?[]const u8 = null,
    priority: ?[]const u8 = null, // low-latency, high-quality, cost-effective
};

pub const CompletionResponse = struct {
    content: []const u8,
    model: []const u8,
    provider: []const u8, // "ollama", "anthropic", "openai"
    tokens_in: u32,
    tokens_out: u32,
    latency_ms: u32,
};

const RoutingDecision = struct {
    provider: ProviderType,
    complexity: Complexity,
    timeout_ms: u32,
};

const ProviderType = enum {
    local, // Ollama
    cloud, // OMEN
    hybrid, // Try local, fallback to cloud
};

const Complexity = enum {
    simple,
    medium,
    complex,
};

/// Create default routing config from environment
pub fn defaultConfig() RoutingConfig {
    return RoutingConfig{};
}

/// Test smart routing
pub fn testRouting() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize providers
    var ollama_provider = try ollama.fromEnv(allocator);
    defer ollama_provider.deinit();

    var omen_client = try omen.fromEnv(allocator);
    defer omen_client.deinit();

    // Create router
    var router = SmartRouter.init(
        allocator,
        &ollama_provider,
        &omen_client,
        null, // No database for test
        defaultConfig(),
    );

    // Test simple code completion (should use local)
    std.debug.print("\n=== Test 1: Simple Code Completion ===\n", .{});
    const simple_request = CompletionRequest{
        .prompt = "Write a Zig function that adds two numbers",
        .intent = "code",
        .complexity = "simple",
        .max_tokens = 256,
    };

    const simple_response = try router.complete(simple_request);
    std.debug.print("Provider: {s}\n", .{simple_response.provider});
    std.debug.print("Model: {s}\n", .{simple_response.model});
    std.debug.print("Latency: {}ms\n", .{simple_response.latency_ms});
    std.debug.print("Response: {s}\n", .{simple_response.content[0..@min(200, simple_response.content.len)]});

    // Test complex architecture (should use cloud)
    std.debug.print("\n=== Test 2: Complex Architecture ===\n", .{});
    const complex_request = CompletionRequest{
        .prompt = "Design a distributed system architecture for real-time AI routing",
        .intent = "architecture",
        .complexity = "complex",
        .max_tokens = 2048,
    };

    const complex_response = try router.complete(complex_request);
    std.debug.print("Provider: {s}\n", .{complex_response.provider});
    std.debug.print("Model: {s}\n", .{complex_response.model});
    std.debug.print("Latency: {}ms\n", .{complex_response.latency_ms});
}
