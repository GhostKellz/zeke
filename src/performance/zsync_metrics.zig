const std = @import("std");
const zsync = @import("zsync");

/// Enhanced performance monitoring for zsync v0.5.4 features
pub const ZsyncMetrics = struct {
    allocator: std.mem.Allocator,
    start_time: i64,
    request_count: std.atomic.Value(u64),
    success_count: std.atomic.Value(u64),
    error_count: std.atomic.Value(u64),
    
    // Connection pool metrics
    connection_stats: std.AutoHashMap([]const u8, ConnectionPoolMetrics),
    
    const Self = @This();
    
    pub const ConnectionPoolMetrics = struct {
        total_connections: u32,
        active_connections: u32,
        idle_connections: u32,
        failed_connections: u32,
        avg_response_time_ms: f64,
        last_health_check: i64,
    };
    
    pub const PerformanceReport = struct {
        uptime_seconds: i64,
        total_requests: u64,
        success_rate: f64,
        requests_per_second: f64,
        avg_request_time_ms: f64,
        execution_model: zsync.ExecutionModel,
        connection_pools: []ConnectionPoolMetrics,
        
        // zsync v0.5.4 specific metrics
        hybrid_model_switches: u32,
        zero_copy_transfers: u64,
        vectorized_operations: u64,
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        var instance = Self{
            .allocator = allocator,
            .start_time = std.time.timestamp(),
            .request_count = std.atomic.Value(u64).init(0),
            .success_count = std.atomic.Value(u64).init(0),
            .error_count = std.atomic.Value(u64).init(0),
            .connection_stats = undefined,
        };
        instance.connection_stats = std.AutoHashMap([]const u8, ConnectionPoolMetrics).init(allocator);
        return instance;
    }
    
    pub fn deinit(self: *Self) void {
        var iter = self.connection_stats.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.connection_stats.deinit();
    }
    
    /// Record a request completion
    pub fn recordRequest(self: *Self, success: bool, response_time_ms: u64) void {
        _ = response_time_ms;
        _ = self.request_count.fetchAdd(1, .monotonic);
        if (success) {
            _ = self.success_count.fetchAdd(1, .monotonic);
        } else {
            _ = self.error_count.fetchAdd(1, .monotonic);
        }
    }
    
    /// Update connection pool metrics
    pub fn updateConnectionPool(
        self: *Self, 
        pool_name: []const u8, 
        metrics: ConnectionPoolMetrics
    ) !void {
        const owned_name = try self.allocator.dupe(u8, pool_name);
        try self.connection_stats.put(self.allocator, owned_name, metrics);
    }
    
    /// Generate comprehensive performance report
    pub fn generateReport(self: *Self) !PerformanceReport {
        const now = std.time.timestamp();
        const uptime = now - self.start_time;
        const total_requests = self.request_count.load(.monotonic);
        const success_requests = self.success_count.load(.monotonic);
        
        const success_rate = if (total_requests > 0) 
            @as(f64, @floatFromInt(success_requests)) / @as(f64, @floatFromInt(total_requests)) * 100.0
        else 
            0.0;
            
        const requests_per_second = if (uptime > 0)
            @as(f64, @floatFromInt(total_requests)) / @as(f64, @floatFromInt(uptime))
        else
            0.0;
        
        // Collect connection pool metrics
        var pool_metrics = std.ArrayList(ConnectionPoolMetrics){};
        defer pool_metrics.deinit(self.allocator);
        
        var iter = self.connection_stats.iterator();
        while (iter.next()) |entry| {
            try pool_metrics.append(self.allocator, entry.value_ptr.*);
        }
        
        return PerformanceReport{
            .uptime_seconds = uptime,
            .total_requests = total_requests,
            .success_rate = success_rate,
            .requests_per_second = requests_per_second,
            .avg_request_time_ms = 0.0, // TODO: Track actual timing
            .execution_model = .blocking, // TODO: Get from runtime
            .connection_pools = try pool_metrics.toOwnedSlice(self.allocator),
            .hybrid_model_switches = 0, // TODO: Track from hybrid_io
            .zero_copy_transfers = 0, // TODO: Track from advanced_io
            .vectorized_operations = 0, // TODO: Track from advanced_io
        };
    }
    
    /// Print performance summary to console
    pub fn printSummary(self: *Self) !void {
        const report = try self.generateReport();
        defer self.allocator.free(report.connection_pools);
        
        std.log.info("🚀 Zeke Performance Report (zsync v0.5.4)", .{});
        std.log.info("  Uptime: {}s", .{report.uptime_seconds});
        std.log.info("  Total Requests: {}", .{report.total_requests});
        std.log.info("  Success Rate: {d:.2}%", .{report.success_rate});
        std.log.info("  Requests/sec: {d:.2}", .{report.requests_per_second});
        std.log.info("  Execution Model: {}", .{report.execution_model});
        std.log.info("  Connection Pools: {}", .{report.connection_pools.len});
        
        for (report.connection_pools, 0..) |pool, i| {
            std.log.info("    Pool {}: {}/{} connections active", .{
                i, pool.active_connections, pool.total_connections
            });
        }
    }
};

/// Global metrics instance for easy access
var global_metrics: ?*ZsyncMetrics = null;

/// Initialize global metrics
pub fn initGlobalMetrics(allocator: std.mem.Allocator) !void {
    if (global_metrics != null) return;
    
    global_metrics = try allocator.create(ZsyncMetrics);
    global_metrics.?.* = ZsyncMetrics.init(allocator);
}

/// Get global metrics instance
pub fn getGlobalMetrics() ?*ZsyncMetrics {
    return global_metrics;
}

/// Clean up global metrics
pub fn deinitGlobalMetrics(allocator: std.mem.Allocator) void {
    if (global_metrics) |metrics| {
        metrics.deinit();
        allocator.destroy(metrics);
        global_metrics = null;
    }
}