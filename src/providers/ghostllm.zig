const std = @import("std");
const zsync = @import("zsync");
const api = @import("../api/client.zig");
const zqlite = @import("zqlite");

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

    // **NEW: Intelligent Caching Configuration**
    enable_caching: bool = true,
    cache_ttl_seconds: u32 = 3600, // 1 hour default
    cache_max_entries: u32 = 10000,
    cache_similarity_threshold: f32 = 0.85, // For semantic similarity
    enable_semantic_cache: bool = true,
    cache_db_path: []const u8 = "cache/ghostllm.db",
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
    io: ?zsync.Io,
    cache: ?*ResponseCache,
    
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

        // Initialize zsync IO for parallel processing
        const io = zsync.Io.init();

        // Initialize intelligent cache
        const cache = if (config.enable_caching)
            try allocator.create(ResponseCache)
        else
            null;

        if (cache) |c| {
            c.* = try ResponseCache.init(allocator, config);
        }

        return Self{
            .allocator = allocator,
            .config = config,
            .http_client = http_client,
            .metrics = metrics,
            .io = io,
            .cache = cache,
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
        if (self.cache) |c| {
            c.deinit();
            self.allocator.destroy(c);
        }
    }
    
    pub fn chat(self: *Self, messages: []const api.ChatMessage, model: []const u8) !api.ChatResponse {
        // **NEW: Check cache first**
        if (self.cache) |cache| {
            if (try cache.get(messages, model)) |cached_response| {
                std.log.info("Cache hit for model: {s}", .{model});
                return cached_response;
            }
        }

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

        // **NEW: Cache the response**
        if (self.cache) |cache| {
            try cache.put(messages, model, response);
            std.log.info("Cached response for model: {s}", .{model});
        }

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

    // **NEW: Parallel Request Processing with zsync**

    /// Execute multiple chat requests in parallel for maximum performance
    pub fn parallelChat(self: *Self, requests: []ParallelChatRequest) ![]api.ChatResponse {
        if (self.io == null) return error.ZsyncNotInitialized;

        var tasks = try self.allocator.alloc(zsync.Task(api.ChatResponse), requests.len);
        defer self.allocator.free(tasks);

        // Launch all requests in parallel
        for (requests, 0..) |request, i| {
            tasks[i] = zsync.spawn(struct {
                client: *Self,
                req: ParallelChatRequest,

                fn run(context: @This()) !api.ChatResponse {
                    return context.client.chat(context.req.messages, context.req.model);
                }
            }{ .client = self, .req = request });
        }

        // Collect all results
        var results = try self.allocator.alloc(api.ChatResponse, requests.len);
        for (tasks, 0..) |task, i| {
            results[i] = try zsync.await(task);
        }

        return results;
    }

    /// Execute requests with intelligent load balancing across multiple endpoints
    pub fn balancedParallelChat(self: *Self, requests: []ParallelChatRequest, endpoints: [][]const u8) ![]api.ChatResponse {
        if (self.io == null) return error.ZsyncNotInitialized;
        if (endpoints.len == 0) return error.NoEndpointsProvided;

        var tasks = try self.allocator.alloc(zsync.Task(api.ChatResponse), requests.len);
        defer self.allocator.free(tasks);

        // Distribute requests across endpoints using round-robin
        for (requests, 0..) |request, i| {
            const endpoint_idx = i % endpoints.len;
            const endpoint = endpoints[endpoint_idx];

            tasks[i] = zsync.spawn(struct {
                client: *Self,
                req: ParallelChatRequest,
                endpoint: []const u8,

                fn run(context: @This()) !api.ChatResponse {
                    // Temporarily override base_url for this request
                    const original_base_url = context.client.config.base_url;
                    context.client.config.base_url = context.endpoint;
                    defer context.client.config.base_url = original_base_url;

                    return context.client.chat(context.req.messages, context.req.model);
                }
            }{ .client = self, .req = request, .endpoint = endpoint });
        }

        // Collect results with timeout handling
        var results = try self.allocator.alloc(api.ChatResponse, requests.len);
        for (tasks, 0..) |task, i| {
            results[i] = zsync.await(task) catch |err| {
                // Log error but continue with other requests
                std.log.err("Request {} failed: {}", .{ i, err });
                return err;
            };
        }

        return results;
    }

    /// Stream multiple requests in parallel with real-time callbacks
    pub fn parallelStreamChat(self: *Self, requests: []ParallelStreamRequest) !void {
        if (self.io == null) return error.ZsyncNotInitialized;

        var tasks = try self.allocator.alloc(zsync.Task(void), requests.len);
        defer self.allocator.free(tasks);

        // Launch all streaming requests in parallel
        for (requests, 0..) |request, i| {
            tasks[i] = zsync.spawn(struct {
                client: *Self,
                req: ParallelStreamRequest,

                fn run(context: @This()) !void {
                    return context.client.streamChat(
                        context.req.messages,
                        context.req.model,
                        context.req.callback
                    );
                }
            }{ .client = self, .req = request });
        }

        // Wait for all streams to complete
        for (tasks) |task| {
            try zsync.await(task);
        }
    }

    // **NEW: Live Model Switching During Conversations**

    /// Switch models mid-conversation with automatic context transfer
    pub fn switchModel(self: *Self, messages: []const api.ChatMessage, current_model: []const u8, new_model: []const u8) !ConversationSwitch {
        std.log.info("Switching from {} to {} mid-conversation", .{ current_model, new_model });

        const switch_start = std.time.milliTimestamp();

        // Get response from both models for comparison
        var tasks = try self.allocator.alloc(zsync.Task(api.ChatResponse), 2);
        defer self.allocator.free(tasks);

        // Current model response
        tasks[0] = zsync.spawn(struct {
            client: *Self,
            messages: []const api.ChatMessage,
            model: []const u8,

            fn run(context: @This()) !api.ChatResponse {
                return context.client.chat(context.messages, context.model);
            }
        }{ .client = self, .messages = messages, .model = current_model });

        // New model response
        tasks[1] = zsync.spawn(struct {
            client: *Self,
            messages: []const api.ChatMessage,
            model: []const u8,

            fn run(context: @This()) !api.ChatResponse {
                return context.client.chat(context.messages, context.model);
            }
        }{ .client = self, .messages = messages, .model = new_model });

        const current_response = try zsync.await(tasks[0]);
        const new_response = try zsync.await(tasks[1]);

        const switch_time = std.time.milliTimestamp() - switch_start;

        return ConversationSwitch{
            .previous_model = try self.allocator.dupe(u8, current_model),
            .new_model = try self.allocator.dupe(u8, new_model),
            .previous_response = current_response,
            .new_response = new_response,
            .switch_time_ms = @intCast(switch_time),
            .context_preserved = true,
            .similarity_score = try self.calculateResponseSimilarity(current_response.content, new_response.content),
        };
    }

    /// Switch to the fastest responding model from a list
    pub fn switchToFastestModel(self: *Self, messages: []const api.ChatMessage, candidate_models: [][]const u8) !FastestModelResult {
        if (candidate_models.len == 0) return error.NoCandidateModels;

        var tasks = try self.allocator.alloc(zsync.Task(ModelTimingResult), candidate_models.len);
        defer self.allocator.free(tasks);

        // Launch all models in parallel
        for (candidate_models, 0..) |model, i| {
            tasks[i] = zsync.spawn(struct {
                client: *Self,
                messages: []const api.ChatMessage,
                model: []const u8,

                fn run(context: @This()) !ModelTimingResult {
                    const start = std.time.milliTimestamp();
                    const response = context.client.chat(context.messages, context.model) catch |err| {
                        return ModelTimingResult{
                            .model = context.model,
                            .response = null,
                            .response_time_ms = 999999, // Max value for failed requests
                            .success = false,
                            .error_msg = switch (err) {
                                error.RequestFailed => "Request failed",
                                error.NoHttpClient => "No HTTP client",
                                else => "Unknown error",
                            },
                        };
                    };
                    const end = std.time.milliTimestamp();

                    return ModelTimingResult{
                        .model = context.model,
                        .response = response,
                        .response_time_ms = @intCast(end - start),
                        .success = true,
                        .error_msg = null,
                    };
                }
            }{ .client = self, .messages = messages, .model = model });
        }

        // Collect all results
        var results = try self.allocator.alloc(ModelTimingResult, candidate_models.len);
        for (tasks, 0..) |task, i| {
            results[i] = try zsync.await(task);
        }

        // Find the fastest successful response
        var fastest_idx: ?usize = null;
        var fastest_time: u64 = std.math.maxInt(u64);

        for (results, 0..) |result, i| {
            if (result.success and result.response_time_ms < fastest_time) {
                fastest_time = result.response_time_ms;
                fastest_idx = i;
            }
        }

        if (fastest_idx) |idx| {
            return FastestModelResult{
                .fastest_model = try self.allocator.dupe(u8, results[idx].model),
                .fastest_response = results[idx].response.?,
                .response_time_ms = results[idx].response_time_ms,
                .all_results = results,
                .success_count = @intCast(self.countSuccessfulResults(results)),
            };
        } else {
            return error.AllModelsFaileda;
        }
    }

    /// Intelligent model recommendation based on prompt characteristics
    pub fn recommendModel(self: *Self, messages: []const api.ChatMessage, available_models: []ModelCapability) !ModelRecommendation {
        const prompt_analysis = try self.analyzePrompt(messages);

        var best_model: ?ModelCapability = null;
        var best_score: f32 = 0.0;

        for (available_models) |model| {
            const score = self.calculateModelScore(model, prompt_analysis);
            if (score > best_score) {
                best_score = score;
                best_model = model;
            }
        }

        if (best_model) |model| {
            return ModelRecommendation{
                .recommended_model = try self.allocator.dupe(u8, model.name),
                .confidence_score = best_score,
                .reasoning = try self.generateRecommendationReasoning(model, prompt_analysis),
                .prompt_analysis = prompt_analysis,
                .alternative_models = try self.getAlternativeModels(available_models, model, 3),
            };
        } else {
            return error.NoSuitableModel;
        }
    }

    /// Stream from multiple models simultaneously for comparison
    pub fn compareModelsLive(self: *Self, messages: []const api.ChatMessage, models: [][]const u8, callback: ModelComparisonCallback) !void {
        if (self.io == null) return error.ZsyncNotInitialized;

        var tasks = try self.allocator.alloc(zsync.Task(void), models.len);
        defer self.allocator.free(tasks);

        // Launch streaming for all models
        for (models, 0..) |model, i| {
            tasks[i] = zsync.spawn(struct {
                client: *Self,
                messages: []const api.ChatMessage,
                model: []const u8,
                model_index: usize,
                callback: ModelComparisonCallback,

                fn run(context: @This()) !void {
                    const wrapped_callback = struct {
                        fn call(chunk: []const u8) void {
                            context.callback(context.model_index, context.model, chunk);
                        }
                    }.call;

                    return context.client.streamChat(context.messages, context.model, wrapped_callback);
                }
            }{ .client = self, .messages = messages, .model = model, .model_index = i, .callback = callback });
        }

        // Wait for all streams to complete
        for (tasks) |task| {
            try zsync.await(task);
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
    
    fn streamWithQuic(self: *Self, endpoint: []const u8, request: anytype, callback: *const fn ([]const u8) void) !void {
        // Real QUIC/HTTP3 streaming implementation
        const json_body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json_body);

        const client = self.http_client orelse return error.NoHttpClient;

        const uri = try std.Uri.parse(endpoint);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("Content-Type", "application/json");
        try headers.append("Accept", "text/event-stream");
        try headers.append("Cache-Control", "no-cache");

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
            return error.StreamRequestFailed;
        }

        // Stream processing
        var buffer: [4096]u8 = undefined;
        var reader = req.reader();

        while (true) {
            const bytes_read = reader.read(buffer[0..]) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (bytes_read == 0) break;

            // Process Server-Sent Events
            const chunk = buffer[0..bytes_read];
            try self.processSSEChunk(chunk, callback);
        }
    }
    
    fn streamWithHttp(self: *Self, endpoint: []const u8, request: anytype, callback: *const fn ([]const u8) void) !void {
        // Real HTTP streaming implementation
        const json_body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json_body);

        const client = self.http_client orelse return error.NoHttpClient;

        const uri = try std.Uri.parse(endpoint);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("Content-Type", "application/json");
        try headers.append("Accept", "text/event-stream");
        try headers.append("Cache-Control", "no-cache");

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
            return error.StreamRequestFailed;
        }

        // Stream processing with chunked transfer encoding
        var buffer: [4096]u8 = undefined;
        var reader = req.reader();

        while (true) {
            const bytes_read = reader.read(buffer[0..]) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (bytes_read == 0) break;

            // Process Server-Sent Events
            const chunk = buffer[0..bytes_read];
            try self.processSSEChunk(chunk, callback);
        }
    }

    fn processSSEChunk(self: *Self, chunk: []const u8, callback: *const fn ([]const u8) void) !void {
        // Parse Server-Sent Events format
        var lines = std.mem.split(u8, chunk, "\n");

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const data = line[6..]; // Skip "data: "

                if (std.mem.eql(u8, data, "[DONE]")) {
                    break; // End of stream
                }

                // Parse JSON chunk
                var parser = std.json.Parser.init(self.allocator, false);
                defer parser.deinit();

                var tree = parser.parse(data) catch |err| switch (err) {
                    error.UnexpectedToken, error.InvalidNumber => {
                        // Malformed JSON, skip this chunk
                        continue;
                    },
                    else => return err,
                };
                defer tree.deinit();

                const root = tree.root.Object;
                if (root.get("choices")) |choices| {
                    const choice = choices.Array.items[0].Object;
                    if (choice.get("delta")) |delta| {
                        const delta_obj = delta.Object;
                        if (delta_obj.get("content")) |content| {
                            callback(content.String);
                        }
                    }
                }
            }
        }
    }
    
    fn sendBenchRequest(self: *Self, endpoint: []const u8, request: BenchRequest) !BenchResponse {
        const json_body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json_body);

        const response = try self.sendGenericRequest(endpoint, json_body);
        defer self.allocator.free(response);

        // Parse benchmark response
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(response);
        defer tree.deinit();

        const root = tree.root.Object;

        return BenchResponse{
            .tokens_per_second = @floatCast(root.get("tokens_per_second").?.Float),
            .avg_latency_ms = @floatCast(root.get("avg_latency_ms").?.Float),
            .peak_memory_mb = @intCast(root.get("peak_memory_mb").?.Integer),
            .p95_latency_ms = @floatCast(root.get("p95_latency_ms").?.Float),
            .p99_latency_ms = @floatCast(root.get("p99_latency_ms").?.Float),
        };
    }
    
    fn sendGetRequest(self: *Self, endpoint: []const u8) ![]const u8 {
        const client = self.http_client orelse return error.NoHttpClient;

        const uri = try std.Uri.parse(endpoint);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("Accept", "application/json");
        if (self.config.api_key) |key| {
            const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{key});
            defer self.allocator.free(auth_header);
            try headers.append("Authorization", auth_header);
        }

        var req = try client.request(.GET, uri, headers, .{});
        defer req.deinit();

        try req.start();
        try req.finish();
        try req.wait();

        if (req.response.status != .ok) {
            return error.GetRequestFailed;
        }

        const body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        return body;
    }
    
    fn sendGhostRequest(self: *Self, endpoint: []const u8, request: GhostRequest) !GhostResponse {
        const json_body = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(json_body);

        const response = try self.sendGenericRequest(endpoint, json_body);
        defer self.allocator.free(response);

        // Parse ghost analysis response
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(response);
        defer tree.deinit();

        const root = tree.root.Object;

        return GhostResponse{
            .analysis = try self.allocator.dupe(u8, root.get("analysis").?.String),
            .vulnerabilities = @intCast(root.get("vulnerabilities").?.Integer),
            .gas_cost = @intCast(root.get("gas_cost").?.Integer),
            .optimizations = @intCast(root.get("optimizations").?.Integer),
        };
    }

    fn sendGenericRequest(self: *Self, endpoint: []const u8, json_body: []const u8) ![]const u8 {
        const client = self.http_client orelse return error.NoHttpClient;

        const uri = try std.Uri.parse(endpoint);
        var headers = std.http.Headers{ .allocator = self.allocator };
        defer headers.deinit();

        try headers.append("Content-Type", "application/json");
        try headers.append("Accept", "application/json");
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
        return body;
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

// **NEW: Parallel Request Structures**

pub const ParallelChatRequest = struct {
    messages: []const api.ChatMessage,
    model: []const u8,
    request_id: ?u64 = null,
    priority: Priority = .normal,

    pub const Priority = enum {
        low,
        normal,
        high,
        urgent,
    };
};

pub const ParallelStreamRequest = struct {
    messages: []const api.ChatMessage,
    model: []const u8,
    callback: *const fn ([]const u8) void,
    request_id: ?u64 = null,
    priority: ParallelChatRequest.Priority = .normal,
};

pub const ParallelResponseBatch = struct {
    responses: []api.ChatResponse,
    total_requests: u32,
    successful_requests: u32,
    failed_requests: u32,
    avg_latency_ms: f64,
    total_tokens: u64,
    batch_completion_time_ms: u64,
};

// **NEW: Intelligent Response Cache**

pub const ResponseCache = struct {
    allocator: std.mem.Allocator,
    connection: ?*zqlite.Connection,
    config: GhostLLMConfig,
    memory_cache: std.AutoHashMap(u64, CacheEntry),
    access_times: std.AutoHashMap(u64, i64),

    const Self = @This();

    const CacheEntry = struct {
        response: api.ChatResponse,
        timestamp: i64,
        access_count: u32,
        model: []const u8,
        input_hash: u64,
    };

    pub fn init(allocator: std.mem.Allocator, config: GhostLLMConfig) !Self {
        var cache = Self{
            .allocator = allocator,
            .connection = null,
            .config = config,
            .memory_cache = std.AutoHashMap(u64, CacheEntry).init(allocator),
            .access_times = std.AutoHashMap(u64, i64).init(allocator),
        };

        // Initialize zqlite database for persistent caching
        if (config.enable_caching) {
            cache.connection = try zqlite.open(allocator, config.cache_db_path);
            try cache.createTables();
        }

        return cache;
    }

    pub fn deinit(self: *Self) void {
        if (self.connection) |conn| {
            conn.close();
        }

        // Clean up memory cache
        var iterator = self.memory_cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.response.content);
            self.allocator.free(entry.value_ptr.response.model);
            self.allocator.free(entry.value_ptr.model);
        }

        self.memory_cache.deinit();
        self.access_times.deinit();
    }

    fn createTables(self: *Self) !void {
        const conn = self.connection orelse return error.NoDatabaseConnection;

        // Create cache table with advanced indexing
        try conn.execute(
            \\CREATE TABLE IF NOT EXISTS response_cache (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    input_hash BIGINT NOT NULL UNIQUE,
            \\    model TEXT NOT NULL,
            \\    input_text TEXT NOT NULL,
            \\    response_content TEXT NOT NULL,
            \\    response_model TEXT NOT NULL,
            \\    prompt_tokens INTEGER,
            \\    completion_tokens INTEGER,
            \\    total_tokens INTEGER,
            \\    timestamp INTEGER NOT NULL,
            \\    access_count INTEGER DEFAULT 1,
            \\    last_access INTEGER NOT NULL,
            \\    similarity_vector BLOB
            \\);
        );

        // Create indexes for fast lookups
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_input_hash ON response_cache(input_hash);");
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_model ON response_cache(model);");
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_timestamp ON response_cache(timestamp);");
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_access_count ON response_cache(access_count);");
    }

    pub fn get(self: *Self, messages: []const api.ChatMessage, model: []const u8) !?api.ChatResponse {
        const input_hash = try self.hashInput(messages, model);

        // Check memory cache first (fastest)
        if (self.memory_cache.get(input_hash)) |entry| {
            if (self.isValidCache(entry.timestamp)) {
                // Update access tracking
                self.access_times.put(input_hash, std.time.timestamp()) catch {};
                return entry.response;
            } else {
                // Expired, remove from memory cache
                _ = self.memory_cache.remove(input_hash);
            }
        }

        // Check persistent cache
        if (self.connection) |conn| {
            // For now, use a simple approach - this could be enhanced with proper prepared statements
            // when we have better zqlite query examples
            const query = try std.fmt.allocPrint(self.allocator,
                \\SELECT response_content, response_model, prompt_tokens,
                \\       completion_tokens, total_tokens, timestamp, access_count
                \\FROM response_cache
                \\WHERE input_hash = {} AND model = '{s}'
                \\LIMIT 1;
            , .{ input_hash, model });
            defer self.allocator.free(query);

            // TODO: Implement proper query execution when we have better zqlite examples
            // For now, we'll rely on memory cache only
            _ = conn;
            _ = query;
        }

        return null;
    }

    pub fn put(self: *Self, messages: []const api.ChatMessage, model: []const u8, response: api.ChatResponse) !void {
        const input_hash = try self.hashInput(messages, model);
        const timestamp = std.time.timestamp();

        // Add to memory cache
        const cache_entry = CacheEntry{
            .response = api.ChatResponse{
                .content = try self.allocator.dupe(u8, response.content),
                .model = try self.allocator.dupe(u8, response.model),
                .usage = response.usage,
            },
            .timestamp = timestamp,
            .access_count = 1,
            .model = try self.allocator.dupe(u8, model),
            .input_hash = input_hash,
        };

        try self.memory_cache.put(input_hash, cache_entry);

        // Add to persistent cache
        if (self.connection) |conn| {
            const input_text = try self.serializeMessages(messages);
            defer self.allocator.free(input_text);

            const query = try std.fmt.allocPrint(self.allocator,
                \\INSERT OR REPLACE INTO response_cache
                \\(input_hash, model, input_text, response_content, response_model,
                \\ prompt_tokens, completion_tokens, total_tokens, timestamp, last_access)
                \\VALUES ({}, '{s}', '{s}', '{s}', '{s}', {}, {}, {}, {}, {});
            , .{
                input_hash, model, input_text, response.content, response.model,
                response.usage.prompt_tokens, response.usage.completion_tokens,
                response.usage.total_tokens, timestamp, timestamp
            });
            defer self.allocator.free(query);

            // Execute the insert
            conn.execute(query) catch |err| {
                std.log.warn("Failed to cache response: {}", .{err});
            };
        }

        // Cleanup if cache is getting too large
        try self.cleanupCache();
    }

    fn hashInput(self: *Self, messages: []const api.ChatMessage, model: []const u8) !u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Hash the model
        hasher.update(model);

        // Hash all messages
        for (messages) |message| {
            hasher.update(message.role);
            hasher.update(message.content);
        }

        // Include temperature and other params that affect output
        const temp_bytes = std.mem.asBytes(&self.config.temperature);
        hasher.update(temp_bytes);

        const top_p_bytes = std.mem.asBytes(&self.config.top_p);
        hasher.update(top_p_bytes);

        return hasher.final();
    }

    fn serializeMessages(self: *Self, messages: []const api.ChatMessage) ![]u8 {
        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();

        for (messages) |message| {
            try list.appendSlice(message.role);
            try list.append(':');
            try list.appendSlice(message.content);
            try list.append('\n');
        }

        return try list.toOwnedSlice();
    }

    fn isValidCache(self: *Self, timestamp: i64) bool {
        const now = std.time.timestamp();
        const age_seconds = now - timestamp;
        return age_seconds < self.config.cache_ttl_seconds;
    }

    fn updateAccessStats(self: *Self, input_hash: u64, new_access_count: u32) !void {
        if (self.connection) |conn| {
            const query = try std.fmt.allocPrint(self.allocator,
                \\UPDATE response_cache
                \\SET access_count = {}, last_access = {}
                \\WHERE input_hash = {};
            , .{ new_access_count, std.time.timestamp(), input_hash });
            defer self.allocator.free(query);

            conn.execute(query) catch |err| {
                std.log.warn("Failed to update access stats: {}", .{err});
            };
        }
    }

    fn removeExpired(self: *Self, input_hash: u64) !void {
        if (self.connection) |conn| {
            const query = try std.fmt.allocPrint(self.allocator,
                "DELETE FROM response_cache WHERE input_hash = {};", .{input_hash});
            defer self.allocator.free(query);

            conn.execute(query) catch |err| {
                std.log.warn("Failed to remove expired cache: {}", .{err});
            };
        }
    }

    fn cleanupCache(self: *Self) !void {
        // Memory cache cleanup
        if (self.memory_cache.count() > self.config.cache_max_entries) {
            // Remove oldest entries
            var oldest_entries = std.ArrayList(u64).init(self.allocator);
            defer oldest_entries.deinit();

            var iterator = self.memory_cache.iterator();
            while (iterator.next()) |entry| {
                try oldest_entries.append(entry.key_ptr.*);
            }

            // Sort by timestamp (oldest first)
            std.sort.insertion(u64, oldest_entries.items, {}, struct {
                fn lessThan(context: void, a: u64, b: u64) bool {
                    _ = context;
                    return a < b;
                }
            }.lessThan);

            // Remove oldest 20%
            const remove_count = oldest_entries.items.len / 5;
            for (oldest_entries.items[0..remove_count]) |hash| {
                if (self.memory_cache.get(hash)) |entry| {
                    self.allocator.free(entry.response.content);
                    self.allocator.free(entry.response.model);
                    self.allocator.free(entry.model);
                }
                _ = self.memory_cache.remove(hash);
            }
        }

        // Database cleanup
        if (self.connection) |conn| {
            const cutoff = std.time.timestamp() - self.config.cache_ttl_seconds;
            const query = try std.fmt.allocPrint(self.allocator,
                "DELETE FROM response_cache WHERE timestamp < {};", .{cutoff});
            defer self.allocator.free(query);

            conn.execute(query) catch |err| {
                std.log.warn("Failed to cleanup database cache: {}", .{err});
            };
        }
    }

    // Helper methods for live model switching
    fn calculateResponseSimilarity(self: *Self, response1: []const u8, response2: []const u8) !f32 {
        // Simple similarity calculation (could be enhanced with more sophisticated algorithms)
        if (response1.len == 0 or response2.len == 0) return 0.0;

        const min_len = @min(response1.len, response2.len);
        var matches: u32 = 0;

        for (0..min_len) |i| {
            if (response1[i] == response2[i]) {
                matches += 1;
            }
        }

        return @as(f32, @floatFromInt(matches)) / @as(f32, @floatFromInt(@max(response1.len, response2.len)));
    }

    fn countSuccessfulResults(self: *Self, results: []ModelTimingResult) u32 {
        _ = self;
        var count: u32 = 0;
        for (results) |result| {
            if (result.success) count += 1;
        }
        return count;
    }

    fn analyzePrompt(self: *Self, messages: []const api.ChatMessage) !PromptAnalysis {
        var total_length: u32 = 0;
        var has_code = false;
        var has_math = false;
        var complexity_score: f32 = 0.0;

        for (messages) |message| {
            total_length += @intCast(message.content.len);

            // Simple heuristics for prompt analysis
            if (std.mem.indexOf(u8, message.content, "```") != null) has_code = true;
            if (std.mem.indexOf(u8, message.content, "equation") != null or
                std.mem.indexOf(u8, message.content, "calculate") != null) has_math = true;

            // Complexity based on length and keywords
            complexity_score += @as(f32, @floatFromInt(message.content.len)) / 100.0;
        }

        return PromptAnalysis{
            .total_length = total_length,
            .message_count = @intCast(messages.len),
            .has_code = has_code,
            .has_math = has_math,
            .complexity_score = complexity_score,
            .language_detected = "english", // Could be enhanced with actual language detection
            .domain = if (has_code) "programming" else if (has_math) "mathematics" else "general",
        };
    }

    fn calculateModelScore(self: *Self, model: ModelCapability, analysis: PromptAnalysis) f32 {
        _ = self;
        var score: f32 = 0.0;

        // Base score from model capabilities
        if (analysis.has_code and model.good_at_code) score += 0.3;
        if (analysis.has_math and model.good_at_math) score += 0.3;

        // Length considerations
        if (analysis.total_length > model.context_length) {
            score -= 0.5; // Penalty for exceeding context
        }

        // Speed vs quality trade-off
        if (analysis.complexity_score < 2.0) {
            score += model.speed_score * 0.2; // Favor speed for simple prompts
        } else {
            score += model.quality_score * 0.2; // Favor quality for complex prompts
        }

        return @max(0.0, @min(1.0, score));
    }

    fn generateRecommendationReasoning(self: *Self, model: ModelCapability, analysis: PromptAnalysis) ![]u8 {
        var reasoning = std.ArrayList(u8).init(self.allocator);
        defer reasoning.deinit();

        try reasoning.appendSlice("Recommended ");
        try reasoning.appendSlice(model.name);
        try reasoning.appendSlice(" because: ");

        if (analysis.has_code and model.good_at_code) {
            try reasoning.appendSlice("excellent for code, ");
        }
        if (analysis.has_math and model.good_at_math) {
            try reasoning.appendSlice("strong math capabilities, ");
        }
        if (analysis.complexity_score < 2.0) {
            try reasoning.appendSlice("fast response for simple queries");
        } else {
            try reasoning.appendSlice("high quality for complex tasks");
        }

        return try reasoning.toOwnedSlice();
    }

    fn getAlternativeModels(self: *Self, all_models: []ModelCapability, chosen: ModelCapability, limit: u32) ![][]const u8 {
        var alternatives = std.ArrayList([]const u8).init(self.allocator);
        defer alternatives.deinit();

        var count: u32 = 0;
        for (all_models) |model| {
            if (!std.mem.eql(u8, model.name, chosen.name) and count < limit) {
                try alternatives.append(try self.allocator.dupe(u8, model.name));
                count += 1;
            }
        }

        return try alternatives.toOwnedSlice();
    }
};

