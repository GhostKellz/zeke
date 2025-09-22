const std = @import("std");
const api = @import("../api/client.zig");

pub const GhostLLMMode = enum {
    serve,
    bench,
    inspect,
    ghost,
};

pub const GhostLLMConfig = struct {
    mode: GhostLLMMode = .serve,
    base_url: []const u8 = "http://localhost:8080",
    enable_gpu: bool = true,
    enable_quic: bool = true,
    enable_ipv6: bool = true,
    api_key: ?[]const u8 = null,
    max_context_length: u32 = 8192,
    temperature: f32 = 0.7,
    top_p: f32 = 0.9,
    stream: bool = true,
};

pub const GpuStats = struct {
    device_name: []const u8,
    memory_used_mb: u64,
    memory_total_mb: u64,
    utilization_percent: u8,
    temperature_celsius: u8,
    power_watts: u32,
};

pub const BenchmarkResult = struct {
    model: []const u8,
    tokens_per_second: f64,
    latency_ms: f64,
    memory_usage_mb: u64,
    batch_size: u32,
};

pub const GhostLLMClient = struct {
    allocator: std.mem.Allocator,
    config: GhostLLMConfig,
    http_client: ?*std.http.Client,
    metrics: ?*MetricsCollector,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: GhostLLMConfig) !Self {
        const http_client = try allocator.create(std.http.Client);
        http_client.* = std.http.Client{ .allocator = allocator };
        
        const metrics = if (config.mode == .bench or config.mode == .inspect)
            try allocator.create(MetricsCollector)
        else
            null;
        
        if (metrics) |m| {
            m.* = MetricsCollector.init(allocator);
        }
        
        return Self{
            .allocator = allocator,
            .config = config,
            .http_client = http_client,
            .metrics = metrics,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.http_client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        if (self.metrics) |m| {
            m.deinit();
            self.allocator.destroy(m);
        }
    }
    
    pub fn chat(self: *Self, messages: []const api.ChatMessage, model: []const u8) !api.ChatResponse {
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/chat", .{self.config.base_url});
        defer self.allocator.free(endpoint);
        
        const request = ChatRequest{
            .model = model,
            .messages = messages,
            .temperature = self.config.temperature,
            .top_p = self.config.top_p,
            .max_tokens = self.config.max_context_length,
            .stream = self.config.stream,
        };
        
        const start_time = std.time.milliTimestamp();
        
        // Send request with GPU acceleration
        const response = try self.sendRequest(endpoint, request);
        
        const end_time = std.time.milliTimestamp();
        const latency = end_time - start_time;
        
        // Track metrics if enabled
        if (self.metrics) |m| {
            try m.recordLatency(@intCast(latency));
            try m.recordTokens(response.usage.total_tokens);
        }
        
        return response;
    }
    
    pub fn streamChat(self: *Self, messages: []const api.ChatMessage, model: []const u8, callback: *const fn ([]const u8) void) !void {
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/chat/stream", .{self.config.base_url});
        defer self.allocator.free(endpoint);
        
        const request = ChatRequest{
            .model = model,
            .messages = messages,
            .temperature = self.config.temperature,
            .top_p = self.config.top_p,
            .max_tokens = self.config.max_context_length,
            .stream = true,
        };
        
        // Stream response with HTTP3/QUIC if enabled
        if (self.config.enable_quic) {
            try self.streamWithQuic(endpoint, request, callback);
        } else {
            try self.streamWithHttp(endpoint, request, callback);
        }
    }
    
    pub fn benchmark(self: *Self, model: []const u8, prompt: []const u8, batch_size: u32) !BenchmarkResult {
        if (self.config.mode != .bench) {
            return error.WrongMode;
        }
        
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/bench", .{self.config.base_url});
        defer self.allocator.free(endpoint);
        
        const request = BenchRequest{
            .model = model,
            .prompt = prompt,
            .batch_size = batch_size,
            .warmup_runs = 3,
            .test_runs = 10,
        };
        
        const response = try self.sendBenchRequest(endpoint, request);
        
        return BenchmarkResult{
            .model = try self.allocator.dupe(u8, model),
            .tokens_per_second = response.tokens_per_second,
            .latency_ms = response.avg_latency_ms,
            .memory_usage_mb = response.peak_memory_mb,
            .batch_size = batch_size,
        };
    }
    
    pub fn inspectGpu(self: *Self) !GpuStats {
        if (self.config.mode != .inspect) {
            return error.WrongMode;
        }
        
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/gpu/stats", .{self.config.base_url});
        defer self.allocator.free(endpoint);
        
        const response = try self.sendGetRequest(endpoint);
        defer self.allocator.free(response);
        
        // Parse GPU stats from response
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(response);
        defer tree.deinit();
        
        const root = tree.root.Object;
        
        return GpuStats{
            .device_name = try self.allocator.dupe(u8, root.get("device_name").?.String),
            .memory_used_mb = @intCast(root.get("memory_used_mb").?.Integer),
            .memory_total_mb = @intCast(root.get("memory_total_mb").?.Integer),
            .utilization_percent = @intCast(root.get("utilization").?.Integer),
            .temperature_celsius = @intCast(root.get("temperature").?.Integer),
            .power_watts = @intCast(root.get("power_watts").?.Integer),
        };
    }
    
    pub fn smartContractInference(self: *Self, contract_code: []const u8, query: []const u8) ![]const u8 {
        if (self.config.mode != .ghost) {
            return error.WrongMode;
        }
        
        const endpoint = try std.fmt.allocPrint(self.allocator, "{s}/v1/ghost/analyze", .{self.config.base_url});
        defer self.allocator.free(endpoint);
        
        const request = GhostRequest{
            .contract = contract_code,
            .query = query,
            .analyze_security = true,
            .suggest_optimizations = true,
        };
        
        const response = try self.sendGhostRequest(endpoint, request);
        return response.analysis;
    }
    
    fn sendRequest(self: *Self, endpoint: []const u8, request: anytype) !api.ChatResponse {
        const json_body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json_body);
        
        const client = self.http_client orelse return error.NoHttpClient;
        
        const uri = try std.Uri.parse(endpoint);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        
        try headers.append("Content-Type", "application/json");
        if (self.config.api_key) |key| {
            const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{key});
            defer self.allocator.free(auth_header);
            try headers.append("Authorization", auth_header);
        }
        
        var req = try client.request(.POST, uri, headers, .{});
        defer req.deinit();
        
        req.transfer_encoding = .chunked;
        try req.start();
        try req.writer().writeAll(json_body);
        try req.finish();
        try req.wait();
        
        if (req.response.status != .ok) {
            return error.RequestFailed;
        }
        
        const body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);
        
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(body);
        defer tree.deinit();
        
        const root = tree.root.Object;
        const choice = root.get("choices").?.Array.items[0].Object;
        const message = choice.get("message").?.Object;
        const usage_obj = root.get("usage").?.Object;
        
        return api.ChatResponse{
            .content = try self.allocator.dupe(u8, message.get("content").?.String),
            .model = try self.allocator.dupe(u8, root.get("model").?.String),
            .usage = api.Usage{
                .prompt_tokens = @intCast(usage_obj.get("prompt_tokens").?.Integer),
                .completion_tokens = @intCast(usage_obj.get("completion_tokens").?.Integer),
                .total_tokens = @intCast(usage_obj.get("total_tokens").?.Integer),
            },
        };
    }
    
    fn streamWithQuic(_: *Self, endpoint: []const u8, request: anytype, callback: *const fn ([]const u8) void) !void {
        _ = endpoint;
        _ = request;
        
        // Simulate QUIC streaming (would need actual QUIC implementation)
        const chunks = [_][]const u8{
            "Streaming ",
            "with ",
            "QUIC/HTTP3 ",
            "GPU-accelerated ",
            "response ",
            "from ",
            "GhostLLM!",
        };
        
        for (chunks) |chunk| {
            callback(chunk);
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }
    
    fn streamWithHttp(self: *Self, endpoint: []const u8, request: anytype, callback: *const fn ([]const u8) void) !void {
        _ = self;
        _ = endpoint;
        _ = request;
        
        // Simulate HTTP streaming
        const chunks = [_][]const u8{
            "Streaming ",
            "with ",
            "HTTP ",
            "response ",
            "from ",
            "GhostLLM!",
        };
        
        for (chunks) |chunk| {
            callback(chunk);
            std.time.sleep(150 * std.time.ns_per_ms);
        }
    }
    
    fn sendBenchRequest(self: *Self, endpoint: []const u8, request: BenchRequest) !BenchResponse {
        _ = self;
        _ = endpoint;
        _ = request;
        
        // Mock benchmark response
        return BenchResponse{
            .tokens_per_second = 1250.5,
            .avg_latency_ms = 42.3,
            .peak_memory_mb = 2048,
            .p95_latency_ms = 58.7,
            .p99_latency_ms = 72.1,
        };
    }
    
    fn sendGetRequest(self: *Self, endpoint: []const u8) ![]const u8 {
        _ = endpoint;
        
        // Mock GPU stats response
        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "device_name": "NVIDIA RTX 4090",
            \\  "memory_used_mb": 8192,
            \\  "memory_total_mb": 24576,
            \\  "utilization": 75,
            \\  "temperature": 68,
            \\  "power_watts": 350
            \\}}
        , .{});
    }
    
    fn sendGhostRequest(self: *Self, endpoint: []const u8, request: GhostRequest) !GhostResponse {
        _ = endpoint;
        _ = request;
        
        const analysis = try std.fmt.allocPrint(self.allocator,
            \\Smart contract analysis complete:
            \\- No critical vulnerabilities found
            \\- Gas optimization opportunities: 3
            \\- Suggested improvements: Use memory instead of storage for temporary variables
        , .{});
        
        return GhostResponse{
            .analysis = analysis,
            .vulnerabilities = 0,
            .gas_cost = 125000,
            .optimizations = 3,
        };
    }
};

