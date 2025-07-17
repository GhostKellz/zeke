const std = @import("std");
const api = @import("../api/client.zig");
const providers = @import("../providers/mod.zig");

pub const ZekeErrorType = enum {
    network_error,
    authentication_error,
    rate_limit_error,
    provider_unavailable,
    invalid_response,
    timeout_error,
    configuration_error,
    unknown_error,
};

pub const ZekeError = struct {
    error_type: ZekeErrorType,
    message: []const u8,
    provider: ?api.ApiProvider,
    timestamp: i64,
    retry_after_ms: ?u64,
    
    pub fn init(allocator: std.mem.Allocator, error_type: ZekeErrorType, message: []const u8, provider: ?api.ApiProvider) !ZekeError {
        return ZekeError{
            .error_type = error_type,
            .message = try allocator.dupe(u8, message),
            .provider = provider,
            .timestamp = std.time.timestamp(),
            .retry_after_ms = null,
        };
    }
    
    pub fn deinit(self: *ZekeError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
    
    pub fn shouldRetry(self: *const ZekeError) bool {
        return switch (self.error_type) {
            .network_error, .timeout_error, .provider_unavailable => true,
            .rate_limit_error => true,
            .authentication_error, .configuration_error => false,
            .invalid_response, .unknown_error => false,
        };
    }
    
    pub fn getRetryDelayMs(self: *const ZekeError) u64 {
        if (self.retry_after_ms) |delay| {
            return delay;
        }
        
        return switch (self.error_type) {
            .network_error => 1000,
            .timeout_error => 2000,
            .provider_unavailable => 5000,
            .rate_limit_error => 60000, // 1 minute
            else => 0,
        };
    }
};

pub const RetryPolicy = struct {
    max_retries: u32,
    base_delay_ms: u64,
    max_delay_ms: u64,
    exponential_backoff: bool,
    jitter: bool,
    
    pub fn default() RetryPolicy {
        return RetryPolicy{
            .max_retries = 3,
            .base_delay_ms = 1000,
            .max_delay_ms = 30000,
            .exponential_backoff = true,
            .jitter = true,
        };
    }
    
    pub fn calculateDelay(self: *const RetryPolicy, attempt: u32, error_info: ?*const ZekeError) u64 {
        var delay = self.base_delay_ms;
        
        // Use error-specific retry delay if available
        if (error_info) |err| {
            const error_delay = err.getRetryDelayMs();
            if (error_delay > 0) {
                delay = error_delay;
            }
        }
        
        // Apply exponential backoff
        if (self.exponential_backoff) {
            delay = delay << @intCast(attempt);
        }
        
        // Cap at max delay
        if (delay > self.max_delay_ms) {
            delay = self.max_delay_ms;
        }
        
        // Add jitter to prevent thundering herd
        if (self.jitter) {
            var random = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
            const jitter_range = delay / 4; // ±25% jitter
            const jitter_offset = random.random().uintLessThan(u64, jitter_range * 2);
            delay = delay - jitter_range + jitter_offset;
        }
        
        return delay;
    }
};

pub const CircuitBreaker = struct {
    allocator: std.mem.Allocator,
    provider: api.ApiProvider,
    failure_threshold: u32,
    timeout_ms: u64,
    failure_count: u32,
    last_failure_time: i64,
    state: CircuitBreakerState,
    
    const CircuitBreakerState = enum {
        closed,   // Normal operation
        open,     // Failing, rejecting requests
        half_open, // Testing if service is back
    };
    
    pub fn init(allocator: std.mem.Allocator, provider: api.ApiProvider) CircuitBreaker {
        return CircuitBreaker{
            .allocator = allocator,
            .provider = provider,
            .failure_threshold = 5,
            .timeout_ms = 60000, // 1 minute
            .failure_count = 0,
            .last_failure_time = 0,
            .state = .closed,
        };
    }
    
    pub fn canRequest(self: *CircuitBreaker) bool {
        const now = std.time.timestamp();
        
        switch (self.state) {
            .closed => return true,
            .open => {
                if (now - self.last_failure_time > @as(i64, @intCast(self.timeout_ms / 1000))) {
                    self.state = .half_open;
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }
    
    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.failure_count = 0;
        self.state = .closed;
    }
    
    pub fn recordFailure(self: *CircuitBreaker) void {
        self.failure_count += 1;
        self.last_failure_time = std.time.timestamp();
        
        if (self.failure_count >= self.failure_threshold) {
            self.state = .open;
        }
    }
    
    pub fn getState(self: *const CircuitBreaker) CircuitBreakerState {
        return self.state;
    }
};

pub const FallbackManager = struct {
    allocator: std.mem.Allocator,
    circuit_breakers: std.AutoHashMap(api.ApiProvider, CircuitBreaker),
    error_history: std.ArrayList(ZekeError),
    max_error_history: u32,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .circuit_breakers = std.AutoHashMap(api.ApiProvider, CircuitBreaker).init(allocator),
            .error_history = std.ArrayList(ZekeError).init(allocator),
            .max_error_history = 100,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.error_history.items) |*error_item| {
            error_item.deinit(self.allocator);
        }
        self.error_history.deinit();
        self.circuit_breakers.deinit();
    }
    
    pub fn getCircuitBreaker(self: *Self, provider: api.ApiProvider) !*CircuitBreaker {
        if (!self.circuit_breakers.contains(provider)) {
            try self.circuit_breakers.put(provider, CircuitBreaker.init(self.allocator, provider));
        }
        
        return self.circuit_breakers.getPtr(provider) orelse return error.CircuitBreakerNotFound;
    }
    
    pub fn canUseProvider(self: *Self, provider: api.ApiProvider) !bool {
        const breaker = try self.getCircuitBreaker(provider);
        return breaker.canRequest();
    }
    
    pub fn recordSuccess(self: *Self, provider: api.ApiProvider) !void {
        const breaker = try self.getCircuitBreaker(provider);
        breaker.recordSuccess();
    }
    
    pub fn recordFailure(self: *Self, provider: api.ApiProvider, error_type: ZekeErrorType, message: []const u8) !void {
        const breaker = try self.getCircuitBreaker(provider);
        breaker.recordFailure();
        
        // Record error in history
        const error_info = try ZekeError.init(self.allocator, error_type, message, provider);
        try self.error_history.append(error_info);
        
        // Cleanup old errors if history is too large
        if (self.error_history.items.len > self.max_error_history) {
            var old_error = self.error_history.orderedRemove(0);
            old_error.deinit(self.allocator);
        }
    }
    
    pub fn selectFallbackProviders(self: *Self, _: providers.ProviderCapability, preferred_providers: []const api.ApiProvider) ![]api.ApiProvider {
        var available_providers = std.ArrayList(api.ApiProvider).init(self.allocator);
        
        for (preferred_providers) |provider| {
            if (try self.canUseProvider(provider)) {
                try available_providers.append(provider);
            }
        }
        
        return available_providers.toOwnedSlice();
    }
    
    pub fn getErrorStats(self: *const Self) ErrorStats {
        var stats = ErrorStats{
            .total_errors = 0,
            .network_errors = 0,
            .auth_errors = 0,
            .rate_limit_errors = 0,
            .provider_errors = 0,
        };
        
        for (self.error_history.items) |error_item| {
            stats.total_errors += 1;
            
            switch (error_item.error_type) {
                .network_error, .timeout_error => stats.network_errors += 1,
                .authentication_error => stats.auth_errors += 1,
                .rate_limit_error => stats.rate_limit_errors += 1,
                .provider_unavailable => stats.provider_errors += 1,
                else => {},
            }
        }
        
        return stats;
    }
    
    pub fn getProviderErrors(self: *const Self, provider: api.ApiProvider) u32 {
        var count: u32 = 0;
        
        for (self.error_history.items) |error_item| {
            if (error_item.provider == provider) {
                count += 1;
            }
        }
        
        return count;
    }
};

pub const ErrorStats = struct {
    total_errors: u32,
    network_errors: u32,
    auth_errors: u32,
    rate_limit_errors: u32,
    provider_errors: u32,
};

pub const RetryableOperation = struct {
    allocator: std.mem.Allocator,
    retry_policy: RetryPolicy,
    fallback_manager: *FallbackManager,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, fallback_manager: *FallbackManager) Self {
        return Self{
            .allocator = allocator,
            .retry_policy = RetryPolicy.default(),
            .fallback_manager = fallback_manager,
        };
    }
    
    pub fn execute(
        self: *Self,
        comptime T: type,
        provider: api.ApiProvider,
        operation: *const fn () anyerror!T,
        fallback_providers: []const api.ApiProvider,
    ) !T {
        // Try primary provider with retries
        if (try self.fallback_manager.canUseProvider(provider)) {
            if (try self.executeWithRetry(T, provider, operation)) |result| {
                try self.fallback_manager.recordSuccess(provider);
                return result;
            }
        }
        
        // Try fallback providers
        for (fallback_providers) |fallback_provider| {
            if (try self.fallback_manager.canUseProvider(fallback_provider)) {
                if (try self.executeWithRetry(T, fallback_provider, operation)) |result| {
                    try self.fallback_manager.recordSuccess(fallback_provider);
                    return result;
                }
            }
        }
        
        return error.AllProvidersFailed;
    }
    
    fn executeWithRetry(
        self: *Self,
        comptime T: type,
        provider: api.ApiProvider,
        operation: *const fn () anyerror!T,
    ) !?T {
        var attempt: u32 = 0;
        
        while (attempt <= self.retry_policy.max_retries) {
            const result = operation() catch |err| {
                attempt += 1;
                
                const error_type = self.classifyError(err);
                const error_message = try std.fmt.allocPrint(self.allocator, "Operation failed: {s}", .{@errorName(err)});
                defer self.allocator.free(error_message);
                
                try self.fallback_manager.recordFailure(provider, error_type, error_message);
                
                const error_info = try ZekeError.init(self.allocator, error_type, error_message, provider);
                defer error_info.deinit(self.allocator);
                
                if (!error_info.shouldRetry() or attempt > self.retry_policy.max_retries) {
                    std.log.err("Operation failed permanently for provider {s}: {s}", .{ @tagName(provider), @errorName(err) });
                    return null;
                }
                
                const delay_ms = self.retry_policy.calculateDelay(attempt - 1, &error_info);
                std.log.warn("Retrying operation for provider {s} in {d}ms (attempt {d}/{d})", .{ @tagName(provider), delay_ms, attempt, self.retry_policy.max_retries });
                
                std.time.sleep(delay_ms * std.time.ns_per_ms);
                continue;
            };
            
            return result;
        }
        
        return null;
    }
    
    fn classifyError(self: *Self, err: anyerror) ZekeErrorType {
        _ = self;
        
        return switch (err) {
            error.ConnectionRefused, error.NetworkUnreachable, error.HostNotFound => .network_error,
            error.Timeout, error.TimedOut => .timeout_error,
            error.Unauthorized, error.Forbidden => .authentication_error,
            error.TooManyRequests, error.RateLimitExceeded => .rate_limit_error,
            error.ServiceUnavailable, error.BadGateway => .provider_unavailable,
            error.InvalidResponse, error.ParseError => .invalid_response,
            else => .unknown_error,
        };
    }
};

