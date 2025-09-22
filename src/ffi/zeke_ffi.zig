//! Zeke FFI - C ABI exports for Rust integration
//! This module provides a C-compatible interface for Zeke's core functionality
//! to enable seamless integration with Rust projects like GhostFlow and Jarvis

const std = @import("std");
// Import root with explicit fallback for different Zig versions
const zeke = @import("../root.zig");

// Safe imports with compatibility checks
const ghostllm = if (@hasDecl(zeke, "ghostllm")) zeke.ghostllm else struct {};
const api = if (@hasDecl(zeke, "api")) zeke.api else struct {};
const auth = if (@hasDecl(zeke, "auth")) zeke.auth else struct {};
const config = if (@hasDecl(zeke, "config")) zeke.config else struct {};  
const streaming = if (@hasDecl(zeke, "streaming")) zeke.streaming else struct {};

// C-compatible type definitions
pub const ZekeHandle = opaque {};
pub const ZekeConfigHandle = opaque {};
pub const ZekeAuthHandle = opaque {};
pub const ZekeProviderHandle = opaque {};
pub const ZekeStreamHandle = opaque {};
pub const ZekeGhostLLMHandle = opaque {};

// Error codes for C FFI
pub const ZekeErrorCode = enum(c_int) {
    success = 0,
    initialization_failed = -1,
    authentication_failed = -2,
    config_load_failed = -3,
    network_error = -4,
    invalid_model = -5,
    token_exchange_failed = -6,
    unexpected_response = -7,
    memory_error = -8,
    invalid_parameter = -9,
    provider_unavailable = -10,
    streaming_failed = -11,
};

// Core structures for FFI
pub const ZekeConfig = extern struct {
    base_url: [*:0]const u8,
    api_key: [*:0]const u8,
    provider: c_int, // ApiProvider as integer
    model_name: [*:0]const u8,
    temperature: f32,
    max_tokens: u32,
    stream: bool,
    enable_gpu: bool,
    enable_fallback: bool,
    timeout_ms: u32,
};

pub const ZekeResponse = extern struct {
    content: [*:0]const u8,
    provider_used: c_int,
    tokens_used: u32,
    response_time_ms: u32,
    error_code: ZekeErrorCode,
    error_message: [*:0]const u8,
};

pub const ZekeStreamChunk = extern struct {
    content: [*:0]const u8,
    is_final: bool,
    chunk_index: u32,
    total_chunks: u32,
};

pub const ZekeGpuInfo = extern struct {
    device_name: [*:0]const u8,
    memory_used_mb: u64,
    memory_total_mb: u64,
    utilization_percent: u8,
    temperature_celsius: u8,
    power_watts: u32,
};

pub const ZekeProviderStatus = extern struct {
    provider: c_int,
    is_healthy: bool,
    response_time_ms: u32,
    error_rate: f32,
    requests_per_minute: u32,
};

// Callback types for streaming and async operations
pub const ZekeStreamCallback = ?*const fn(chunk: *const ZekeStreamChunk, user_data: ?*anyopaque) callconv(.C) void;
pub const ZekeAsyncCallback = ?*const fn(response: *const ZekeResponse, user_data: ?*anyopaque) callconv(.C) void;

// ============================================================================
// Core Zeke Instance Management
// ============================================================================

/// Initialize a new Zeke instance with the given configuration
export fn zeke_init(config: *const ZekeConfig) ?*ZekeHandle {
    const allocator = std.heap.c_allocator;
    
    const zeke_config = config.Config{
        .api_base_url = std.mem.span(config.base_url),
        .default_model = std.mem.span(config.model_name),
        .temperature = config.temperature,
        .max_tokens = config.max_tokens,
        .stream = config.stream,
        .timeout_ms = config.timeout_ms,
    };
    
    const zeke_instance = allocator.create(zeke.Zeke) catch return null;
    zeke_instance.* = zeke.Zeke.init(allocator, zeke_config) catch |err| {
        allocator.destroy(zeke_instance);
        return null;
    };
    
    return @ptrCast(zeke_instance);
}

