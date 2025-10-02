//! Cross-platform file watching for Watch Mode
//! Supports inotify (Linux) and FSEvents (macOS)

const std = @import("std");
const builtin = @import("builtin");

/// File event types
pub const EventType = enum {
    created,
    modified,
    deleted,
    renamed,
};

/// File change event
pub const Event = struct {
    path: []const u8,
    event_type: EventType,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Event) void {
        self.allocator.free(self.path);
    }
};

/// Cross-platform file watcher
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watch_paths: []const []const u8,
    ignore_patterns: []const []const u8,
    running: bool,
    impl: switch (builtin.os.tag) {
        .linux => LinuxWatcher,
        .macos => MacOSWatcher,
        else => PollingWatcher,
    },

    pub fn init(
        allocator: std.mem.Allocator,
        watch_paths: []const []const u8,
        ignore_patterns: []const []const u8,
    ) !FileWatcher {
        return .{
            .allocator = allocator,
            .watch_paths = watch_paths,
            .ignore_patterns = ignore_patterns,
            .running = false,
            .impl = try switch (builtin.os.tag) {
                .linux => LinuxWatcher.init(allocator, watch_paths),
                .macos => MacOSWatcher.init(allocator, watch_paths),
                else => PollingWatcher.init(allocator, watch_paths),
            },
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        self.impl.deinit();
    }

    /// Start watching for file changes
    pub fn start(self: *FileWatcher) !void {
        self.running = true;
        try self.impl.start();
    }

    /// Stop watching
    pub fn stop(self: *FileWatcher) void {
        self.running = false;
        self.impl.stop();
    }

    /// Get next file event (blocking)
    pub fn nextEvent(self: *FileWatcher) !?Event {
        if (!self.running) return null;

        var event = try self.impl.nextEvent();
        if (event) |*e| {
            // Check ignore patterns
            if (self.shouldIgnore(e.path)) {
                e.deinit();
                return try self.nextEvent(); // Skip and get next
            }
            return e.*;
        }
        return null;
    }

    fn shouldIgnore(self: *FileWatcher, path: []const u8) bool {
        for (self.ignore_patterns) |pattern| {
            if (std.mem.indexOf(u8, pattern, "**") != null) {
                const prefix = std.mem.sliceTo(pattern, '*');
                if (std.mem.indexOf(u8, path, prefix) != null) return true;
            } else if (std.mem.indexOf(u8, path, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};

/// Linux inotify-based watcher
const LinuxWatcher = struct {
    allocator: std.mem.Allocator,
    inotify_fd: std.posix.fd_t,
    watch_descriptors: std.ArrayList(WatchDesc),

    const WatchDesc = struct {
        wd: i32,
        path: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, watch_paths: []const []const u8) !LinuxWatcher {
        const IN = std.os.linux.IN;
        const fd = try std.posix.inotify_init1(IN.NONBLOCK);
        errdefer std.posix.close(fd);

        var wds: std.ArrayList(WatchDesc) = .{};
        errdefer wds.deinit(allocator);

        // Add watches for all paths recursively
        for (watch_paths) |path| {
            try addWatchRecursive(allocator, fd, path, &wds);
        }

        return .{
            .allocator = allocator,
            .inotify_fd = fd,
            .watch_descriptors = wds,
        };
    }

    fn addWatchRecursive(
        allocator: std.mem.Allocator,
        fd: std.posix.fd_t,
        path: []const u8,
        wds: *std.ArrayList(WatchDesc),
    ) !void {
        // Add watch for this directory
        const IN = std.os.linux.IN;
        const mask = IN.CREATE | IN.MODIFY | IN.DELETE | IN.MOVE;

        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        const wd = std.posix.inotify_add_watch(fd, path_z, mask) catch |err| {
            std.log.warn("Failed to watch {s}: {}", .{ path, err });
            return;
        };

        try wds.append(allocator, .{
            .wd = wd,
            .path = try allocator.dupe(u8, path),
        });

        // Recursively add watches for subdirectories
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry.name });
                defer allocator.free(full_path);
                try addWatchRecursive(allocator, fd, full_path, wds);
            }
        }
    }

    pub fn deinit(self: *LinuxWatcher) void {
        for (self.watch_descriptors.items) |wd| {
            self.allocator.free(wd.path);
        }
        self.watch_descriptors.deinit(self.allocator);
        std.posix.close(self.inotify_fd);
    }

    pub fn start(self: *LinuxWatcher) !void {
        _ = self;
        // inotify is passive, no start action needed
    }

    pub fn stop(self: *LinuxWatcher) void {
        _ = self;
        // No explicit stop needed
    }

    pub fn nextEvent(self: *LinuxWatcher) !?Event {
        var buf: [4096]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;

        const len = std.posix.read(self.inotify_fd, &buf) catch |err| {
            if (err == error.WouldBlock) {
                // No events available, sleep briefly
                std.Thread.sleep(100 * std.time.ns_per_ms);
                return null;
            }
            return err;
        };

        if (len == 0) return null;

        // Parse inotify event
        const event_ptr: *const std.os.linux.inotify_event = @alignCast(@ptrCast(&buf[0]));
        const event = event_ptr.*;

        // Find the watch descriptor's path
        var base_path: ?[]const u8 = null;
        for (self.watch_descriptors.items) |wd| {
            if (wd.wd == event.wd) {
                base_path = wd.path;
                break;
            }
        }

        if (base_path == null) return null;

        // Get filename from event (null-terminated string after event struct)
        const name_len = event.len;
        const name_ptr = @as([*]const u8, @ptrCast(&buf[@sizeOf(std.os.linux.inotify_event)]));
        const name = if (name_len > 0)
            std.mem.sliceTo(name_ptr[0..name_len], 0)
        else
            "";

        const full_path = if (name.len > 0)
            try std.fs.path.join(self.allocator, &[_][]const u8{ base_path.?, name })
        else
            try self.allocator.dupe(u8, base_path.?);

        const IN = std.os.linux.IN;
        const event_type: EventType = if (event.mask & IN.CREATE != 0)
            .created
        else if (event.mask & IN.MODIFY != 0)
            .modified
        else if (event.mask & IN.DELETE != 0)
            .deleted
        else if (event.mask & IN.MOVE != 0)
            .renamed
        else
            .modified;

        return Event{
            .path = full_path,
            .event_type = event_type,
            .allocator = self.allocator,
        };
    }
};

