//! FFI utility functions for safe interaction with zeke-sys

use crate::{Error, Result};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Convert a Rust string to a C string
pub(crate) fn string_to_c_string(s: &str) -> Result<CString> {
    CString::new(s).map_err(Error::from)
}

/// Convert a C string pointer to a Rust string
/// 
/// # Safety
/// 
/// The pointer must be valid and point to a null-terminated C string.
pub(crate) unsafe fn c_string_to_string(ptr: *const c_char) -> Result<String> {
    if ptr.is_null() {
        return Err(Error::custom("Null pointer provided"));
    }

    let c_str = CStr::from_ptr(ptr);
    let str_slice = c_str.to_str()?;
    Ok(str_slice.to_owned())
}

/// Convert a C string pointer to an optional Rust string
/// 
/// # Safety
/// 
/// If not null, the pointer must point to a valid null-terminated C string.
pub(crate) unsafe fn c_string_to_option_string(ptr: *const c_char) -> Result<Option<String>> {
    if ptr.is_null() {
        Ok(None)
    } else {
        c_string_to_string(ptr).map(Some)
    }
}

/// RAII wrapper for C strings that automatically frees memory
#[derive(Debug)]
pub(crate) struct CStringHolder {
    inner: CString,
}

impl CStringHolder {
    /// Create a new C string holder
    pub fn new(s: &str) -> Result<Self> {
        Ok(Self {
            inner: string_to_c_string(s)?,
        })
    }

    /// Get the raw pointer (for passing to C functions)
    pub fn as_ptr(&self) -> *const c_char {
        self.inner.as_ptr()
    }

    /// Get the raw mutable pointer (for passing to C functions that expect mutable)
    pub fn as_mut_ptr(&mut self) -> *mut c_char {
        // This is safe because CString guarantees the memory is valid
        self.inner.as_ptr() as *mut c_char
    }
}

/// Helper for managing multiple C strings with automatic cleanup
#[derive(Debug)]
pub(crate) struct CStringManager {
    strings: Vec<CString>,
}

impl CStringManager {
    /// Create a new C string manager
    pub fn new() -> Self {
        Self {
            strings: Vec::new(),
        }
    }

    /// Add a string and get its C pointer
    pub fn add(&mut self, s: &str) -> Result<*const c_char> {
        let c_string = string_to_c_string(s)?;
        let ptr = c_string.as_ptr();
        self.strings.push(c_string);
        Ok(ptr)
    }

    /// Add an optional string and get its C pointer (null if None)
    pub fn add_optional(&mut self, s: Option<&str>) -> Result<*const c_char> {
        match s {
            Some(string) => self.add(string),
            None => Ok(std::ptr::null()),
        }
    }

    /// Get the number of managed strings
    pub fn len(&self) -> usize {
        self.strings.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.strings.is_empty()
    }
}

impl Default for CStringManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_c_string_holder() {
        let holder = CStringHolder::new("test string").unwrap();
        
        // The pointer should not be null
        assert!(!holder.as_ptr().is_null());
        
        // Should be able to convert back to string
        unsafe {
            let back = c_string_to_string(holder.as_ptr()).unwrap();
            assert_eq!(back, "test string");
        }
    }

    #[test]
    fn test_c_string_manager() {
        let mut manager = CStringManager::new();
        
        let ptr1 = manager.add("string1").unwrap();
        let ptr2 = manager.add("string2").unwrap();
        let ptr3 = manager.add_optional(Some("string3")).unwrap();
        let ptr4 = manager.add_optional(None).unwrap();
        
        assert!(!ptr1.is_null());
        assert!(!ptr2.is_null());
        assert!(!ptr3.is_null());
        assert!(ptr4.is_null());
        
        assert_eq!(manager.len(), 3); // Only non-null strings are stored
        
        unsafe {
            assert_eq!(c_string_to_string(ptr1).unwrap(), "string1");
            assert_eq!(c_string_to_string(ptr2).unwrap(), "string2");
            assert_eq!(c_string_to_string(ptr3).unwrap(), "string3");
        }
    }

    #[test]
    fn test_string_with_null_bytes() {
        let result = CStringHolder::new("string\0with\0nulls");
        assert!(result.is_err());
    }

    #[test]
    fn test_null_pointer_handling() {
        unsafe {
            let result = c_string_to_string(std::ptr::null());
            assert!(result.is_err());
            
            let result = c_string_to_option_string(std::ptr::null()).unwrap();
            assert_eq!(result, None);
        }
    }
}