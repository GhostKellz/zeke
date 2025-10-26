# Zeke Release Directory

This directory contains all release-related files and scripts for building and distributing Zeke packages.

## Directory Structure

```
release/
├── README.md              # This file
├── RELEASE_NOTES.md       # Release notes for current version
├── PKGBUILD              # Arch Linux package definition
├── install.sh            # Universal installation script
├── packages/             # Built packages and distribution files
│   ├── arch/            # Arch Linux packages (.pkg.tar.zst)
│   ├── debian/          # Debian/Ubuntu packages (.deb) - planned
│   └── macos/           # macOS packages (.dmg, .pkg) - planned
└── scripts/             # Release automation scripts
    ├── test_cleanup.sh  # Uninstall and cleanup script
    └── build-packages.sh # Package building automation (planned)
```

## Release Process

### 1. Version Bump

Update version in these files:
- `build.zig.zon` - Line 12: `.version = "0.3.0"`
- `README.md` - Title and badge
- `PKGBUILD` - Line 4: `pkgver=0.3.0`
- `install.sh` - Line 19: `ZEKE_VERSION="${ZEKE_VERSION:-0.3.0}"`
- `docs/HTTP_API.md` - Health check examples

### 2. Update Changelog

Edit `CHANGELOG.md` in project root:
```markdown
## [0.3.0] - 2025-10-26

### Added
- Feature descriptions...

### Changed
- Breaking changes...

### Fixed
- Bug fixes...
```

### 3. Build and Test

```bash
# Build release binary
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Test installation locally
./release/install.sh

# Verify version
zeke --version
```

### 4. Create Release Notes

Update `release/RELEASE_NOTES.md` with:
- Overview of changes
- Upgrade instructions
- Breaking changes
- Known issues

### 5. Build Packages

#### Arch Linux Package
```bash
# Test PKGBUILD locally
cd /tmp
cp /data/projects/zeke/release/PKGBUILD .
makepkg -si

# Verify installation
zeke --version
pacman -Ql zeke
```

#### Universal Installer
```bash
# Test install script
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zeke/main/release/install.sh | bash

# Or local test
bash release/install.sh
```

### 6. Tag Release

```bash
# Create and push tag
git tag -a v0.3.0 -m "Release v0.3.0: OAuth Broker and MCP Support"
git push origin v0.3.0

# Create GitHub release
gh release create v0.3.0 \
  --title "Zeke v0.3.0 - Broker" \
  --notes-file release/RELEASE_NOTES.md \
  zig-out/bin/zeke
```

### 7. Publish

- **AUR**: Update `PKGBUILD` in AUR repository
- **GitHub Releases**: Upload binaries for Linux x86_64/aarch64
- **Homebrew**: Update formula (when macOS support added)
- **Website**: Update download links

## Installation Methods

### Quick Install (Recommended)
```bash
curl -fsSL https://zeke.cktech.org | bash
```

### Arch Linux
```bash
yay -S zeke
```

### From Source
```bash
git clone https://github.com/ghostkellz/zeke.git
cd zeke
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zeke /usr/local/bin/
```

### Manual Binary Download
```bash
# Download from GitHub releases
wget https://github.com/ghostkellz/zeke/releases/download/v0.3.0/zeke-linux-x86_64
chmod +x zeke-linux-x86_64
sudo mv zeke-linux-x86_64 /usr/local/bin/zeke
```

## Build Scripts

### build-packages.sh (Planned)

Automated package building for all platforms:
```bash
./release/scripts/build-packages.sh --all
./release/scripts/build-packages.sh --arch
./release/scripts/build-packages.sh --deb
```

### test_cleanup.sh

Uninstall script for testing:
```bash
# Remove Zeke but keep config
./release/scripts/test_cleanup.sh

# Full removal including credentials
./release/scripts/test_cleanup.sh --full
```

## Platform Support

| Platform | Status | Package Format | Installation |
|----------|--------|----------------|--------------|
| **Arch Linux** | ✅ Supported | `.pkg.tar.zst` | `yay -S zeke` |
| **Ubuntu/Debian** | 🚧 Planned | `.deb` | `dpkg -i zeke.deb` |
| **Fedora/RHEL** | 🚧 Planned | `.rpm` | `rpm -i zeke.rpm` |
| **macOS** | 🚧 Planned | `.pkg`, `.dmg` | Homebrew |
| **Windows** | 🚧 Planned | `.exe`, `.msi` | Installer |
| **FreeBSD** | 📋 Backlog | - | From source |

## Release Checklist

- [ ] Version bumped in all files
- [ ] CHANGELOG.md updated
- [ ] RELEASE_NOTES.md created
- [ ] Tests passing (`zig build test`)
- [ ] Binary built (`zig build -Doptimize=ReleaseSafe`)
- [ ] Documentation updated
- [ ] PKGBUILD tested locally
- [ ] install.sh tested
- [ ] Git tag created
- [ ] GitHub release created
- [ ] Binaries uploaded
- [ ] AUR updated
- [ ] Announcement posted

## Versioning

Zeke follows [Semantic Versioning](https://semver.org/):
- **Major** (X.0.0): Breaking API changes
- **Minor** (0.X.0): New features, backward compatible
- **Patch** (0.0.X): Bug fixes, backward compatible

## Support

For release-related questions:
- **Issues**: https://github.com/ghostkellz/zeke/issues
- **Email**: ckelley@ghostkellz.sh

## License

MIT License - See [LICENSE](../LICENSE) for details.
