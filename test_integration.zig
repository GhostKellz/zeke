const std = @import("std");
const zeke = @import("src/root.zig");

test "integration: api client initialization" {
    var client = zeke.api.ApiClient.init(std.testing.allocator, .openai) catch |err| {
        std.log.err("Failed to initialize API client: {}", .{err});
        return err;
    };
    defer client.deinit();
    
    try std.testing.expect(client.provider == .openai);
    try std.testing.expect(client.http_client != null);
}

test "integration: authentication token storage" {
    var auth_manager = zeke.auth.AuthManager.init(std.testing.allocator) catch |err| {
        std.log.err("Failed to initialize auth manager: {}", .{err});
        return err;
    };
    defer auth_manager.deinit();
    
    // Test token storage
    try auth_manager.setOpenAIToken("test_token_123");
    
    const token = try auth_manager.getToken(.openai);
    try std.testing.expect(token != null);
    defer if (token) |t| std.testing.allocator.free(t);
    
    if (token) |t| {
        try std.testing.expect(t.len > 0);
    }
}

test "integration: streaming client initialization" {
    var http_client = std.http.Client{ .allocator = std.testing.allocator };
    defer http_client.deinit();
    
    var streaming_client = zeke.streaming.StreamingClient.init(std.testing.allocator, &http_client);
    defer streaming_client.deinit();
    
    // Test SSE parser
    try std.testing.expect(streaming_client.sse_parser.buffer.items.len == 0);
}

test "integration: websocket handler" {
    var ws_handler = zeke.streaming.WebSocketHandler.init(std.testing.allocator);
    defer ws_handler.deinit();
    
    try std.testing.expect(!ws_handler.isConnected());
    try std.testing.expect(ws_handler.message_queue.items.len == 0);
    
    // Test simulated connection
    try ws_handler.connect("ws://localhost:8081/test");
    try std.testing.expect(ws_handler.isConnected());
    
    // Test message sending
    try ws_handler.sendMessage("test message");
    const received = try ws_handler.receiveMessage();
    try std.testing.expect(received != null);
    if (received) |msg| {
        defer std.testing.allocator.free(msg);
        try std.testing.expect(std.mem.startsWith(u8, msg, "Echo:"));
    }
}

test "integration: error handling circuit breaker" {
    var circuit_breaker = zeke.error_handling.CircuitBreaker.init(std.testing.allocator, .openai);
    
    // Initially closed
    try std.testing.expect(circuit_breaker.getState() == .closed);
    try std.testing.expect(circuit_breaker.canRequest());
    
    // Record multiple failures
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        circuit_breaker.recordFailure();
    }
    
    // Should be open now
    try std.testing.expect(circuit_breaker.getState() == .open);
    try std.testing.expect(!circuit_breaker.canRequest());
    
    // Reset with success
    circuit_breaker.recordSuccess();
    try std.testing.expect(circuit_breaker.getState() == .closed);
    try std.testing.expect(circuit_breaker.canRequest());
}

test "integration: fallback manager" {
    var fallback_manager = zeke.error_handling.FallbackManager.init(std.testing.allocator);
    defer fallback_manager.deinit();
    
    // Test provider availability
    try std.testing.expect(try fallback_manager.canUseProvider(.openai));
    
    // Record failure
    try fallback_manager.recordFailure(.openai, .network_error, "Connection failed");
    
    // Test error stats
    const stats = fallback_manager.getErrorStats();
    try std.testing.expect(stats.total_errors == 1);
    try std.testing.expect(stats.network_errors == 1);
    
    // Test provider-specific error count
    const provider_errors = fallback_manager.getProviderErrors(.openai);
    try std.testing.expect(provider_errors == 1);
}

test "integration: provider health monitoring" {
    var health_monitor = zeke.error_handling.HealthMonitor.init(std.testing.allocator);
    defer health_monitor.deinit();
    
    // Initially healthy
    try std.testing.expect(health_monitor.isHealthy(.openai));
    
    // Record success
    try health_monitor.recordSuccess(.openai, 1500);
    try std.testing.expect(health_monitor.isHealthy(.openai));
    
    // Record failures
    try health_monitor.recordFailure(.openai);
    try health_monitor.recordFailure(.openai);
    try health_monitor.recordFailure(.openai);
    
    // Should be unhealthy after 3 failures
    try std.testing.expect(!health_monitor.isHealthy(.openai));
    
    // Get health stats
    const stats = health_monitor.getHealthStats(.openai);
    try std.testing.expect(stats != null);
    if (stats) |s| {
        try std.testing.expect(s.consecutive_failures == 3);
        try std.testing.expect(s.total_requests == 4);
        try std.testing.expect(s.successful_requests == 1);
    }
}

test "integration: timeout manager" {
    var timeout_manager = zeke.error_handling.TimeoutManager.init(std.testing.allocator);
    defer timeout_manager.deinit();
    
    // Test default timeouts
    try std.testing.expect(timeout_manager.getTimeout(.openai) == 30000);
    try std.testing.expect(timeout_manager.getTimeout(.claude) == 35000);
    try std.testing.expect(timeout_manager.getTimeout(.ollama) == 60000);
    
    // Test custom timeout
    try timeout_manager.setProviderTimeout(.openai, 45000);
    try std.testing.expect(timeout_manager.getTimeout(.openai) == 45000);
}

test "integration: full zeke initialization and chat" {
    var zeke_instance = zeke.Zeke.init(std.testing.allocator) catch |err| {
        std.log.err("Failed to initialize Zeke: {}", .{err});
        return err;
    };
    defer zeke_instance.deinit();
    
    // Test basic properties
    try std.testing.expect(std.mem.eql(u8, zeke_instance.current_model, "gpt-4"));
    try std.testing.expect(zeke_instance.current_provider == .ghostllm);
    
    // Test model switching
    try zeke_instance.setModel("gpt-3.5-turbo");
    try std.testing.expect(std.mem.eql(u8, zeke_instance.current_model, "gpt-3.5-turbo"));
    
    // Test provider status
    const status = try zeke_instance.getProviderStatus();
    defer std.testing.allocator.free(status);
    try std.testing.expect(status.len > 0);
}

test "integration: retry policy" {
    const retry_policy = zeke.error_handling.RetryPolicy.default();
    
    // Test delay calculation
    const delay1 = retry_policy.calculateDelay(0, null);
    const delay2 = retry_policy.calculateDelay(1, null);
    const delay3 = retry_policy.calculateDelay(2, null);
    
    // With exponential backoff, delays should increase
    try std.testing.expect(delay2 > delay1);
    try std.testing.expect(delay3 > delay2);
    
    // But shouldn't exceed max delay
    try std.testing.expect(delay3 <= retry_policy.max_delay_ms);
}

test "integration: progress indicator" {
    var progress = try zeke.streaming.ProgressIndicator.init(std.testing.allocator, "chat_completion");
    defer progress.deinit();
    
    try std.testing.expect(!progress.isComplete());
    
    // Test stage progression
    const stage1 = progress.nextStage();
    try std.testing.expect(stage1 != null);
    
    const stage2 = progress.nextStage();
    try std.testing.expect(stage2 != null);
    
    // Test current stage
    const current = progress.getCurrentStage();
    try std.testing.expect(current != null);
    
    // Test elapsed time
    const elapsed = progress.getElapsedTime();
    try std.testing.expect(elapsed >= 0);
}