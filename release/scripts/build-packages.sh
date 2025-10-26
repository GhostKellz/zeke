#!/usr/bin/env bash
#
# Zeke Package Builder
# Builds release packages for multiple platforms
#
# Usage: ./build-packages.sh [--all|--arch|--deb|--rpm]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_DIR="${PROJECT_ROOT}/release"
PACKAGES_DIR="${RELEASE_DIR}/packages"
BUILD_DIR="${PROJECT_ROOT}/zig-out"
VERSION=$(grep -oP 'pkgver=\K[0-9.]+' "${RELEASE_DIR}/PKGBUILD")

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

build_binary() {
    info "Building Zeke v${VERSION}..."
    cd "${PROJECT_ROOT}"

    zig build -Doptimize=ReleaseSafe

    if [ -f "${BUILD_DIR}/bin/zeke" ]; then
        success "Binary built successfully"
        ls -lh "${BUILD_DIR}/bin/zeke"
    else
        error "Failed to build binary"
        exit 1
    fi
}

build_arch_package() {
    info "Building Arch Linux package..."

    # Create temporary build directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT

    cp "${RELEASE_DIR}/PKGBUILD" "${TEMP_DIR}/"
    cd "${TEMP_DIR}"

    # Build package
    makepkg -sf --noconfirm

    # Move to packages directory
    mkdir -p "${PACKAGES_DIR}/arch"
    mv *.pkg.tar.zst "${PACKAGES_DIR}/arch/"

    success "Arch package built: $(ls ${PACKAGES_DIR}/arch/*.pkg.tar.zst)"
}

build_deb_package() {
    warn "Debian package building not yet implemented"
    # TODO: Implement .deb packaging
    # mkdir -p "${PACKAGES_DIR}/debian"
}

build_rpm_package() {
    warn "RPM package building not yet implemented"
    # TODO: Implement .rpm packaging
    # mkdir -p "${PACKAGES_DIR}/rpm"
}

build_macos_package() {
    warn "macOS package building not yet implemented"
    # TODO: Implement .pkg/.dmg packaging
    # mkdir -p "${PACKAGES_DIR}/macos"
}

create_tarball() {
    info "Creating source tarball..."

    cd "${PROJECT_ROOT}"
    TARBALL="zeke-${VERSION}.tar.gz"

    git archive --format=tar.gz --prefix="zeke-${VERSION}/" HEAD > "${PACKAGES_DIR}/${TARBALL}"

    success "Tarball created: ${PACKAGES_DIR}/${TARBALL}"
}

show_usage() {
    cat << EOF
Zeke Package Builder v${VERSION}

Usage: $0 [OPTIONS]

Options:
    --all       Build packages for all platforms
    --arch      Build Arch Linux package
    --deb       Build Debian/Ubuntu package (planned)
    --rpm       Build Fedora/RHEL package (planned)
    --macos     Build macOS package (planned)
    --tarball   Create source tarball
    --help      Show this help message

Examples:
    $0 --all              # Build all packages
    $0 --arch --tarball   # Build Arch package and tarball
    $0 --help             # Show help

EOF
}

main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi

    # Parse arguments
    BUILD_ALL=false
    BUILD_ARCH=false
    BUILD_DEB=false
    BUILD_RPM=false
    BUILD_MACOS=false
    BUILD_TARBALL=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                BUILD_ALL=true
                shift
                ;;
            --arch)
                BUILD_ARCH=true
                shift
                ;;
            --deb)
                BUILD_DEB=true
                shift
                ;;
            --rpm)
                BUILD_RPM=true
                shift
                ;;
            --macos)
                BUILD_MACOS=true
                shift
                ;;
            --tarball)
                BUILD_TARBALL=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    info "Zeke Package Builder v${VERSION}"
    echo

    # Build binary first
    build_binary
    echo

    # Build packages
    if [ "$BUILD_ALL" = true ]; then
        BUILD_ARCH=true
        BUILD_DEB=true
        BUILD_RPM=true
        BUILD_TARBALL=true
    fi

    [ "$BUILD_ARCH" = true ] && { build_arch_package; echo; }
    [ "$BUILD_DEB" = true ] && { build_deb_package; echo; }
    [ "$BUILD_RPM" = true ] && { build_rpm_package; echo; }
    [ "$BUILD_MACOS" = true ] && { build_macos_package; echo; }
    [ "$BUILD_TARBALL" = true ] && { create_tarball; echo; }

    success "Build complete!"
    info "Packages available in: ${PACKAGES_DIR}"
}

main "$@"
