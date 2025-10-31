// File Watcher - Monitors file system changes for incremental updates
// Uses Zig's std.fs.watch for cross-platform file watching

const std = @import("std");
const bus = @import("bus.zig");

pub const WatchEvent = enum {
    created,
    modified,
    deleted,
};

pub const FileChange = struct {
    path: []const u8,
    event: WatchEvent,
    timestamp: i64,
};

/// File watcher that publishes events to the event bus
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watch_path: []const u8,
    event_bus: *bus.EventBus,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,

    pub fn init(
        allocator: std.mem.Allocator,
        watch_path: []const u8,
        event_bus: *bus.EventBus,
    ) !FileWatcher {
        return .{
            .allocator = allocator,
            .watch_path = try allocator.dupe(u8, watch_path),
            .event_bus = event_bus,
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        self.stop();
        self.allocator.free(self.watch_path);
    }

    /// Start watching in background thread
    pub fn start(self: *FileWatcher) !void {
        if (self.running.load(.acquire)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, watchLoop, .{self});
    }

    /// Stop watching
    pub fn stop(self: *FileWatcher) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Main watch loop (runs in separate thread)
    fn watchLoop(self: *FileWatcher) void {
        self.watchDirectory() catch |err| {
            std.debug.print("File watcher error: {}\n", .{err});
        };
    }

    /// Watch directory for changes
    fn watchDirectory(self: *FileWatcher) !void {
        var dir = try std.fs.cwd().openDir(self.watch_path, .{ .iterate = true });
        defer dir.close();

        // Simplified polling-based approach for now
        // In production, use platform-specific APIs (inotify, FSEvents, etc.)
        var last_check = std.time.milliTimestamp();
        var file_mtimes = std.StringHashMap(i64).init(self.allocator);
        defer {
            var iter = file_mtimes.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            file_mtimes.deinit();
        }

        // Initial scan
        try self.scanDirectory(dir, &file_mtimes);

        while (self.running.load(.acquire)) {
            std.Thread.sleep(1 * std.time.ns_per_s); // Check every second

            const now = std.time.milliTimestamp();
            if (now - last_check < 1000) continue;
            last_check = now;

            // Rescan and detect changes
            try self.detectChanges(dir, &file_mtimes);
        }
    }

    /// Scan directory and record file mtimes
    fn scanDirectory(self: *FileWatcher, dir: std.fs.Dir, mtimes: *std.StringHashMap(i64)) !void {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            const stat = try dir.statFile(entry.name);
            const mtime = @divTrunc(stat.mtime, 1_000_000_000); // Convert to seconds

            const owned_name = try self.allocator.dupe(u8, entry.name);
            try mtimes.put(owned_name, mtime);
        }
    }

    /// Detect file changes
    fn detectChanges(self: *FileWatcher, dir: std.fs.Dir, mtimes: *std.StringHashMap(i64)) !void {
        var current_files = std.StringHashMap(i64).init(self.allocator);
        defer current_files.deinit();

        // Scan current state
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (self.shouldIgnore(entry.name)) continue;

            const stat = try dir.statFile(entry.name) catch continue;
            const mtime = @divTrunc(stat.mtime, 1_000_000_000);

            try current_files.put(entry.name, mtime);

            // Check if file is new or modified
            if (mtimes.get(entry.name)) |old_mtime| {
                if (mtime > old_mtime) {
                    // File modified
                    const full_path = try std.fs.path.join(
                        self.allocator,
                        &[_][]const u8{ self.watch_path, entry.name },
                    );
                    defer self.allocator.free(full_path);

                    self.event_bus.publish(.{
                        .file_changed = .{
                            .path = full_path,
                            .mtime = mtime,
                        },
                    });
                }
            } else {
                // New file
                const full_path = try std.fs.path.join(
                    self.allocator,
                    &[_][]const u8{ self.watch_path, entry.name },
                );
                defer self.allocator.free(full_path);

                self.event_bus.publish(.{ .file_added = .{ .path = full_path } });
            }
        }

        // Check for deleted files
        var old_iter = mtimes.iterator();
        while (old_iter.next()) |entry| {
            if (!current_files.contains(entry.key_ptr.*)) {
                // File deleted
                const full_path = try std.fs.path.join(
                    self.allocator,
                    &[_][]const u8{ self.watch_path, entry.key_ptr.* },
                );
                defer self.allocator.free(full_path);

                self.event_bus.publish(.{ .file_deleted = .{ .path = full_path } });
            }
        }

        // Update mtimes map
        old_iter = mtimes.iterator();
        while (old_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        mtimes.clearAndFree();

        var current_iter = current_files.iterator();
        while (current_iter.next()) |entry| {
            const owned_name = try self.allocator.dupe(u8, entry.key_ptr.*);
            try mtimes.put(owned_name, entry.value_ptr.*);
        }
    }

    /// Check if file should be ignored
    fn shouldIgnore(self: *FileWatcher, filename: []const u8) bool {
        _ = self;

        // Ignore common temp/swap files
        const ignore_patterns = [_][]const u8{
            ".swp",
            ".swo",
            ".tmp",
            "~",
            ".log",
        };

        for (ignore_patterns) |pattern| {
            if (std.mem.endsWith(u8, filename, pattern)) {
                return true;
            }
        }

        return false;
    }
};
