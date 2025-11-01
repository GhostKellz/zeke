//! ZEKE - The Zig-Native AI Dev Companion
const std = @import("std");
const zsync = @import("zsync");

// Re-export all modules
pub const api = @import("api/client.zig");
pub const auth = @import("auth/mod.zig");
pub const config = @import("config/mod.zig");
pub const providers = @import("providers/mod.zig");
pub const streaming = @import("streaming/mod.zig");
pub const error_handling = @import("error_handling/mod.zig");
pub const context = @import("context/mod.zig");
pub const concurrent = @import("concurrent/mod.zig");
pub const system = @import("system/arch.zig");
pub const tui = @import("tui/mod.zig");
pub const ui = @import("ui/mod.zig");
pub const usage = @import("usage/mod.zig");
pub const routing = struct {
    pub const SmartRouter = @import("routing/router.zig").SmartRouter;
    pub const RoutingConfig = @import("routing/router.zig").RoutingConfig;
    pub const CompletionRequest = @import("routing/router.zig").CompletionRequest;
    pub const CompletionResponse = @import("routing/router.zig").CompletionResponse;
};
pub const db = struct {
    pub const RoutingDB = @import("db/routing.zig").RoutingDB;
    pub const RoutingStats = @import("db/routing.zig").RoutingStats;
    pub const RoutingPrefs = @import("db/routing.zig").RoutingPrefs;
    pub const Model = @import("db/routing.zig").Model;
    pub const getRecentStats = @import("db/routing.zig").getRecentStats;
};
pub const rpc = struct {
    pub const GhostRPC = @import("rpc/ghost_rpc_standalone.zig").GhostRPC;
    pub const HttpServer = @import("rpc/http_server.zig").HttpServer;
    pub const ZhttpServer = @import("rpc/zhttp_server.zig").ZhttpServer;
    pub const ResponseFormats = @import("rpc/response_formats.zig").ResponseFormats;
    pub const MsgPackRPC = GhostRPC; // Alias for backward compatibility
};
pub const git = @import("git/mod.zig");
pub const search = @import("search/mod.zig");
pub const build = @import("build/mod.zig");
pub const storage = @import("storage/mod.zig");
pub const watch = @import("watch.zig");
pub const integrations = @import("integrations/mod.zig");
pub const mcp = @import("mcp/mod.zig");
// TODO: Temporarily commented out until circular dependency is resolved
// pub const tools = @import("tools/mod.zig");

pub const ZekeError = error{
    InitializationFailed,
    AuthenticationFailed,
    ConfigLoadFailed,
    NetworkError,
    InvalidModel,
    TokenExchangeFailed,
    UnexpectedResponse,
};

