const std = @import("std");

/// Permission action type
pub const PermissionAction = enum {
    file_read,
    file_write,
    file_delete,
    shell_execute,
    network_request,

    pub fn toString(self: PermissionAction) []const u8 {
        return switch (self) {
            .file_read => "Read File",
            .file_write => "Write File",
            .file_delete => "Delete File",
            .shell_execute => "Execute Shell Command",
            .network_request => "Network Request",
        };
    }
};

/// User's permission response
pub const PermissionResponse = enum {
    allow_once,
    allow_always,
    deny,
    modify,

    pub fn toString(self: PermissionResponse) []const u8 {
        return switch (self) {
            .allow_once => "Allow Once",
            .allow_always => "Allow Always",
            .deny => "Deny",
            .modify => "Modify",
        };
    }
};

/// Permission request data
pub const PermissionRequest = struct {
    action: PermissionAction,
    target: []const u8, // File path, command, URL, etc.
    details: ?[]const u8 = null, // Optional details (diff preview, command args, etc.)
    reason: ?[]const u8 = null, // Why the AI wants to do this

    pub fn format(
        self: PermissionRequest,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("╭─ Permission Request ─────────────────────────╮\n", .{});
        try writer.print("│ Action: {s}\n", .{self.action.toString()});
        try writer.print("│ Target: {s}\n", .{self.target});

        if (self.reason) |reason| {
            try writer.print("│ Reason: {s}\n", .{reason});
        }

        if (self.details) |details| {
            try writer.print("│ Details:\n", .{});
            // Show details with indentation
            var lines = std.mem.splitScalar(u8, details, '\n');
            while (lines.next()) |line| {
                try writer.print("│   {s}\n", .{line});
            }
        }

        try writer.print("╰──────────────────────────────────────────────╯\n", .{});
    }
};

/// Permission dialog component
pub const PermissionDialog = struct {
    request: PermissionRequest,

    pub fn init(action: PermissionAction, target: []const u8) PermissionDialog {
        return PermissionDialog{
            .request = PermissionRequest{
                .action = action,
                .target = target,
            },
        };
    }

    pub fn withDetails(self: PermissionDialog, details: []const u8) PermissionDialog {
        var new_dialog = self;
        new_dialog.request.details = details;
        return new_dialog;
    }

    pub fn withReason(self: PermissionDialog, reason: []const u8) PermissionDialog {
        var new_dialog = self;
        new_dialog.request.reason = reason;
        return new_dialog;
    }

    /// Render the permission dialog to stdout
    pub fn render(self: *const PermissionDialog, stdout: std.posix.fd_t) !void {
        // Clear screen area for dialog
        _ = try std.posix.write(stdout, "\r\n");

        // Format and display the request
        var buf: [4096]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "{}", .{self.request});
        _ = try std.posix.write(stdout, msg);

        // Show options
        const options =
            \\Options:
            \\  [1] Allow Once     - Execute this action one time
            \\  [2] Allow Always   - Always allow this action without asking
            \\  [3] Deny           - Reject this action
            \\  [4] Modify         - Edit the command/path before allowing
            \\
            \\Your choice (1-4):
        ;
        _ = try std.posix.write(stdout, options);
    }

    /// Read user's permission response from stdin
    pub fn getUserResponse(stdin: std.posix.fd_t) !PermissionResponse {
        var buf: [128]u8 = undefined;
        const bytes_read = try std.posix.read(stdin, &buf);

        if (bytes_read == 0) return error.EndOfStream;

        const input = std.mem.trim(u8, buf[0..bytes_read], &std.ascii.whitespace);

        if (std.mem.eql(u8, input, "1")) return .allow_once;
        if (std.mem.eql(u8, input, "2")) return .allow_always;
        if (std.mem.eql(u8, input, "3")) return .deny;
        if (std.mem.eql(u8, input, "4")) return .modify;

        return error.InvalidChoice;
    }

    /// Prompt user for permission and return response
    pub fn prompt(self: *const PermissionDialog, stdin: std.posix.fd_t, stdout: std.posix.fd_t) !PermissionResponse {
        try self.render(stdout);

        while (true) {
            const response = self.getUserResponse(stdin) catch |err| {
                if (err == error.InvalidChoice) {
                    _ = try std.posix.write(stdout, "Invalid choice. Please enter 1-4: ");
                    continue;
                }
                return err;
            };

            return response;
        }
    }
};

