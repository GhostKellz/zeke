// LSP Diagnostic Aggregator - Collects diagnostics from multiple LSP servers

const std = @import("std");
const types = @import("types.zig");

/// Diagnostic storage for a single file
pub const FileDiagnostics = struct {
    file_uri: []const u8,
    diagnostics: std.ArrayList(types.Diagnostic),
    server_name: []const u8,
    last_updated: i64,

    pub fn deinit(self: *FileDiagnostics, allocator: std.mem.Allocator) void {
        allocator.free(self.file_uri);
        allocator.free(self.server_name);
        for (self.diagnostics.items) |diag| {
            allocator.free(diag.message);
            if (diag.source) |src| allocator.free(src);
        }
        self.diagnostics.deinit(allocator);
    }
};

/// Aggregates diagnostics from multiple LSP servers
pub const DiagnosticAggregator = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.StringHashMap(std.ArrayList(types.Diagnostic)),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) DiagnosticAggregator {
        return .{
            .allocator = allocator,
            .diagnostics = std.StringHashMap(std.ArrayList(types.Diagnostic)).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *DiagnosticAggregator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.diagnostics.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |diag| {
                self.allocator.free(diag.message);
                if (diag.source) |src| self.allocator.free(src);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.diagnostics.deinit();
    }

    /// Store diagnostics for a file
    pub fn storeDiagnostics(
        self: *DiagnosticAggregator,
        file_uri: []const u8,
        diagnostics: []const types.Diagnostic,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove old diagnostics for this file
        if (self.diagnostics.getPtr(file_uri)) |old_diags| {
            for (old_diags.items) |diag| {
                self.allocator.free(diag.message);
                if (diag.source) |src| self.allocator.free(src);
            }
            old_diags.clearRetainingCapacity();
        }

        // Store new diagnostics
        var diag_list = std.ArrayList(types.Diagnostic).empty;
        for (diagnostics) |diag| {
            const owned_message = try self.allocator.dupe(u8, diag.message);
            const owned_source = if (diag.source) |src|
                try self.allocator.dupe(u8, src)
            else
                null;

            try diag_list.append(self.allocator, .{
                .range = diag.range,
                .severity = diag.severity,
                .message = owned_message,
                .source = owned_source,
            });
        }

        const owned_uri = try self.allocator.dupe(u8, file_uri);
        try self.diagnostics.put(owned_uri, diag_list);
    }

    /// Get diagnostics for a file
    pub fn getDiagnostics(
        self: *DiagnosticAggregator,
        file_uri: []const u8,
    ) ?[]const types.Diagnostic {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.diagnostics.get(file_uri)) |diags| {
            return diags.items;
        }
        return null;
    }

    /// Get all diagnostics
    pub fn getAllDiagnostics(
        self: *DiagnosticAggregator,
    ) !std.ArrayList(FileDiagnostics) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(FileDiagnostics).empty;

        var iter = self.diagnostics.iterator();
        while (iter.next()) |entry| {
            try result.append(self.allocator, .{
                .file_uri = entry.key_ptr.*,
                .diagnostics = entry.value_ptr.*,
                .server_name = "unknown", // TODO: Track server name
                .last_updated = std.time.timestamp(),
            });
        }

        return result;
    }

    /// Get diagnostic count for a file
    pub fn getCount(self: *DiagnosticAggregator, file_uri: []const u8) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.diagnostics.get(file_uri)) |diags| {
            return diags.items.len;
        }
        return 0;
    }

    /// Clear diagnostics for a file
    pub fn clearFile(self: *DiagnosticAggregator, file_uri: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.diagnostics.fetchRemove(file_uri)) |kv| {
            for (kv.value.items) |diag| {
                self.allocator.free(diag.message);
                if (diag.source) |src| self.allocator.free(src);
            }
            kv.value.deinit(self.allocator);
            self.allocator.free(kv.key);
        }
    }

    /// Clear all diagnostics
    pub fn clearAll(self: *DiagnosticAggregator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.diagnostics.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |diag| {
                self.allocator.free(diag.message);
                if (diag.source) |src| self.allocator.free(src);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.diagnostics.clearAndFree();
    }
};

// Tests
test "DiagnosticAggregator: store and retrieve" {
    const allocator = std.testing.allocator;

    var aggregator = DiagnosticAggregator.init(allocator);
    defer aggregator.deinit();

    const diagnostics = [_]types.Diagnostic{
        .{
            .range = .{
                .start = .{ .line = 10, .character = 5 },
                .end = .{ .line = 10, .character = 15 },
            },
            .severity = .@"error",
            .message = "Undefined variable",
            .source = "zls",
        },
    };

    try aggregator.storeDiagnostics("file:///test.zig", &diagnostics);

    const retrieved = aggregator.getDiagnostics("file:///test.zig");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(usize, 1), retrieved.?.len);
}