// Helper functions for graceful degradation
pub fn createGracefulResponse(allocator: std.mem.Allocator, operation_type: []const u8, provider: api.ApiProvider) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        "🔄 Service temporarily unavailable\n" ++
        "Operation: {s}\n" ++
        "Provider: {s}\n" ++
        "Status: Attempting fallback providers...\n" ++
        "Please try again in a few moments.",
        .{ operation_type, @tagName(provider) }
    );
}

pub fn createOfflineResponse(allocator: std.mem.Allocator, operation_type: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        "📴 Offline Mode\n" ++
        "Operation: {s}\n" ++
        "All AI providers are currently unavailable.\n" ++
        "Cached responses and local features remain available.\n" ++
        "Check your network connection and try again later.",
        .{operation_type}
    );
}

// Enhanced timeout handling with configurable timeouts
pub const TimeoutManager = struct {
    allocator: std.mem.Allocator,
    default_timeout_ms: u64,
    provider_timeouts: std.AutoHashMap(api.ApiProvider, u64),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .default_timeout_ms = 30000, // 30 seconds
            .provider_timeouts = std.AutoHashMap(api.ApiProvider, u64).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.provider_timeouts.deinit();
    }
    
    pub fn setProviderTimeout(self: *Self, provider: api.ApiProvider, timeout_ms: u64) !void {
        try self.provider_timeouts.put(provider, timeout_ms);
    }
    
    pub fn getTimeout(self: *const Self, provider: api.ApiProvider) u64 {
        if (self.provider_timeouts.get(provider)) |timeout| {
            return timeout;
        }
        
        // Provider-specific defaults
        return switch (provider) {
            .ghostllm => 20000, // 20 seconds - custom provider might be slower
            .openai => 30000,   // 30 seconds
            .claude => 35000,   // 35 seconds - Claude can be slower
            .copilot => 25000,  // 25 seconds
            .ollama => 60000,   // 60 seconds - local models can be slow
        };
    }
};

