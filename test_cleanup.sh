#!/usr/bin/env bash
#
# Zeke Cleanup Script
# Removes Zeke installations and configuration files
#
# Usage: ./test_cleanup.sh [--full]
#   --full    Also removes config and credentials (WARNING: deletes all saved API keys)
#
# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FULL_CLEANUP=false

# Parse arguments
if [[ "$1" == "--full" ]]; then
    FULL_CLEANUP=true
fi

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
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo -e "${BLUE}"
cat << "EOF"
    ╔════════════════════════════════════════╗
    ║    🧹 Zeke Cleanup Script             ║
    ╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Remove binaries
info "Checking for Zeke binaries..."

BINARY_LOCATIONS=(
    "/usr/local/bin/zeke"
    "/usr/bin/zeke"
    "$HOME/.local/bin/zeke"
)

for location in "${BINARY_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        info "Removing $location..."
        if [[ "$location" == "$HOME"* ]]; then
            rm -f "$location"
        else
            $SUDO rm -f "$location"
        fi
        success "Removed $location"
    fi
done

# Remove build artifacts in current directory
if [ -d "./zig-out" ]; then
    info "Removing local build artifacts..."
    rm -rf ./zig-out
    success "Removed ./zig-out"
fi

if [ -d "./zig-cache" ]; then
    rm -rf ./zig-cache
    success "Removed ./zig-cache"
fi

# Remove Zig installation (if installed by our script)
if [ -d "/usr/local/zig" ]; then
    warning "Found Zig installation at /usr/local/zig"
    read -p "Remove Zig compiler? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $SUDO rm -rf /usr/local/zig
        success "Removed /usr/local/zig"

        # Clean up PATH entries
        if [ -f "$HOME/.bashrc" ]; then
            sed -i '/\/usr\/local\/zig/d' "$HOME/.bashrc"
            success "Removed from PATH in ~/.bashrc"
        fi
        if [ -f "$HOME/.zshrc" ]; then
            sed -i '/\/usr\/local\/zig/d' "$HOME/.zshrc"
            success "Removed from PATH in ~/.zshrc"
        fi
    fi
fi

# Remove package manager installations
info "Checking package manager installations..."

# Arch Linux
if command -v pacman &> /dev/null; then
    if pacman -Qi zeke &> /dev/null; then
        warning "Found pacman package 'zeke'"
        read -p "Remove via pacman? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $SUDO pacman -Rns zeke
            success "Removed via pacman"
        fi
    fi
fi

# Snap
if command -v snap &> /dev/null; then
    if snap list | grep -q "^zeke "; then
        warning "Found snap package 'zeke'"
        read -p "Remove via snap? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $SUDO snap remove zeke
            success "Removed via snap"
        fi
    fi
fi

# Homebrew
if command -v brew &> /dev/null; then
    if brew list | grep -q "^zeke$"; then
        warning "Found Homebrew formula 'zeke'"
        read -p "Remove via brew? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            brew uninstall zeke
            success "Removed via brew"
        fi
    fi
fi

# Clean up config and credentials
if [ "$FULL_CLEANUP" = true ]; then
    warning "Full cleanup mode: Will remove config and credentials!"
    echo -e "${RED}This will delete all saved API keys and OAuth tokens!${NC}"
    read -p "Are you sure? (type 'yes'): " -r
    echo

    if [[ "$REPLY" == "yes" ]]; then
        CONFIG_DIR="$HOME/.config/zeke"

        if [ -d "$CONFIG_DIR" ]; then
            info "Removing $CONFIG_DIR..."
            rm -rf "$CONFIG_DIR"
            success "Removed configuration directory"
        fi

        # Also check for old locations
        if [ -f "$HOME/.zekerc" ]; then
            rm -f "$HOME/.zekerc"
            success "Removed ~/.zekerc"
        fi
    else
        info "Skipping config removal (credentials preserved)"
    fi
else
    info "Config and credentials preserved at ~/.config/zeke"
    info "Use --full to remove them"
fi

# Remove systemd services (if any)
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
if [ -f "$SYSTEMD_USER_DIR/zeke.service" ]; then
    info "Removing systemd user service..."
    systemctl --user stop zeke.service 2>/dev/null || true
    systemctl --user disable zeke.service 2>/dev/null || true
    rm -f "$SYSTEMD_USER_DIR/zeke.service"
    systemctl --user daemon-reload
    success "Removed systemd user service"
fi

# Remove system-wide service
if [ -f "/etc/systemd/system/zeke.service" ]; then
    warning "Found system-wide service"
    read -p "Remove system service? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $SUDO systemctl stop zeke.service 2>/dev/null || true
        $SUDO systemctl disable zeke.service 2>/dev/null || true
        $SUDO rm -f /etc/systemd/system/zeke.service
        $SUDO systemctl daemon-reload
        success "Removed system service"
    fi
fi

# Clean up temp files
info "Cleaning up temp files..."
rm -rf /tmp/zeke-* 2>/dev/null || true
success "Cleaned up temp files"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   ✓ Cleanup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if anything is left
if command -v zeke &> /dev/null; then
    warning "Zeke is still in PATH: $(which zeke)"
    echo "  You may need to restart your shell or check PATH manually"
else
    success "Zeke binary not found in PATH"
fi

if [ "$FULL_CLEANUP" = false ]; then
    echo ""
    info "Configuration preserved at ~/.config/zeke"
    info "To remove config and credentials, run:"
    echo "  ${YELLOW}./test_cleanup.sh --full${NC}"
fi

echo ""
