# zeke-sys

[![Crates.io](https://img.shields.io/crates/v/zeke-sys)](https://crates.io/crates/zeke-sys)
[![Documentation](https://docs.rs/zeke-sys/badge.svg)](https://docs.rs/zeke-sys)
[![Build Status](https://img.shields.io/github/workflow/status/ghostkellz/zeke/CI)](https://github.com/ghostkellz/zeke/actions)

Low-level Rust bindings for the [Zeke AI development companion](https://github.com/ghostkellz/zeke).

This crate provides unsafe, low-level FFI bindings to the Zeke Zig library. For a safe, high-level interface, use the [`zeke`](https://crates.io/crates/zeke) crate instead.

## Features

- **Multi-Provider AI**: Support for OpenAI, Claude, GitHub Copilot, Ollama, and GhostLLM
- **GPU Acceleration**: GhostLLM integration with CUDA/Metal support
- **Streaming Responses**: Real-time token streaming for interactive applications
- **Provider Health Monitoring**: Automatic failover and health checks
- **Thread-Safe**: Safe for use in multithreaded Rust applications

## Requirements

- **Zig Compiler**: Version 0.11.0 or later
- **Rust**: Version 1.70.0 or later
- **Platform**: Linux, macOS, or Windows

### Installing Zig

```bash
# Linux/macOS
curl -L https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar xJ
export PATH=$PATH:./zig-linux-x86_64-0.11.0

# Or use your package manager
brew install zig        # macOS
pacman -S zig           # Arch Linux
apt install zig         # Ubuntu (may be outdated)
```

## Usage

Add this to your `Cargo.toml`:

```toml
[dependencies]
zeke-sys = "0.2.0"
```

### Basic Example

```rust
use zeke_sys::*;
use std::ffi::CString;
use std::ptr;

unsafe {
    // Initialize configuration
    let config = ZekeConfig {
        base_url: CString::new("https://api.openai.com/v1")
            .unwrap().as_ptr(),
        api_key: CString::new("your-api-key-here")
            .unwrap().as_ptr(),
        provider: ZEKE_PROVIDER_OPENAI as i32,
        model_name: CString::new("gpt-4").unwrap().as_ptr(),
        temperature: 0.7,
        max_tokens: 2048,
        stream: false,
        enable_gpu: false,
        enable_fallback: true,
        timeout_ms: 30000,
    };
    
    // Initialize Zeke
    let handle = zeke_init(&config);
    if handle.is_null() {
        panic!("Failed to initialize Zeke");
    }
    
    // Send a chat message
    let message = CString::new("Hello, AI!").unwrap();
    let mut response = std::mem::zeroed::<ZekeResponse>();
    
    let result = zeke_chat(handle, message.as_ptr(), &mut response);
    if result == ZEKE_SUCCESS {
        let response_text = std::ffi::CStr::from_ptr(response.content)
            .to_string_lossy();
        println!("AI Response: {}", response_text);
        
        // Free the response memory
        zeke_free_response(&mut response);
    } else {
        println!("Error: {}", error_to_string(result));
    }
    
    // Cleanup
    zeke_destroy(handle);
}
```

### Streaming Example

```rust
use zeke_sys::*;
use std::ffi::CString;

unsafe extern "C" fn stream_callback(
    chunk: *const ZekeStreamChunk,
    _user_data: *mut std::ffi::c_void,
) {
    if !chunk.is_null() {
        let chunk_ref = &*chunk;
        if let Some(content) = c_ptr_to_str(chunk_ref.content) {
            print!("{}", content);
            if chunk_ref.is_final {
                println!("\n[Stream complete]");
            }
        }
    }
}

unsafe {
    let handle = /* ... initialize Zeke ... */;
    
    let message = CString::new("Tell me a story").unwrap();
    let result = zeke_chat_stream(
        handle,
        message.as_ptr(),
        Some(stream_callback),
        ptr::null_mut(),
    );
    
    if result != ZEKE_SUCCESS {
        println!("Streaming failed: {}", error_to_string(result));
    }
}
```

### GhostLLM GPU Example

Enable the `ghostllm` feature:

```toml
[dependencies]
zeke-sys = { version = "0.2.0", features = ["ghostllm"] }
```

```rust
use zeke_sys::{*, ghostllm::*};

unsafe {
    let handle = /* ... initialize Zeke ... */;
    
    // Initialize GhostLLM with GPU acceleration
    let result = init_default(handle);
    if result == ZEKE_SUCCESS {
        // Get GPU memory usage
        if let Some(usage) = get_gpu_memory_usage(handle) {
            println!("GPU Memory Usage: {:.1}%", usage);
        }
        
        // Run benchmark
        let model = CString::new("llama2-7b").unwrap();
        let result = zeke_ghostllm_benchmark(handle, model.as_ptr(), 32);
        if result == ZEKE_SUCCESS {
            println!("Benchmark completed successfully");
        }
    }
}
```

## Safety

⚠️ **All functions in this crate are unsafe** and require careful memory management.

### Memory Management Rules

1. **Always call cleanup functions**: Use `zeke_destroy()`, `zeke_free_response()`, etc.
2. **Check for null pointers**: Verify handles and responses before use
3. **String lifetime management**: Ensure C strings outlive their usage
4. **Thread safety**: While the underlying Zig code is thread-safe, FFI requires careful synchronization

### Common Pitfalls

```rust
// ❌ WRONG - String goes out of scope
unsafe {
    let config = ZekeConfig {
        api_key: CString::new("key").unwrap().as_ptr(), // String freed here!
        // ...
    };
    let handle = zeke_init(&config); // Use-after-free!
}

// ✅ CORRECT - Keep strings alive
unsafe {
    let api_key = CString::new("key").unwrap();
    let config = ZekeConfig {
        api_key: api_key.as_ptr(),
        // ...
    };
    let handle = zeke_init(&config); // Safe!
    // ... use handle ...
    zeke_destroy(handle);
}
```

## Feature Flags

- `default = ["ghostllm"]` - Default features
- `ghostllm` - Enable GhostLLM GPU acceleration support
- `streaming` - Enable streaming response helpers

## Platform Support

| Platform | Architecture | Status |
|----------|-------------|---------|
| Linux    | x86_64      | ✅ Fully Supported |
| Linux    | aarch64     | ✅ Fully Supported |
| macOS    | x86_64      | ✅ Fully Supported |
| macOS    | aarch64 (M1/M2) | ✅ Fully Supported |
| Windows  | x86_64      | 🔄 In Progress |

## Error Handling

All functions return `ZekeErrorCode` values. Use the provided utilities:

```rust
let result = zeke_chat(handle, message.as_ptr(), &mut response);
if is_success(result) {
    // Handle success
} else {
    println!("Error: {}", error_to_string(result));
    if let Some(details) = get_last_error() {
        println!("Details: {}", details);
    }
}
```

## Build Requirements

The build script automatically:

1. Checks for Zig compiler availability
2. Compiles the Zig FFI library with appropriate optimizations
3. Links system libraries (pthread, dl, etc.)
4. Generates Rust bindings with bindgen
5. Creates a test script for manual verification

### Build Environment Variables

- `TARGET` - Rust target triple (auto-detected)
- `OUT_DIR` - Cargo build output directory
- `CARGO_MANIFEST_DIR` - Path to Cargo.toml directory

## Contributing

1. **Fork the repository**: https://github.com/ghostkellz/zeke
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Add tests**: Ensure your changes are covered by tests
4. **Update documentation**: Keep docs and examples current
5. **Submit a pull request**: Describe your changes clearly

### Development Setup

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zeke
cd zeke/bindings/rust/zeke-sys

# Install dependencies
cargo build

# Run tests
cargo test

# Check documentation
cargo doc --open
```

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT License ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Links

- **Main Repository**: https://github.com/ghostkellz/zeke
- **Documentation**: https://docs.rs/zeke-sys
- **Crates.io**: https://crates.io/crates/zeke-sys
- **Zig Language**: https://ziglang.org/

## Changelog

### 0.2.0

- Initial release with FFI bindings
- GhostLLM GPU acceleration support
- Streaming response capabilities
- Multi-provider authentication
- Cross-platform support (Linux, macOS)
- Comprehensive error handling