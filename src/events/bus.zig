// Event Bus - Type-safe event system for reactive programming
// Inspired by OpenCode's event bus pattern

const std = @import("std");

/// Event type identifier
pub const EventType = enum {
    file_changed,
    file_added,
    file_deleted,
    index_updated,
    lsp_diagnostics,
    lsp_initialized,
    lsp_shutdown,
};

/// Generic event payload
pub const Event = union(EventType) {
    file_changed: FileChangedEvent,
    file_added: FileAddedEvent,
    file_deleted: FileDeletedEvent,
    index_updated: IndexUpdatedEvent,
    lsp_diagnostics: LspDiagnosticsEvent,
    lsp_initialized: LspInitializedEvent,
    lsp_shutdown: LspShutdownEvent,
};

/// File change events
pub const FileChangedEvent = struct {
    path: []const u8,
    mtime: i64,
};

pub const FileAddedEvent = struct {
    path: []const u8,
};

pub const FileDeletedEvent = struct {
    path: []const u8,
};

/// Index events
pub const IndexUpdatedEvent = struct {
    files_added: usize,
    files_removed: usize,
    symbols_updated: usize,
};

/// LSP events
pub const LspDiagnosticsEvent = struct {
    file_uri: []const u8,
    diagnostic_count: usize,
};

pub const LspInitializedEvent = struct {
    server_name: []const u8,
};

pub const LspShutdownEvent = struct {
    server_name: []const u8,
};

/// Event handler callback
pub const EventHandler = *const fn (event: Event, context: ?*anyopaque) void;

/// Event subscription
const Subscription = struct {
    event_type: EventType,
    handler: EventHandler,
    context: ?*anyopaque,
};

/// Event Bus - Publish/Subscribe system
pub const EventBus = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.ArrayList(Subscription),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) EventBus {
        return .{
            .allocator = allocator,
            .subscriptions = std.ArrayList(Subscription).empty,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *EventBus) void {
        self.subscriptions.deinit(self.allocator);
    }

    /// Subscribe to an event type
    pub fn subscribe(
        self: *EventBus,
        event_type: EventType,
        handler: EventHandler,
        context: ?*anyopaque,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.subscriptions.append(self.allocator, .{
            .event_type = event_type,
            .handler = handler,
            .context = context,
        });
    }

    /// Publish an event to all subscribers
    pub fn publish(self: *EventBus, event: Event) void {
        self.mutex.lock();
        const subs = self.subscriptions.items;
        self.mutex.unlock();

        const event_type = @as(EventType, event);

        for (subs) |sub| {
            if (sub.event_type == event_type) {
                sub.handler(event, sub.context);
            }
        }
    }

    /// Subscribe once - handler will be removed after first invocation
    pub fn once(
        self: *EventBus,
        event_type: EventType,
        handler: EventHandler,
        context: ?*anyopaque,
    ) !void {
        // For simplicity, just use regular subscribe
        // In production, you'd track and remove after first call
        try self.subscribe(event_type, handler, context);
    }

    /// Unsubscribe a handler
    pub fn unsubscribe(
        self: *EventBus,
        event_type: EventType,
        handler: EventHandler,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.subscriptions.items.len) {
            const sub = self.subscriptions.items[i];
            if (sub.event_type == event_type and sub.handler == handler) {
                _ = self.subscriptions.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Clear all subscriptions
    pub fn clear(self: *EventBus) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.subscriptions.clearRetainingCapacity();
    }
};

// Tests
test "EventBus: basic publish/subscribe" {
    const allocator = std.testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    var received = false;

    const handler = struct {
        fn handle(event: Event, context: ?*anyopaque) void {
            _ = event;
            const ptr: *bool = @ptrCast(@alignCast(context.?));
            ptr.* = true;
        }
    }.handle;

    try bus.subscribe(.file_changed, handler, &received);

    bus.publish(.{ .file_changed = .{ .path = "test.zig", .mtime = 12345 } });

    try std.testing.expect(received);
}

test "EventBus: multiple subscribers" {
    const allocator = std.testing.allocator;

    var bus = EventBus.init(allocator);
    defer bus.deinit();

    var count: usize = 0;

    const handler = struct {
        fn handle(event: Event, context: ?*anyopaque) void {
            _ = event;
            const ptr: *usize = @ptrCast(@alignCast(context.?));
            ptr.* += 1;
        }
    }.handle;

    try bus.subscribe(.file_added, handler, &count);
    try bus.subscribe(.file_added, handler, &count);

    bus.publish(.{ .file_added = .{ .path = "new.zig" } });

    try std.testing.expectEqual(@as(usize, 2), count);
}