/// macOS FSEvents-based watcher (stub for now)
const MacOSWatcher = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, watch_paths: []const []const u8) !MacOSWatcher {
        _ = watch_paths;
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MacOSWatcher) void {
        _ = self;
    }

    pub fn start(self: *MacOSWatcher) !void {
        _ = self;
        return error.NotImplemented;
    }

    pub fn stop(self: *MacOSWatcher) void {
        _ = self;
    }

    pub fn nextEvent(self: *MacOSWatcher) !?Event {
        _ = self;
        return error.NotImplemented;
    }
};

/// Fallback polling-based watcher
const PollingWatcher = struct {
    allocator: std.mem.Allocator,
    last_check: i64,

    pub fn init(allocator: std.mem.Allocator, watch_paths: []const []const u8) !PollingWatcher {
        _ = watch_paths;
        return .{
            .allocator = allocator,
            .last_check = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *PollingWatcher) void {
        _ = self;
    }

    pub fn start(self: *PollingWatcher) !void {
        _ = self;
        return error.NotImplemented;
    }

    pub fn stop(self: *PollingWatcher) void {
        _ = self;
    }

    pub fn nextEvent(self: *PollingWatcher) !?Event {
        _ = self;
        // TODO: Implement polling-based detection
        std.Thread.sleep(1 * std.time.ns_per_s);
        return null;
    }
};

test "FileWatcher init" {
    const allocator = std.testing.allocator;
    var watcher = try FileWatcher.init(
        allocator,
        &[_][]const u8{"."},
        &[_][]const u8{ ".git/**", "zig-cache/**" },
    );
    defer watcher.deinit();
}