/// Clean up and destroy a Zeke instance
export fn zeke_destroy(handle: *ZekeHandle) void {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    const allocator = zeke_instance.allocator;
    zeke_instance.deinit();
    allocator.destroy(zeke_instance);
}

/// Get the version string of Zeke
export fn zeke_version() [*:0]const u8 {
    return "0.2.0";
}

// ============================================================================
// Chat and Completion API
// ============================================================================

/// Send a chat message and get a response
export fn zeke_chat(
    handle: *ZekeHandle,
    message: [*:0]const u8,
    response_out: *ZekeResponse,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    const allocator = zeke_instance.allocator;
    
    const message_str = std.mem.span(message);
    
    const response = zeke_instance.chat(message_str) catch |err| {
        response_out.* = .{
            .content = "",
            .provider_used = @intFromEnum(zeke_instance.current_provider),
            .tokens_used = 0,
            .response_time_ms = 0,
            .error_code = switch (err) {
                error.NetworkError => .network_error,
                error.AuthenticationFailed => .authentication_failed,
                error.InvalidModel => .invalid_model,
                else => .unexpected_response,
            },
            .error_message = @errorName(err).ptr,
        };
        return response_out.error_code;
    };
    
    // Allocate and copy response string
    const response_cstr = allocator.dupeZ(u8, response) catch {
        allocator.free(response);
        response_out.error_code = .memory_error;
        response_out.error_message = "Memory allocation failed";
        return .memory_error;
    };
    
    response_out.* = .{
        .content = response_cstr.ptr,
        .provider_used = @intFromEnum(zeke_instance.current_provider),
        .tokens_used = 0, // TODO: Get actual token count
        .response_time_ms = 0, // TODO: Measure response time
        .error_code = .success,
        .error_message = "",
    };
    
    allocator.free(response);
    return .success;
}

/// Send a streaming chat message with callback for chunks
export fn zeke_chat_stream(
    handle: *ZekeHandle,
    message: [*:0]const u8,
    callback: ZekeStreamCallback,
    user_data: ?*anyopaque,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    const message_str = std.mem.span(message);
    
    if (callback == null) return .invalid_parameter;
    
    const StreamHandler = struct {
        cb: ZekeStreamCallback,
        data: ?*anyopaque,
        
        fn handleChunk(self: @This(), chunk: streaming.StreamChunk) void {
            if (self.cb) |callback_fn| {
                const ffi_chunk = ZekeStreamChunk{
                    .content = chunk.content.ptr,
                    .is_final = chunk.is_final,
                    .chunk_index = chunk.chunk_index,
                    .total_chunks = chunk.total_chunks,
                };
                callback_fn(&ffi_chunk, self.data);
            }
        }
    };
    
    const handler = StreamHandler{ .cb = callback, .data = user_data };
    
    zeke_instance.streamChat(message_str, handler.handleChunk) catch |err| {
        return switch (err) {
            error.NetworkError => .network_error,
            error.AuthenticationFailed => .authentication_failed,
            error.InvalidModel => .invalid_model,
            else => .streaming_failed,
        };
    };
    
    return .success;
}

/// Free memory allocated for a ZekeResponse
export fn zeke_free_response(response: *ZekeResponse) void {
    if (response.content != null and response.content.len > 0) {
        const allocator = std.heap.c_allocator;
        const content_slice = std.mem.span(response.content);
        allocator.free(content_slice);
        response.content = "";
    }
}

// ============================================================================
// Authentication Management
// ============================================================================

/// Set authentication token for a provider
export fn zeke_set_auth_token(
    handle: *ZekeHandle,
    provider: c_int,
    token: [*:0]const u8,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    const token_str = std.mem.span(token);
    
    const auth_provider = switch (provider) {
        0 => auth.AuthProvider.copilot,
        1 => auth.AuthProvider.claude,
        2 => auth.AuthProvider.openai,
        3 => auth.AuthProvider.ollama,
        4 => auth.AuthProvider.ghostllm,
        else => return .invalid_parameter,
    };
    
    zeke_instance.auth_manager.setToken(auth_provider, token_str) catch |err| {
        return switch (err) {
            error.AuthenticationFailed => .authentication_failed,
            error.NetworkError => .network_error,
            else => .unexpected_response,
        };
    };
    
    return .success;
}

