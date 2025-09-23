# Zeke CLI + GhostLLM Integration Guide

## Overview

This guide shows how to integrate the **Zig-based Zeke CLI** with **Rust-based GhostLLM** for a blazing-fast AI development experience.

**Zeke** = High-performance AI CLI/TUI in Zig (zsync runtime, multi-provider support)
**GhostLLM** = Enterprise LLM proxy in Rust (unified API, cost tracking, auth)

## Architecture

```
┌─────────────────┐    FFI    ┌─────────────────┐    HTTP    ┌─────────────────┐
│   Zeke CLI      │◄─────────►│   GhostLLM      │◄──────────►│   AI Providers  │
│   (Zig v0.16)   │  Bindings │   (Rust Proxy)  │            │   (OpenAI, etc) │
└─────────────────┘           └─────────────────┘            └─────────────────┘
        ▲                             ▲
        │ WebSocket                   │ REST API
        ▼                             ▼
┌─────────────────┐           ┌─────────────────┐
│   zeke.nvim     │           │   Web Dashboard │
│   (Lua Plugin)  │           │   (Yew/WASM)    │
└─────────────────┘           └─────────────────┘
```

## Integration Benefits

### 🚀 **Performance Stack**
- **Zeke**: Zig's zero-cost abstractions + zsync async runtime
- **GhostLLM**: Rust's memory safety + high-throughput proxy
- **FFI**: Direct C ABI communication (no serialization overhead)

### 🔄 **Multi-Provider Flexibility**
- Zeke handles UI/UX and editor integration
- GhostLLM manages provider routing, auth, and cost tracking
- Switch providers seamlessly without Zeke code changes

### 🛡️ **Enterprise Features**
- API key management and rotation
- Cost tracking and budget limits
- Rate limiting and caching
- Audit logs for compliance

## Setup Instructions

### 1. Build GhostLLM FFI Library

```bash
# Clone GhostLLM
git clone https://github.com/your-org/ghostllm
cd ghostllm

# Build FFI library
./build_ffi.sh

# Verify build
ls zig-out/lib/
# Should show: libghostllm_core.so, ghostllm.h
```

### 2. Configure Zeke Build System

Add to your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zeke_exe = b.addExecutable(.{
        .name = "zeke",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link GhostLLM FFI
    zeke_exe.addLibraryPath(b.path("../ghostllm/zig-out/lib"));
    zeke_exe.linkSystemLibrary("ghostllm_core");
    zeke_exe.addIncludePath(b.path("../ghostllm/zig-out/lib"));
    zeke_exe.linkLibC();

    // Performance optimizations
    if (optimize == .ReleaseFast) {
        zeke_exe.want_lto = true;
        zeke_exe.strip = true;
        zeke_exe.single_threaded = true; // If appropriate
    }

    b.installArtifact(zeke_exe);
}
```

### 3. Integrate GhostLLM in Zeke

Create `src/ghostllm_client.zig`:

```zig
const std = @import("std");
const c = @cImport({
    @cInclude("ghostllm.h");
});

pub const GhostClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator, config_path: []const u8) !Self {
        var self = Self{ .allocator = allocator };

        // Convert to C string
        const config_cstr = try allocator.dupeZ(u8, config_path);
        defer allocator.free(config_cstr);

        const result = c.ghostllm_init(config_cstr.ptr);
        if (result != 0) {
            return error.InitializationFailed;
        }

        self.initialized = true;
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            c.ghostllm_shutdown();
        }
    }

    // Async-compatible chat completion
    pub fn chatCompletion(
        self: *Self,
        model: []const u8,
        messages: []const u8,
        api_key: ?[]const u8
    ) ![]u8 {
        const model_cstr = try self.allocator.dupeZ(u8, model);
        defer self.allocator.free(model_cstr);

        const messages_cstr = try self.allocator.dupeZ(u8, messages);
        defer self.allocator.free(messages_cstr);

        const key_cstr = if (api_key) |key|
            try self.allocator.dupeZ(u8, key)
        else
            try self.allocator.dupeZ(u8, "default");
        defer self.allocator.free(key_cstr);

        const result = c.ghostllm_chat_completion(
            model_cstr.ptr,
            messages_cstr.ptr,
            key_cstr.ptr
        );

        if (result.success != 0) {
            const data = std.mem.span(result.data);
            const owned = try self.allocator.dupe(u8, data);
            c.ghostllm_free_string(result.data);
            return owned;
        } else {
            const error_msg = if (result.error) |err| std.mem.span(err) else "Unknown error";
            c.ghostllm_free_string(result.error);
            return error.RequestFailed;
        }
    }

    // Streaming for real-time responses
    pub fn chatStream(
        self: *Self,
        model: []const u8,
        messages: []const u8,
        callback: fn([]const u8) void
    ) !void {
        const CallbackWrapper = struct {
            user_callback: fn([]const u8) void,

            fn cCallback(chunk_ptr: [*c]const u8) callconv(.C) c_int {
                // Note: This is simplified - real implementation needs proper context passing
                const chunk = std.mem.span(chunk_ptr);
                // Call user callback here
                return 0;
            }
        };

        var wrapper = CallbackWrapper{ .user_callback = callback };

        const model_cstr = try self.allocator.dupeZ(u8, model);
        defer self.allocator.free(model_cstr);

        const messages_cstr = try self.allocator.dupeZ(u8, messages);
        defer self.allocator.free(messages_cstr);

        const result = c.ghostllm_chat_completion_stream(
            model_cstr.ptr,
            messages_cstr.ptr,
            "default",
            CallbackWrapper.cCallback
        );

        if (result != 0) {
            return error.StreamingFailed;
        }
    }

    pub fn getModels(self: *Self) ![][]const u8 {
        const result = c.ghostllm_get_models();

        if (result.success != 0) {
            const json_data = std.mem.span(result.data);
            defer c.ghostllm_free_string(result.data);

            // Parse JSON array of model names
            const parsed = try std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                json_data,
                .{}
            );
            defer parsed.deinit();

            const array = parsed.value.array;
            var models = try self.allocator.alloc([]const u8, array.items.len);

            for (array.items, 0..) |item, i| {
                models[i] = try self.allocator.dupe(u8, item.string);
            }

            return models;
        } else {
            c.ghostllm_free_string(result.error);
            return error.ModelsFetchFailed;
        }
    }
};
```

### 4. Update Zeke Main Loop

Modify your main Zeke application:

```zig
const std = @import("std");
const ghostllm = @import("ghostllm_client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize GhostLLM client
    var ghost_client = try ghostllm.GhostClient.init(allocator, "config/ghostllm.toml");
    defer ghost_client.deinit();

    // Get available models
    const models = try ghost_client.getModels();
    defer {
        for (models) |model| allocator.free(model);
        allocator.free(models);
    }

    std.debug.print("Available models: ");
    for (models) |model| {
        std.debug.print("{s} ", .{model});
    }
    std.debug.print("\n");

    // Example chat completion
    const messages_json =
        \\[{"role": "user", "content": "Explain async/await in Zig"}]
    ;

    const response = try ghost_client.chatCompletion("gpt-4", messages_json, null);
    defer allocator.free(response);

    std.debug.print("Response: {s}\n", .{response});
}
```

## Configuration

### GhostLLM Config (`config/ghostllm.toml`)

```toml
[server]
host = "127.0.0.1"
port = 8080

