#!/bin/bash

# Build script for Zeke Rust bindings
# This script builds both the low-level sys crate and high-level safe wrapper

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BINDINGS_DIR="$PROJECT_ROOT/bindings/rust"

echo -e "${BLUE}🦀 Building Zeke Rust Bindings${NC}"
echo "Project root: $PROJECT_ROOT"
echo "Bindings dir: $BINDINGS_DIR"
echo

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

# Check Rust
if ! command -v rustc &> /dev/null; then
    echo -e "${RED}❌ Rust compiler not found${NC}"
    echo "Please install Rust: https://rustup.rs/"
    exit 1
fi

RUST_VERSION=$(rustc --version)
echo -e "${GREEN}✅ Rust: $RUST_VERSION${NC}"

# Check Cargo
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}❌ Cargo not found${NC}"
    exit 1
fi

# Check Zig
if ! command -v zig &> /dev/null; then
    echo -e "${YELLOW}⚠️  Zig compiler not found${NC}"
    echo "Some features may not work. Install Zig: https://ziglang.org/"
    echo "Continuing with limited functionality..."
    ZIG_AVAILABLE=false
else
    ZIG_VERSION=$(zig version)
    echo -e "${GREEN}✅ Zig: $ZIG_VERSION${NC}"
    ZIG_AVAILABLE=true
fi

# Check bindgen dependencies
if ! command -v clang &> /dev/null; then
    echo -e "${YELLOW}⚠️  Clang not found - bindgen may fail${NC}"
    echo "Install clang/llvm for bindgen support"
fi

echo

# Parse command line arguments
BUILD_TYPE="release"
FEATURES=""
RUN_TESTS=false
VERBOSE=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_TYPE="debug"
            shift
            ;;
        --dev)
            BUILD_TYPE="debug"
            shift
            ;;
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --features)
            FEATURES="$2"
            shift 2
            ;;
        --test)
            RUN_TESTS=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --debug, --dev    Build in debug mode"
            echo "  --release         Build in release mode (default)"
            echo "  --features FEAT   Enable specific features (comma-separated)"
            echo "  --test            Run tests after building"
            echo "  --verbose, -v     Verbose output"
            echo "  --clean           Clean before building"
            echo "  --help, -h        Show this help"
            echo
            echo "Examples:"
            echo "  $0 --release --features ghostllm,async"
            echo "  $0 --debug --test --verbose"
            echo "  $0 --clean --release"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Setup build flags
CARGO_FLAGS=""
if [ "$BUILD_TYPE" = "release" ]; then
    CARGO_FLAGS="--release"
fi

if [ -n "$FEATURES" ]; then
    CARGO_FLAGS="$CARGO_FLAGS --features $FEATURES"
fi

if [ "$VERBOSE" = true ]; then
    CARGO_FLAGS="$CARGO_FLAGS --verbose"
fi

echo -e "${BLUE}🔧 Build Configuration${NC}"
echo "Build type: $BUILD_TYPE"
echo "Features: ${FEATURES:-default}"
echo "Cargo flags: $CARGO_FLAGS"
echo "Run tests: $RUN_TESTS"
echo

# Change to bindings directory
cd "$BINDINGS_DIR" || {
    echo -e "${RED}❌ Could not change to bindings directory: $BINDINGS_DIR${NC}"
    exit 1
}

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
    cargo clean
    echo
fi

# Build sys crate first
echo -e "${BLUE}🔨 Building zeke-sys (low-level bindings)...${NC}"
cd zeke-sys

if cargo build $CARGO_FLAGS; then
    echo -e "${GREEN}✅ zeke-sys built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build zeke-sys${NC}"
    exit 1
fi

cd ..

# Build high-level crate
echo -e "${BLUE}🔨 Building zeke (high-level wrapper)...${NC}"
cd zeke

if cargo build $CARGO_FLAGS; then
    echo -e "${GREEN}✅ zeke built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build zeke${NC}"
    exit 1
fi

cd ..

# Run tests if requested
if [ "$RUN_TESTS" = true ]; then
    echo -e "${BLUE}🧪 Running tests...${NC}"
    
    echo "Testing zeke-sys..."
    cd zeke-sys
    if cargo test $CARGO_FLAGS; then
        echo -e "${GREEN}✅ zeke-sys tests passed${NC}"
    else
        echo -e "${YELLOW}⚠️  zeke-sys tests failed${NC}"
    fi
    cd ..
    
    echo "Testing zeke..."
    cd zeke
    if cargo test $CARGO_FLAGS; then
        echo -e "${GREEN}✅ zeke tests passed${NC}"
    else
        echo -e "${YELLOW}⚠️  zeke tests failed${NC}"
    fi
    cd ..
fi

# Show build artifacts
echo
echo -e "${BLUE}📦 Build Artifacts${NC}"

if [ "$BUILD_TYPE" = "release" ]; then
    TARGET_DIR="target/release"
else
    TARGET_DIR="target/debug"
fi

echo "Libraries built in: $BINDINGS_DIR/$TARGET_DIR"
if [ -f "$TARGET_DIR/libzeke_sys.rlib" ]; then
    echo -e "${GREEN}✅ libzeke_sys.rlib${NC}"
fi
if [ -f "$TARGET_DIR/libzeke.rlib" ]; then
    echo -e "${GREEN}✅ libzeke.rlib${NC}"
fi

# Show examples of how to use
echo
echo -e "${BLUE}🚀 Usage Examples${NC}"
echo
echo "Add to your Cargo.toml:"
echo "[dependencies]"
echo 'zeke = { path = "'$BINDINGS_DIR'/zeke" }'
echo
echo "Basic usage:"
echo 'use zeke::{Zeke, Config, Provider};'
echo
echo '#[tokio::main]'
echo 'async fn main() -> Result<(), Box<dyn std::error::Error>> {'
echo '    let zeke = Zeke::builder()'
echo '        .provider(Provider::OpenAI)'
echo '        .api_key("your-key")'
echo '        .build()?;'
echo
echo '    let response = zeke.chat("Hello!").await?;'
echo '    println!("{}", response.content);'
echo '    Ok(())'
echo '}'

if [ -n "$FEATURES" ] && [[ "$FEATURES" == *"ghostllm"* ]]; then
    echo
    echo "GhostLLM usage:"
    echo 'let mut ghostllm = zeke.ghostllm();'
    echo 'ghostllm.initialize().await?;'
    echo 'let gpu_info = ghostllm.gpu_info().await?;'
    echo 'println!("GPU: {} ({}% utilized)", gpu_info.device_name, gpu_info.utilization_percent);'
fi

echo
echo -e "${GREEN}🎉 Rust bindings built successfully!${NC}"

# Final warnings/notes
if [ "$ZIG_AVAILABLE" = false ]; then
    echo
    echo -e "${YELLOW}⚠️  Note: Zig compiler not available${NC}"
    echo "Some FFI features may not work correctly."
    echo "Install Zig from https://ziglang.org/ for full functionality."
fi

if [ -n "$FEATURES" ] && [[ "$FEATURES" == *"ghostllm"* ]] && [ "$ZIG_AVAILABLE" = false ]; then
    echo -e "${YELLOW}⚠️  GhostLLM features require Zig compiler${NC}"
fi