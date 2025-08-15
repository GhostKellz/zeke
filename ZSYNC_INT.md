# Zsync Integration for ZEKE

ZEKE can leverage zsync's async I/O runtime for high-performance operations, concurrent processing, and responsive user interfaces.

## Quick Setup

### 1. Add Zsync to build.zig.zon

```bash
zig fetch --save https://github.com/ghostkellz/zsync/archive/main.tar.gz
```

Your `build.zig.zon` will be updated with:
```zig
.dependencies = .{
    .zsync = .{
        .url = "https://github.com/ghostkellz/zsync/archive/main.tar.gz",
        .hash = "...", // Auto-generated
    },
},
```

### 2. Update build.zig

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsync_dep = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });

    const zeke_exe = b.addExecutable(.{
        .name = "zeke",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    zeke_exe.root_module.addImport("zsync", zsync_dep.module("zsync"));
    b.installArtifact(zeke_exe);
}
```

## Core Integration Patterns

### 1. Basic Async Runtime Setup

```zig
const std = @import("std");
const zsync = @import("zsync");

pub fn main() !void {
    try zsync.runHighPerf(zekeMain);
}

fn zekeMain(io: zsync.Io) !void {
    var zeke = try ZekeCore.init(std.heap.page_allocator, io);
    defer zeke.deinit();
    
    try zeke.run();
}

const ZekeCore = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        return @This(){
            .allocator = allocator,
            .io = io,
        };
    }
    
    pub fn deinit(self: *@This()) void {
        _ = self;
    }
    
    pub fn run(self: *@This()) !void {
        // Your ZEKE implementation here
        const data = "Hello from ZEKE with zsync!\n";
        var future = try self.io.async_write(data);
        defer future.destroy(self.allocator);
        try future.await();
    }
};
```

### 2. Network Operations

```zig
const NetworkClient = struct {
    allocator: std.mem.Allocator,
    pool: zsync.NetworkPool,
    
    pub fn init(allocator: std.mem.Allocator) !@This() {
        var pool = try zsync.NetworkPool.init(allocator, .{
            .max_connections = 10,
            .timeout_ms = 30000,
            .keep_alive = true,
        });
        
        return @This(){
            .allocator = allocator,
            .pool = pool,
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.pool.deinit();
    }
    
    pub fn makeRequest(self: *@This(), url: []const u8) ![]const u8 {
        const request = zsync.NetworkRequest{
            .method = .GET,
            .url = url,
            .headers = &.{
                .{ .name = "User-Agent", .value = "ZEKE/1.0" },
                .{ .name = "Accept", .value = "application/json" },
            },
        };
        
        var response = try self.pool.execute(request);
        defer response.deinit();
        
        return try self.allocator.dupe(u8, response.body);
    }
    
    pub fn concurrentRequests(self: *@This(), urls: []const []const u8) ![][]const u8 {
        var batch = zsync.TaskBatch.init(self.allocator);
        defer batch.deinit();
        
        var results = try self.allocator.alloc([]const u8, urls.len);
        
        for (urls, 0..) |url, i| {
            const task = try zsync.Task.init(self.allocator, makeRequestImpl, .{ self, url, &results[i] });
            try batch.add(task);
        }
        
        try batch.executeAll();
        return results;
    }
    
    fn makeRequestImpl(self: *@This(), url: []const u8, result: *[]const u8) !void {
        result.* = try self.makeRequest(url);
    }
};
```

### 3. File Processing with Async I/O

```zig
const FileProcessor = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    file_ops: zsync.FileOps,
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        return @This(){
            .allocator = allocator,
            .io = io,
            .file_ops = zsync.FileOps.init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.file_ops.deinit();
    }
    
    pub fn processFiles(self: *@This(), file_paths: []const []const u8) !void {
        var batch = zsync.TaskBatch.init(self.allocator);
        defer batch.deinit();
        
        for (file_paths) |path| {
            const task = try zsync.Task.init(self.allocator, processFileImpl, .{ self, path });
            try batch.add(task);
        }
        
        // Process with limited concurrency to avoid overwhelming the system
        try batch.executeAllWithLimit(4);
    }
    
    fn processFileImpl(self: *@This(), path: []const u8) !void {
        const content = try self.file_ops.readFile(path);
        defer self.allocator.free(content);
        
        // Process the file content
        const processed = try self.transformContent(content);
        defer self.allocator.free(processed);
        
        // Write back asynchronously
        const output_path = try std.fmt.allocPrint(self.allocator, "{s}.processed", .{path});
        defer self.allocator.free(output_path);
        
        try self.file_ops.writeFile(output_path, processed);
    }
    
    fn transformContent(self: *@This(), content: []const u8) ![]u8 {
        // Your content transformation logic
        return try self.allocator.dupe(u8, content);
    }
};
```

### 4. Real-time Data Processing

```zig
const DataProcessor = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    stream: zsync.RealtimeStream,
    cancel_token: zsync.CancelToken,
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        var stream = try zsync.RealtimeStream.builder()
            .buffer_size(8192)
            .enable_backpressure(true)
            .build();
        
        return @This(){
            .allocator = allocator,
            .io = io,
            .stream = stream,
            .cancel_token = zsync.CancelToken.init(),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.cancel_token.cancel();
        self.stream.deinit();
        self.cancel_token.deinit();
    }
    
    pub fn startProcessing(self: *@This()) !void {
        // Start data ingestion
        _ = try zsync.spawn(dataIngestionLoop, .{self});
        
        // Start processing
        _ = try zsync.spawn(dataProcessingLoop, .{self});
        
        std.log.info("ZEKE: Data processing started");
    }
    
    fn dataIngestionLoop(self: *@This()) !void {
        while (!self.cancel_token.isCancelled()) {
            // Simulate data ingestion
            const data = try self.generateData();
            defer self.allocator.free(data);
            
            try self.stream.write(data);
            
            // Ingest at 10Hz
            try zsync.sleep(100);
        }
    }
    
    fn dataProcessingLoop(self: *@This()) !void {
        while (!self.cancel_token.isCancelled()) {
            if (try self.stream.read()) |data| {
                defer self.allocator.free(data);
                try self.processData(data);
            } else {
                try zsync.sleep(10); // Wait for more data
            }
        }
    }
    
    fn generateData(self: *@This()) ![]u8 {
        const timestamp = std.time.milliTimestamp();
        return try std.fmt.allocPrint(self.allocator, "{{\"timestamp\":{},\"value\":{}}}", .{ timestamp, timestamp % 100 });
    }
    
    fn processData(self: *@This(), data: []const u8) !void {
        std.log.debug("ZEKE: Processing data: {s}", .{data});
        // Your data processing logic here
    }
    
    pub fn stop(self: *@This()) void {
        self.cancel_token.cancel();
    }
};
```

### 5. Terminal UI Integration

```zig
const ZekeUI = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    terminal: zsync.AsyncPTY,
    renderer: zsync.RenderingPipeline,
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        var terminal = try zsync.AsyncPTY.init(allocator, .{
            .enable_colors = true,
            .buffer_size = 4096,
        });
        
        var renderer = try zsync.RenderingPipeline.init(allocator, .{
            .frame_rate = 30,
            .buffer_size = 8192,
        });
        
        return @This(){
            .allocator = allocator,
            .io = io,
            .terminal = terminal,
            .renderer = renderer,
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.terminal.deinit();
        self.renderer.deinit();
    }
    
    pub fn startUI(self: *@This()) !void {
        // Start render loop
        _ = try zsync.spawn(renderLoop, .{self});
        
        // Handle user input
        _ = try zsync.spawn(inputLoop, .{self});
        
        self.terminal.print("🚀 ZEKE UI Started\n", .{});
    }
    
    fn renderLoop(self: *@This()) !void {
        var frame_count: u64 = 0;
        
        while (true) {
            // Clear screen
            try self.terminal.clearScreen();
            
            // Render UI elements
            try self.renderHeader(frame_count);
            try self.renderStatus();
            try self.renderFooter();
            
            // Render to screen
            try self.renderer.render();
            
            frame_count += 1;
            
            // 30 FPS
            try zsync.sleep(33);
        }
    }
    
    fn inputLoop(self: *@This()) !void {
        while (true) {
            const input = try self.terminal.readKey();
            try self.handleInput(input);
        }
    }
    
    fn renderHeader(self: *@This(), frame_count: u64) !void {
        try self.terminal.print("┌─ ZEKE v1.0 ─ Frame: {} ─┐\n", .{frame_count});
    }
    
    fn renderStatus(self: *@This()) !void {
        try self.terminal.print("│ Status: Running         │\n", .{});
        try self.terminal.print("│ Tasks:  Active          │\n", .{});
    }
    
    fn renderFooter(self: *@This()) !void {
        try self.terminal.print("└─ Press 'q' to quit ────┘\n", .{});
    }
    
    fn handleInput(self: *@This(), key: u8) !void {
        switch (key) {
            'q' => {
                try self.terminal.print("Goodbye!\n", .{});
                std.process.exit(0);
            },
            'r' => {
                try self.terminal.print("Refreshing...\n", .{});
            },
            else => {
                try self.terminal.print("Unknown key: {c}\n", .{key});
            },
        }
    }
};
```

## Advanced Usage Patterns

### Task Coordination with Cancellation

```zig
const TaskCoordinator = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    tasks: std.ArrayList(TaskInfo),
    global_cancel: zsync.CancelToken,
    
    const TaskInfo = struct {
        name: []const u8,
        handle: zsync.Task,
        cancel_token: zsync.CancelToken,
    };
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        return @This(){
            .allocator = allocator,
            .io = io,
            .tasks = std.ArrayList(TaskInfo).init(allocator),
            .global_cancel = zsync.CancelToken.init(),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.cancelAll();
        self.tasks.deinit();
        self.global_cancel.deinit();
    }
    
    pub fn addTask(self: *@This(), name: []const u8, task_fn: anytype, args: anytype) !void {
        var cancel_token = zsync.CancelToken.init();
        var task = try zsync.Task.init(self.allocator, task_fn, args ++ .{&cancel_token});
        
        try self.tasks.append(.{
            .name = try self.allocator.dupe(u8, name),
            .handle = task,
            .cancel_token = cancel_token,
        });
    }
    
    pub fn executeAll(self: *@This()) !void {
        var batch = zsync.TaskBatch.init(self.allocator);
        defer batch.deinit();
        
        for (self.tasks.items) |task_info| {
            try batch.add(task_info.handle);
        }
        
        try batch.executeAll();
    }
    
    pub fn cancelAll(self: *@This()) void {
        self.global_cancel.cancel();
        
        for (self.tasks.items) |task_info| {
            task_info.cancel_token.cancel();
        }
    }
};
```

### Performance Monitoring

```zig
const PerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    io: zsync.Io,
    metrics: std.HashMap([]const u8, Metric, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    
    const Metric = struct {
        count: u64,
        total_time_ns: u64,
        min_time_ns: u64,
        max_time_ns: u64,
        
        pub fn update(self: *@This(), duration_ns: u64) void {
            self.count += 1;
            self.total_time_ns += duration_ns;
            
            if (duration_ns < self.min_time_ns or self.min_time_ns == 0) {
                self.min_time_ns = duration_ns;
            }
            
            if (duration_ns > self.max_time_ns) {
                self.max_time_ns = duration_ns;
            }
        }
        
        pub fn averageTimeNs(self: *const @This()) u64 {
            if (self.count == 0) return 0;
            return self.total_time_ns / self.count;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, io: zsync.Io) !@This() {
        return @This(){
            .allocator = allocator,
            .io = io,
            .metrics = std.HashMap([]const u8, Metric, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        var iterator = self.metrics.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.metrics.deinit();
    }
    
    pub fn time(self: *@This(), name: []const u8, func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        const start_time = std.time.nanoTimestamp();
        const result = try @call(.auto, func, args);
        const end_time = std.time.nanoTimestamp();
        
        const duration = @as(u64, @intCast(end_time - start_time));
        try self.recordMetric(name, duration);
        
        return result;
    }
    
    fn recordMetric(self: *@This(), name: []const u8, duration_ns: u64) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        
        const result = try self.metrics.getOrPut(owned_name);
        if (result.found_existing) {
            result.value_ptr.update(duration_ns);
        } else {
            result.value_ptr.* = Metric{
                .count = 1,
                .total_time_ns = duration_ns,
                .min_time_ns = duration_ns,
                .max_time_ns = duration_ns,
            };
        }
    }
    
    pub fn printReport(self: *@This()) !void {
        var future = try self.io.async_write("Performance Report:\n");
        defer future.destroy(self.allocator);
        try future.await();
        
        var iterator = self.metrics.iterator();
        while (iterator.next()) |entry| {
            const metric = entry.value_ptr.*;
            const report = try std.fmt.allocPrint(self.allocator,
                "{s}: count={}, avg={}ns, min={}ns, max={}ns\n",
                .{ entry.key_ptr.*, metric.count, metric.averageTimeNs(), metric.min_time_ns, metric.max_time_ns }
            );
            defer self.allocator.free(report);
            
            var report_future = try self.io.async_write(report);
            defer report_future.destroy(self.allocator);
            try report_future.await();
        }
    }
};
```

## Complete Example

```zig
const std = @import("std");
const zsync = @import("zsync");

pub fn main() !void {
    try zsync.runHighPerf(zekeExample);
}

fn zekeExample(io: zsync.Io) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    // Initialize ZEKE components
    var network = try NetworkClient.init(gpa.allocator());
    defer network.deinit();
    
    var processor = try FileProcessor.init(gpa.allocator(), io);
    defer processor.deinit();
    
    var monitor = try PerformanceMonitor.init(gpa.allocator(), io);
    defer monitor.deinit();
    
    // Example operations
    const urls = &.{
        "https://api.github.com/repos/ziglang/zig/releases/latest",
        "https://api.github.com/repos/microsoft/TypeScript/releases/latest",
        "https://api.github.com/repos/rust-lang/rust/releases/latest",
    };
    
    const responses = try monitor.time("network_requests", network.concurrentRequests, .{urls});
    defer {
        for (responses) |response| {
            gpa.allocator().free(response);
        }
        gpa.allocator().free(responses);
    }
    
    std.log.info("ZEKE: Fetched {} API responses", .{responses.len});
    
    // Print performance report
    try monitor.printReport();
    
    std.log.info("ZEKE: Example completed successfully!");
}
```

This integration provides ZEKE with:
- High-performance async I/O operations
- Concurrent network and file processing
- Real-time data handling capabilities
- Terminal UI with smooth rendering
- Task coordination and cancellation
- Performance monitoring and metrics
- Easy integration via `zig fetch`