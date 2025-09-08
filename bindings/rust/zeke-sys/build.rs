use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let zeke_root = manifest_dir
        .parent().unwrap()
        .parent().unwrap()
        .parent().unwrap()
        .to_path_buf();
    
    println!("cargo:rerun-if-changed={}", zeke_root.join("src/ffi/zeke_ffi_minimal.zig").display());
    println!("cargo:rerun-if-changed={}", zeke_root.join("src/ffi/zeke_ffi_minimal.h").display());
    println!("cargo:rerun-if-changed=build.rs");
    
    // Check if Zig is available and verify version compatibility
    let zig_version = Command::new("zig")
        .arg("version")
        .output()
        .expect("Zig compiler not found. Please install Zig 0.11+ from https://ziglang.org/");
    
    if !zig_version.status.success() {
        panic!("Failed to get Zig version. Please ensure Zig is properly installed.");
    }
    
    let zig_version_str = String::from_utf8_lossy(&zig_version.stdout);
    let version_clean = zig_version_str.trim();
    println!("cargo:warning=Building with Zig version: {}", version_clean);
    
    // Parse version to ensure compatibility (0.11+, including 0.16)
    if version_clean.starts_with("0.") {
        let version_parts: Vec<&str> = version_clean.split('.').collect();
        if let Some(minor_str) = version_parts.get(1) {
            if let Some(minor_part) = minor_str.split('-').next() {
                if let Ok(minor) = minor_part.parse::<u32>() {
                    if minor < 11 {
                        panic!("Zig version {} is too old. Please install Zig 0.11+ (0.16+ recommended)", version_clean);
                    }
                    if minor >= 16 {
                        println!("cargo:warning=Using Zig 0.16+ - excellent compatibility");
                    } else if minor >= 11 {
                        println!("cargo:warning=Using Zig 0.11-0.15 - good compatibility");
                    }
                }
            }
        }
    }
    
    // Build the Zig FFI library (using minimal version for testing)
    let zig_source = zeke_root.join("src/ffi/zeke_ffi_minimal.zig");
    let lib_output = out_dir.join("libzeke_ffi.a");
    
    // Determine target architecture for Zig
    let target = env::var("TARGET").unwrap();
    let zig_target = match target.as_str() {
        "x86_64-unknown-linux-gnu" => "x86_64-linux-gnu",
        "x86_64-unknown-linux-musl" => "x86_64-linux-musl", 
        "x86_64-pc-windows-gnu" => "x86_64-windows-gnu",
        "x86_64-pc-windows-msvc" => "x86_64-windows-gnu", // Use MinGW for MSVC too
        "x86_64-apple-darwin" => "x86_64-macos-none",
        "aarch64-apple-darwin" => "aarch64-macos-none",
        "aarch64-unknown-linux-gnu" => "aarch64-linux-gnu",
        _ => "native", // Fallback to native compilation
    };
    
    // Check Zig version for command compatibility
    let _is_zig_016_plus = version_clean.starts_with("0.") && 
        version_clean.split('.').nth(1).and_then(|s| s.split('-').next().and_then(|p| p.parse::<u32>().ok())).unwrap_or(0) >= 16;
    
    // Optimization level based on profile
    let opt_level = if cfg!(debug_assertions) {
        "Debug"
    } else {
        "ReleaseFast"
    };
    
    println!("cargo:warning=Compiling Zig FFI library with target: {} optimization: {}", zig_target, opt_level);
    
    let mut zig_build = Command::new("zig");
    zig_build
        .args(&[
            "build-lib",
            zig_source.to_str().unwrap(),
            "-target", zig_target,
            &format!("-O{}", opt_level),
            "--name", "zeke_ffi",
            &format!("-femit-bin={}", lib_output.display()),
            "-fno-emit-h", // We provide our own header
            "-lc", // Link with C standard library
        ]);
    
    // For now, compile without complex dependencies for testing
    // In a real implementation, we would set up the proper module path
    
    let output = zig_build
        .output()
        .expect("Failed to execute Zig compiler");
    
    if !output.status.success() {
        eprintln!("Zig compilation failed:");
        eprintln!("stdout: {}", String::from_utf8_lossy(&output.stdout));
        eprintln!("stderr: {}", String::from_utf8_lossy(&output.stderr));
        panic!("Zig compilation failed");
    }
    
    // Verify the library was created
    if !lib_output.exists() {
        panic!("Failed to create Zig library at: {}", lib_output.display());
    }
    
    println!("cargo:warning=Successfully built Zig FFI library: {}", lib_output.display());
    
    // Link the Zig library
    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=zeke_ffi");
    
    // Link system libraries that Zig needs
    #[cfg(target_os = "linux")]
    {
        println!("cargo:rustc-link-lib=pthread");
        println!("cargo:rustc-link-lib=dl");
        println!("cargo:rustc-link-lib=m");
    }
    
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-lib=framework=System");
        println!("cargo:rustc-link-lib=pthread");
    }
    
    #[cfg(target_os = "windows")]
    {
        println!("cargo:rustc-link-lib=ws2_32");
        println!("cargo:rustc-link-lib=kernel32");
        println!("cargo:rustc-link-lib=ntdll");
    }
    
    // Generate Rust bindings using bindgen
    println!("cargo:warning=Generating Rust bindings with bindgen");
    
    let header_path = zeke_root.join("src/ffi/zeke_ffi_minimal.h");
    let bindings = bindgen::Builder::default()
        .header(header_path.to_str().unwrap())
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        
        // Generate comments from header documentation
        .generate_comments(true)
        
        // Use core instead of std for no_std compatibility
        .use_core()
        .ctypes_prefix("libc")
        
        // Allowlist the Zeke functions and types
        .allowlist_function("zeke_.*")
        .allowlist_type("Zeke.*")
        .allowlist_var("ZEKE_.*")
        
        // Customize enum generation
        .default_enum_style(bindgen::EnumVariation::Rust { 
            non_exhaustive: false 
        })
        .prepend_enum_name(false)
        
        // Derive common traits
        .derive_debug(true)
        .derive_default(true)
        .derive_copy(true)
        .derive_eq(true)
        .derive_partialeq(true)
        .derive_ord(true)
        .derive_partialord(true)
        .derive_hash(true)
        
        // Layout tests for struct sizes
        .layout_tests(true)
        .size_t_is_usize(true)
        
        // Custom type replacements
        .blocklist_type("size_t")
        
        .generate()
        .expect("Unable to generate Rust bindings");
    
    let bindings_path = out_dir.join("bindings.rs");
    bindings
        .write_to_file(&bindings_path)
        .expect("Couldn't write bindings!");
    
    println!("cargo:warning=Generated Rust bindings at: {}", bindings_path.display());
    
    // Create a convenience script for manual testing
    let test_script = out_dir.join("test_ffi.sh");
    let script_content = format!(r#"#!/bin/bash
set -e
echo "Testing Zeke FFI library..."
echo "Library path: {}"
echo "Bindings path: {}"

# Check if library exists and is readable
if [ -f "{}" ]; then
    echo "✓ FFI library exists"
    file "{}" 
    nm -D "{}" | head -10 || nm "{}" | head -10
else
    echo "✗ FFI library not found"
    exit 1
fi

# Check bindings
if [ -f "{}" ]; then
    echo "✓ Rust bindings generated"
    wc -l "{}"
else
    echo "✗ Rust bindings not found"
    exit 1
fi

echo "FFI build successful!"
"#, 
        lib_output.display(),       // Library path echo
        bindings_path.display(),    // Bindings path echo
        lib_output.display(),       // if [ -f "..." check
        lib_output.display(),       // file command
        lib_output.display(),       // nm -D command
        lib_output.display(),       // nm command (fallback)
        bindings_path.display(),    // bindings if [ -f "..." check
        bindings_path.display()     // wc -l command
    );
    std::fs::write(&test_script, script_content).expect("Failed to write test script");
    
    // Make script executable on Unix
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&test_script).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&test_script, perms).unwrap();
    }
}