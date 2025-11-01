const std = @import("std");
const builtin = @import("builtin");

/// Daemon lifecycle manager - handles startup, shutdown, PID file, health checks
pub const LifecycleManager = struct {
    allocator: std.mem.Allocator,
    pid_file_path: []const u8,
    shutdown_requested: std.atomic.Value(bool),
    start_time: i64,
    health_check_enabled: bool,

    pub const Error = error{
        DaemonAlreadyRunning,
        CannotCreatePidFile,
        CannotRemovePidFile,
        InvalidPidFile,
    };

    pub const HealthStatus = struct {
        running: bool,
        uptime_seconds: i64,
        pid: std.c.pid_t,
        start_time: i64,
        memory_usage_kb: usize,

        pub fn toJson(self: HealthStatus, allocator: std.mem.Allocator) ![]u8 {
            return std.fmt.allocPrint(allocator,
                \\{{
                \\  "running": {s},
                \\  "uptime_seconds": {},
                \\  "pid": {},
                \\  "start_time": {},
                \\  "memory_usage_kb": {}
                \\}}
            , .{
                if (self.running) "true" else "false",
                self.uptime_seconds,
                self.pid,
                self.start_time,
                self.memory_usage_kb,
            });
        }
    };

    pub fn init(allocator: std.mem.Allocator, pid_file_path: []const u8) !LifecycleManager {
        return LifecycleManager{
            .allocator = allocator,
            .pid_file_path = try allocator.dupe(u8, pid_file_path),
            .shutdown_requested = std.atomic.Value(bool).init(false),
            .start_time = std.time.timestamp(),
            .health_check_enabled = true,
        };
    }

    pub fn deinit(self: *LifecycleManager) void {
        self.allocator.free(self.pid_file_path);
    }

    /// Start daemon - create PID file, register signal handlers
    pub fn start(self: *LifecycleManager) !void {
        // Check if daemon already running
        if (try self.isRunning()) {
            return Error.DaemonAlreadyRunning;
        }

        // Create PID file
        try self.createPidFile();

        // Register signal handlers for graceful shutdown
        try self.registerSignalHandlers();

        std.debug.print("✅ Daemon started (PID: {})\n", .{std.c.getpid()});
    }

    /// Stop daemon - remove PID file, cleanup
    pub fn stop(self: *LifecycleManager) !void {
        self.shutdown_requested.store(true, .release);

        // Remove PID file
        try self.removePidFile();

        std.debug.print("✅ Daemon stopped gracefully\n", .{});
    }

    /// Check if shutdown has been requested
    pub fn shouldShutdown(self: *LifecycleManager) bool {
        return self.shutdown_requested.load(.acquire);
    }

    /// Request graceful shutdown
    pub fn requestShutdown(self: *LifecycleManager) void {
        std.debug.print("🛑 Shutdown requested...\n", .{});
        self.shutdown_requested.store(true, .release);
    }

    /// Get health status
    pub fn getHealthStatus(self: *LifecycleManager) !HealthStatus {
        const now = std.time.timestamp();
        const uptime = now - self.start_time;

        return HealthStatus{
            .running = !self.shouldShutdown(),
            .uptime_seconds = uptime,
            .pid = std.c.getpid(),
            .start_time = self.start_time,
            .memory_usage_kb = try self.getMemoryUsage(),
        };
    }

    /// Check if daemon is currently running (by checking PID file)
    pub fn isRunning(self: *LifecycleManager) !bool {
        const file = std.fs.cwd().openFile(self.pid_file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };
        defer file.close();

        // Read PID from file
        var buf: [32]u8 = undefined;
        const bytes_read = try file.readAll(&buf);
        const pid_str = std.mem.trim(u8, buf[0..bytes_read], &std.ascii.whitespace);

        const pid = std.fmt.parseInt(std.c.pid_t, pid_str, 10) catch {
            return Error.InvalidPidFile;
        };

        // Check if process is still alive
        return self.isProcessAlive(pid);
    }

    /// Get PID of running daemon
    pub fn getRunningPid(self: *LifecycleManager) !?std.c.pid_t {
        const file = std.fs.cwd().openFile(self.pid_file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return null;
            }
            return err;
        };
        defer file.close();

        var buf: [32]u8 = undefined;
        const bytes_read = try file.readAll(&buf);
        const pid_str = std.mem.trim(u8, buf[0..bytes_read], &std.ascii.whitespace);

        return std.fmt.parseInt(std.c.pid_t, pid_str, 10) catch null;
    }

    // === Private Methods ===

    fn createPidFile(self: *LifecycleManager) !void {
        const file = try std.fs.cwd().createFile(self.pid_file_path, .{ .truncate = true });
        defer file.close();

        const pid = std.c.getpid();
        const pid_str = try std.fmt.allocPrint(self.allocator, "{}\n", .{pid});
        defer self.allocator.free(pid_str);

        try file.writeAll(pid_str);
    }

    fn removePidFile(self: *LifecycleManager) !void {
        std.fs.cwd().deleteFile(self.pid_file_path) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("⚠️  Warning: Failed to remove PID file: {}\n", .{err});
                return err;
            }
        };
    }

    fn isProcessAlive(self: *LifecycleManager, pid: std.c.pid_t) bool {
        _ = self;

        // On Unix, send signal 0 to check if process exists
        if (builtin.os.tag != .windows) {
            const result = std.posix.kill(pid, 0) catch |err| {
                // ESRCH means process doesn't exist
                if (err == error.ProcessNotFound) {
                    return false;
                }
                // Other errors (permission denied, etc.) - assume it's alive
                return true;
            };
            _ = result;
            return true;
        } else {
            // On Windows, would need different approach
            // For now, assume alive if we can't check
            return true;
        }
    }

    fn registerSignalHandlers(self: *LifecycleManager) !void {
        _ = self;

        // Note: Zig doesn't have great signal handling yet
        // In production, would use std.posix.sigaction
        // For now, this is a placeholder for future implementation

        // TODO: Register SIGTERM, SIGINT handlers
        // std.posix.sigaction(std.posix.SIG.TERM, &action, null);
        // std.posix.sigaction(std.posix.SIG.INT, &action, null);
    }

    fn getMemoryUsage(self: *LifecycleManager) !usize {
        // Platform-specific memory usage detection
        if (builtin.os.tag == .linux) {
            return try self.getMemoryUsageLinux();
        } else if (builtin.os.tag == .macos) {
            return try self.getMemoryUsageMacOS();
        }
        // Fallback - return 0
        return 0;
    }

    fn getMemoryUsageLinux(self: *LifecycleManager) !usize {
        const pid = std.c.getpid();
        const status_path = try std.fmt.allocPrint(
            self.allocator,
            "/proc/{}/status",
            .{pid},
        );
        defer self.allocator.free(status_path);

        const file = std.fs.cwd().openFile(status_path, .{}) catch {
            return 0;
        };
        defer file.close();

        var buf: [4096]u8 = undefined;
        const bytes_read = try file.readAll(&buf);
        const content = buf[0..bytes_read];

        // Look for VmRSS line (resident set size)
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "VmRSS:")) {
                // Extract number from "VmRSS:    12345 kB"
                var parts = std.mem.splitScalar(u8, line, ':');
                _ = parts.next(); // Skip "VmRSS"
                if (parts.next()) |value_part| {
                    const trimmed = std.mem.trim(u8, value_part, &std.ascii.whitespace);
                    var value_parts = std.mem.splitScalar(u8, trimmed, ' ');
                    if (value_parts.next()) |num_str| {
                        return std.fmt.parseInt(usize, num_str, 10) catch 0;
                    }
                }
            }
        }

        return 0;
    }

    fn getMemoryUsageMacOS(self: *LifecycleManager) !usize {
        _ = self;
        // TODO: Implement using task_info() or similar
        return 0;
    }
};