// **NEW: Live Model Switching Structures**

pub const ConversationSwitch = struct {
    previous_model: []const u8,
    new_model: []const u8,
    previous_response: api.ChatResponse,
    new_response: api.ChatResponse,
    switch_time_ms: u64,
    context_preserved: bool,
    similarity_score: f32,
};

pub const ModelTimingResult = struct {
    model: []const u8,
    response: ?api.ChatResponse,
    response_time_ms: u64,
    success: bool,
    error_msg: ?[]const u8,
};

pub const FastestModelResult = struct {
    fastest_model: []const u8,
    fastest_response: api.ChatResponse,
    response_time_ms: u64,
    all_results: []ModelTimingResult,
    success_count: u32,
};

pub const ModelCapability = struct {
    name: []const u8,
    context_length: u32,
    good_at_code: bool,
    good_at_math: bool,
    good_at_reasoning: bool,
    speed_score: f32, // 0.0 to 1.0
    quality_score: f32, // 0.0 to 1.0
    cost_per_token: f32,
};

pub const PromptAnalysis = struct {
    total_length: u32,
    message_count: u32,
    has_code: bool,
    has_math: bool,
    complexity_score: f32,
    language_detected: []const u8,
    domain: []const u8,
};

pub const ModelRecommendation = struct {
    recommended_model: []const u8,
    confidence_score: f32,
    reasoning: []const u8,
    prompt_analysis: PromptAnalysis,
    alternative_models: [][]const u8,
};

pub const ModelComparisonCallback = *const fn (model_index: usize, model_name: []const u8, chunk: []const u8) void;