#!/bin/bash
set -e
echo "Testing Zeke FFI library..."
echo "Library path: /data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/libzeke_ffi.a"
echo "Bindings path: /data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/bindings.rs"

# Check if library exists and is readable
if [ -f "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/libzeke_ffi.a" ]; then
    echo "✓ FFI library exists"
    file "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/libzeke_ffi.a" 
    nm -D "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/libzeke_ffi.a" | head -10 || nm "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/libzeke_ffi.a" | head -10
else
    echo "✗ FFI library not found"
    exit 1
fi

# Check bindings
if [ -f "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/bindings.rs" ]; then
    echo "✓ Rust bindings generated"
    wc -l "/data/projects/zeke/bindings/rust/target/x86_64-unknown-linux-gnu/debug/build/zeke-sys-97ce0d2e64425d94/out/bindings.rs"
else
    echo "✗ Rust bindings not found"
    exit 1
fi

echo "FFI build successful!"
