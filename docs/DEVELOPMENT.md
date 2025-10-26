# Zeke Development Guide

Complete guide for contributing to and developing Zeke.

## Quick Start

### Prerequisites

- **Zig 0.16.0-dev or later** ([Download](https://ziglang.org/download/))
- **Git** for version control
- **zlib** development headers
- **Docker** (optional, for Ollama testing)

### Clone and Build

```bash
# Clone repository
git clone https://github.com/ghostkellz/zeke.git
cd zeke

# Build debug version
zig build

# Build release version
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test

# Install locally
sudo cp zig-out/bin/zeke /usr/local/bin/
```

### Verify Installation

```bash
zeke --help
zeke doctor  # Check system health
```

## Project Structure

```
zeke/
├── build.zig              # Build configuration
├── build.zig.zon          # Dependencies manifest
├── src/                   # Source code
│   ├── main.zig          # CLI entry point
│   ├── root.zig          # Library root
│   ├── api/              # HTTP API layer
│   ├── auth/             # Authentication
│   ├── cli/              # CLI commands
│   ├── config/           # Configuration handling
│   ├── mcp/              # MCP integration
│   ├── providers/        # AI provider implementations
│   ├── routing/          # Smart routing logic
│   └── tools/            # Tool implementations
├── docs/                  # Documentation
├── release/               # Release files
│   ├── PKGBUILD          # Arch Linux package
│   ├── install.sh        # Universal installer
│   └── scripts/          # Release automation
├── archive/               # Historical analysis
└── examples/              # Example code

Config Files:
~/.config/zeke/
├── zeke.toml             # User configuration
├── credentials.json       # Encrypted API keys
└── zeke.db               # SQLite database
```

## Development Workflow

### 1. Set Up Development Environment

```bash
# Create development config
mkdir -p ~/.config/zeke
cp zeke.toml.example ~/.config/zeke/zeke.toml

# Configure Ollama for local testing
docker run -d --name ollama --network host ollama/ollama
docker exec -it ollama ollama pull qwen2.5-coder:7b

# Set up API keys (optional)
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-proj-..."
```

### 2. Build and Test

```bash
# Watch mode (rebuild on change)
while inotifywait -r -e modify src/; do
    clear
    zig build && echo "✓ Build successful"
done

# Run specific tests
zig test src/routing/router.zig
zig test src/providers/ollama.zig

# Run all tests
zig build test

# Test with debug logging
ZEKE_LOG_LEVEL=debug zig build run -- serve
```

### 3. Code Style

Zeke follows standard Zig formatting:

```bash
# Format all source files
zig fmt src/

# Check specific file
zig fmt --check src/main.zig
```

**Naming Conventions**:
- **Files**: `snake_case.zig`
- **Types**: `PascalCase`
- **Functions**: `camelCase`
- **Constants**: `SCREAMING_SNAKE_CASE`
- **Variables**: `snake_case`

Example:
```zig
const std = @import("std");

pub const ChatRequest = struct {
    message: []const u8,
    model: []const u8,
};

const MAX_RETRIES = 3;

pub fn sendRequest(req: ChatRequest) !void {
    var retry_count: u32 = 0;
    // Implementation
}
```

### 4. Adding a New Provider

Create `src/providers/my_provider.zig`:

```zig
const std = @import("std");
const flash = @import("flash");

pub const MyProvider = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: ProviderConfig) !*MyProvider {
        var provider = try allocator.create(MyProvider);
        provider.* = .{
            .allocator = allocator,
            .base_url = config.base_url,
            .api_key = config.api_key,
        };
        return provider;
    }

    pub fn deinit(self: *MyProvider) void {
        self.allocator.destroy(self);
    }

    pub fn chat(self: *MyProvider, request: ChatRequest) !ChatResponse {
        // Implementation
        const client = try flash.Client.init(self.allocator);
        defer client.deinit();

        const response = try client.post(
            self.base_url,
            .{
                .headers = &.{
                    .{ "Authorization", self.api_key },
                    .{ "Content-Type", "application/json" },
                },
                .body = request.toJson(),
            },
        );
        defer response.deinit();

        return ChatResponse.fromJson(response.body);
    }
};
```

Register in `src/providers/mod.zig`:
```zig
const my_provider = @import("my_provider.zig");

pub fn createProvider(name: []const u8, config: Config) !*Provider {
    if (std.mem.eql(u8, name, "myprovider")) {
        return my_provider.MyProvider.init(allocator, config);
    }
    // ... other providers
}
```

### 5. Adding MCP Tools

Tools are discovered automatically via MCP protocol. To add custom tools, create an MCP server:

```zig
// Example MCP tool server
const std = @import("std");
const rune = @import("rune");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // MCP stdio transport
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        const request = try stdin.readUntilDelimiterAlloc(allocator, '\n', 1024 * 1024);
        defer allocator.free(request);

        const response = try handleRequest(allocator, request);
        defer allocator.free(response);

        try stdout.print("{s}\n", .{response});
    }
}

fn handleRequest(allocator: std.mem.Allocator, request: []const u8) ![]const u8 {
    // Parse JSON-RPC request
    // Execute tool
    // Return JSON-RPC response
}
```

### 6. Testing Guidelines

```zig
// Unit test example
test "chat request serialization" {
    const allocator = std.testing.allocator;

    const request = ChatRequest{
        .message = "Hello",
        .model = "gpt-4",
    };

    const json = try request.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        \\{"message":"Hello","model":"gpt-4"}
        , json
    );
}

// Integration test example
test "ollama provider integration" {
    const allocator = std.testing.allocator;

    var provider = try OllamaProvider.init(allocator, .{
        .base_url = "http://localhost:11434",
    });
    defer provider.deinit();

    const response = try provider.chat(.{
        .message = "Test message",
        .model = "qwen2.5-coder:7b",
    });
    defer response.deinit();

    try std.testing.expect(response.content.len > 0);
}
```

Run tests:
```bash
zig test src/providers/ollama.zig
```

## Common Development Tasks

### Add a New CLI Command

Edit `src/cli/mod.zig`:

```zig
pub fn executeCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const command = args[0];

    if (std.mem.eql(u8, command, "mycommand")) {
        return myCommand(allocator, args[1..]);
    }
    // ... other commands
}

fn myCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    std.debug.print("Executing my command\n", .{});
    // Implementation
}
```

### Add Configuration Option

Edit `src/config/mod.zig`:

```zig
pub const Config = struct {
    // Existing fields...

    my_new_option: bool = false,  // Add new field

    pub fn loadConfig(allocator: std.mem.Allocator) !Config {
        // Load from TOML
        const toml = try loadToml(allocator);
        defer toml.deinit();

        return Config{
            .my_new_option = toml.get("my_new_option") orelse false,
            // ... other fields
        };
    }
};
```

Update `zeke.toml.example`:
```toml
# My new feature
my_new_option = true
```

### Add Database Table

Edit `src/db/schema.zig`:

```zig
pub fn migrate(db: *zqlite.Database) !void {
    // Create new table
    try db.exec(
        \\CREATE TABLE IF NOT EXISTS my_table (
        \\    id INTEGER PRIMARY KEY,
        \\    data TEXT NOT NULL,
        \\    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        \\)
    , .{});
}
```

## Debugging

### Debug Build

```bash
# Build with debug symbols
zig build

# Run with debugger
gdb zig-out/bin/zeke
(gdb) break src/main.zig:42
(gdb) run serve
```

### Logging

```bash
# Enable debug logging
ZEKE_LOG_LEVEL=debug zeke serve

# Log to file
zeke serve --log-file /tmp/zeke.log

# Trace mode (very verbose)
ZEKE_LOG_LEVEL=trace zeke chat "test"
```

### Common Issues

**Build fails with "too few arguments"**:
- Check Zig version: `zig version`
- Update to 0.16.0-dev or later

**Provider connection fails**:
```bash
# Test Ollama
curl http://localhost:11434/api/tags

# Test MCP
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | /path/to/mcp-server

# Check credentials
cat ~/.config/zeke/credentials.json | jq .
```

**Tests hang**:
- Check for deadlocks in async code
- Ensure proper cleanup in defer blocks
- Use `--test-filter` to isolate:
  ```bash
  zig test src/providers/ollama.zig --test-filter "basic chat"
  ```

## Performance Profiling

### CPU Profiling

```bash
# Build with profiling
zig build -Doptimize=ReleaseSafe

# Profile with perf
perf record -g ./zig-out/bin/zeke serve
perf report

# Or use valgrind
valgrind --tool=callgrind ./zig-out/bin/zeke serve
```

### Memory Profiling

```bash
# Memory leaks
valgrind --leak-check=full ./zig-out/bin/zeke serve

# Heap profiling
heaptrack ./zig-out/bin/zeke serve
```

### Benchmarking

```zig
// Benchmark example
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var timer = try std.time.Timer.start();

    // Code to benchmark
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try sendChatRequest(allocator, "test");
    }

    const elapsed = timer.read();
    const avg = elapsed / 1000;

    std.debug.print("Average latency: {}ns\n", .{avg});
}
```

## Contributing

### Pull Request Process

1. **Fork & Branch**:
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make Changes**:
   - Write code
   - Add tests
   - Update documentation

3. **Test**:
   ```bash
   zig build test
   zig fmt --check src/
   ```

4. **Commit**:
   ```bash
   git add .
   git commit -m "feat: Add my feature"
   ```

   Use [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation
   - `perf:` - Performance
   - `refactor:` - Code refactoring
   - `test:` - Tests
   - `chore:` - Maintenance

5. **Push & PR**:
   ```bash
   git push origin feature/my-feature
   # Create PR on GitHub
   ```

### Code Review Checklist

- [ ] Code follows Zig style guide
- [ ] Tests added for new functionality
- [ ] Documentation updated
- [ ] No memory leaks (valgrind clean)
- [ ] Error handling comprehensive
- [ ] Performance acceptable

## Release Process

See [release/README.md](../release/README.md) for detailed release instructions.

Quick overview:
1. Update version in all files
2. Update CHANGELOG.md
3. Build and test
4. Create git tag
5. Build packages
6. Publish release

## Resources

- **Zig Language**: https://ziglang.org/documentation/
- **zsync Async**: https://github.com/rsepassi/zsync
- **MCP Spec**: https://spec.modelcontextprotocol.io/
- **Zeke Docs**: https://github.com/ghostkellz/zeke/tree/main/docs
- **Issues**: https://github.com/ghostkellz/zeke/issues
- **Discussions**: https://github.com/ghostkellz/zeke/discussions

## Getting Help

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and community support
- **Email**: ckelley@ghostkellz.sh

## License

MIT License - See [LICENSE](../LICENSE) for details.
