const std = @import("std");

/// Shell command executor with output capture and safety checks
pub const ShellRunner = struct {
    allocator: std.mem.Allocator,
    allowed_commands: std.StringHashMap(bool),
    timeout_ms: u64,

    pub fn init(allocator: std.mem.Allocator, timeout_ms: u64) ShellRunner {
        return .{
            .allocator = allocator,
            .allowed_commands = std.StringHashMap(bool).init(allocator),
            .timeout_ms = timeout_ms,
        };
    }

    pub fn deinit(self: *ShellRunner) void {
        self.allowed_commands.deinit();
    }

    /// Shell command execution result
    pub const Result = struct {
        stdout: []const u8,
        stderr: []const u8,
        exit_code: u8,
        duration_ms: u64,

        pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
            allocator.free(self.stdout);
            allocator.free(self.stderr);
        }
    };

    /// Execute a shell command
    pub fn execute(self: *ShellRunner, command: []const u8) !Result {
        // Validate command
        try self.validateCommand(command);

        const start_time = std.time.milliTimestamp();

        // Create child process
        var child = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", command }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Collect output
        var stdout_buf = std.ArrayList(u8).init(self.allocator);
        defer stdout_buf.deinit();

        var stderr_buf = std.ArrayList(u8).init(self.allocator);
        defer stderr_buf.deinit();

        // Read stdout
        if (child.stdout) |stdout_pipe| {
            var buf: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try stdout_pipe.read(&buf);
                if (bytes_read == 0) break;
                try stdout_buf.appendSlice(buf[0..bytes_read]);
            }
        }

        // Read stderr
        if (child.stderr) |stderr_pipe| {
            var buf: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try stderr_pipe.read(&buf);
                if (bytes_read == 0) break;
                try stderr_buf.appendSlice(buf[0..bytes_read]);
            }
        }

        // Wait for completion
        const term = try child.wait();

        const end_time = std.time.milliTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        return Result{
            .stdout = try stdout_buf.toOwnedSlice(),
            .stderr = try stderr_buf.toOwnedSlice(),
            .exit_code = switch (term) {
                .Exited => |code| code,
                .Signal => 1,
                .Stopped => 1,
                .Unknown => 1,
            },
            .duration_ms = duration,
        };
    }

    /// Validate command for safety
    fn validateCommand(self: *ShellRunner, command: []const u8) !void {
        _ = self;

        // Block dangerous commands
        const dangerous = [_][]const u8{
            "rm -rf /",
            ":(){ :|:& };:", // Fork bomb
            "mkfs",
            "dd if=/dev/zero",
            "> /dev/sda",
        };

        for (dangerous) |pattern| {
            if (std.mem.indexOf(u8, command, pattern) != null) {
                return error.DangerousCommand;
            }
        }

        // Check command length
        if (command.len > 4096) {
            return error.CommandTooLong;
        }

        // Block shell metacharacters that could be abused
        const suspicious = [_]u8{ '`', '$', '(', ')' };
        var suspicious_count: usize = 0;
        for (command) |char| {
            for (suspicious) |sus_char| {
                if (char == sus_char) {
                    suspicious_count += 1;
                }
            }
        }

        if (suspicious_count > 10) {
            return error.SuspiciousCommand;
        }
    }

    /// Execute with timeout
    pub fn executeWithTimeout(
        self: *ShellRunner,
        command: []const u8,
    ) !Result {
        _ = self;
        _ = command;
        // TODO: Implement timeout using threads
        return error.NotImplemented;
    }

    /// Add command to allowlist
    pub fn allowCommand(self: *ShellRunner, pattern: []const u8) !void {
        const owned = try self.allocator.dupe(u8, pattern);
        try self.allowed_commands.put(owned, true);
    }

    /// Check if command is allowed
    pub fn isAllowed(self: *ShellRunner, command: []const u8) bool {
        // Extract base command
        var tokens = std.mem.tokenizeAny(u8, command, " \t\n");
        const base_cmd = tokens.next() orelse return false;

        return self.allowed_commands.contains(base_cmd);
    }
};

// Tests
test "shell runner basic" {
    const allocator = std.testing.allocator;

    var runner = ShellRunner.init(allocator, 5000);
    defer runner.deinit();

    var result = try runner.execute("echo 'Hello, World!'");
    defer result.deinit(allocator);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello, World!") != null);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "validate dangerous commands" {
    const allocator = std.testing.allocator;

    var runner = ShellRunner.init(allocator, 5000);
    defer runner.deinit();

    try std.testing.expectError(
        error.DangerousCommand,
        runner.validateCommand("rm -rf /"),
    );
}

test "command too long" {
    const allocator = std.testing.allocator;

    var runner = ShellRunner.init(allocator, 5000);
    defer runner.deinit();

    const long_cmd = try allocator.alloc(u8, 5000);
    defer allocator.free(long_cmd);
    @memset(long_cmd, 'a');

    try std.testing.expectError(
        error.CommandTooLong,
        runner.validateCommand(long_cmd),
    );
}

test "allowlist" {
    const allocator = std.testing.allocator;

    var runner = ShellRunner.init(allocator, 5000);
    defer runner.deinit();

    try runner.allowCommand("git");
    try runner.allowCommand("npm");

    try std.testing.expect(runner.isAllowed("git status"));
    try std.testing.expect(runner.isAllowed("npm install"));
    try std.testing.expect(!runner.isAllowed("rm -rf /"));
}
