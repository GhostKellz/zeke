use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=Cargo.toml");
    
    // Get the workspace root
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let workspace_root = PathBuf::from(manifest_dir)
        .parent()
        .unwrap()
        .parent()
        .unwrap();
    
    println!("cargo:rerun-if-changed={}", workspace_root.join("src").display());
    
    // Check if we're in a development environment with Zig source
    let zig_src = workspace_root.join("src/ffi/zeke_ffi.zig");
    if zig_src.exists() {
        println!("cargo:warning=Development build: FFI source available at {}", zig_src.display());
        
        // Check for Zig compiler
        match Command::new("zig").arg("version").output() {
            Ok(output) if output.status.success() => {
                let version = String::from_utf8_lossy(&output.stdout);
                println!("cargo:warning=Zig compiler found: {}", version.trim());
            }
            Ok(_) => println!("cargo:warning=Zig compiler found but version check failed"),
            Err(_) => println!("cargo:warning=Zig compiler not found - FFI bindings may not build correctly"),
        }
    } else {
        println!("cargo:warning=Release build: Using pre-compiled bindings");
    }
    
    // Set up feature flags based on available features
    let features: Vec<_> = env::vars()
        .filter(|(key, _)| key.starts_with("CARGO_FEATURE_"))
        .map(|(key, _)| key.replace("CARGO_FEATURE_", "").to_lowercase())
        .collect();
    
    println!("cargo:warning=Active features: {:?}", features);
    
    if features.contains(&"ghostllm".to_string()) {
        println!("cargo:warning=GhostLLM GPU acceleration enabled");
    }
    
    if features.contains(&"async".to_string()) {
        println!("cargo:warning=Async/tokio support enabled");
    }
}