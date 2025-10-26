#!/usr/bin/env bash
#
# Zeke Installation Script
# Usage: curl -fsSL https://zeke.cktech.org | bash
#        or: bash install.sh
#
# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ZEKE_VERSION="${ZEKE_VERSION:-0.3.0}"
ZEKE_REPO="${ZEKE_REPO:-https://github.com/ghostkellz/zeke.git}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${HOME}/.config/zeke"
ZIG_MIN_VERSION="0.15.0"

# Functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        warning "Running as root. Installing to /usr/local/bin"
        SUDO=""
    else
        SUDO="sudo"
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ "$(uname)" = "Darwin" ]; then
        OS="macos"
        OS_VERSION=$(sw_vers -productVersion)
    else
        error "Unsupported operating system"
    fi

    ARCH=$(uname -m)

    info "Detected: $OS $OS_VERSION ($ARCH)"
}

# Install Zig if needed
install_zig() {
    if command -v zig &> /dev/null; then
        ZIG_VERSION=$(zig version | cut -d' ' -f1)
        success "Zig already installed: $ZIG_VERSION"
        return
    fi

    info "Installing Zig compiler..."

    case "$OS" in
        arch|manjaro)
            $SUDO pacman -S --noconfirm zig
            ;;
        ubuntu|debian|pop)
            # Snap has newer Zig version
            if command -v snap &> /dev/null; then
                $SUDO snap install zig --classic --beta
            else
                warning "Installing via APT (may be outdated)"
                $SUDO apt-get update
                $SUDO apt-get install -y zig
            fi
            ;;
        fedora|rhel|centos)
            $SUDO dnf install -y zig
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install zig
            else
                error "Homebrew not found. Install from https://brew.sh"
            fi
            ;;
        *)
            warning "Unknown OS, trying to download Zig binary..."
            install_zig_binary
            ;;
    esac

    success "Zig installed: $(zig version)"
}

# Install Zig from binary (fallback)
install_zig_binary() {
    ZIG_VERSION="0.16.0"

    case "$ARCH" in
        x86_64)
            ZIG_ARCH="x86_64"
            ;;
        aarch64|arm64)
            ZIG_ARCH="aarch64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac

    case "$OS" in
        macos)
            ZIG_OS="macos"
            ;;
        *)
            ZIG_OS="linux"
            ;;
    esac

    ZIG_TARBALL="zig-${ZIG_OS}-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARBALL}"

    info "Downloading Zig ${ZIG_VERSION}..."
    cd /tmp
    curl -fsSL -O "$ZIG_URL"

    info "Extracting Zig..."
    tar -xf "$ZIG_TARBALL"

    info "Installing Zig to /usr/local/zig..."
    $SUDO rm -rf /usr/local/zig
    $SUDO mv "zig-${ZIG_OS}-${ZIG_ARCH}-${ZIG_VERSION}" /usr/local/zig

    # Add to PATH if not already there
    if ! grep -q "/usr/local/zig" ~/.bashrc; then
        echo 'export PATH="/usr/local/zig:$PATH"' >> ~/.bashrc
    fi

    export PATH="/usr/local/zig:$PATH"

    success "Zig installed to /usr/local/zig"
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."

    case "$OS" in
        arch|manjaro)
            $SUDO pacman -S --noconfirm git base-devel zlib
            ;;
        ubuntu|debian|pop)
            $SUDO apt-get update
            $SUDO apt-get install -y git build-essential zlib1g-dev curl
            ;;
        fedora|rhel|centos)
            $SUDO dnf install -y git gcc zlib-devel
            ;;
        macos)
            # Git and zlib should be available via Xcode Command Line Tools
            if ! command -v git &> /dev/null; then
                xcode-select --install
            fi
            ;;
    esac

    success "Dependencies installed"
}

# Clone and build Zeke
build_zeke() {
    info "Cloning Zeke repository..."

    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    git clone --depth 1 --branch "v${ZEKE_VERSION}" "$ZEKE_REPO" zeke 2>/dev/null || \
        git clone --depth 1 "$ZEKE_REPO" zeke

    cd zeke

    info "Building Zeke (this may take a few minutes)..."
    zig build -Doptimize=ReleaseSafe

    success "Build complete"

    # Install binary
    info "Installing Zeke to $INSTALL_DIR..."
    $SUDO mkdir -p "$INSTALL_DIR"
    $SUDO cp zig-out/bin/zeke "$INSTALL_DIR/zeke"
    $SUDO chmod +x "$INSTALL_DIR/zeke"

    success "Zeke installed to $INSTALL_DIR/zeke"

    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
}

# Setup config directory
setup_config() {
    info "Setting up configuration directory..."

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    success "Config directory created at $CONFIG_DIR"
}

# Print next steps
print_next_steps() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ Zeke installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "  1. Verify installation:"
    echo "     ${YELLOW}zeke --version${NC}"
    echo ""
    echo "  2. Authenticate with providers:"
    echo "     ${YELLOW}zeke auth google${NC}      # Claude Max + ChatGPT Pro"
    echo "     ${YELLOW}zeke auth github${NC}      # GitHub Copilot Pro"
    echo ""
    echo "  3. Or use API keys:"
    echo "     ${YELLOW}zeke auth openai <key>${NC}"
    echo "     ${YELLOW}zeke auth anthropic <key>${NC}"
    echo ""
    echo "  4. Start the HTTP server:"
    echo "     ${YELLOW}zeke serve${NC}"
    echo ""
    echo "  5. Ask Zeke a question:"
    echo "     ${YELLOW}zeke ask 'How do I use Zig?'${NC}"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  • GitHub: https://github.com/ghostkellz/zeke"
    echo "  • Docs:   $CONFIG_DIR"
    echo ""
    echo -e "${BLUE}Optional integrations:${NC}"
    echo "  • OMEN (AI router):  Install via Docker"
    echo "  • Neovim plugin:     https://github.com/ghostkellz/zeke.nvim"
    echo ""

    # Check if PATH includes install directory
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        warning "Add $INSTALL_DIR to your PATH:"
        echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc"
        echo "  source ~/.bashrc"
        echo ""
    fi
}

# Main installation flow
main() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔════════════════════════════════════════╗
    ║   ⚡ Zeke AI Development Assistant    ║
    ║      Installation Script v0.2.9        ║
    ╚════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    check_root
    detect_os
    install_dependencies
    install_zig
    build_zeke
    setup_config
    print_next_steps
}

# Run installation
main
