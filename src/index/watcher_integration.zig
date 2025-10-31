// Index Watcher Integration - Connects file watching to incremental index updates

const std = @import("std");
const Index = @import("index.zig").Index;
const bus = @import("../events/bus.zig");

/// Integrates file watcher with index for incremental updates
pub const IndexWatcher = struct {
    allocator: std.mem.Allocator,
    index: *Index,
    event_bus: *bus.EventBus,
    subscription_ids: std.ArrayList(usize),

    pub fn init(
        allocator: std.mem.Allocator,
        index: *Index,
        event_bus: *bus.EventBus,
    ) IndexWatcher {
        return .{
            .allocator = allocator,
            .index = index,
            .event_bus = event_bus,
            .subscription_ids = std.ArrayList(usize).empty,
        };
    }

    pub fn deinit(self: *IndexWatcher) void {
        // Unsubscribe from all events
        for (self.subscription_ids.items) |id| {
            self.event_bus.unsubscribe(id) catch {};
        }
        self.subscription_ids.deinit(self.allocator);
    }

    /// Start watching for file changes and updating index
    pub fn start(self: *IndexWatcher) !void {
        // Subscribe to file change events
        try self.event_bus.subscribe(
            .file_changed,
            handleFileChanged,
            self,
        );

        try self.event_bus.subscribe(
            .file_added,
            handleFileAdded,
            self,
        );

        try self.event_bus.subscribe(
            .file_deleted,
            handleFileDeleted,
            self,
        );

        std.debug.print("IndexWatcher: Started monitoring file changes\n", .{});
    }

    /// Handle file changed event
    fn handleFileChanged(event: bus.Event, context: ?*anyopaque) void {
        const self = @as(*IndexWatcher, @ptrCast(@alignCast(context.?)));

        switch (event) {
            .file_changed => |e| {
                std.debug.print("IndexWatcher: File changed: {s}\n", .{e.path});

                // Update file in index
                self.index.updateFile(e.path) catch |err| {
                    std.debug.print("IndexWatcher: Failed to update file: {}\n", .{err});
                    return;
                };

                // Publish index updated event
                self.event_bus.publish(.{
                    .index_updated = .{
                        .file_path = e.path,
                        .operation = "updated",
                        .timestamp = std.time.timestamp(),
                    },
                });
            },
            else => {},
        }
    }

    /// Handle file added event
    fn handleFileAdded(event: bus.Event, context: ?*anyopaque) void {
        const self = @as(*IndexWatcher, @ptrCast(@alignCast(context.?)));

        switch (event) {
            .file_added => |e| {
                std.debug.print("IndexWatcher: File added: {s}\n", .{e.path});

                // Check if already indexed
                if (self.index.containsFile(e.path)) {
                    return;
                }

                // Add file to index
                self.index.updateFile(e.path) catch |err| {
                    std.debug.print("IndexWatcher: Failed to add file: {}\n", .{err});
                    return;
                };

                // Publish index updated event
                self.event_bus.publish(.{
                    .index_updated = .{
                        .file_path = e.path,
                        .operation = "added",
                        .timestamp = std.time.timestamp(),
                    },
                });
            },
            else => {},
        }
    }

    /// Handle file deleted event
    fn handleFileDeleted(event: bus.Event, context: ?*anyopaque) void {
        const self = @as(*IndexWatcher, @ptrCast(@alignCast(context.?)));

        switch (event) {
            .file_deleted => |e| {
                std.debug.print("IndexWatcher: File deleted: {s}\n", .{e.path});

                // Remove file from index
                self.index.removeFile(e.path);

                // Publish index updated event
                self.event_bus.publish(.{
                    .index_updated = .{
                        .file_path = e.path,
                        .operation = "deleted",
                        .timestamp = std.time.timestamp(),
                    },
                });
            },
            else => {},
        }
    }
};

// Tests
test "IndexWatcher: integration" {
    const allocator = std.testing.allocator;

    var event_bus = bus.EventBus.init(allocator);
    defer event_bus.deinit();

    var index = try Index.init(allocator, "/tmp/test");
    defer index.deinit();

    var watcher = IndexWatcher.init(allocator, &index, &event_bus);
    defer watcher.deinit();

    try watcher.start();

    // Simulate file changed event
    event_bus.publish(.{
        .file_changed = .{
            .path = "/tmp/test/file.zig",
            .mtime = std.time.timestamp(),
        },
    });

    // The handler would be called here in real scenario
}