/// Permission manager to track "always allow" rules
pub const PermissionManager = struct {
    allocator: std.mem.Allocator,
    allowed_rules: std.array_list.AlignedManaged(PermissionRule, null),

    pub const PermissionRule = struct {
        action: PermissionAction,
        target_pattern: []const u8, // Can be exact path or glob pattern

        pub fn deinit(self: *PermissionRule, allocator: std.mem.Allocator) void {
            allocator.free(self.target_pattern);
        }

        pub fn matches(self: *const PermissionRule, action: PermissionAction, target: []const u8) bool {
            if (self.action != action) return false;

            // For now, exact match. TODO: Add glob pattern matching
            return std.mem.eql(u8, self.target_pattern, target);
        }
    };

    pub fn init(allocator: std.mem.Allocator) PermissionManager {
        return PermissionManager{
            .allocator = allocator,
            .allowed_rules = std.array_list.AlignedManaged(PermissionRule, null).init(allocator),
        };
    }

    pub fn deinit(self: *PermissionManager) void {
        for (self.allowed_rules.items) |*rule| {
            rule.deinit(self.allocator);
        }
        self.allowed_rules.deinit();
    }

    /// Check if action is pre-authorized
    pub fn isAllowed(self: *const PermissionManager, action: PermissionAction, target: []const u8) bool {
        for (self.allowed_rules.items) |*rule| {
            if (rule.matches(action, target)) {
                return true;
            }
        }
        return false;
    }

    /// Add a new "always allow" rule
    pub fn addRule(self: *PermissionManager, action: PermissionAction, target: []const u8) !void {
        const owned_target = try self.allocator.dupe(u8, target);
        const rule = PermissionRule{
            .action = action,
            .target_pattern = owned_target,
        };
        try self.allowed_rules.append(rule);
    }

    /// Request permission with automatic check against saved rules
    pub fn requestPermission(
        self: *PermissionManager,
        action: PermissionAction,
        target: []const u8,
        stdin: std.posix.fd_t,
        stdout: std.posix.fd_t,
    ) !PermissionResponse {
        // Check if pre-authorized
        if (self.isAllowed(action, target)) {
            return .allow_once; // Already authorized, no need to prompt
        }

        // Create and show permission dialog
        const dialog = PermissionDialog.init(action, target);
        const response = try dialog.prompt(stdin, stdout);

        // Save "always allow" rules
        if (response == .allow_always) {
            try self.addRule(action, target);
        }

        return response;
    }
};

// Tests
test "permission dialog init" {
    const dialog = PermissionDialog.init(.file_write, "/tmp/test.txt");
    try std.testing.expectEqual(PermissionAction.file_write, dialog.request.action);
    try std.testing.expectEqualStrings("/tmp/test.txt", dialog.request.target);
}

test "permission manager" {
    const allocator = std.testing.allocator;
    var manager = PermissionManager.init(allocator);
    defer manager.deinit();

    // Not allowed initially
    try std.testing.expect(!manager.isAllowed(.file_write, "/tmp/test.txt"));

    // Add rule
    try manager.addRule(.file_write, "/tmp/test.txt");

    // Now allowed
    try std.testing.expect(manager.isAllowed(.file_write, "/tmp/test.txt"));

    // Different file not allowed
    try std.testing.expect(!manager.isAllowed(.file_write, "/tmp/other.txt"));
}
