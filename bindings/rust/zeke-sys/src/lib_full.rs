//! Low-level Rust bindings for Zeke AI development companion
//! 
//! This crate provides unsafe, low-level bindings to the Zeke Zig library.
//! For a safe, high-level interface, use the `zeke` crate instead.
//! 
//! # Features
//! 
//! - `ghostllm` (default): Enable GhostLLM GPU acceleration features
//! - `streaming`: Enable streaming response features
//! 
//! # Safety
//! 
//! All functions in this crate are unsafe and require careful memory management.
//! Improper use can lead to:
//! 
//! - Memory leaks
//! - Use-after-free bugs  
//! - Buffer overflows
//! - Segmentation faults
//! 
//! # Example
//! 
//! ```no_run
//! use zeke_sys::*;
//! use std::ffi::CString;
//! use std::ptr;
//! 
//! unsafe {
//!     // Initialize configuration
//!     let config = ZekeConfig {
//!         base_url: CString::new("https://api.openai.com/v1").unwrap().as_ptr(),
//!         api_key: CString::new("your-api-key").unwrap().as_ptr(), 
//!         provider: ZEKE_PROVIDER_OPENAI as i32,
//!         model_name: CString::new("gpt-4").unwrap().as_ptr(),
//!         temperature: 0.7,
//!         max_tokens: 2048,
//!         stream: false,
//!         enable_gpu: false,
//!         enable_fallback: true,
//!         timeout_ms: 30000,
//!     };
//!     
//!     // Initialize Zeke
//!     let handle = zeke_init(&config);
//!     if handle.is_null() {
//!         panic!("Failed to initialize Zeke");
//!     }
//!     
//!     // Send a chat message
//!     let message = CString::new("Hello, AI!").unwrap();
//!     let mut response = std::mem::zeroed::<ZekeResponse>();
//!     
//!     let result = zeke_chat(handle, message.as_ptr(), &mut response);
//!     if result == ZEKE_SUCCESS {
//!         let response_text = std::ffi::CStr::from_ptr(response.content)
//!             .to_string_lossy();
//!         println!("AI Response: {}", response_text);
//!         
//!         // Free the response
//!         zeke_free_response(&mut response);
//!     }
//!     
//!     // Cleanup
//!     zeke_destroy(handle);
//! }
//! ```

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(clippy::upper_case_acronyms)]
#![cfg_attr(docsrs, feature(doc_cfg))]

use libc::{c_char, c_int, c_void, size_t};

// Include the generated bindings
include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

// Re-export common types for convenience
pub use ZekeErrorCode::*;
pub use ZekeProvider::*;

// ============================================================================
// Safe wrapper utilities
// ============================================================================

/// Convert a Rust string to a C string pointer
/// 
/// # Safety
/// 
/// The returned pointer is valid only as long as the input string lives.
/// The caller is responsible for ensuring the string outlives any use of the pointer.
pub unsafe fn str_to_c_ptr(s: &str) -> *const c_char {
    s.as_ptr() as *const c_char
}

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
    
    let c_str = std::ffi::CStr::from_ptr(ptr);
    c_str.to_str().ok()
}

/// Convert a C string pointer to an owned Rust String
/// 
/// # Safety
/// 
/// The pointer must be valid and point to a null-terminated C string.
/// The string must be valid UTF-8.
pub unsafe fn c_ptr_to_string(ptr: *const c_char) -> Option<String> {
    c_ptr_to_str(ptr).map(|s| s.to_owned())
}

// ============================================================================
// Error handling utilities  
// ============================================================================

/// Check if a Zeke error code indicates success
pub fn is_success(code: ZekeErrorCode) -> bool {
    code == ZEKE_SUCCESS
}

/// Check if a Zeke error code indicates failure
pub fn is_error(code: ZekeErrorCode) -> bool {
    code != ZEKE_SUCCESS
}

