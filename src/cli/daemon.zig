// CLI commands for daemon management

const std = @import("std");
const daemon_mod = @import("../daemon/daemon.zig");
const client = @import("../daemon/client.zig");

pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "start")) {
        try handleStart(allocator);
    } else if (std.mem.eql(u8, subcommand, "stop")) {
        try handleStop(allocator);
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try handleStatus(allocator);
    } else if (std.mem.eql(u8, subcommand, "restart")) {
        try handleRestart(allocator);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        showHelp();
    } else {
        std.debug.print("Unknown subcommand: {s}\n\n", .{subcommand});
        showHelp();
    }
}

fn handleStart(allocator: std.mem.Allocator) !void {
    // Check if already running
    if (client.isDaemonRunning()) {
        std.debug.print("⚠️  Daemon is already running\n", .{});
        std.debug.print("   Use 'zeke daemon stop' first or 'zeke daemon restart'\n\n", .{});
        return;
    }

    std.debug.print("Starting Zeke daemon...\n\n", .{});

    // Fork and start daemon in background
    const pid = try std.posix.fork();

    if (pid == 0) {
        // Child process - start daemon
        const daemon_ptr = try daemon_mod.Daemon.init(allocator);
        defer daemon_ptr.deinit();

        try daemon_ptr.start();
    } else {
        // Parent process - just exit
        std.debug.print("✓ Daemon started (PID: {})\n", .{pid});
        std.debug.print("  Socket: {s}\n\n", .{daemon_mod.SOCKET_PATH});
    }
}

fn handleStop(allocator: std.mem.Allocator) !void {
    if (!client.isDaemonRunning()) {
        std.debug.print("Daemon is not running\n\n", .{});
        return;
    }

    std.debug.print("Stopping daemon...\n", .{});

    // Send stop signal via socket
    const request = "{\"method\":\"stop\"}";
    const response = client.sendRequest(allocator, request) catch |err| {
        std.debug.print("Error stopping daemon: {}\n", .{err});
        std.debug.print("Removing socket file anyway...\n", .{});
        std.fs.cwd().deleteFile(daemon_mod.SOCKET_PATH) catch {};
        return;
    };
    defer allocator.free(response);

    std.debug.print("✓ Daemon stopped\n\n", .{});
}

fn handleStatus(allocator: std.mem.Allocator) !void {
    if (!client.isDaemonRunning()) {
        std.debug.print("❌ Daemon is not running\n\n", .{});
        return;
    }

    std.debug.print("Checking daemon status...\n", .{});

    // Ping daemon
    const response = client.ping(allocator) catch |err| {
        std.debug.print("❌ Daemon is not responding: {}\n\n", .{err});
        return;
    };
    defer allocator.free(response);

    std.debug.print("✓ Daemon is running\n", .{});
    std.debug.print("  Socket: {s}\n", .{daemon_mod.SOCKET_PATH});
    std.debug.print("  Response: {s}\n\n", .{response});
}

fn handleRestart(allocator: std.mem.Allocator) !void {
    std.debug.print("Restarting daemon...\n\n", .{});

    // Stop if running
    if (client.isDaemonRunning()) {
        try handleStop(allocator);
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }

    // Start
    try handleStart(allocator);
}

fn showHelp() void {
    std.debug.print(
        \\
        \\🔧 Daemon Management
        \\
        \\USAGE:
        \\    zeke daemon <command>
        \\
        \\COMMANDS:
        \\    start      Start the background daemon
        \\    stop       Stop the running daemon
        \\    status     Check daemon status
        \\    restart    Restart the daemon
        \\
        \\EXAMPLES:
        \\    # Start daemon in background
        \\    zeke daemon start
        \\
        \\    # Check if daemon is running
        \\    zeke daemon status
        \\
        \\    # Stop daemon
        \\    zeke daemon stop
        \\
        \\FEATURES:
        \\    • Persistent LSP server connections
        \\    • Fast response times (no startup delay)
        \\    • Real-time diagnostics via notifications
        \\    • Cached index for instant search
        \\    • Unix socket IPC
        \\
        \\
    , .{});
}
