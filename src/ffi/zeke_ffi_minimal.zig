//! Minimal Zeke FFI for testing - without complex dependencies
//! This is a simplified version for initial testing and build verification

const std = @import("std");

// Minimal types for testing
pub const ZekeHandle = opaque {};
pub const ZekeConfigHandle = opaque {};

// Error codes
pub const ZekeErrorCode = enum(c_int) {
    ZEKE_SUCCESS = 0,
    ZEKE_INITIALIZATION_FAILED = -1,
    ZEKE_AUTHENTICATION_FAILED = -2,
    ZEKE_NETWORK_ERROR = -4,
    ZEKE_MEMORY_ERROR = -8,
    ZEKE_INVALID_PARAMETER = -9,
};

// Basic config structure
pub const ZekeConfig = extern struct {
    base_url: [*:0]const u8,
    api_key: [*:0]const u8,
    provider: c_int,
    model_name: [*:0]const u8,
    temperature: f32,
    max_tokens: u32,
    stream: bool,
    enable_gpu: bool,
    enable_fallback: bool,
    timeout_ms: u32,
};

// Basic response structure
pub const ZekeResponse = extern struct {
    content: [*:0]const u8,
    provider_used: c_int,
    tokens_used: u32,
    response_time_ms: u32,
    error_code: ZekeErrorCode,
    error_message: [*:0]const u8,
};

// Minimal context for testing
const MinimalContext = struct {
    allocator: std.mem.Allocator,
    config: ZekeConfig,
    test_response: []u8,
};

/// Initialize Zeke (minimal test implementation)
export fn zeke_init(config: *const ZekeConfig) ?*ZekeHandle {
    const allocator = std.heap.c_allocator;
    const ctx = allocator.create(MinimalContext) catch return null;
    
    // Create a test response
    const test_response = allocator.dupe(u8, "Hello from Zeke FFI test!") catch {
        allocator.destroy(ctx);
        return null;
    };
    
    ctx.* = .{
        .allocator = allocator,
        .config = config.*,
        .test_response = test_response,
    };
    
    return @ptrCast(ctx);
}

/// Send a chat message (minimal test implementation)
export fn zeke_chat(
    handle: *ZekeHandle,
    message: [*:0]const u8,
    response_out: *ZekeResponse,
) ZekeErrorCode {
    const ctx: *MinimalContext = @ptrCast(@alignCast(handle));
    const allocator = ctx.allocator;
    
    // Basic validation - skip null checks for opaque pointers in minimal version
    _ = message; // Mark as used
    
    // Create response with test data
    const response_content = allocator.dupeZ(u8, ctx.test_response) catch {
        return .ZEKE_MEMORY_ERROR;
    };
    
    response_out.* = .{
        .content = response_content.ptr,
        .provider_used = ctx.config.provider,
        .tokens_used = 42,
        .response_time_ms = 100,
        .error_code = .ZEKE_SUCCESS,
        .error_message = "",
    };
    
    return .ZEKE_SUCCESS;
}

/// Test authentication (minimal implementation)
export fn zeke_test_auth(handle: *ZekeHandle, provider: c_int) ZekeErrorCode {
    _ = handle;
    _ = provider;
    // Always return success for testing
    return .ZEKE_SUCCESS;
}

/// Free a response
export fn zeke_free_response(response: *ZekeResponse) void {
    if (std.mem.len(response.content) > 0) {
        const allocator = std.heap.c_allocator;
        const content_slice = std.mem.span(response.content);
        allocator.free(content_slice);
        response.content = "";
    }
}

/// Destroy Zeke instance
export fn zeke_destroy(handle: *ZekeHandle) void {
    const ctx: *MinimalContext = @ptrCast(@alignCast(handle));
    const allocator = ctx.allocator;
    
    allocator.free(ctx.test_response);
    allocator.destroy(ctx);
}

/// Get version string
export fn zeke_version() [*:0]const u8 {
    return "0.2.0-test";
}

/// Health check
export fn zeke_health_check(handle: *ZekeHandle) ZekeErrorCode {
    _ = handle;
    return .ZEKE_SUCCESS;
}

/// Get last error (minimal implementation)  
threadlocal var last_error: [256:0]u8 = std.mem.zeroes([256:0]u8);

export fn zeke_get_last_error() [*:0]const u8 {
    return &last_error;
}