// === Tests ===

test "lifecycle manager init/deinit" {
    const allocator = std.testing.allocator;

    var manager = try LifecycleManager.init(allocator, "/tmp/zeke_test.pid");
    defer manager.deinit();

    try std.testing.expect(!manager.shouldShutdown());
}

test "shutdown request" {
    const allocator = std.testing.allocator;

    var manager = try LifecycleManager.init(allocator, "/tmp/zeke_test.pid");
    defer manager.deinit();

    try std.testing.expect(!manager.shouldShutdown());

    manager.requestShutdown();

    try std.testing.expect(manager.shouldShutdown());
}

test "PID file creation and removal" {
    const allocator = std.testing.allocator;
    const test_pid_file = "/tmp/zeke_test_lifecycle.pid";

    // Clean up any existing test file
    std.fs.cwd().deleteFile(test_pid_file) catch {};

    var manager = try LifecycleManager.init(allocator, test_pid_file);
    defer manager.deinit();

    // Should not be running initially
    try std.testing.expect(!try manager.isRunning());

    // Start (creates PID file)
    try manager.start();

    // Should be running now
    try std.testing.expect(try manager.isRunning());

    // Get PID
    const pid = try manager.getRunningPid();
    try std.testing.expect(pid != null);
    try std.testing.expectEqual(std.c.getpid(), pid.?);

    // Stop (removes PID file)
    try manager.stop();

    // Should not be running after stop
    try std.testing.expect(!try manager.isRunning());
}

test "health status" {
    const allocator = std.testing.allocator;

    var manager = try LifecycleManager.init(allocator, "/tmp/zeke_test_health.pid");
    defer manager.deinit();

    const status = try manager.getHealthStatus();

    try std.testing.expect(status.running);
    try std.testing.expect(status.uptime_seconds >= 0);
    try std.testing.expectEqual(std.c.getpid(), status.pid);

    // Test JSON serialization
    const json = try status.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"running\": true") != null);
}
