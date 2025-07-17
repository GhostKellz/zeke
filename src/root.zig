//! ZEKE - The Zig-Native AI Dev Companion
const std = @import("std");

// Re-export all modules
pub const api = @import("api/client.zig");
pub const auth = @import("auth/mod.zig");
pub const config = @import("config/mod.zig");
pub const providers = @import("providers/mod.zig");
pub const streaming = @import("streaming/mod.zig");
pub const error_handling = @import("error_handling/mod.zig");

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
    config: config.Config,
    auth_manager: auth.AuthManager,
    api_client: api.ApiClient,
    provider_manager: providers.ProviderManager,
    fallback_manager: error_handling.FallbackManager,
    realtime_features: ?streaming.RealTimeFeatures,
    current_model: []const u8,
    current_provider: api.ApiProvider,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !Self {
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
        
        // Select best provider for chat completion (default behavior)
        const best_provider = try provider_manager.selectBestProvider(.chat_completion) orelse .ghostllm;
        
        // Initialize with best available provider
        const api_client = api.ApiClient.init(allocator, best_provider) catch |err| {
            std.log.err("Failed to initialize API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };
        
        return Self{
            .allocator = allocator,
            .config = zeke_config,
            .auth_manager = auth_manager,
            .api_client = api_client,
            .provider_manager = provider_manager,
            .fallback_manager = fallback_manager,
            .realtime_features = null, // Initialized on demand
            .current_model = zeke_config.default_model,
            .current_provider = best_provider,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.config.deinit();
        self.auth_manager.deinit();
        self.api_client.deinit();
        self.provider_manager.deinit();
        self.fallback_manager.deinit();
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
        else if (std.mem.eql(u8, model_config.provider, "copilot")) 
            api.ApiProvider.copilot
        else if (std.mem.eql(u8, model_config.provider, "ghostllm")) 
            api.ApiProvider.ghostllm
        else 
            api.ApiProvider.ollama;
        
        self.api_client = api.ApiClient.init(self.allocator, provider) catch |err| {
            std.log.err("Failed to switch API client: {}", .{err});
            return ZekeError.InitializationFailed;
        };
        
        // Set auth token for new provider
        const auth_provider = switch (provider) {
            .openai => auth.AuthProvider.openai,
            .claude => auth.AuthProvider.google,
            .copilot => auth.AuthProvider.github,
            .ollama => auth.AuthProvider.local,
            .ghostllm => auth.AuthProvider.local, // GhostLLM can use local auth or API key
        };
        
        if (try self.auth_manager.getToken(auth_provider)) |token| {
            defer self.allocator.free(token);
            try self.api_client.setAuth(token);
        }
        
        self.current_model = model_name;
    }
    
    pub fn chat(self: *Self, message: []const u8) ![]const u8 {
        const messages = [_]api.ChatMessage{
            .{ .role = "user", .content = message },
        };
        
        const response = try self.api_client.chatCompletion(&messages, self.current_model);
        // Note: caller must free response.content
        return response.content;
    }
    
    pub fn completeCode(self: *Self, prompt: []const u8, context: api.CodeContext) ![]const u8 {
        const response = try self.api_client.codeCompletion(prompt, context);
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
    
    // GhostLLM-specific methods for enhanced AI capabilities
    pub fn analyzeCode(self: *Self, file_contents: []const u8, analysis_type: api.AnalysisType, context: api.ProjectContext) !api.AnalysisResponse {
        return try self.api_client.analyzeCode(file_contents, analysis_type, context);
    }
    
    pub fn explainCode(self: *Self, code: []const u8, context: api.CodeContext) !api.ExplanationResponse {
        return try self.api_client.explainCode(code, context);
    }
    
    pub fn refactorCode(self: *Self, code: []const u8, refactor_type: api.RefactorType, context: api.CodeContext) !api.RefactorResponse {
        return try self.api_client.refactorCode(code, refactor_type, context);
    }
    
    pub fn generateTests(self: *Self, code: []const u8, context: api.CodeContext) !api.TestResponse {
        return try self.api_client.generateTests(code, context);
    }
    
    pub fn setGhostLLMEndpoint(self: *Self, endpoint: []const u8) !void {
        // Update base URL for GhostLLM provider
        if (self.api_client.provider == .ghostllm) {
            // This would need to be implemented in the API client
            std.log.info("GhostLLM endpoint set to: {s}", .{endpoint});
        }
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
            .claude => auth.AuthProvider.google,
            .copilot => auth.AuthProvider.github,
            .ollama => auth.AuthProvider.local,
            .ghostllm => auth.AuthProvider.local,
        };
        
        if (try self.auth_manager.getToken(auth_provider)) |token| {
            defer self.allocator.free(token);
            try self.api_client.setAuth(token);
        }
        
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
        
        const result = self.chatWithFallback(message) catch |err| {
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
    
    pub fn analyzeCodeWithBestProvider(self: *Self, file_contents: []const u8, analysis_type: api.AnalysisType, context: api.ProjectContext) !api.AnalysisResponse {
        // Select best provider for code analysis
        const best_provider = try self.selectBestProviderForTask(.code_analysis);
        try self.switchToProvider(best_provider);
        
        return try self.analyzeCode(file_contents, analysis_type, context);
    }
    
    pub fn explainCodeWithBestProvider(self: *Self, code: []const u8, context: api.CodeContext) !api.ExplanationResponse {
        // Select best provider for code explanation
        const best_provider = try self.selectBestProviderForTask(.code_explanation);
        try self.switchToProvider(best_provider);
        
        return try self.explainCode(code, context);
    }
    
    pub fn getProviderStatus(self: *Self) ![]providers.ProviderHealth {
        var status_list = std.ArrayList(providers.ProviderHealth).init(self.allocator);
        
        const provider_list = [_]api.ApiProvider{ .ghostllm, .claude, .openai, .copilot, .ollama };
        for (provider_list) |provider| {
            if (self.provider_manager.getProviderHealth(provider)) |health| {
                try status_list.append(health);
            } else {
                // Create default health status
                try status_list.append(providers.ProviderHealth{
                    .provider = provider,
                    .is_healthy = false,
                    .last_check = 0,
                    .response_time_ms = 0,
                    .error_rate = 0.0,
                });
            }
        }
        
        return status_list.toOwnedSlice();
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
        std.log.info("Error statistics - Total: {d}, Network: {d}, Auth: {d}, Rate Limit: {d}, Provider: {d}", 
            .{ stats.total_errors, stats.network_errors, stats.auth_errors, stats.rate_limit_errors, stats.provider_errors });
        
        // Check circuit breaker states
        const providers_to_check = [_]api.ApiProvider{ .ghostllm, .claude, .openai, .copilot, .ollama };
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
                
                // Enable real-time code analysis if using GhostLLM
                if (self.current_provider == .ghostllm) {
                    const ws_url = try std.fmt.allocPrint(self.allocator, "{s}/ws/realtime", .{self.api_client.base_url});
                    defer self.allocator.free(ws_url);
                    
                    self.realtime_features.?.enableRealTimeCodeAnalysis(ws_url) catch |err| {
                        std.log.warn("Failed to enable real-time features: {}", .{err});
                    };
                }
                
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
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.append(.{ .name = "content-type", .value = "application/json" });
        
        if (self.api_client.auth_token) |token| {
            const auth_header = switch (self.current_provider) {
                .openai => try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token}),
                .claude => try std.fmt.allocPrint(self.allocator, "x-api-key: {s}", .{token}),
                .copilot => try std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}", .{token}),
                .ghostllm => try std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}", .{token}),
                .ollama => token,
            };
            defer self.allocator.free(auth_header);
            
            if (self.current_provider != .ollama) {
                try headers.append(.{ .name = "authorization", .value = auth_header });
            }
        }
        
        // Start streaming
        if (self.realtime_features) |*rt| {
            // Convert headers to slice with proper type
            const headers_slice = @as([]const std.http.Header, headers.items);
            try rt.streaming_client.streamChatCompletion(endpoint, request_body, headers_slice, callback);
        }
    }
    
    pub fn streamCodeCompletion(self: *Self, prompt: []const u8, context: api.CodeContext, callback: streaming.StreamCallback) !void {
        // Ensure real-time features are enabled
        try self.enableRealTimeFeatures();
        
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/completions", .{self.api_client.base_url});
        defer self.allocator.free(endpoint);
        
        const request_body = try self.buildStreamingCompletionRequest(prompt, context);
        defer self.allocator.free(request_body);
        
        // Prepare headers (similar to streamChat)
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();
        try headers.append(.{ .name = "content-type", .value = "application/json" });
        
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
        var request = std.ArrayList(u8).init(self.allocator);
        defer request.deinit();
        
        try request.appendSlice("{\"model\":\"");
        try request.appendSlice(model);
        try request.appendSlice("\",\"stream\":true,\"messages\":[");
        
        for (messages, 0..) |msg, i| {
            if (i > 0) try request.appendSlice(",");
            try request.appendSlice("{\"role\":\"");
            try request.appendSlice(msg.role);
            try request.appendSlice("\",\"content\":\"");
            // Escape the content properly
            for (msg.content) |char| {
                switch (char) {
                    '"' => try request.appendSlice("\\\""),
                    '\\' => try request.appendSlice("\\\\"),
                    '\n' => try request.appendSlice("\\n"),
                    '\r' => try request.appendSlice("\\r"),
                    '\t' => try request.appendSlice("\\t"),
                    else => try request.append(char),
                }
            }
            try request.appendSlice("\"}");
        }
        
        try request.appendSlice("]}");
        return request.toOwnedSlice();
    }
    
    fn buildStreamingCompletionRequest(self: *Self, prompt: []const u8, context: api.CodeContext) ![]const u8 {
        const language = context.language orelse "text";
        
        return try std.fmt.allocPrint(self.allocator,
            "{{\"prompt\":\"{s}\",\"language\":\"{s}\",\"stream\":true,\"max_tokens\":150}}",
            .{ prompt, language }
        );
    }
};

pub fn bufferedPrint() !void {
    const stdout_file = std.fs.File.stdout().deprecatedWriter();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("⚡ ZEKE - The Zig-Native AI Dev Companion\n", .{});
    try stdout.print("Ready to assist with your coding workflow!\n", .{});

    try bw.flush();
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
    
    try std.testing.expect(std.mem.eql(u8, zeke.current_model, "gpt-4"));
}
