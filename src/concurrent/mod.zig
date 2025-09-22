const std = @import("std");
const zsync = @import("zsync");
const api = @import("../api/client.zig");
const providers = @import("../providers/mod.zig");

// Note: Advanced zsync v0.5.4 features are available but not all are exported
// We'll integrate them gradually as the API stabilizes

/// Enhanced concurrent request handling with zsync v0.5.4 features
pub const ConcurrentRequestHandler = struct {
    allocator: std.mem.Allocator,
    io: ?zsync.Io,
    active_requests: std.AutoHashMap(u64, *RequestTask),
    request_counter: std.atomic.Value(u64),
    cancel_token: ?*zsync.CancelToken,

    // Enhanced v0.5.4 features (simplified until APIs stabilize)
    connection_stats: std.AutoHashMap(api.ApiProvider, ConnectionMetrics),
    pool_enabled: bool,

    pub const ConnectionMetrics = struct {
        active_connections: u32,
        total_requests: u64,
        avg_response_time_ms: f64,
        last_health_check: i64,
    };

    pub const RequestTask = struct {
        id: u64,
        provider: api.ApiProvider,
        request_type: RequestType,
        status: RequestStatus,
        result: ?RequestResult,
        error_info: ?[]const u8,
        start_time: i64,
        completion_time: ?i64,
        callback: ?RequestCallback,
        context: ?*anyopaque,

        pub const RequestType = enum {
            chat_completion,
            code_completion,
            code_analysis,
            code_explanation,
            health_check,
        };

        pub const RequestStatus = enum {
            pending,
            in_progress,
            completed,
            failed,
            cancelled,
        };

        pub const RequestResult = union(RequestType) {
            chat_completion: []const u8,
            code_completion: []const u8,
            code_analysis: api.AnalysisResponse,
            code_explanation: api.ExplanationResponse,
            health_check: bool,
        };

        pub const RequestCallback = *const fn (task: *RequestTask) void;

        pub fn deinit(self: *RequestTask, allocator: std.mem.Allocator) void {
            if (self.error_info) |error_msg| {
                allocator.free(error_msg);
            }

            if (self.result) |*result| {
                switch (result.*) {
                    .chat_completion => |content| allocator.free(content),
                    .code_completion => |content| allocator.free(content),
                    .code_analysis => |*analysis| analysis.deinit(allocator),
                    .code_explanation => |*explanation| explanation.deinit(allocator),
                    .health_check => {},
                }
            }
        }
    };

    pub const RequestOptions = struct {
        timeout_ms: u32 = 30000,
        retry_count: u8 = 3,
        priority: Priority = .normal,
        callback: ?RequestTask.RequestCallback = null,
        context: ?*anyopaque = null,

        pub const Priority = enum {
            low,
            normal,
            high,
            critical,
        };
    };

    pub const BatchRequestOptions = struct {
        max_concurrent: u8 = 5,
        fail_fast: bool = false,
        timeout_ms: u32 = 60000,
        callback: ?BatchCallback = null,

        pub const BatchCallback = *const fn (results: []RequestTask) void;
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_threads: u32) !Self {
        return Self.initWithZsync(allocator, max_threads, null);
    }

    pub fn initWithZsync(allocator: std.mem.Allocator, max_threads: u32, io: anytype) !Self {
        _ = max_threads; // zsync manages threads automatically

        var instance = Self{
            .allocator = allocator,
            .io = io,
            .active_requests = undefined,
            .request_counter = std.atomic.Value(u64).init(0),
            .cancel_token = if (io != null) zsync.CancelToken.init(allocator, .user_requested) catch null else null,
            .connection_stats = undefined,
            .pool_enabled = io != null,
        };
        instance.active_requests = std.AutoHashMap(u64, *RequestTask).init(allocator);
        instance.connection_stats = std.AutoHashMap(api.ApiProvider, ConnectionMetrics).init(allocator);
        return instance;
    }

    pub fn deinit(self: *Self) void {
        // Clean up connection stats
        self.connection_stats.deinit();

        // Cancel all active requests
        var iter = self.active_requests.iterator();
        while (iter.next()) |entry| {
            const task = entry.value_ptr.*;
            task.status = .cancelled;
            task.deinit(self.allocator);
            self.allocator.destroy(task);
        }

        self.active_requests.deinit();
    }

    pub fn submitChatRequest(self: *Self, provider: api.ApiProvider, client: *api.ApiClient, messages: []const api.ChatMessage, model: []const u8, options: RequestOptions) !u64 {
        const task = try self.createTask(.chat_completion, provider, options);

        // Store chat request data
        const chat_data = try self.allocator.create(ChatRequestData);
        chat_data.* = ChatRequestData{
            .client = client,
            .messages = messages,
            .model = try self.allocator.dupe(u8, model),
        };
        task.context = chat_data;

        // Submit using zsync if available, otherwise use fallback
        if (self.io != null) {
            _ = try zsync.globalSpawn(chatCompletionWorkerAsync, .{ self, task });
        } else {
            // Fallback to synchronous execution
            chatCompletionWorker(self, task);
        }

        return task.id;
    }

    pub fn submitCodeAnalysisRequest(self: *Self, provider: api.ApiProvider, client: *api.ApiClient, code: []const u8, analysis_type: api.AnalysisType, project_context: api.ProjectContext, options: RequestOptions) !u64 {
        const task = try self.createTask(.code_analysis, provider, options);

        // Store analysis request data
        const analysis_data = try self.allocator.create(AnalysisRequestData);
        analysis_data.* = AnalysisRequestData{
            .client = client,
            .code = try self.allocator.dupe(u8, code),
            .analysis_type = analysis_type,
            .project_context = project_context,
        };
        task.context = analysis_data;

        // Submit using zsync if available, otherwise use fallback
        if (self.io != null) {
            _ = try zsync.globalSpawn(codeAnalysisWorkerAsync, .{ self, task });
        } else {
            // Fallback to synchronous execution
            codeAnalysisWorker(self, task);
        }

        return task.id;
    }

    pub fn submitBatchRequests(self: *Self, requests: []const BatchRequest, options: BatchRequestOptions) ![]u64 {
        var request_ids = std.ArrayList(u64){};
        defer request_ids.deinit(self.allocator);

        var semaphore = std.Thread.Semaphore{ .permits = options.max_concurrent };

        for (requests) |request| {
            semaphore.wait();

            const request_id = switch (request) {
                .chat => |chat_req| try self.submitChatRequest(chat_req.provider, chat_req.client, chat_req.messages, chat_req.model, chat_req.options),
                .analysis => |analysis_req| try self.submitCodeAnalysisRequest(analysis_req.provider, analysis_req.client, analysis_req.code, analysis_req.analysis_type, analysis_req.project_context, analysis_req.options),
            };

            try request_ids.append(self.allocator, request_id);

            // Set up completion callback to release semaphore
            if (self.active_requests.get(request_id)) |task| {
                const sem_ptr = &semaphore;
                const original_callback = task.callback;
                task.callback = struct {
                    const sem = sem_ptr;
                    const orig_cb = original_callback;
                    fn callback(completed_task: *RequestTask) void {
                        sem.post();
                        if (orig_cb) |cb| {
                            cb(completed_task);
                        }
                    }
                }.callback;
            }
        }

        return request_ids.toOwnedSlice(self.allocator);
    }

    pub fn waitForRequest(self: *Self, request_id: u64) !*RequestTask {
        while (true) {
            if (self.active_requests.get(request_id)) |task| {
                switch (task.status) {
                    .completed, .failed, .cancelled => return task,
                    else => {
                        // Small delay to avoid busy waiting
                        std.time.sleep(1 * std.time.ns_per_ms);
                    },
                }
            } else {
                return error.RequestNotFound;
            }
        }
    }

    pub fn waitForAllRequests(self: *Self, request_ids: []const u64) ![]RequestTask {
        var results = std.ArrayList(RequestTask){};
        defer results.deinit(self.allocator);

        for (request_ids) |request_id| {
            const task = try self.waitForRequest(request_id);
            try results.append(self.allocator, task.*);
        }

        return results.toOwnedSlice(self.allocator);
    }

    pub fn cancelRequest(self: *Self, request_id: u64) !void {
        if (self.active_requests.getPtr(request_id)) |task| {
            task.status = .cancelled;
        } else {
            return error.RequestNotFound;
        }
    }

    pub fn getRequestStatus(self: *Self, request_id: u64) ?RequestTask.RequestStatus {
        if (self.active_requests.get(request_id)) |task| {
            return task.status;
        }
        return null;
    }

    pub fn getActiveRequestCount(self: *const Self) u32 {
        return @intCast(self.active_requests.count());
    }

    pub fn getRequestStats(self: *const Self) RequestStats {
        var stats = RequestStats{
            .total_requests = self.request_counter.load(.acquire),
            .active_requests = @intCast(self.active_requests.count()),
            .completed_requests = 0,
            .failed_requests = 0,
            .cancelled_requests = 0,
            .average_completion_time_ms = 0,
        };

        var total_time: i64 = 0;
        var iter = self.active_requests.iterator();
        while (iter.next()) |entry| {
            const task = entry.value_ptr.*;
            switch (task.status) {
                .completed => {
                    stats.completed_requests += 1;
                    if (task.completion_time) |completion_time| {
                        total_time += completion_time - task.start_time;
                    }
                },
                .failed => stats.failed_requests += 1,
                .cancelled => stats.cancelled_requests += 1,
                else => {},
            }
        }

        if (stats.completed_requests > 0) {
            stats.average_completion_time_ms = @intCast(total_time / @as(i64, @intCast(stats.completed_requests)));
        }

        return stats;
    }

    // Helper types and functions
    const ChatRequestData = struct {
        client: *api.ApiClient,
        messages: []const api.ChatMessage,
        model: []const u8,

        pub fn deinit(self: *ChatRequestData, allocator: std.mem.Allocator) void {
            allocator.free(self.model);
        }
    };

    const AnalysisRequestData = struct {
        client: *api.ApiClient,
        code: []const u8,
        analysis_type: api.AnalysisType,
        project_context: api.ProjectContext,

        pub fn deinit(self: *AnalysisRequestData, allocator: std.mem.Allocator) void {
            allocator.free(self.code);
        }
    };

    pub const BatchRequest = union(enum) {
        chat: struct {
            provider: api.ApiProvider,
            client: *api.ApiClient,
            messages: []const api.ChatMessage,
            model: []const u8,
            options: RequestOptions,
        },
        analysis: struct {
            provider: api.ApiProvider,
            client: *api.ApiClient,
            code: []const u8,
            analysis_type: api.AnalysisType,
            project_context: api.ProjectContext,
            options: RequestOptions,
        },
    };

    pub const RequestStats = struct {
        total_requests: u64,
        active_requests: u32,
        completed_requests: u32,
        failed_requests: u32,
        cancelled_requests: u32,
        average_completion_time_ms: u32,
    };

    fn createTask(self: *Self, request_type: RequestTask.RequestType, provider: api.ApiProvider, options: RequestOptions) !*RequestTask {
        const task_id = self.request_counter.fetchAdd(1, .acq_rel);
        const task = try self.allocator.create(RequestTask);

        task.* = RequestTask{
            .id = task_id,
            .provider = provider,
            .request_type = request_type,
            .status = .pending,
            .result = null,
            .error_info = null,
            .start_time = std.time.timestamp(),
            .completion_time = null,
            .callback = options.callback,
            .context = options.context,
        };

        try self.active_requests.put(task_id, task);
        return task;
    }

    fn chatCompletionWorkerAsync(self: *Self, task: *RequestTask) !void {
        self.chatCompletionWorker(task);
    }

    fn chatCompletionWorker(self: *Self, task: *RequestTask) void {
        task.status = .in_progress;

        const chat_data = @as(*ChatRequestData, @ptrCast(@alignCast(task.context.?)));
        defer chat_data.deinit(self.allocator);

        // Perform the chat completion
        const response = chat_data.client.chatCompletion(chat_data.messages, chat_data.model) catch |err| {
            task.status = .failed;
            task.error_info = std.fmt.allocPrint(self.allocator, "Chat completion failed: {}", .{err}) catch "Unknown error";
            task.completion_time = std.time.timestamp();

            if (task.callback) |callback| {
                callback(task);
            }
            return;
        };

        // Store result
        task.result = RequestTask.RequestResult{
            .chat_completion = response.content,
        };
        task.status = .completed;
        task.completion_time = std.time.timestamp();

        if (task.callback) |callback| {
            callback(task);
        }
    }

    fn codeAnalysisWorkerAsync(self: *Self, task: *RequestTask) !void {
        self.codeAnalysisWorker(task);
    }

    fn codeAnalysisWorker(self: *Self, task: *RequestTask) void {
        task.status = .in_progress;

        const analysis_data = @as(*AnalysisRequestData, @ptrCast(@alignCast(task.context.?)));
        defer analysis_data.deinit(self.allocator);

        // Perform the code analysis
        const response = analysis_data.client.analyzeCode(analysis_data.code, analysis_data.analysis_type, analysis_data.project_context) catch |err| {
            task.status = .failed;
            task.error_info = std.fmt.allocPrint(self.allocator, "Code analysis failed: {}", .{err}) catch "Unknown error";
            task.completion_time = std.time.timestamp();

            if (task.callback) |callback| {
                callback(task);
            }
            return;
        };

        // Store result
        task.result = RequestTask.RequestResult{
            .code_analysis = response,
        };
        task.status = .completed;
        task.completion_time = std.time.timestamp();

        if (task.callback) |callback| {
            callback(task);
        }
    }

    pub fn cleanupCompletedTasks(self: *Self) !void {
        var tasks_to_remove = std.ArrayList(u64){};
        defer tasks_to_remove.deinit(self.allocator);

        const now = std.time.timestamp();
        const cleanup_threshold = 300; // 5 minutes

        var iter = self.active_requests.iterator();
        while (iter.next()) |entry| {
            const task = entry.value_ptr.*;
            const is_completed = task.status == .completed or task.status == .failed or task.status == .cancelled;

            if (is_completed and task.completion_time) |completion_time| {
                if (now - completion_time > cleanup_threshold) {
                    try tasks_to_remove.append(self.allocator, task.id);
                }
            }
        }

        // Remove old completed tasks
        for (tasks_to_remove.items) |task_id| {
            if (self.active_requests.fetchRemove(task_id)) |entry| {
                entry.value.deinit(self.allocator);
                self.allocator.destroy(entry.value);
            }
        }
    }

    // New v0.5.4 methods leveraging enhanced future combinators

    /// Execute requests across multiple providers with race semantics
    /// Returns the first successful response
    pub fn raceProviders(self: *Self, messages: []const api.ChatMessage, api_providers: []const api.ApiProvider, options: RequestOptions) ![]const u8 {
        if (api_providers.len == 0) return error.NoProviders;

        // For now, simulate racing by trying providers sequentially
        // TODO: Implement actual future racing when zsync types are stable
        for (api_providers) |provider| {
            const task = try self.submitChatRequest(provider, messages, options);

            // Wait for first successful completion
            const result = self.waitForCompletion(task.id) catch |err| {
                std.log.warn("Provider {} failed: {}", .{ provider, err });
                continue;
            };

            if (result) |res| {
                switch (res) {
                    .chat_completion => |response| return response,
                    else => continue,
                }
            }
        }

        return error.AllProvidersFailed;
    }

    /// Execute the same request across all providers and return all successful results
    pub fn broadcastToProviders(self: *Self, messages: []const api.ChatMessage, api_providers: []const api.ApiProvider, options: RequestOptions) ![][]const u8 {
        var results = std.ArrayList([]const u8){};
        defer results.deinit(self.allocator);

        var submitted_tasks = std.ArrayList(u64){};
        defer submitted_tasks.deinit(self.allocator);

        // Submit to all providers
        for (api_providers) |provider| {
            const task = self.submitChatRequest(provider, messages, options) catch |err| {
                std.log.warn("Failed to submit to provider {}: {}", .{ provider, err });
                continue;
            };
            try submitted_tasks.append(self.allocator, task.id);
        }

        // Collect all results
        for (submitted_tasks.items) |task_id| {
            const result = self.waitForCompletion(task_id) catch |err| {
                std.log.warn("Task {} failed: {}", .{ task_id, err });
                continue;
            };

            if (result) |res| {
                switch (res) {
                    .chat_completion => |response| {
                        try results.append(self.allocator, response);
                    },
                    else => continue,
                }
            }
        }

        return try results.toOwnedSlice(self.allocator);
    }

    /// Enhanced parallel execution with timeout support
    pub fn parallelChatWithTimeout(self: *Self, messages: []const api.ChatMessage, api_providers: []const api.ApiProvider, timeout_ms: u64) ![]const u8 {

        // For now, fallback to racing providers
        return self.raceProviders(messages, api_providers, RequestOptions{
            .timeout_ms = @intCast(timeout_ms),
            .priority = .high,
        });
    }

    /// Get connection pool statistics for monitoring
    pub fn getConnectionStats(self: *Self) ConnectionStats {
        var total_connections: u32 = 0;
        var active_connections: u32 = 0;

        var iter = self.connection_stats.iterator();
        while (iter.next()) |entry| {
            const metrics = entry.value_ptr.*;
            total_connections += 20; // Default pool size
            active_connections += metrics.active_connections;
        }

        return ConnectionStats{
            .total_providers = @intCast(self.connection_stats.count()),
            .total_connections = total_connections,
            .active_connections = active_connections,
            .pool_enabled = self.pool_enabled,
        };
    }

    pub const ConnectionStats = struct {
        total_providers: u32,
        total_connections: u32,
        active_connections: u32,
        pool_enabled: bool,
    };
};