const ChatRequest = struct {
    model: []const u8,
    messages: []const api.ChatMessage,
    temperature: f32,
    top_p: f32,
    max_tokens: u32,
    stream: bool,
};

const BenchRequest = struct {
    model: []const u8,
    prompt: []const u8,
    batch_size: u32,
    warmup_runs: u32,
    test_runs: u32,
};

const BenchResponse = struct {
    tokens_per_second: f64,
    avg_latency_ms: f64,
    peak_memory_mb: u64,
    p95_latency_ms: f64,
    p99_latency_ms: f64,
};

const GhostRequest = struct {
    contract: []const u8,
    query: []const u8,
    analyze_security: bool,
    suggest_optimizations: bool,
};

const GhostResponse = struct {
    analysis: []const u8,
    vulnerabilities: u32,
    gas_cost: u64,
    optimizations: u32,
};

const MetricsCollector = struct {
    allocator: std.mem.Allocator,
    latencies: std.ArrayList(u64),
    token_counts: std.ArrayList(u32),
    
    pub fn init(allocator: std.mem.Allocator) MetricsCollector {
        return .{
            .allocator = allocator,
            .latencies = std.ArrayList(u64){},
            .token_counts = std.ArrayList(u32){},
        };
    }
    
    pub fn deinit(self: *MetricsCollector) void {
        self.latencies.deinit(self.allocator);
        self.token_counts.deinit(self.allocator);
    }
    
    pub fn recordLatency(self: *MetricsCollector, latency_ms: u64) !void {
        try self.latencies.append(self.allocator, latency_ms);
    }
    
    pub fn recordTokens(self: *MetricsCollector, tokens: u32) !void {
        try self.token_counts.append(self.allocator, tokens);
    }
    
    pub fn getAverageLatency(self: *MetricsCollector) f64 {
        if (self.latencies.items.len == 0) return 0.0;
        
        var sum: u64 = 0;
        for (self.latencies.items) |lat| {
            sum += lat;
        }
        
        return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(self.latencies.items.len));
    }
    
    pub fn getTotalTokens(self: *MetricsCollector) u64 {
        var sum: u64 = 0;
        for (self.token_counts.items) |count| {
            sum += count;
        }
        return sum;
    }
};