/// Test authentication for a provider
export fn zeke_test_auth(handle: *ZekeHandle, provider: c_int) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    const auth_provider = switch (provider) {
        0 => auth.AuthProvider.copilot,
        1 => auth.AuthProvider.claude,
        2 => auth.AuthProvider.openai,
        3 => auth.AuthProvider.ollama,
        4 => auth.AuthProvider.ghostllm,
        else => return .invalid_parameter,
    };
    
    const is_authenticated = zeke_instance.auth_manager.isAuthenticated(auth_provider) catch false;
    
    return if (is_authenticated) .success else .authentication_failed;
}

// ============================================================================
// Provider Management
// ============================================================================

/// Switch to a different provider
export fn zeke_switch_provider(handle: *ZekeHandle, provider: c_int) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    const api_provider = switch (provider) {
        0 => api.ApiProvider.copilot,
        1 => api.ApiProvider.claude,
        2 => api.ApiProvider.openai,
        3 => api.ApiProvider.ollama,
        4 => api.ApiProvider.ghostllm,
        else => return .invalid_parameter,
    };
    
    zeke_instance.switchToProvider(api_provider) catch |err| {
        return switch (err) {
            error.AuthenticationFailed => .authentication_failed,
            error.NetworkError => .network_error,
            error.InvalidModel => .invalid_model,
            else => .provider_unavailable,
        };
    };
    
    return .success;
}

/// Get status of all providers
export fn zeke_get_provider_status(
    handle: *ZekeHandle,
    status_array: [*]ZekeProviderStatus,
    array_size: usize,
    actual_count: *usize,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    const provider_status = zeke_instance.getProviderStatus() catch |err| {
        return switch (err) {
            error.NetworkError => .network_error,
            else => .unexpected_response,
        };
    };
    defer zeke_instance.allocator.free(provider_status);
    
    const count = @min(provider_status.len, array_size);
    actual_count.* = provider_status.len;
    
    for (0..count) |i| {
        const status = provider_status[i];
        status_array[i] = ZekeProviderStatus{
            .provider = @intFromEnum(status.provider),
            .is_healthy = status.is_healthy,
            .response_time_ms = status.response_time_ms,
            .error_rate = status.error_rate,
            .requests_per_minute = 0, // TODO: Add RPM tracking
        };
    }
    
    return .success;
}

// ============================================================================
// GhostLLM GPU Integration
// ============================================================================

/// Initialize GhostLLM GPU client
export fn zeke_ghostllm_init(
    handle: *ZekeHandle,
    base_url: [*:0]const u8,
    enable_gpu: bool,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    const url_str = std.mem.span(base_url);
    
    const ghostllm_config = ghostllm.GhostLLMConfig{
        .base_url = url_str,
        .enable_gpu = enable_gpu,
        .enable_quic = true,
        .stream = true,
    };
    
    const ghostllm_client = ghostllm.GhostLLMClient.init(
        zeke_instance.allocator,
        ghostllm_config,
    ) catch |err| {
        return switch (err) {
            error.NetworkError => .network_error,
            error.InitializationFailed => .initialization_failed,
            else => .unexpected_response,
        };
    };
    
    zeke_instance.ghostllm_client = ghostllm_client;
    return .success;
}

/// Get GPU information from GhostLLM
export fn zeke_ghostllm_get_gpu_info(
    handle: *ZekeHandle,
    gpu_info: *ZekeGpuInfo,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    if (zeke_instance.ghostllm_client == null) {
        return .initialization_failed;
    }
    
    const client = zeke_instance.ghostllm_client.?;
    const stats = client.getGpuStats() catch |err| {
        return switch (err) {
            error.NetworkError => .network_error,
            else => .unexpected_response,
        };
    };
    
    // Allocate device name string
    const allocator = std.heap.c_allocator;
    const device_name_cstr = allocator.dupeZ(u8, stats.device_name) catch {
        return .memory_error;
    };
    
    gpu_info.* = ZekeGpuInfo{
        .device_name = device_name_cstr.ptr,
        .memory_used_mb = stats.memory_used_mb,
        .memory_total_mb = stats.memory_total_mb,
        .utilization_percent = stats.utilization_percent,
        .temperature_celsius = stats.temperature_celsius,
        .power_watts = stats.power_watts,
    };
    
    return .success;
}

