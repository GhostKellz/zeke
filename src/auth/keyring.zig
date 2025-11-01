const std = @import("std");

/// Cross-platform secure keyring for storing OAuth tokens
/// - Linux: libsecret (GNOME Keyring / KWallet)
/// - macOS: Keychain
/// - Windows: Credential Manager
pub const Keyring = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Keyring {
        return .{ .allocator = allocator };
    }

    /// Store a secret in the system keyring
    pub fn set(self: *Keyring, service: []const u8, account: []const u8, secret: []const u8) !void {
        const os_tag = @import("builtin").os.tag;

        switch (os_tag) {
            .linux => try self.setLinux(service, account, secret),
            .macos => try self.setMacOS(service, account, secret),
            .windows => try self.setWindows(service, account, secret),
            else => return error.UnsupportedPlatform,
        }
    }

    /// Get a secret from the system keyring
    pub fn get(self: *Keyring, service: []const u8, account: []const u8) !?[]const u8 {
        const os_tag = @import("builtin").os.tag;

        return switch (os_tag) {
            .linux => try self.getLinux(service, account),
            .macos => try self.getMacOS(service, account),
            .windows => try self.getWindows(service, account),
            else => error.UnsupportedPlatform,
        };
    }

    /// Delete a secret from the system keyring
    pub fn delete(self: *Keyring, service: []const u8, account: []const u8) !void {
        const os_tag = @import("builtin").os.tag;

        switch (os_tag) {
            .linux => try self.deleteLinux(service, account),
            .macos => try self.deleteMacOS(service, account),
            .windows => try self.deleteWindows(service, account),
            else => return error.UnsupportedPlatform,
        }
    }

    // === Linux (libsecret via secret-tool) ===

    fn setLinux(self: *Keyring, service: []const u8, account: []const u8, secret: []const u8) !void {
        // Use secret-tool to store in GNOME Keyring / KWallet
        // Format: secret-tool store --label="label" service "service" account "account"
        const label = try std.fmt.allocPrint(self.allocator, "Zeke - {s}", .{service});
        defer self.allocator.free(label);

        var child = std.process.Child.init(&[_][]const u8{
            "secret-tool",
            "store",
            "--label",
            label,
            "service",
            service,
            "account",
            account,
        }, self.allocator);

        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Write secret to stdin
        try child.stdin.?.writeAll(secret);
        child.stdin.?.close();
        child.stdin = null;

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringSetFailed;
                }
            },
            else => return error.KeyringSetFailed,
        }
    }

    fn getLinux(self: *Keyring, service: []const u8, account: []const u8) !?[]const u8 {
        // Use secret-tool to retrieve from GNOME Keyring / KWallet
        // Format: secret-tool lookup service "service" account "account"
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "secret-tool",
                "lookup",
                "service",
                service,
                "account",
                account,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code == 0) {
                    // Remove trailing newline if present
                    const secret = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
                    return if (secret.len > 0)
                        try self.allocator.dupe(u8, secret)
                    else
                        null;
                } else if (code == 1) {
                    // Not found (exit code 1)
                    return null;
                } else {
                    return error.KeyringGetFailed;
                }
            },
            else => return error.KeyringGetFailed,
        }
    }

    fn deleteLinux(self: *Keyring, service: []const u8, account: []const u8) !void {
        // Use secret-tool to delete from GNOME Keyring / KWallet
        // Format: secret-tool clear service "service" account "account"
        var child = std.process.Child.init(&[_][]const u8{
            "secret-tool",
            "clear",
            "service",
            service,
            "account",
            account,
        }, self.allocator);

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringDeleteFailed;
                }
            },
            else => return error.KeyringDeleteFailed,
        }
    }

    // === macOS (Keychain via security command) ===

    fn setMacOS(self: *Keyring, service: []const u8, account: []const u8, secret: []const u8) !void {
        // First try to delete existing entry (ignore errors)
        self.deleteMacOS(service, account) catch {};

        // Add new entry
        var child = std.process.Child.init(&[_][]const u8{
            "security",
            "add-generic-password",
            "-s",
            service,
            "-a",
            account,
            "-w",
            secret,
        }, self.allocator);

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringSetFailed;
                }
            },
            else => return error.KeyringSetFailed,
        }
    }

    fn getMacOS(self: *Keyring, service: []const u8, account: []const u8) !?[]const u8 {
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "security",
                "find-generic-password",
                "-s",
                service,
                "-a",
                account,
                "-w", // Print password only
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code == 0) {
                    const secret = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
                    return if (secret.len > 0)
                        try self.allocator.dupe(u8, secret)
                    else
                        null;
                } else {
                    return null; // Not found
                }
            },
            else => return error.KeyringGetFailed,
        }
    }

    fn deleteMacOS(self: *Keyring, service: []const u8, account: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{
            "security",
            "delete-generic-password",
            "-s",
            service,
            "-a",
            account,
        }, self.allocator);

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringDeleteFailed;
                }
            },
            else => return error.KeyringDeleteFailed,
        }
    }

    // === Windows (Credential Manager via cmdkey) ===

    fn setWindows(self: *Keyring, service: []const u8, account: []const u8, secret: []const u8) !void {
        const target = try std.fmt.allocPrint(self.allocator, "Zeke/{s}/{s}", .{ service, account });
        defer self.allocator.free(target);

        // First delete if exists (ignore errors)
        self.deleteWindows(service, account) catch {};

        // Add new credential
        var child = std.process.Child.init(&[_][]const u8{
            "cmdkey",
            "/generic",
            target,
            "/user",
            account,
            "/pass",
            secret,
        }, self.allocator);

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringSetFailed;
                }
            },
            else => return error.KeyringSetFailed,
        }
    }

    fn getWindows(self: *Keyring, service: []const u8, account: []const u8) !?[]const u8 {
        // Windows cmdkey doesn't have a direct "get" command
        // We'll use PowerShell to access the credential manager
        const target = try std.fmt.allocPrint(self.allocator, "Zeke/{s}/{s}", .{ service, account });
        defer self.allocator.free(target);

        const ps_script = try std.fmt.allocPrint(
            self.allocator,
            "(Get-Credential -Target '{s}').GetNetworkCredential().Password",
            .{target},
        );
        defer self.allocator.free(ps_script);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "powershell.exe",
                "-NoProfile",
                "-Command",
                ps_script,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code == 0) {
                    const secret = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
                    return if (secret.len > 0)
                        try self.allocator.dupe(u8, secret)
                    else
                        null;
                } else {
                    return null; // Not found
                }
            },
            else => return error.KeyringGetFailed,
        }
    }

    fn deleteWindows(self: *Keyring, service: []const u8, account: []const u8) !void {
        const target = try std.fmt.allocPrint(self.allocator, "Zeke/{s}/{s}", .{ service, account });
        defer self.allocator.free(target);

        var child = std.process.Child.init(&[_][]const u8{
            "cmdkey",
            "/delete",
            target,
        }, self.allocator);

        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const term = try child.wait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    return error.KeyringDeleteFailed;
                }
            },
            else => return error.KeyringDeleteFailed,
        }
    }
};

// === Tests ===

test "keyring compile" {
    const allocator = std.testing.allocator;
    const keyring = Keyring.init(allocator);
    _ = keyring;
}
