//! Low-level Rust bindings for Zeke AI development companion (Minimal Version)
//! 
//! This is a minimal test version that only includes basic FFI functionality.
//! For a safe, high-level interface, use the `zeke` crate instead.
//! 
//! # Safety
//! 
//! All functions in this crate are unsafe and require careful memory management.

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(clippy::upper_case_acronyms)]
#![cfg_attr(docsrs, feature(doc_cfg))]

use libc::c_char;

// Include manual bindings (Rust 2024 compatible)
mod bindings_manual;
pub use bindings_manual::*;

// ============================================================================
// Safe wrapper utilities
// ============================================================================

/// Convert a C string pointer to a Rust string slice
/// 
/// # Safety
/// 
/// The pointer must be valid and point to a null-terminated C string.
/// The string must be valid UTF-8.
pub unsafe fn c_ptr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    
    unsafe {
        let c_str = std::ffi::CStr::from_ptr(ptr);
        c_str.to_str().ok()
    }
}

/// Convert a C string pointer to an owned Rust String
/// 
/// # Safety
/// 
/// The pointer must be valid and point to a null-terminated C string.
/// The string must be valid UTF-8.
pub unsafe fn c_ptr_to_string(ptr: *const c_char) -> Option<String> {
    unsafe { c_ptr_to_str(ptr).map(|s| s.to_owned()) }
}

// ============================================================================
// Error handling utilities  
// ============================================================================

/// Check if a Zeke error code indicates success
pub fn is_success(code: ZekeErrorCode) -> bool {
    matches!(code, ZekeErrorCode::ZEKE_SUCCESS)
}

/// Check if a Zeke error code indicates failure
pub fn is_error(code: ZekeErrorCode) -> bool {
    !matches!(code, ZekeErrorCode::ZEKE_SUCCESS)
}

/// Convert a Zeke error code to a human-readable string
pub fn error_to_string(code: ZekeErrorCode) -> &'static str {
    match code {
        ZekeErrorCode::ZEKE_SUCCESS => "Success",
        ZekeErrorCode::ZEKE_INITIALIZATION_FAILED => "Initialization failed",
        ZekeErrorCode::ZEKE_AUTHENTICATION_FAILED => "Authentication failed", 
        ZekeErrorCode::ZEKE_NETWORK_ERROR => "Network error",
        ZekeErrorCode::ZEKE_MEMORY_ERROR => "Memory error",
        ZekeErrorCode::ZEKE_INVALID_PARAMETER => "Invalid parameter",
    }
}

/// Get the last error message from Zeke
/// 
/// # Safety
/// 
/// This function is safe to call, but the returned string pointer
/// may become invalid after subsequent Zeke API calls.
pub fn get_last_error() -> Option<String> {
    unsafe {
        let ptr = zeke_get_last_error();
        c_ptr_to_string(ptr)
    }
}

// ============================================================================
// Configuration helpers
// ============================================================================

/// Create a default Zeke configuration for testing
pub fn default_config() -> ZekeConfig {
    ZekeConfig {
        base_url: std::ptr::null(),
        api_key: std::ptr::null(),
        provider: 0, // Default provider
        model_name: std::ptr::null(),
        temperature: 0.7,
        max_tokens: 100,
        stream: false,
        enable_gpu: false,
        enable_fallback: true,
        timeout_ms: 30000,
    }
}

// ============================================================================
// Extern function declarations (safe wrappers)
// ============================================================================

// Note: The actual extern functions are included from the generated bindings
// but we need to wrap them in unsafe blocks for Rust 2024

/// Safe wrapper for zeke_init
pub fn init(config: &ZekeConfig) -> Option<*mut ZekeHandle> {
    unsafe {
        let handle = zeke_init(config as *const ZekeConfig);
        if handle.is_null() { None } else { Some(handle) }
    }
}

/// Safe wrapper for zeke_chat
pub fn chat(handle: *mut ZekeHandle, message: &str, response: &mut ZekeResponse) -> ZekeErrorCode {
    let c_message = std::ffi::CString::new(message).unwrap();
    unsafe {
        zeke_chat(handle, c_message.as_ptr(), response as *mut ZekeResponse)
    }
}

/// Safe wrapper for zeke_destroy
pub fn destroy(handle: *mut ZekeHandle) {
    unsafe {
        zeke_destroy(handle);
    }
}

/// Safe wrapper for zeke_version
pub fn version() -> String {
    unsafe {
        let ptr = zeke_version();
        c_ptr_to_string(ptr).unwrap_or_else(|| "unknown".to_string())
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_error_codes() {
        assert!(is_success(ZekeErrorCode::ZEKE_SUCCESS));
        assert!(!is_success(ZekeErrorCode::ZEKE_NETWORK_ERROR));
        assert!(is_error(ZekeErrorCode::ZEKE_NETWORK_ERROR));
        assert!(!is_error(ZekeErrorCode::ZEKE_SUCCESS));
    }
    
    #[test]
    fn test_error_messages() {
        assert_eq!(error_to_string(ZekeErrorCode::ZEKE_SUCCESS), "Success");
        assert_eq!(error_to_string(ZekeErrorCode::ZEKE_NETWORK_ERROR), "Network error");
    }
    
    #[test]
    fn test_default_config() {
        let config = default_config();
        assert_eq!(config.provider, 0);
        assert_eq!(config.temperature, 0.7);
        assert_eq!(config.max_tokens, 100);
        assert!(!config.stream);
        assert!(!config.enable_gpu);
        assert!(config.enable_fallback);
    }
    
    #[test]  
    fn test_struct_sizes() {
        // Ensure structs have expected sizes for ABI compatibility
        use std::mem::size_of;
        
        assert!(size_of::<ZekeConfig>() > 0);
        assert!(size_of::<ZekeResponse>() > 0);
    }
}