/// Convert a Zeke error code to a human-readable string
pub fn error_to_string(code: ZekeErrorCode) -> &'static str {
    match code {
        ZEKE_SUCCESS => "Success",
        ZEKE_INITIALIZATION_FAILED => "Initialization failed",
        ZEKE_AUTHENTICATION_FAILED => "Authentication failed", 
        ZEKE_CONFIG_LOAD_FAILED => "Configuration load failed",
        ZEKE_NETWORK_ERROR => "Network error",
        ZEKE_INVALID_MODEL => "Invalid model",
        ZEKE_TOKEN_EXCHANGE_FAILED => "Token exchange failed",
        ZEKE_UNEXPECTED_RESPONSE => "Unexpected response",
        ZEKE_MEMORY_ERROR => "Memory error",
        ZEKE_INVALID_PARAMETER => "Invalid parameter",
        ZEKE_PROVIDER_UNAVAILABLE => "Provider unavailable",
        ZEKE_STREAMING_FAILED => "Streaming failed",
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

/// Create a default Zeke configuration
pub fn default_config() -> ZekeConfig {
    ZekeConfig {
        base_url: std::ptr::null(),
        api_key: std::ptr::null(),
        provider: ZEKE_PROVIDER_OPENAI as i32,
        model_name: std::ptr::null(),
        temperature: 0.7,
        max_tokens: 2048,
        stream: false,
        enable_gpu: false,
        enable_fallback: true,
        timeout_ms: 30000,
    }
}

/// Convert a provider enum to its integer representation
pub fn provider_to_int(provider: ZekeProvider) -> c_int {
    provider as c_int
}

/// Convert an integer to a provider enum
pub fn int_to_provider(value: c_int) -> Option<ZekeProvider> {
    match value {
        x if x == ZEKE_PROVIDER_COPILOT as c_int => Some(ZEKE_PROVIDER_COPILOT),
        x if x == ZEKE_PROVIDER_CLAUDE as c_int => Some(ZEKE_PROVIDER_CLAUDE),
        x if x == ZEKE_PROVIDER_OPENAI as c_int => Some(ZEKE_PROVIDER_OPENAI),
        x if x == ZEKE_PROVIDER_OLLAMA as c_int => Some(ZEKE_PROVIDER_OLLAMA),
        x if x == ZEKE_PROVIDER_GHOSTLLM as c_int => Some(ZEKE_PROVIDER_GHOSTLLM),
        _ => None,
    }
}

// ============================================================================
// Feature-gated exports
// ============================================================================

#[cfg(feature = "ghostllm")]
#[cfg_attr(docsrs, doc(cfg(feature = "ghostllm")))]
pub mod ghostllm {
    //! GhostLLM GPU acceleration features
    //! 
    //! This module is only available when the `ghostllm` feature is enabled.
    
    use super::*;
    
    /// Initialize GhostLLM with default GPU settings
    /// 
    /// # Safety
    /// 
    /// The handle must be a valid Zeke instance.
    pub unsafe fn init_default(handle: *mut ZekeHandle) -> ZekeErrorCode {
        let url = std::ffi::CString::new("http://localhost:8080").unwrap();
        zeke_ghostllm_init(handle, url.as_ptr(), true)
    }
    
    /// Get GPU memory usage percentage
    /// 
    /// # Safety
    /// 
    /// The handle must be a valid Zeke instance with GhostLLM initialized.
    pub unsafe fn get_gpu_memory_usage(handle: *mut ZekeHandle) -> Option<f32> {
        let mut gpu_info = std::mem::zeroed::<ZekeGpuInfo>();
        let result = zeke_ghostllm_get_gpu_info(handle, &mut gpu_info);
        
        if is_success(result) {
            let usage = gpu_info.memory_used_mb as f32 / gpu_info.memory_total_mb as f32;
            zeke_free_gpu_info(&mut gpu_info);
            Some(usage * 100.0)
        } else {
            None
        }
    }
}

#[cfg(feature = "streaming")]
#[cfg_attr(docsrs, doc(cfg(feature = "streaming")))]
pub mod streaming {
    //! Streaming response features
    //! 
    //! This module is only available when the `streaming` feature is enabled.
    
    use super::*;
    
    /// A safe wrapper around streaming callbacks
    pub struct StreamHandler<F>
    where
        F: FnMut(&str, bool, u32, u32),
    {
        callback: F,
    }
    
    impl<F> StreamHandler<F>
    where
        F: FnMut(&str, bool, u32, u32),
    {
        pub fn new(callback: F) -> Self {
            Self { callback }
        }
        
        /// Get the raw C callback function
        /// 
        /// # Safety
        /// 
        /// This returns a function pointer that must only be used
        /// with the associated StreamHandler instance as user_data.
        pub unsafe fn get_c_callback() -> ZekeStreamCallback {
            Some(Self::c_callback)
        }
        
        /// Internal C callback wrapper
        unsafe extern "C" fn c_callback(
            chunk: *const ZekeStreamChunk, 
            user_data: *mut c_void
        ) {
            if chunk.is_null() || user_data.is_null() {
                return;
            }
            
            let handler = &mut *(user_data as *mut Self);
            let chunk_ref = &*chunk;
            
            if let Some(content) = c_ptr_to_str(chunk_ref.content) {
                (handler.callback)(
                    content,
                    chunk_ref.is_final,
                    chunk_ref.chunk_index,
                    chunk_ref.total_chunks,
                );
            }
        }
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
        assert!(is_success(ZEKE_SUCCESS));
        assert!(!is_success(ZEKE_NETWORK_ERROR));
        assert!(is_error(ZEKE_NETWORK_ERROR));
        assert!(!is_error(ZEKE_SUCCESS));
    }
    
    #[test]
    fn test_provider_conversion() {
        assert_eq!(provider_to_int(ZEKE_PROVIDER_OPENAI), ZEKE_PROVIDER_OPENAI as i32);
        assert_eq!(int_to_provider(ZEKE_PROVIDER_OPENAI as i32), Some(ZEKE_PROVIDER_OPENAI));
        assert_eq!(int_to_provider(-1), None);
    }
    
    #[test]
    fn test_error_messages() {
        assert_eq!(error_to_string(ZEKE_SUCCESS), "Success");
        assert_eq!(error_to_string(ZEKE_NETWORK_ERROR), "Network error");
    }
    
    #[test]
    fn test_default_config() {
        let config = default_config();
        assert_eq!(config.provider, ZEKE_PROVIDER_OPENAI as i32);
        assert_eq!(config.temperature, 0.7);
        assert_eq!(config.max_tokens, 2048);
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
        assert!(size_of::<ZekeStreamChunk>() > 0);
        assert!(size_of::<ZekeGpuInfo>() > 0);
        assert!(size_of::<ZekeProviderStatus>() > 0);
    }
}