// Connection pool for managing HTTP connections
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    max_connections: u32,
    idle_timeout_ms: u64,
    connections: std.AutoHashMap(api.ApiProvider, std.ArrayList(*std.http.Client)),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .max_connections = 10,
            .idle_timeout_ms = 300000, // 5 minutes
            .connections = std.AutoHashMap(api.ApiProvider, std.ArrayList(*std.http.Client)).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            for (entry.value_ptr.items) |client| {
                client.deinit();
                self.allocator.destroy(client);
            }
            entry.value_ptr.deinit();
        }
        self.connections.deinit();
    }
    
    pub fn getConnection(self: *Self, provider: api.ApiProvider) !*std.http.Client {
        if (self.connections.get(provider)) |*pool| {
            if (pool.items.len > 0) {
                return pool.swapRemove(pool.items.len - 1);
            }
        }
        
        // Create new connection
        const client = try self.allocator.create(std.http.Client);
        client.* = std.http.Client{ .allocator = self.allocator };
        return client;
    }
    
    pub fn returnConnection(self: *Self, provider: api.ApiProvider, client: *std.http.Client) !void {
        if (!self.connections.contains(provider)) {
            try self.connections.put(provider, std.ArrayList(*std.http.Client).init(self.allocator));
        }
        
        var pool = self.connections.getPtr(provider).?;
        if (pool.items.len < self.max_connections) {
            try pool.append(client);
        } else {
            // Pool is full, close the connection
            client.deinit();
            self.allocator.destroy(client);
        }
    }
};