pub const Zeke = struct {
    allocator: std.mem.Allocator,
    io: ?zsync.Io,
    config: config.Config,
    auth_manager: auth.AuthManager,
    api_client: api.ApiClient,
    provider_manager: providers.ProviderManager,
    fallback_manager: error_handling.FallbackManager,
    context_cache: context.ProjectContextCache,
    storage_manager: ?storage.StorageManager,
    concurrent_ai: ?concurrent.ConcurrentAI,
    arch_system: ?system.ArchSystem,
    realtime_features: ?streaming.RealTimeFeatures,
    token_tracker: usage.TokenTracker,
    current_model: []const u8,
    current_provider: api.ApiProvider,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self.initWithIO(allocator, null);
    }

    pub fn initWithIO(allocator: std.mem.Allocator, io: ?zsync.Io) !Self {
        const zeke_config = config.loadConfig(allocator) catch |err| {
            std.log.err("Failed to load config: {}", .{err});
            return ZekeError.ConfigLoadFailed;
        };

        const auth_manager = auth.AuthManager.init(allocator) catch |err| {
            std.log.err("Failed to initialize auth manager: {}", .{err});
            return ZekeError.InitializationFailed;
        };

        // Initialize provider manager
        var provider_manager = providers.ProviderManager.init(allocator) catch |err| {
            std.log.err("Failed to initialize provider manager: {}", .{err});
            return ZekeError.InitializationFailed;
        };

        // Initialize fallback manager for error handling
        const fallback_manager = error_handling.FallbackManager.init(allocator);

        // Initialize context cache for project intelligence
        const context_cache = context.ProjectContextCache.init(allocator);

        // Initialize concurrent AI handler
        const concurrent_ai = if (io != null)
            concurrent.ConcurrentAI.initWithZsync(allocator, &provider_manager, io) catch null
        else
            concurrent.ConcurrentAI.init(allocator, &provider_manager) catch null;

        // Initialize Arch Linux system integration if available
        const arch_system = if (system.ArchSystem.isArchLinux())
            system.ArchSystem.init(allocator)
        else
            null;

        // Initialize storage manager with encrypted database
        const storage_manager = storage.StorageManager.init(allocator, "zeke_data.db", "zeke_secure_2024" // Default password, should be from config
        ) catch |err| blk: {
            std.log.warn("Failed to initialize storage: {}, continuing without persistence", .{err});
            break :blk null;
        };

        // Select best provider for chat completion (default behavior)
        const best_provider = try provider_manager.selectBestProvider(.chat_completion) orelse .openai;

        // Initialize with best available provider
        const api_client = api.ApiClient.init(allocator, best_provider) catch |err| {
            std.log.err("Failed to initialize API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };

        return Self{
            .allocator = allocator,
            .io = io,
            .config = zeke_config,
            .auth_manager = auth_manager,
            .api_client = api_client,
            .provider_manager = provider_manager,
            .fallback_manager = fallback_manager,
            .context_cache = context_cache,
            .storage_manager = storage_manager,
            .concurrent_ai = concurrent_ai,
            .arch_system = arch_system,
            .realtime_features = null, // Initialized on demand
            .token_tracker = usage.TokenTracker.init(allocator),
            .current_model = zeke_config.default_model,
            .current_provider = best_provider,
        };
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit();
        self.auth_manager.deinit();
        self.api_client.deinit();
        self.token_tracker.deinit();
        self.provider_manager.deinit();
        self.fallback_manager.deinit();
        self.context_cache.deinit();
        if (self.storage_manager) |*storage_mgr| {
            storage_mgr.deinit();
        }
        if (self.concurrent_ai) |*concurrent_ai| {
            concurrent_ai.deinit();
        }
        if (self.arch_system) |*arch| {
            arch.deinit();
        }
        if (self.realtime_features) |*rt| {
            rt.deinit();
        }
    }

    pub fn setModel(self: *Self, model_name: []const u8) !void {
        const model_config = self.config.getModel(model_name) orelse return ZekeError.InvalidModel;

        // Switch API client based on provider
        self.api_client.deinit();

        const provider = if (std.mem.eql(u8, model_config.provider, "openai"))
            api.ApiProvider.openai
        else if (std.mem.eql(u8, model_config.provider, "claude"))
            api.ApiProvider.claude
        else if (std.mem.eql(u8, model_config.provider, "xai"))
            api.ApiProvider.xai
        else if (std.mem.eql(u8, model_config.provider, "azure"))
            api.ApiProvider.azure
        else
            api.ApiProvider.ollama;

        self.api_client = api.ApiClient.init(self.allocator, provider) catch |err| {
            std.log.err("Failed to switch API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };

        // Set auth token for new provider
        const auth_provider = switch (provider) {
            .openai => auth.AuthProvider.openai,
            .claude => auth.AuthProvider.anthropic,
            .xai => auth.AuthProvider.openai, // Use OpenAI for xAI compatibility
            .google => auth.AuthProvider.google,
            .azure => auth.AuthProvider.azure,
            .ollama => auth.AuthProvider.local,
            .github_copilot => auth.AuthProvider.github,
        };

        // Auth manager integration (TODO: implement getApiKey method in AuthManager)
        _ = auth_provider;

        self.current_model = model_name;
    }

    pub fn chat(self: *Self, message: []const u8) ![]const u8 {
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };

        const response = try self.api_client.chatCompletion(&messages, self.current_model);

        // Track token usage if available
        if (response.usage) |usage_data| {
            try self.token_tracker.track(self.current_provider, usage_data);
        }

        // Note: caller must free response.content
        return response.content;
    }

    /// Chat with detailed response including usage data
    pub fn chatWithUsage(self: *Self, message: []const u8) !api.ChatResponse {
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };

        const response = try self.api_client.chatCompletion(&messages, self.current_model);

        // Track token usage if available
        if (response.usage) |usage_data| {
            try self.token_tracker.track(self.current_provider, usage_data);
        }

        return response;
    }

    /// Print token usage summary for the current session
    pub fn printUsageSummary(self: *Self) !void {
        try self.token_tracker.printSummary(self.allocator);
    }

    /// Print compact usage info (for after each response)
    pub fn printLastUsage(self: *Self) void {
        if (self.token_tracker.getProviderUsage(self.current_provider)) |provider_usage| {
            // Create a simple usage struct for the last request
            // This is an approximation - ideally we'd track the last request separately
            self.token_tracker.printCompact(self.current_provider, api.Usage{
                .prompt_tokens = 0,
                .completion_tokens = 0,
                .total_tokens = provider_usage.total_tokens,
            });
        }
    }

    pub fn completeCode(self: *Self, prompt: []const u8, code_context: api.CodeContext) ![]const u8 {
        const response = try self.api_client.codeCompletion(prompt, code_context);
        return response.text;
    }

    pub fn authenticateGitHub(self: *Self, token: []const u8) !void {
        try self.auth_manager.authenticateGitHub(token);
    }

    pub fn authenticateGoogle(self: *Self, auth_code: []const u8) !void {
        try self.auth_manager.authenticateGoogle(auth_code);
    }

    pub fn setOpenAIKey(self: *Self, key: []const u8) !void {
        try self.auth_manager.setOpenAIToken(key);
    }

    pub fn analyzeCode(self: *Self, file_contents: []const u8, analysis_type: api.AnalysisType, project_context: api.ProjectContext) !api.AnalysisResponse {
        return try self.api_client.analyzeCode(file_contents, analysis_type, project_context);
    }

    pub fn explainCode(self: *Self, code: []const u8, code_context: api.CodeContext) !api.ExplanationResponse {
        return try self.api_client.explainCode(code, code_context);
    }

    pub fn refactorCode(self: *Self, code: []const u8, refactor_type: api.RefactorType, code_context: api.CodeContext) !api.RefactorResponse {
        return try self.api_client.refactorCode(code, refactor_type, code_context);
    }

    pub fn generateTests(self: *Self, code: []const u8, code_context: api.CodeContext) !api.TestResponse {
        return try self.api_client.generateTests(code, code_context);
    }

    // Smart provider selection methods
    pub fn selectBestProviderForTask(self: *Self, capability: providers.ProviderCapability) !api.ApiProvider {
        // Perform health checks if needed
        try self.provider_manager.performHealthChecks();

        // Select best provider for the given capability
        return try self.provider_manager.selectBestProvider(capability) orelse {
            std.log.warn("No healthy provider found for capability: {s}", .{@tagName(capability)});
            return ZekeError.InitializationFailed;
        };
    }

    pub fn switchToProvider(self: *Self, provider: api.ApiProvider) !void {
        if (self.current_provider == provider) return;

        // Deinitialize current client
        self.api_client.deinit();

        // Get or create new client for the provider
        const client = try self.provider_manager.getOrCreateClient(provider);
        self.api_client = client.*;
        self.current_provider = provider;

        // Update authentication for new provider
        const auth_provider = switch (provider) {
            .openai => auth.AuthProvider.openai,
            .claude => auth.AuthProvider.anthropic,
            .xai => auth.AuthProvider.openai, // Use OpenAI for xAI compatibility
            .google => auth.AuthProvider.google,
            .azure => auth.AuthProvider.azure,
            .ollama => auth.AuthProvider.local,
            .github_copilot => auth.AuthProvider.github,
        };

        // Auth manager integration (TODO: implement getApiKey method in AuthManager)
        _ = auth_provider;

        std.log.info("Switched to provider: {s}", .{@tagName(provider)});
    }

    pub fn chatWithFallback(self: *Self, message: []const u8) ![]const u8 {
        // TODO: Implement proper fallback mechanism
        _ = self.provider_manager;
        _ = self.fallback_manager;

        // For now, just use the regular chat function until error handling is fully implemented
        const result = self.chat(message) catch |err| {
            std.log.err("Chat operation failed: {}", .{err});

            // Return graceful degradation message
            return try std.fmt.allocPrint(self.allocator, "Chat service temporarily unavailable. Error: {}", .{err});
        };

        return result;
    }

    pub fn chatRobust(self: *Self, message: []const u8) ![]const u8 {
        // Enhanced chat with full error handling and monitoring
        const start_time = std.time.milliTimestamp();

        // Try parallel execution first if available
        const result = if (self.concurrent_ai != null) blk: {
            const all_providers = [_]api.ApiProvider{ self.current_provider, .claude, .openai, .ollama };
            break :blk self.parallelChat(message, &all_providers) catch |err| {
                std.log.warn("Parallel chat failed: {}, falling back to single provider", .{err});
                break :blk self.chatWithFallback(message);
            };
        } else self.chatWithFallback(message) catch |err| {
            const end_time = std.time.milliTimestamp();
            const response_time: u64 = @intCast(end_time - start_time);

            // Record failure in provider health
            self.provider_manager.updateHealth(self.current_provider, false, response_time) catch {};

            // Check if we should provide a graceful response
            if (err == error.AllProvidersFailed) {
                return error_handling.createOfflineResponse(self.allocator, "chat");
            }

            return err;
        };

        // Record success
        const end_time = std.time.milliTimestamp();
        const response_time: u64 = @intCast(end_time - start_time);
        self.provider_manager.updateHealth(self.current_provider, true, response_time) catch {};

        return result;
    }

    pub fn analyzeCodeWithBestProvider(self: *Self, file_contents: []const u8, analysis_type: api.AnalysisType, project_context: api.ProjectContext) !api.AnalysisResponse {
        // Select best provider for code analysis
        const best_provider = try self.selectBestProviderForTask(.code_analysis);
        try self.switchToProvider(best_provider);

        return try self.analyzeCode(file_contents, analysis_type, project_context);
    }

    pub fn explainCodeWithBestProvider(self: *Self, code: []const u8, code_context: api.CodeContext) !api.ExplanationResponse {
        // Select best provider for code explanation
        const best_provider = try self.selectBestProviderForTask(.code_explanation);
        try self.switchToProvider(best_provider);

        return try self.explainCode(code, code_context);
    }

    pub fn getProviderStatus(self: *Self) ![]providers.ProviderHealth {
        var status_list = std.ArrayList(providers.ProviderHealth){};

        const provider_list = [_]api.ApiProvider{ .claude, .openai, .xai, .azure, .ollama };
        for (provider_list) |provider| {
            if (self.provider_manager.getProviderHealth(provider)) |health| {
                try status_list.append(self.allocator, health);
            } else {
                // Create default health status
                try status_list.append(self.allocator, providers.ProviderHealth{
                    .provider = provider,
                    .is_healthy = false,
                    .last_check = 0,
                    .response_time_ms = 0,
                    .error_rate = 0.0,
                });
            }
        }

        return status_list.toOwnedSlice(self.allocator);
    }

    // Enhanced error handling and diagnostics
    pub fn getErrorStats(self: *Self) error_handling.ErrorStats {
        return self.fallback_manager.getErrorStats();
    }

    pub fn getProviderErrorCount(self: *Self, provider: api.ApiProvider) u32 {
        return self.fallback_manager.getProviderErrors(provider);
    }

    pub fn performHealthCheck(self: *Self) !void {
        std.log.info("Performing comprehensive health check...");

        try self.provider_manager.performHealthChecks();

        const stats = self.getErrorStats();
        std.log.info("Error statistics - Total: {d}, Network: {d}, Auth: {d}, Rate Limit: {d}, Provider: {d}", .{ stats.total_errors, stats.network_errors, stats.auth_errors, stats.rate_limit_errors, stats.provider_errors });

        // Check circuit breaker states
        const providers_to_check = [_]api.ApiProvider{ .claude, .openai, .xai, .azure, .ollama };
        for (providers_to_check) |provider| {
            const breaker = self.fallback_manager.getCircuitBreaker(provider) catch continue;
            const state = breaker.getState();
            std.log.info("Circuit breaker for {s}: {s}", .{ @tagName(provider), @tagName(state) });
        }
    }

    pub fn resetErrorState(self: *Self, provider: api.ApiProvider) !void {
        try self.fallback_manager.recordSuccess(provider);
        std.log.info("Reset error state for provider: {s}", .{@tagName(provider)});
    }

    pub fn enableGracefulDegradation(_: *Self) void {
        // Configure system for graceful degradation
        std.log.info("Graceful degradation mode enabled");
        // This could adjust timeouts, retry policies, etc.
    }

    // Streaming and real-time features
    pub fn enableRealTimeFeatures(self: *Self) !void {
        if (self.realtime_features == null) {
            // Get HTTP client from current API client
            if (self.api_client.http_client) |http_client| {
                self.realtime_features = streaming.RealTimeFeatures.init(self.allocator, http_client);

                std.log.info("Real-time features enabled", .{});
            } else {
                return ZekeError.InitializationFailed;
            }
        }
    }

    pub fn streamChat(self: *Self, message: []const u8, callback: streaming.StreamCallback) !void {
        // Ensure real-time features are enabled
        try self.enableRealTimeFeatures();

        // Build chat request
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };

        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/chat/completions", .{self.api_client.base_url});
        defer self.allocator.free(endpoint);

        const request_body = try self.buildStreamingChatRequest(&messages, self.current_model);
        defer self.allocator.free(request_body);

        // Prepare headers
        var headers = std.ArrayList(std.http.Header){};
        defer headers.deinit(self.allocator);

        try headers.append(self.allocator, .{ .name = "content-type", .value = "application/json" });

        if (self.api_client.auth_token) |token| {
            const auth_header = switch (self.current_provider) {
                .openai => try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}),
                .claude => try std.fmt.allocPrint(self.allocator, "x-api-key: {s}", .{token}),
                .xai => try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}), // xAI uses OpenAI-compatible auth
                .google => try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}), // Google API key
                .azure => try std.fmt.allocPrint(self.allocator, "api-key: {s}", .{token}),
                .ollama => token,
                .github_copilot => try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}),
            };
            defer self.allocator.free(auth_header);

            if (self.current_provider != .ollama) {
                try headers.append(self.allocator, .{ .name = "authorization", .value = auth_header });
            }
        }

        // Start streaming
        if (self.realtime_features) |*rt| {
            // Convert headers to slice with proper type
            const headers_slice = @as([]const std.http.Header, headers.items);
            try rt.streaming_client.streamChatCompletion(endpoint, request_body, headers_slice, callback);
        }
    }

    pub fn streamCodeCompletion(self: *Self, prompt: []const u8, code_context: api.CodeContext, callback: streaming.StreamCallback) !void {
        // Ensure real-time features are enabled
        try self.enableRealTimeFeatures();

        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/completions", .{self.api_client.base_url});
        defer self.allocator.free(endpoint);

        const request_body = try self.buildStreamingCompletionRequest(prompt, code_context);
        defer self.allocator.free(request_body);

        // Prepare headers (similar to streamChat)
        var headers = std.ArrayList(std.http.Header){};
        defer headers.deinit(self.allocator);
        try headers.append(self.allocator, .{ .name = "content-type", .value = "application/json" });

        if (self.realtime_features) |*rt| {
            // Convert headers to slice with proper type
            const headers_slice = @as([]const std.http.Header, headers.items);
            try rt.streaming_client.streamCodeCompletion(endpoint, request_body, headers_slice, callback);
        }
    }

    pub fn enableTypingAssistance(self: *Self, text_buffer: []const u8, callback: streaming.StreamCallback) !void {
        try self.enableRealTimeFeatures();

        if (self.realtime_features) |*rt| {
            try rt.streamTypingAssistance(text_buffer, callback);
        }
    }

    pub fn createProgressIndicator(self: *Self, task_type: []const u8) !streaming.ProgressIndicator {
        return try streaming.ProgressIndicator.init(self.allocator, task_type);
    }

    // Helper methods for building streaming requests
    fn buildStreamingChatRequest(self: *Self, messages: []const api.ChatMessage, model: []const u8) ![]const u8 {
        var request = std.ArrayList(u8){};
        defer request.deinit(self.allocator);

        try request.appendSlice(self.allocator, "{\"model\":\"");
        try request.appendSlice(self.allocator, model);
        try request.appendSlice(self.allocator, "\",\"stream\":true,\"messages\":[");

        for (messages, 0..) |msg, i| {
            if (i > 0) try request.appendSlice(self.allocator, ",");
            try request.appendSlice(self.allocator, "{\"role\":\"");
            try request.appendSlice(self.allocator, msg.role);
            try request.appendSlice(self.allocator, "\",\"content\":\"");
            // Escape the content properly
            for (msg.content) |char| {
                switch (char) {
                    '"' => try request.appendSlice(self.allocator, "\\\""),
                    '\\' => try request.appendSlice(self.allocator, "\\\\"),
                    '\n' => try request.appendSlice(self.allocator, "\\n"),
                    '\r' => try request.appendSlice(self.allocator, "\\r"),
                    '\t' => try request.appendSlice(self.allocator, "\\t"),
                    else => try request.append(self.allocator, char),
                }
            }
            try request.appendSlice(self.allocator, "\"}");
        }

        try request.appendSlice(self.allocator, "]}");
        return request.toOwnedSlice(self.allocator);
    }

    fn buildStreamingCompletionRequest(self: *Self, prompt: []const u8, code_context: api.CodeContext) ![]const u8 {
        const language = code_context.language orelse "text";

        return try std.fmt.allocPrint(self.allocator, "{{\"prompt\":\"{s}\",\"language\":\"{s}\",\"stream\":true,\"max_tokens\":150}}", .{ prompt, language });
    }

    // Enhanced AI Methods with concurrent support
    pub fn parallelChat(self: *Self, message: []const u8, provider_list: []const api.ApiProvider) ![]const u8 {
        if (self.concurrent_ai) |*concurrent_ai| {
            const messages = [_]api.ChatMessage{
                .{ .role = "user", .content = message },
            };
            return try concurrent_ai.parallelChat(messages, self.current_model, provider_list);
        } else {
            // Fallback to regular chat
            const messages = [_]api.ChatMessage{
                .{ .role = "user", .content = message },
            };
            const message_content = messages[0].content;
            return try self.chat(message_content);
        }
    }

    pub fn parallelAnalysis(self: *Self, file_path: []const u8, analysis_type: api.AnalysisType) !api.AnalysisResponse {
        const file_contents = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| {
            std.log.err("Failed to read file {s}: {}", .{ file_path, err });
            return err;
        };
        defer self.allocator.free(file_contents);

        // Cache file context if not already cached
        try self.context_cache.cacheContext(file_path, file_contents);

        const project_context = api.ProjectContext{
            .project_path = std.fs.cwd().realpathAlloc(self.allocator, ".") catch null,
            .git_info = null,
            .dependencies = null,
            .framework = null,
        };

        if (self.concurrent_ai) |*concurrent_ai| {
            const providers_to_try = [_]api.ApiProvider{ .claude, .openai };
            return try concurrent_ai.parallelAnalysis(file_contents, analysis_type, project_context, &providers_to_try);
        } else {
            // Fallback to regular analysis
            return try self.analyzeCode(file_contents, analysis_type, project_context);
        }
    }

    pub fn intelligentCodeCompletion(self: *Self, code: []const u8, file_path: []const u8) ![]const u8 {
        // Get cached context for better completion
        const cached_context = self.context_cache.getContext(file_path);

        var code_context = api.CodeContext{
            .file_path = file_path,
            .language = null,
            .cursor_position = null,
            .surrounding_code = null,
        };

        if (cached_context) |ctx| {
            code_context.language = ctx.language;
        }

        return try self.completeCode(code, code_context);
    }

    pub fn analyzeProjectStructure(self: *Self, project_path: []const u8) !void {
        try self.context_cache.analyzeProject(project_path);
    }

    pub fn getCacheStats(self: *const Self) context.ProjectContextCache.CacheStats {
        return self.context_cache.getCacheStats();
    }

    pub fn getRelatedFiles(self: *Self, file_path: []const u8) ![][]const u8 {
        return try self.context_cache.getRelatedFiles(file_path, self.allocator);
    }

    // Arch Linux system integration methods
    pub fn getSystemInfo(self: *Self) !?system.SystemInfo {
        if (self.arch_system) |*arch| {
            return try arch.getSystemInfo();
        }
        return null;
    }

    pub fn checkSystemUpdates(self: *Self) ![]system.PackageUpdate {
        if (self.arch_system) |*arch| {
            return try arch.checkUpdates();
        }
        return &[_]system.PackageUpdate{};
    }

    pub fn createSystemSnapshot(self: *Self, name: []const u8) !void {
        if (self.arch_system) |*arch| {
            try arch.createSnapshot(name);
        } else {
            return error.ArchSystemNotAvailable;
        }
    }

    pub fn listSystemSnapshots(self: *Self) ![][]const u8 {
        if (self.arch_system) |*arch| {
            return try arch.listSnapshots();
        }
        return &[_][]const u8{};
    }

    pub fn runSystemMaintenance(self: *Self, options: system.MaintenanceOptions) !void {
        if (self.arch_system) |*arch| {
            try arch.runMaintenance(options);
        } else {
            return error.ArchSystemNotAvailable;
        }
    }

    pub fn getConcurrentStats(self: *const Self) concurrent.ConcurrentRequestHandler.RequestStats {
        if (self.concurrent_ai) |*concurrent_ai| {
            return concurrent_ai.getStats();
        }
        // Return empty stats if concurrent AI is not available
        return concurrent.ConcurrentRequestHandler.RequestStats{
            .total_requests = 0,
            .active_requests = 0,
            .completed_requests = 0,
            .failed_requests = 0,
            .cancelled_requests = 0,
            .average_completion_time_ms = 0,
        };
    }

    pub fn cleanupConcurrentTasks(self: *Self) !void {
        if (self.concurrent_ai) |*concurrent_ai| {
            try concurrent_ai.cleanup();
        }
    }

    // WASM preparation methods
    pub fn prepareForWASM(self: *Self) !void {
        // Prepare the system for WASM compilation
        std.log.info("Preparing ZEKE for WASM compilation...", .{});

        // Ensure all allocations are properly tracked
        try self.context_cache.clearCache();

        // Optimize provider selection for WASM constraints
        const wasm_friendly_providers = [_]api.ApiProvider{.ollama};
        const best_provider = try self.provider_manager.selectBestProvider(.chat_completion);

        if (best_provider) |provider| {
            var is_wasm_friendly = false;
            for (wasm_friendly_providers) |wasm_provider| {
                if (provider == wasm_provider) {
                    is_wasm_friendly = true;
                    break;
                }
            }

            if (!is_wasm_friendly) {
                std.log.warn("Current provider {} may not be optimal for WASM", .{provider});
                // Switch to a more WASM-friendly provider
                try self.switchToProvider(.ollama);
            }
        }

        std.log.info("WASM preparation complete", .{});
    }

    // Enhanced terminal/CLI mode
    pub fn launchTUI(self: *Self) !void {
        var tui_app = try tui.TuiApp.init(self.allocator, self);
        defer tui_app.deinit();

        try tui_app.run();
    }
};

pub fn bufferedPrint() !void {
    std.debug.print("⚡ ZEKE - The Zig-Native AI Dev Companion\n", .{});
    std.debug.print("Ready to assist with your coding workflow!\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "zeke initialization" {
    var zeke = try Zeke.init(std.testing.allocator);
    defer zeke.deinit();

    // Verify current_model is set from config (default is "gpt-4" but may be overridden)
    try std.testing.expect(zeke.current_model.len > 0);
}
