//! Manual bindings for minimal Zeke FFI (Rust 2024 compatible)

use libc::c_char;

// Error codes matching Zig enum
#[repr(i32)]
#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub enum ZekeErrorCode {
    ZEKE_SUCCESS = 0,
    ZEKE_INITIALIZATION_FAILED = -1,
    ZEKE_AUTHENTICATION_FAILED = -2,
    ZEKE_NETWORK_ERROR = -4,
    ZEKE_MEMORY_ERROR = -8,
    ZEKE_INVALID_PARAMETER = -9,
}

// Config structure matching Zig struct
#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct ZekeConfig {
    pub base_url: *const c_char,
    pub api_key: *const c_char,
    pub provider: i32,
    pub model_name: *const c_char,
    pub temperature: f32,
    pub max_tokens: u32,
    pub stream: bool,
    pub enable_gpu: bool,
    pub enable_fallback: bool,
    pub timeout_ms: u32,
}

// Response structure matching Zig struct
#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct ZekeResponse {
    pub content: *const c_char,
    pub provider_used: i32,
    pub tokens_used: u32,
    pub response_time_ms: u32,
    pub error_code: ZekeErrorCode,
    pub error_message: *const c_char,
}

// Opaque handle types
#[repr(C)]
pub struct ZekeHandle {
    _private: [u8; 0],
}

// External function declarations - using unsafe extern for Rust 2024
unsafe extern "C" {
    pub fn zeke_init(config: *const ZekeConfig) -> *mut ZekeHandle;
    pub fn zeke_chat(
        handle: *mut ZekeHandle,
        message: *const c_char,
        response_out: *mut ZekeResponse,
    ) -> ZekeErrorCode;
    pub fn zeke_test_auth(handle: *mut ZekeHandle, provider: i32) -> ZekeErrorCode;
    pub fn zeke_free_response(response: *mut ZekeResponse);
    pub fn zeke_destroy(handle: *mut ZekeHandle);
    pub fn zeke_version() -> *const c_char;
    pub fn zeke_health_check(handle: *mut ZekeHandle) -> ZekeErrorCode;
    pub fn zeke_get_last_error() -> *const c_char;
}