# Integration Processes Guide

<div align="center">
  <img src="assets/icons/ghostbind.png" alt="Integration Processes" width="150">

  ## Dependency Management & Integration Workflows

  *How to properly integrate and consume Ghost ecosystem projects*
</div>

## Table of Contents

1. [Zig Project Integration](#zig-project-integration)
2. [Rust Project Integration](#rust-project-integration)
3. [When to Use Git vs Package Managers](#when-to-use-git-vs-package-managers)
4. [Cross-Language Dependency Patterns](#cross-language-dependency-patterns)
5. [Build Process Workflows](#build-process-workflows)
6. [Version Management Strategies](#version-management-strategies)

## Zig Project Integration

### Using `zig fetch --save` for Ghost Ecosystem Dependencies

Zig projects use the `zig fetch --save` command to add dependencies from GitHub repositories. This creates entries in `build.zig.zon` for dependency management.

#### Adding Zeke (AI Assistant)

```bash
# Add Zeke as a dependency
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz

# Or use a specific release/tag
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/tags/v0.1.0.tar.gz
```

**Updated `build.zig.zon`:**
```zig
.{
    .name = "my-zig-project",
    .version = "0.1.0",
    .dependencies = .{
        .zeke = .{
            .url = "https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz",
            .hash = "1220abcd1234...", // Auto-generated hash
        },
    },
}
```

**Using in `build.zig`:**
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get Zeke dependency
    const zeke_dep = b.dependency("zeke", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add Zeke module to your executable
    exe.root_module.addImport("zeke", zeke_dep.module("zeke"));

    b.installArtifact(exe);
}
```

#### Adding zbuild (Build System)

```bash
# Add zbuild as a dependency
zig fetch --save https://github.com/ghostkellz/zbuild/archive/refs/heads/main.tar.gz
```

**Using zbuild in `build.zig`:**
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get zbuild dependency
    const zbuild_dep = b.dependency("zbuild", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Import zbuild functionality
    exe.root_module.addImport("zbuild", zbuild_dep.module("zbuild"));

    // Use zbuild for Rust integration
    const rust_build_step = b.addSystemCommand(&[_][]const u8{
        "ghostbind", "build",
        "--manifest-path", "rust_libs/Cargo.toml",
        "--zig-target", @tagName(target.result.cpu.arch),
    });

    exe.step.dependOn(&rust_build_step.step);

    b.installArtifact(exe);
}
```

### Zig Project Structure with Ghost Dependencies

```
my-zig-project/
├── build.zig              # Build configuration using zbuild
├── build.zig.zon          # Dependencies (zeke, zbuild via zig fetch)
├── src/
│   ├── main.zig          # Main application
│   ├── ai_helper.zig     # Using Zeke AI features
│   └── rust_bridge.zig   # FFI bindings to Rust
├── rust_libs/            # Rust crates for performance-critical code
│   ├── core/
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   └── math/
│       ├── Cargo.toml
│       └── src/lib.rs
├── .ghostbind/           # Ghostbind cache and artifacts
└── zig-out/             # Build outputs
```

## Rust Project Integration

### Adding Zig Dependencies via Cargo.toml

Rust projects typically don't directly consume Zig projects as crates. Instead, they use build scripts (`build.rs`) to compile Zig code and link it.

#### Using Zig Projects in Rust

**Cargo.toml:**
```toml
[package]
name = "my-rust-project"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
libc = "0.2"

[build-dependencies]
# For generating bindings from C headers
bindgen = "0.69"
# For downloading and extracting Zig projects
reqwest = { version = "0.11", features = ["blocking"] }
tar = "0.4"
flate2 = "1.0"
```

**build.rs (Custom Build Script):**
```rust
use std::env;
use std::path::PathBuf;
use std::process::Command;
use std::fs;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let zig_project_dir = PathBuf::from(&out_dir).join("zig_algorithms");

    // Download and extract Zig project if not exists
    if !zig_project_dir.exists() {
        download_zig_project(&zig_project_dir);
    }

    // Build Zig project
    let output = Command::new("zig")
        .args(&[
            "build",
            "-Doptimize=ReleaseFast",
            "--prefix-lib-dir", &format!("{}/lib", out_dir),
            "--prefix-exe-dir", &format!("{}/bin", out_dir),
        ])
        .current_dir(&zig_project_dir)
        .output()
        .expect("Failed to build Zig project");

    if !output.status.success() {
        panic!("Zig build failed: {}", String::from_utf8_lossy(&output.stderr));
    }

    // Generate bindings for Zig C exports
    let bindings = bindgen::Builder::default()
        .header(format!("{}/include/algorithms.h", out_dir))
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("zig_bindings.rs"))
        .expect("Couldn't write bindings!");

    // Link Zig library
    println!("cargo:rustc-link-search=native={}/lib", out_dir);
    println!("cargo:rustc-link-lib=static=algorithms");
    println!("cargo:rerun-if-changed=build.rs");
}

fn download_zig_project(target_dir: &PathBuf) {
    // Download from GitHub archive
    let url = "https://github.com/ghostkellz/zig-algorithms/archive/refs/heads/main.tar.gz";
    let response = reqwest::blocking::get(url).expect("Failed to download");
    let bytes = response.bytes().expect("Failed to read response");

    // Extract tarball
    let tar = flate2::read::GzDecoder::new(&bytes[..]);
    let mut archive = tar::Archive::new(tar);
    archive.unpack(target_dir.parent().unwrap()).expect("Failed to extract");

    // Rename extracted directory
    let extracted_name = target_dir.parent().unwrap().join("zig-algorithms-main");
    fs::rename(extracted_name, target_dir).expect("Failed to rename directory");
}
```

#### Alternative: Git Submodules for Zig Projects

**Using Git submodules:**
```bash
# Add Zig project as submodule
git submodule add https://github.com/ghostkellz/zig-algorithms.git zig_deps/algorithms

# Initialize and update submodules
git submodule update --init --recursive
```

**Simplified build.rs with submodules:**
```rust
use std::env;
use std::process::Command;

fn main() {
    let zig_dir = "zig_deps/algorithms";
    let out_dir = env::var("OUT_DIR").unwrap();

    // Build Zig project from submodule
    let output = Command::new("zig")
        .args(&[
            "build",
            "-Doptimize=ReleaseFast",
            "--prefix-lib-dir", &format!("{}/lib", out_dir),
        ])
        .current_dir(zig_dir)
        .output()
        .expect("Failed to build Zig project");

    if !output.status.success() {
        panic!("Zig build failed: {}", String::from_utf8_lossy(&output.stderr));
    }

    println!("cargo:rustc-link-search=native={}/lib", out_dir);
    println!("cargo:rustc-link-lib=static=algorithms");
    println!("cargo:rerun-if-changed={}", zig_dir);
}
```

### Rust Project Structure with Zig Integration

```
my-rust-project/
├── Cargo.toml            # Rust dependencies
├── build.rs              # Custom build script for Zig integration
├── src/
│   ├── lib.rs           # Main Rust library
│   ├── zig_bindings.rs  # Generated FFI bindings
│   └── algorithms.rs    # High-level Rust wrapper
├── zig_deps/            # Git submodules or downloaded Zig projects
│   ├── algorithms/      # Zig algorithm implementations
│   └── data_structures/ # Zig data structure implementations
├── include/             # Generated C headers from Zig
└── target/             # Rust build artifacts
```

## When to Use Git vs Package Managers

### Use `zig fetch --save` When:

✅ **Recommended for Zig projects:**
- Adding stable dependencies from GitHub releases
- You want automatic hash verification
- You need reproducible builds
- The dependency has proper Zig package structure
- You want to use specific tagged versions

```bash
# Preferred: Use tagged releases
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/tags/v1.0.0.tar.gz

# Acceptable: Use main branch for latest features
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz
```

### Use Git Submodules When:

✅ **Recommended for:**
- Active development where you need to modify dependencies
- Complex multi-language projects
- When you need full Git history
- Cross-language integration (Rust projects using Zig)

```bash
# For development and contribution
git submodule add https://github.com/ghostkellz/zbuild.git deps/zbuild
git submodule add https://github.com/ghostkellz/zeke.git deps/zeke
```

### Use Git Clone When:

✅ **Recommended for:**
- Standalone tools and executables
- Build tools that aren't imported as libraries
- One-time setup or evaluation

```bash
# For standalone tools like Ghostbind
git clone https://github.com/ghostkellz/ghostbind.git
cd ghostbind
cargo install --path .
```

## Cross-Language Dependency Patterns

### Pattern 1: Zig Application with Rust Libraries

```
Application Flow:
Zig Main App → zbuild (orchestration) → Ghostbind (FFI) → Rust Crates

Dependencies:
- build.zig.zon: zbuild, zeke (via zig fetch)
- System: ghostbind (installed via cargo install)
- Project: Rust crates in subdirectories
```

**Example Workflow:**
```bash
# 1. Setup Zig project
zig init

# 2. Add Zig dependencies
zig fetch --save https://github.com/ghostkellz/zbuild/archive/refs/heads/main.tar.gz
zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz

# 3. Install Ghostbind (system-wide)
cargo install --git https://github.com/ghostkellz/ghostbind.git

# 4. Create Rust libraries in project
mkdir rust_libs
cd rust_libs && cargo init --lib core
```

### Pattern 2: Rust Application with Zig Performance Modules

```
Application Flow:
Rust Main App → build.rs → Zig Modules (compiled) → FFI Integration

Dependencies:
- Cargo.toml: bindgen, build dependencies
- Git submodules or downloaded Zig projects
- System: Zig compiler
```

**Example Workflow:**
```bash
# 1. Setup Rust project
cargo init --lib

# 2. Add Zig modules as submodules
git submodule add https://github.com/ghostkellz/zig-simd.git zig_deps/simd
git submodule add https://github.com/your-org/zig-algorithms.git zig_deps/algorithms

# 3. Configure build.rs for Zig compilation
# (See build.rs examples above)
```

### Pattern 3: Hybrid Workspace

```
Workspace Flow:
Root Project → Multiple Language Modules → Shared Build System

Dependencies:
- Workspace-level dependency management
- Cross-compilation coordination
- Shared artifact caching
```

**Example Structure:**
```
hybrid-workspace/
├── workspace.json        # Workspace configuration
├── apps/
│   ├── zig-cli/         # Zig executable (uses zig fetch)
│   └── rust-service/    # Rust service (uses Cargo.toml)
├── libs/
│   ├── shared-zig/      # Zig libraries
│   └── shared-rust/     # Rust libraries
└── tools/
    ├── build-coordinator.zig  # Custom build orchestration
    └── integration-tests/     # Cross-language tests
```

## Build Process Workflows

### Zig-Primary Workflow

```bash
# Development workflow for Zig projects using Rust libraries

# 1. Build Rust dependencies
ghostbind build --manifest-path rust_libs/core/Cargo.toml
ghostbind build --manifest-path rust_libs/math/Cargo.toml

# 2. Generate FFI headers
ghostbind headers --manifest-path rust_libs/core/Cargo.toml

# 3. Build Zig application (automatically links Rust artifacts)
zig build

# 4. Run with AI assistance
zeke run --project . --optimize
```

### Rust-Primary Workflow

```bash
# Development workflow for Rust projects using Zig modules

# 1. Update Zig submodules
git submodule update --remote

# 2. Build with Zig integration (build.rs handles Zig compilation)
cargo build

# 3. Run tests including FFI tests
cargo test

# 4. AI-assisted development
zeke analyze --lang rust --zig-integration
```

### Hybrid Workflow

```bash
# Coordinated build for mixed projects

# 1. Clean all artifacts
zbuild clean
cargo clean

# 2. Build in dependency order
zbuild build --parallel --all-targets

# 3. Integration testing
zbuild test --cross-language

# 4. Package for distribution
zbuild package --platform all
```

## Version Management Strategies

### Semantic Versioning Coordination

**For Zig projects (build.zig.zon):**
```zig
.{
    .name = "my-project",
    .version = "1.2.3",
    .dependencies = .{
        .zbuild = .{
            .url = "https://github.com/ghostkellz/zbuild/archive/refs/tags/v1.0.0.tar.gz",
            .hash = "...",
        },
        .zeke = .{
            .url = "https://github.com/ghostkellz/zeke/archive/refs/tags/v0.5.2.tar.gz",
            .hash = "...",
        },
    },
}
```

**For Rust projects (Cargo.toml):**
```toml
[package]
name = "my-project"
version = "1.2.3"

[dependencies]
# Regular Rust dependencies
serde = "1.0"

# Note: Zig dependencies handled in build.rs, not here
# Version pinning done through Git tags/commits
```

### Lock File Management

**Zig projects:**
- Zig automatically manages hashes in `build.zig.zon`
- No separate lock file needed
- Hash verification ensures reproducibility

**Rust projects:**
- Use `Cargo.lock` for Rust dependencies
- Pin Zig submodule commits for reproducibility
- Document Zig compiler version requirements

**Best Practices:**
```bash
# Pin exact versions for production
zig fetch --save https://github.com/ghostkellz/zbuild/archive/refs/tags/v1.0.0.tar.gz

# Use commit hashes for development
git submodule add https://github.com/ghostkellz/zig-libs.git deps/zig-libs
cd deps/zig-libs && git checkout a1b2c3d4e5f6  # specific commit

# Document requirements
echo "# Requires Zig 0.16+ and Rust 1.70+" > REQUIREMENTS.md
```

### Cross-Language Compatibility Matrix

| Zig Version | Rust Version | zbuild | Ghostbind | Zeke | GhostLLM |
|-------------|--------------|--------|-----------|------|----------|
| 0.16.x      | 1.70+        | 1.0.x  | 0.1.x     | 0.5.x| 1.0.x    |
| 0.15.x      | 1.65+        | 0.9.x  | 0.1.x     | 0.4.x| 0.9.x    |

---

## Summary

### Quick Decision Guide:

**For Zig Projects:**
- Use `zig fetch --save` for zbuild and zeke dependencies
- Install ghostbind system-wide via `cargo install`
- Manage Rust libraries as project subdirectories

**For Rust Projects:**
- Use Git submodules for Zig code you need to modify
- Use download-in-build.rs for stable Zig libraries
- Handle Zig compilation in build.rs scripts

**For Hybrid Projects:**
- Use workspace-level coordination
- Prefer tagged releases for stability
- Document cross-language requirements clearly

This approach ensures reliable, reproducible builds while leveraging the strengths of both language ecosystems.