/// High-level interface for concurrent AI operations
pub const ConcurrentAI = struct {
    allocator: std.mem.Allocator,
    request_handler: ConcurrentRequestHandler,
    provider_manager: *providers.ProviderManager,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, provider_manager: *providers.ProviderManager) !Self {
        const max_threads = try std.Thread.getCpuCount();
        const request_handler = try ConcurrentRequestHandler.init(allocator, @intCast(max_threads));

        return Self{
            .allocator = allocator,
            .request_handler = request_handler,
            .provider_manager = provider_manager,
        };
    }

    pub fn initWithZsync(allocator: std.mem.Allocator, provider_manager: *providers.ProviderManager, io: ?zsync.Io) !Self {
        const max_threads = try std.Thread.getCpuCount();
        const request_handler = try ConcurrentRequestHandler.initWithZsync(allocator, @intCast(max_threads), io);

        return Self{
            .allocator = allocator,
            .request_handler = request_handler,
            .provider_manager = provider_manager,
        };
    }

    pub fn deinit(self: *Self) void {
        self.request_handler.deinit();
    }

    pub fn parallelChat(self: *Self, messages: []const api.ChatMessage, model: []const u8, providers_to_try: []const api.ApiProvider) ![]const u8 {
        var request_ids = std.ArrayList(u64){};
        defer request_ids.deinit(self.allocator);

        // Submit requests to all providers in parallel
        for (providers_to_try) |provider| {
            const client = try self.provider_manager.getOrCreateClient(provider);
            const request_id = try self.request_handler.submitChatRequest(provider, client, messages, model, .{ .timeout_ms = 15000 });
            try request_ids.append(self.allocator, request_id);
        }

        // Wait for the first successful response
        while (request_ids.items.len > 0) {
            for (request_ids.items, 0..) |request_id, i| {
                const status = self.request_handler.getRequestStatus(request_id) orelse continue;

                if (status == .completed) {
                    const task = try self.request_handler.waitForRequest(request_id);
                    if (task.result) |result| {
                        switch (result) {
                            .chat_completion => |content| {
                                // Cancel other requests
                                for (request_ids.items) |other_id| {
                                    if (other_id != request_id) {
                                        self.request_handler.cancelRequest(other_id) catch {};
                                    }
                                }
                                return try self.allocator.dupe(u8, content);
                            },
                            else => {},
                        }
                    }
                } else if (status == .failed) {
                    // Remove failed request from list
                    _ = request_ids.swapRemove(i);
                    break;
                }
            }

            // Small delay to avoid busy waiting
            std.time.sleep(10 * std.time.ns_per_ms);
        }

        return error.AllProvidersFailed;
    }

    pub fn parallelAnalysis(self: *Self, code: []const u8, analysis_type: api.AnalysisType, project_context: api.ProjectContext, providers_to_try: []const api.ApiProvider) !api.AnalysisResponse {
        var request_ids = std.ArrayList(u64){};
        defer request_ids.deinit(self.allocator);

        // Submit analysis requests to all providers in parallel
        for (providers_to_try) |provider| {
            const client = try self.provider_manager.getOrCreateClient(provider);
            const request_id = try self.request_handler.submitCodeAnalysisRequest(provider, client, code, analysis_type, project_context, .{ .timeout_ms = 30000 });
            try request_ids.append(self.allocator, request_id);
        }

        // Wait for the first successful response
        while (request_ids.items.len > 0) {
            for (request_ids.items, 0..) |request_id, i| {
                const status = self.request_handler.getRequestStatus(request_id) orelse continue;

                if (status == .completed) {
                    const task = try self.request_handler.waitForRequest(request_id);
                    if (task.result) |result| {
                        switch (result) {
                            .code_analysis => |analysis| {
                                // Cancel other requests
                                for (request_ids.items) |other_id| {
                                    if (other_id != request_id) {
                                        self.request_handler.cancelRequest(other_id) catch {};
                                    }
                                }
                                return analysis;
                            },
                            else => {},
                        }
                    }
                } else if (status == .failed) {
                    // Remove failed request from list
                    _ = request_ids.swapRemove(i);
                    break;
                }
            }

            // Small delay to avoid busy waiting
            std.time.sleep(10 * std.time.ns_per_ms);
        }

        return error.AllProvidersFailed;
    }

    pub fn getStats(self: *const Self) ConcurrentRequestHandler.RequestStats {
        return self.request_handler.getRequestStats();
    }

    pub fn cleanup(self: *Self) !void {
        try self.request_handler.cleanupCompletedTasks();
    }
};
