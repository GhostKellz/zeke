# Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>

pkgname=zeke
pkgver=0.2.9
pkgrel=1
pkgdesc='AI-powered development assistant with smart model routing and MCP integration'
arch=('x86_64' 'aarch64')
url='https://github.com/ghostkellz/zeke'
license=('MIT')
depends=('zlib')
makedepends=('zig>=0.15.0' 'git')
optdepends=(
    'ollama: Local LLM inference'
    'docker: For OMEN container deployment'
)
source=("git+https://github.com/ghostkellz/zeke.git#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
    cd "${srcdir}/${pkgname}"

    # Build in release mode
    zig build -Doptimize=ReleaseSafe
}

check() {
    cd "${srcdir}/${pkgname}"

    # Run tests
    zig build test
}

package() {
    cd "${srcdir}/${pkgname}"

    # Install binary
    install -Dm755 "zig-out/bin/zeke" "${pkgdir}/usr/bin/zeke"

    # Install documentation
    install -Dm644 README.md "${pkgdir}/usr/share/doc/${pkgname}/README.md"
    install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"

    # Install additional docs
    install -Dm644 docs/*.md -t "${pkgdir}/usr/share/doc/${pkgname}/"

    # Create config directory structure
    install -dm755 "${pkgdir}/etc/zeke"

    # Install example config if exists
    if [ -f "zeke.example.toml" ]; then
        install -Dm644 zeke.example.toml "${pkgdir}/etc/zeke/zeke.toml.example"
    fi

    # Install shell completions (if generated)
    # TODO: Add when completions are implemented
    # install -Dm644 "completions/zsh/_zeke" "${pkgdir}/usr/share/zsh/site-functions/_zeke"
    # install -Dm644 "completions/bash/zeke" "${pkgdir}/usr/share/bash-completion/completions/zeke"
    # install -Dm644 "completions/fish/zeke.fish" "${pkgdir}/usr/share/fish/vendor_completions.d/zeke.fish"
}