[auth]
require_auth = false
admin_api_key = "admin-key-for-zeke"

[providers.openai]
api_key = "sk-your-openai-key"
enabled = true
models = ["gpt-4", "gpt-3.5-turbo"]

[providers.anthropic]
api_key = "sk-ant-your-anthropic-key"
enabled = true
models = ["claude-3-sonnet", "claude-3-haiku"]

[features]
billing = true
analytics = true
rate_limiting = true
caching = true
```

### Zeke Integration Config

```zig
// src/config.zig
pub const ZekeConfig = struct {
    ghostllm_config_path: []const u8 = "config/ghostllm.toml",
    default_model: []const u8 = "gpt-4",
    stream_responses: bool = true,
    enable_caching: bool = true,
    max_context_length: u32 = 8192,
};
```

## Advanced Features

### 1. Async Integration with zsync

```zig
// Integration with Zeke's zsync runtime
const zsync = @import("zsync");

pub fn asyncChatCompletion(
    client: *GhostClient,
    model: []const u8,
    messages: []const u8
) zsync.Task([]u8) {
    return zsync.spawn(struct {
        fn run() ![]u8 {
            return client.chatCompletion(model, messages, null);
        }
    }.run);
}
```

### 2. Neovim Integration Hook

```zig
// For zeke.nvim WebSocket communication
pub fn handleNvimRequest(client: *GhostClient, request: NvimRequest) !NvimResponse {
    switch (request.command) {
        .chat => {
            const response = try client.chatCompletion(
                request.model,
                request.messages,
                null
            );
            return NvimResponse{ .data = response };
        },
        .explain => {
            const explain_prompt = try std.fmt.allocPrint(
                client.allocator,
                "Explain this code: {s}",
                .{request.code}
            );
            defer client.allocator.free(explain_prompt);

            return try handleNvimRequest(client, .{
                .command = .chat,
                .model = "gpt-4",
                .messages = explain_prompt,
            });
        },
        .models => {
            const models = try client.getModels();
            return NvimResponse{ .models = models };
        },
    }
}
```

### 3. Performance Monitoring

```zig
pub const ZekeMetrics = struct {
    request_count: u64 = 0,
    total_tokens: u64 = 0,
    avg_latency_ms: f64 = 0,
    cache_hit_rate: f64 = 0,

    pub fn recordRequest(self: *Self, tokens: u32, latency_ms: u64) void {
        self.request_count += 1;
        self.total_tokens += tokens;

        // Update rolling average
        const alpha = 0.1;
        self.avg_latency_ms = (1 - alpha) * self.avg_latency_ms + alpha * @as(f64, @floatFromInt(latency_ms));
    }
};
```

## Deployment

### Development Mode
```bash
# Terminal 1: Start GhostLLM proxy
cd ghostllm && cargo run --bin ghostllm-proxy -- serve --dev

# Terminal 2: Build and run Zeke
cd zeke && zig build run
```

### Production Mode
```bash
# Build optimized versions
cd ghostllm && ./build_ffi.sh
cd zeke && zig build -Doptimize=ReleaseFast

# Deploy both services
systemctl start ghostllm-proxy
./zig-out/bin/zeke --config production.toml
```

## Benefits Summary

✅ **Ultra-fast performance** - Zig + Rust with direct FFI
✅ **Multi-provider support** - Seamless switching via GhostLLM
✅ **Enterprise features** - Auth, billing, analytics built-in
✅ **Editor integration** - Works with existing zeke.nvim
✅ **Cost optimization** - Intelligent caching and routing
✅ **Type safety** - Strong typing in both Zig and Rust

This setup gives you the best of both worlds: Zeke's blazing-fast UI/UX with GhostLLM's robust enterprise proxy capabilities.