// Health monitoring for providers
pub const HealthMonitor = struct {
    allocator: std.mem.Allocator,
    provider_health: std.AutoHashMap(api.ApiProvider, ProviderHealth),
    check_interval_ms: u64,
    last_check_time: i64,
    
    const ProviderHealth = struct {
        is_healthy: bool,
        last_success: i64,
        last_failure: i64,
        consecutive_failures: u32,
        avg_response_time_ms: u64,
        total_requests: u64,
        successful_requests: u64,
    };
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .provider_health = std.AutoHashMap(api.ApiProvider, ProviderHealth).init(allocator),
            .check_interval_ms = 60000, // 1 minute
            .last_check_time = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.provider_health.deinit();
    }
    
    pub fn recordSuccess(self: *Self, provider: api.ApiProvider, response_time_ms: u64) !void {
        const now = std.time.timestamp();
        
        if (self.provider_health.getPtr(provider)) |health| {
            health.is_healthy = true;
            health.last_success = now;
            health.consecutive_failures = 0;
            health.total_requests += 1;
            health.successful_requests += 1;
            
            // Update average response time
            const total_time = health.avg_response_time_ms * (health.total_requests - 1);
            health.avg_response_time_ms = (total_time + response_time_ms) / health.total_requests;
        } else {
            try self.provider_health.put(provider, ProviderHealth{
                .is_healthy = true,
                .last_success = now,
                .last_failure = 0,
                .consecutive_failures = 0,
                .avg_response_time_ms = response_time_ms,
                .total_requests = 1,
                .successful_requests = 1,
            });
        }
    }
    
    pub fn recordFailure(self: *Self, provider: api.ApiProvider) !void {
        const now = std.time.timestamp();
        
        if (self.provider_health.getPtr(provider)) |health| {
            health.last_failure = now;
            health.consecutive_failures += 1;
            health.total_requests += 1;
            
            // Mark as unhealthy after 3 consecutive failures
            if (health.consecutive_failures >= 3) {
                health.is_healthy = false;
            }
        } else {
            try self.provider_health.put(provider, ProviderHealth{
                .is_healthy = false,
                .last_success = 0,
                .last_failure = now,
                .consecutive_failures = 1,
                .avg_response_time_ms = 0,
                .total_requests = 1,
                .successful_requests = 0,
            });
        }
    }
    
    pub fn isHealthy(self: *const Self, provider: api.ApiProvider) bool {
        if (self.provider_health.get(provider)) |health| {
            return health.is_healthy;
        }
        return true; // Assume healthy if no data
    }
    
    pub fn getHealthStats(self: *const Self, provider: api.ApiProvider) ?ProviderHealth {
        return self.provider_health.get(provider);
    }
    
    pub fn performHealthCheck(self: *Self) !void {
        const now = std.time.timestamp();
        
        if (now - self.last_check_time < @as(i64, @intCast(self.check_interval_ms / 1000))) {
            return; // Too soon for next check
        }
        
        self.last_check_time = now;
        
        // Reset health status for providers that haven't been used recently
        var iterator = self.provider_health.iterator();
        while (iterator.next()) |entry| {
            const health = entry.value_ptr;
            const time_since_last_activity = now - @max(health.last_success, health.last_failure);
            
            // Reset status if no activity for 5 minutes
            if (time_since_last_activity > 300) {
                health.is_healthy = true;
                health.consecutive_failures = 0;
            }
        }
    }
};

