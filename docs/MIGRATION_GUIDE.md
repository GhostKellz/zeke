# Migration Guide to ZEKE v0.2.8

## 🔄 Upgrading from Previous Versions

### Breaking Changes

#### 1. Dependency API Updates
- **zsync**: `CancelToken.init()` now requires `(allocator, reason)` parameters
- **zqlite**: `open()` now requires allocator as first parameter
- **Authentication**: Provider enum now includes `ghostllm` (currently stubbed)

#### 2. Command Interface
- New version commands: `zeke version`, `--version`, `-v`
- Enhanced help: `zeke help`, `--help`, `-h`
- Version now dynamically read from build.zig.zon

### Migration Steps

#### From v0.2.7 and Earlier

1. **Update Dependencies**
   ```bash
   # Clean old dependencies
   rm -rf ~/.cache/zig/p/phantom-* ~/.cache/zig/p/flash-* ~/.cache/zig/p/zsync-* ~/.cache/zig/p/zqlite-*

   # Fetch latest
   zig fetch --save https://github.com/ghostkellz/zeke/archive/refs/heads/main.tar.gz
   ```

2. **Code Updates** (if you've modified Zeke)
   ```zig
   // OLD (v0.2.7)
   self.cancel_token = zsync.CancelToken.init() catch null;
   self.connection = try zqlite.open(self.db_path);

   // NEW (v0.2.8)
   self.cancel_token = zsync.CancelToken.init(allocator, .user_requested) catch null;
   self.connection = try zqlite.open(self.allocator, self.db_path);
   ```

3. **Provider Configuration**
   ```zig
   // If you had custom provider logic, add ghostllm case:
   const auth_provider = switch (provider) {
       .openai => auth.AuthProvider.openai,
       .claude => auth.AuthProvider.google,
       .copilot => auth.AuthProvider.github,
       .ollama => auth.AuthProvider.local,
       .ghostllm => auth.AuthProvider.local, // NEW
   };
   ```

4. **Build and Test**
   ```bash
   zig build
   ./zig-out/bin/zeke version  # Should show v0.2.8
   ./zig-out/bin/zeke --help   # Test enhanced help
   ```

### Configuration Updates

#### Environment Variables
No changes required - all existing environment variables work the same:
- `OPENAI_API_KEY`
- `GITHUB_TOKEN`
- `CLAUDE_API_KEY` (if using direct auth)

#### Config Files
No breaking changes to existing configuration formats.

### New Features Available

#### Version Management
```bash
# New commands available:
zeke version
zeke --version
zeke -v
```

#### Enhanced Help
```bash
# More consistent help commands:
zeke help
zeke --help
zeke -h
```

#### GhostLLM Preparation
The codebase now includes stub support for GhostLLM integration:
- Provider enum includes `ghostllm`
- API endpoints defined but return mock responses
- Ready for Rust service integration

### Troubleshooting

#### Build Issues

1. **Dependency Hash Mismatches**
   ```bash
   # Clear all cached dependencies
   rm -rf ~/.cache/zig/p/*
   zig build
   ```

2. **API Compilation Errors**
   ```
   error: expected 2 argument(s), found 0
   ```
   This indicates old dependency usage. Update your code as shown above.

3. **Missing Provider Cases**
   ```
   error: switch must handle all possibilities
   ```
   Add `ghostllm` case to any provider switch statements.

#### Runtime Issues

1. **Authentication Still Works**
   All existing authentication flows remain unchanged.

2. **Provider Switching**
   All existing providers work as before, with ghostllm available but stubbed.

### Rollback Procedure

If you need to rollback to a previous version:

1. **Git Rollback** (if using git)
   ```bash
   git checkout v0.2.7  # or your previous working version
   zig build
   ```

2. **Dependency Rollback**
   ```bash
   # Manually edit build.zig.zon to use previous dependency versions
   # Then rebuild
   rm -rf ~/.cache/zig/p/*
   zig build
   ```

### Benefits of v0.2.8

- **Stability**: Better error handling and resource management
- **Performance**: Updated async runtime with zsync improvements
- **Maintainability**: Cleaner dependency management
- **Future-Ready**: Foundation for upcoming GhostLLM integration
- **User Experience**: Better version and help commands

### Support

If you encounter issues during migration:
1. Check this guide for common solutions
2. Clear Zig cache: `rm -rf ~/.cache/zig/p/*`
3. Rebuild from scratch: `zig build`
4. Open an issue with your specific error message

The v0.2.8 update provides a solid foundation while maintaining backward compatibility where possible.