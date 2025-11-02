const std = @import("std");
const permissions = @import("permissions.zig");
const file_editor = @import("../tools/file_editor.zig");
const shell_runner = @import("../tools/shell_runner.zig");

/// Tool execution engine for TUI
pub const ToolExecutor = struct {
    allocator: std.mem.Allocator,
    file_editor: file_editor.FileEditorTool,
    shell_runner: shell_runner.ShellRunner,
    queue: std.ArrayList(ToolCall),

    pub fn init(allocator: std.mem.Allocator) ToolExecutor {
        return .{
            .allocator = allocator,
            .file_editor = file_editor.FileEditorTool.init(allocator, ".zeke_backups"),
            .shell_runner = shell_runner.ShellRunner.init(allocator, 30000), // 30s timeout
            .queue = std.ArrayList(ToolCall).init(allocator),
        };
    }

    pub fn deinit(self: *ToolExecutor) void {
        self.shell_runner.deinit();
        for (self.queue.items) |*call| {
            call.deinit(self.allocator);
        }
        self.queue.deinit();
    }

    /// Tool call from AI
    pub const ToolCall = struct {
        name: []const u8,
        arguments: std.json.Value,
        id: ?[]const u8 = null,

        pub fn deinit(self: *ToolCall, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.id) |id| allocator.free(id);
        }
    };

    /// Tool execution result
    pub const ToolResult = struct {
        tool_call_id: ?[]const u8,
        success: bool,
        output: []const u8,
        error_message: ?[]const u8 = null,

        pub fn deinit(self: *ToolResult, allocator: std.mem.Allocator) void {
            if (self.tool_call_id) |id| allocator.free(id);
            allocator.free(self.output);
            if (self.error_message) |msg| allocator.free(msg);
        }
    };

    /// Enqueue a tool call
    pub fn enqueue(self: *ToolExecutor, call: ToolCall) !void {
        try self.queue.append(call);
    }

    /// Execute next tool in queue
    pub fn executeNext(
        self: *ToolExecutor,
        permission_mgr: *permissions.PermissionManager,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !?ToolResult {
        if (self.queue.items.len == 0) return null;

        const call = self.queue.orderedRemove(0);
        defer call.deinit(self.allocator);

        return try self.executeToolCall(call, permission_mgr, stdin, stdout);
    }

    /// Execute a specific tool call
    fn executeToolCall(
        self: *ToolExecutor,
        call: ToolCall,
        permission_mgr: *permissions.PermissionManager,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !ToolResult {
        if (std.mem.eql(u8, call.name, "write_file") or std.mem.eql(u8, call.name, "edit_file")) {
            return try self.executeFileEdit(call, permission_mgr, stdin, stdout);
        } else if (std.mem.eql(u8, call.name, "run_shell") or std.mem.eql(u8, call.name, "bash")) {
            return try self.executeShellCommand(call, permission_mgr, stdin, stdout);
        } else if (std.mem.eql(u8, call.name, "read_file")) {
            return try self.executeFileRead(call, permission_mgr, stdin, stdout);
        } else {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try std.fmt.allocPrint(self.allocator, "Unknown tool: {s}", .{call.name}),
                .error_message = try self.allocator.dupe(u8, "Tool not found"),
            };
        }
    }

    /// Execute file edit tool
    fn executeFileEdit(
        self: *ToolExecutor,
        call: ToolCall,
        permission_mgr: *permissions.PermissionManager,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !ToolResult {
        // Extract arguments
        const args = call.arguments;
        if (args != .object) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Invalid arguments"),
            };
        }

        const file_path = args.object.get("path") orelse args.object.get("file_path") orelse {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Missing 'path' argument"),
            };
        };

        const content = args.object.get("content") orelse args.object.get("new_content") orelse {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Missing 'content' argument"),
            };
        };

        if (file_path != .string or content != .string) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Arguments must be strings"),
            };
        }

        // Request permission
        const response = try permission_mgr.requestPermission(
            .file_write,
            file_path.string,
            stdin,
            stdout,
        );

        if (response != .allow_once) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Permission denied"),
            };
        }

        // Execute edit
        const edit = file_editor.FileEditorTool.Edit{
            .file_path = try self.allocator.dupe(u8, file_path.string),
            .new_content = try self.allocator.dupe(u8, content.string),
        };
        defer {
            self.allocator.free(edit.file_path);
            self.allocator.free(edit.new_content);
        }

        self.file_editor.execute(edit) catch |err| {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try std.fmt.allocPrint(self.allocator, "Edit failed: {}", .{err}),
            };
        };

        return ToolResult{
            .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
            .success = true,
            .output = try std.fmt.allocPrint(
                self.allocator,
                "Successfully wrote to {s}",
                .{file_path.string},
            ),
        };
    }

    /// Execute shell command tool
    fn executeShellCommand(
        self: *ToolExecutor,
        call: ToolCall,
        permission_mgr: *permissions.PermissionManager,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !ToolResult {
        const args = call.arguments;
        if (args != .object) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Invalid arguments"),
            };
        }

        const command = args.object.get("command") orelse {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Missing 'command' argument"),
            };
        };

        if (command != .string) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Command must be a string"),
            };
        }

        // Request permission
        const response = try permission_mgr.requestPermission(
            .shell_execute,
            command.string,
            stdin,
            stdout,
        );

        if (response != .allow_once) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Permission denied"),
            };
        }

        // Execute command
        var result = self.shell_runner.execute(command.string) catch |err| {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try std.fmt.allocPrint(self.allocator, "Execution failed: {}", .{err}),
            };
        };
        defer result.deinit(self.allocator);

        const output = try std.fmt.allocPrint(
            self.allocator,
            "Exit code: {d}\n\nStdout:\n{s}\n\nStderr:\n{s}",
            .{ result.exit_code, result.stdout, result.stderr },
        );

        return ToolResult{
            .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
            .success = result.exit_code == 0,
            .output = output,
        };
    }

    /// Execute file read tool
    fn executeFileRead(
        self: *ToolExecutor,
        call: ToolCall,
        permission_mgr: *permissions.PermissionManager,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !ToolResult {
        const args = call.arguments;
        if (args != .object) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Invalid arguments"),
            };
        }

        const file_path = args.object.get("path") orelse args.object.get("file_path") orelse {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Missing 'path' argument"),
            };
        };

        if (file_path != .string) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Path must be a string"),
            };
        }

        // Request permission
        const response = try permission_mgr.requestPermission(
            .file_read,
            file_path.string,
            stdin,
            stdout,
        );

        if (response != .allow_once) {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try self.allocator.dupe(u8, "Permission denied"),
            };
        }

        // Read file
        const content = std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path.string,
            10 * 1024 * 1024, // 10MB max
        ) catch |err| {
            return ToolResult{
                .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
                .success = false,
                .output = try std.fmt.allocPrint(self.allocator, "Read failed: {}", .{err}),
            };
        };

        return ToolResult{
            .tool_call_id = if (call.id) |id| try self.allocator.dupe(u8, id) else null,
            .success = true,
            .output = content,
        };
    }
};

// Tests
test "tool executor init" {
    const allocator = std.testing.allocator;

    var executor = ToolExecutor.init(allocator);
    defer executor.deinit();
}

test "enqueue tool call" {
    const allocator = std.testing.allocator;

    var executor = ToolExecutor.init(allocator);
    defer executor.deinit();

    const call = ToolExecutor.ToolCall{
        .name = try allocator.dupe(u8, "write_file"),
        .arguments = .{ .object = std.json.ObjectMap.init(allocator) },
    };

    try executor.enqueue(call);
    try std.testing.expectEqual(@as(usize, 1), executor.queue.items.len);
}