// Comprehensive fallback chain manager
pub const FallbackChain = struct {
    allocator: std.mem.Allocator,
    primary_provider: api.ApiProvider,
    fallback_providers: []api.ApiProvider,
    timeout_manager: TimeoutManager,
    health_monitor: HealthMonitor,
    connection_pool: ConnectionPool,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, primary: api.ApiProvider, fallbacks: []const api.ApiProvider) !Self {
        return Self{
            .allocator = allocator,
            .primary_provider = primary,
            .fallback_providers = try allocator.dupe(api.ApiProvider, fallbacks),
            .timeout_manager = TimeoutManager.init(allocator),
            .health_monitor = HealthMonitor.init(allocator),
            .connection_pool = ConnectionPool.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.fallback_providers);
        self.timeout_manager.deinit();
        self.health_monitor.deinit();
        self.connection_pool.deinit();
    }
    
    pub fn executeWithFallback(
        self: *Self,
        comptime T: type,
        operation: *const fn (api.ApiProvider, *std.http.Client) anyerror!T,
    ) !T {
        const start_time = std.time.milliTimestamp();
        
        // Try primary provider first
        if (self.health_monitor.isHealthy(self.primary_provider)) {
            if (try self.tryProvider(T, self.primary_provider, operation, start_time)) |result| {
                return result;
            }
        }
        
        // Try fallback providers
        for (self.fallback_providers) |provider| {
            if (self.health_monitor.isHealthy(provider)) {
                if (try self.tryProvider(T, provider, operation, start_time)) |result| {
                    return result;
                }
            }
        }
        
        // All providers failed
        std.log.err("All providers failed for operation", .{});
        return error.AllProvidersFailed;
    }
    
    fn tryProvider(
        self: *Self,
        comptime T: type,
        provider: api.ApiProvider,
        operation: *const fn (api.ApiProvider, *std.http.Client) anyerror!T,
        start_time: i64,
    ) !?T {
        const client = try self.connection_pool.getConnection(provider);
        defer self.connection_pool.returnConnection(provider, client) catch {};
        
        const result = operation(provider, client) catch |err| {
            std.log.warn("Provider {s} failed: {s}", .{ @tagName(provider), @errorName(err) });
            try self.health_monitor.recordFailure(provider);
            return null;
        };
        
        const end_time = std.time.milliTimestamp();
        const response_time: u64 = @intCast(end_time - start_time);
        
        try self.health_monitor.recordSuccess(provider, response_time);
        return result;
    }
    
    pub fn getProviderStats(self: *const Self, provider: api.ApiProvider) ?@TypeOf(self.health_monitor).ProviderHealth {
        return self.health_monitor.getHealthStats(provider);
    }
    
    pub fn performHealthCheck(self: *Self) !void {
        try self.health_monitor.performHealthCheck();
    }
};