/// Free GPU info memory
export fn zeke_free_gpu_info(gpu_info: *ZekeGpuInfo) void {
    if (gpu_info.device_name != null) {
        const allocator = std.heap.c_allocator;
        const device_name_slice = std.mem.span(gpu_info.device_name);
        allocator.free(device_name_slice);
        gpu_info.device_name = "";
    }
}

/// Run GhostLLM benchmark
export fn zeke_ghostllm_benchmark(
    handle: *ZekeHandle,
    model_name: [*:0]const u8,
    batch_size: u32,
) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    if (zeke_instance.ghostllm_client == null) {
        return .initialization_failed;
    }
    
    const client = zeke_instance.ghostllm_client.?;
    const model_str = std.mem.span(model_name);
    
    const benchmark_result = client.runBenchmark(model_str, batch_size) catch |err| {
        return switch (err) {
            error.NetworkError => .network_error,
            error.InvalidModel => .invalid_model,
            else => .unexpected_response,
        };
    };
    
    // TODO: Store benchmark result for later retrieval
    _ = benchmark_result;
    return .success;
}

// ============================================================================
// Configuration Management
// ============================================================================

/// Load configuration from file
export fn zeke_load_config(config_path: [*:0]const u8) ?*ZekeConfigHandle {
    const allocator = std.heap.c_allocator;
    const path_str = std.mem.span(config_path);
    
    const zeke_config = config.Config.loadFromFile(allocator, path_str) catch return null;
    
    const config_ptr = allocator.create(config.Config) catch return null;
    config_ptr.* = zeke_config;
    
    return @ptrCast(config_ptr);
}

/// Save configuration to file
export fn zeke_save_config(
    config_handle: *ZekeConfigHandle,
    config_path: [*:0]const u8,
) ZekeErrorCode {
    const zeke_config = @ptrCast(*config.Config, @alignCast(config_handle));
    const path_str = std.mem.span(config_path);
    
    zeke_config.saveToFile(path_str) catch |err| {
        return switch (err) {
            error.AccessDenied => .config_load_failed,
            error.FileNotFound => .config_load_failed,
            else => .unexpected_response,
        };
    };
    
    return .success;
}

/// Free configuration handle
export fn zeke_free_config(config_handle: *ZekeConfigHandle) void {
    const zeke_config = @ptrCast(*config.Config, @alignCast(config_handle));
    const allocator = std.heap.c_allocator;
    zeke_config.deinit();
    allocator.destroy(zeke_config);
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Get last error message (thread-local)
thread_local var last_error_message: [256:0]u8 = std.mem.zeroes([256:0]u8);

export fn zeke_get_last_error() [*:0]const u8 {
    return &last_error_message;
}

/// Set internal error message
fn setLastError(message: []const u8) void {
    const len = @min(message.len, last_error_message.len - 1);
    @memcpy(last_error_message[0..len], message[0..len]);
    last_error_message[len] = 0;
}

/// Check if Zeke instance is healthy
export fn zeke_health_check(handle: *ZekeHandle) ZekeErrorCode {
    const zeke_instance = @ptrCast(*zeke.Zeke, @alignCast(handle));
    
    // Basic health checks
    if (zeke_instance.current_provider == .ghostllm and zeke_instance.ghostllm_client == null) {
        setLastError("GhostLLM client not initialized");
        return .initialization_failed;
    }
    
    // Test a simple request to current provider
    const test_response = zeke_instance.chat("test") catch |err| {
        setLastError(@errorName(err));
        return switch (err) {
            error.NetworkError => .network_error,
            error.AuthenticationFailed => .authentication_failed,
            else => .unexpected_response,
        };
    };
    defer zeke_instance.allocator.free(test_response);
    
    return .success;
}