const std = @import("std");

/// System-wide cache stored in ~/.cache/zeke/cache.bin
/// Uses in-memory HashMap with binary serialization for persistence
pub const SystemCache = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap(CacheEntry),
    persist_path: []const u8,
    dirty: bool,

    pub const CacheEntry = struct {
        value: []const u8,
        timestamp: i64,
        ttl_seconds: i64,

        pub fn isExpired(self: *const CacheEntry) bool {
            const now = std.time.timestamp();
            return (now - self.timestamp) > self.ttl_seconds;
        }

        pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
            allocator.free(self.value);
        }
    };

    pub fn init(allocator: std.mem.Allocator) !SystemCache {
        // Get cache directory (~/.cache/zeke)
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

        const cache_dir = try std.fs.path.join(
            allocator,
            &[_][]const u8{ home, ".cache", "zeke" },
        );
        defer allocator.free(cache_dir);

        // Create cache directory if it doesn't exist
        std.fs.cwd().makePath(cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const persist_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ cache_dir, "cache.bin" },
        );

        var cache = SystemCache{
            .allocator = allocator,
            .data = std.StringHashMap(CacheEntry).init(allocator),
            .persist_path = persist_path,
            .dirty = false,
        };

        // Load from disk if exists
        cache.load() catch |err| {
            std.debug.print("⚠️  Could not load system cache: {} (starting fresh)\n", .{err});
        };

        return cache;
    }

    pub fn deinit(self: *SystemCache) void {
        // Save before destroying
        if (self.dirty) {
            self.save() catch |err| {
                std.debug.print("⚠️  Failed to save system cache: {}\n", .{err});
            };
        }

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_entry = entry.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.data.deinit();
        self.allocator.free(self.persist_path);
    }

    /// Get value from cache
    pub fn get(self: *SystemCache, key: []const u8) ?[]const u8 {
        if (self.data.getPtr(key)) |entry| {
            if (entry.isExpired()) {
                // Remove expired entry
                self.remove(key);
                return null;
            }
            return entry.value;
        }
        return null;
    }

    /// Put value into cache
    pub fn put(self: *SystemCache, key: []const u8, value: []const u8, ttl_seconds: i64) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        const entry = CacheEntry{
            .value = try self.allocator.dupe(u8, value),
            .timestamp = std.time.timestamp(),
            .ttl_seconds = ttl_seconds,
        };

        // Remove old entry if exists
        if (self.data.fetchRemove(key)) |old_kv| {
            self.allocator.free(old_kv.key);
            var mut_old = old_kv.value;
            mut_old.deinit(self.allocator);
        }

        try self.data.put(owned_key, entry);
        self.dirty = true;
    }

    /// Remove value from cache
    pub fn remove(self: *SystemCache, key: []const u8) void {
        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            var mut_entry = kv.value;
            mut_entry.deinit(self.allocator);
            self.dirty = true;
        }
    }

    /// Clear all entries
    pub fn clear(self: *SystemCache) void {
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_entry = entry.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.data.clearRetainingCapacity();
        self.dirty = true;
    }

    /// Clean up expired entries
    pub fn cleanExpired(self: *SystemCache) void {
        var to_remove = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch return;
        defer to_remove.deinit(self.allocator);

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isExpired()) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            self.remove(key);
        }
    }

    /// Save cache to disk (binary format)
    pub fn save(self: *SystemCache) !void {
        const file = try std.fs.cwd().createFile(self.persist_path, .{});
        defer file.close();

        // Clean expired entries before saving
        self.cleanExpired();

        // Write magic header
        try file.writeAll("ZEKE");

        // Write version
        var version_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &version_buf, 1, .little);
        try file.writeAll(&version_buf);

        // Write entry count
        var count_buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &count_buf, self.data.count(), .little);
        try file.writeAll(&count_buf);

        // Write each entry
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Write key length + key
            var key_len_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &key_len_buf, key.len, .little);
            try file.writeAll(&key_len_buf);
            try file.writeAll(key);

            // Write value length + value
            var value_len_buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &value_len_buf, value.value.len, .little);
            try file.writeAll(&value_len_buf);
            try file.writeAll(value.value);

            // Write metadata
            var timestamp_buf: [8]u8 = undefined;
            std.mem.writeInt(i64, &timestamp_buf, value.timestamp, .little);
            try file.writeAll(&timestamp_buf);

            var ttl_buf: [8]u8 = undefined;
            std.mem.writeInt(i64, &ttl_buf, value.ttl_seconds, .little);
            try file.writeAll(&ttl_buf);
        }

        self.dirty = false;
        std.debug.print("✅ Saved {} cache entries to {s}\n", .{ self.data.count(), self.persist_path });
    }

    /// Load cache from disk
    pub fn load(self: *SystemCache) !void {
        const file = try std.fs.cwd().openFile(self.persist_path, .{});
        defer file.close();

        // Read and verify magic header
        var magic: [4]u8 = undefined;
        _ = try file.readAll(&magic);
        if (!std.mem.eql(u8, &magic, "ZEKE")) {
            return error.InvalidCacheFile;
        }

        // Read version
        var version_buf: [4]u8 = undefined;
        _ = try file.readAll(&version_buf);
        const version = std.mem.readInt(u32, &version_buf, .little);
        if (version != 1) {
            return error.UnsupportedCacheVersion;
        }

        // Read entry count
        var count_buf: [8]u8 = undefined;
        _ = try file.readAll(&count_buf);
        const count = std.mem.readInt(u64, &count_buf, .little);

        // Read each entry
        var i: usize = 0;
        while (i < count) : (i += 1) {
            // Read key length
            var key_len_buf: [8]u8 = undefined;
            _ = try file.readAll(&key_len_buf);
            const key_len = std.mem.readInt(u64, &key_len_buf, .little);

            // Read key
            const key = try self.allocator.alloc(u8, key_len);
            errdefer self.allocator.free(key);
            _ = try file.readAll(key);

            // Read value length
            var value_len_buf: [8]u8 = undefined;
            _ = try file.readAll(&value_len_buf);
            const value_len = std.mem.readInt(u64, &value_len_buf, .little);

            // Read value
            const value = try self.allocator.alloc(u8, value_len);
            errdefer self.allocator.free(value);
            _ = try file.readAll(value);

            // Read metadata
            var timestamp_buf: [8]u8 = undefined;
            _ = try file.readAll(&timestamp_buf);
            const timestamp = std.mem.readInt(i64, &timestamp_buf, .little);

            var ttl_buf: [8]u8 = undefined;
            _ = try file.readAll(&ttl_buf);
            const ttl_seconds = std.mem.readInt(i64, &ttl_buf, .little);

            const entry = CacheEntry{
                .value = value,
                .timestamp = timestamp,
                .ttl_seconds = ttl_seconds,
            };

            // Skip expired entries
            if (entry.isExpired()) {
                self.allocator.free(key);
                self.allocator.free(value);
                continue;
            }

            try self.data.put(key, entry);
        }

        self.dirty = false;
        std.debug.print("✅ Loaded {} cache entries from {s}\n", .{ self.data.count(), self.persist_path });
    }

    /// Get cache statistics
    pub fn getStats(self: *SystemCache) CacheStats {
        var total_size: usize = 0;
        var expired_count: usize = 0;

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            total_size += entry.key_ptr.*.len + entry.value_ptr.value.len;
            if (entry.value_ptr.isExpired()) {
                expired_count += 1;
            }
        }

        return .{
            .entries = self.data.count(),
            .total_bytes = total_size,
            .expired_entries = expired_count,
        };
    }
};

pub const CacheStats = struct {
    entries: usize,
    total_bytes: usize,
    expired_entries: usize,
};

// === Tests ===

test "system cache init/deinit" {
    const allocator = std.testing.allocator;

    // Skip if HOME not set (CI environment)
    if (std.posix.getenv("HOME") == null) return error.SkipZigTest;

    var cache = try SystemCache.init(allocator);
    defer cache.deinit();
}

test "system cache put/get" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME") == null) return error.SkipZigTest;

    var cache = try SystemCache.init(allocator);
    defer cache.deinit();

    // Put value
    try cache.put("test_key", "test_value", 3600);

    // Get value
    const value = cache.get("test_key");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("test_value", value.?);
}

test "system cache expiration" {
    const allocator = std.testing.allocator;

    if (std.posix.getenv("HOME") == null) return error.SkipZigTest;

    var cache = try SystemCache.init(allocator);
    defer cache.deinit();

    // Put value with -1 TTL (already expired)
    try cache.put("expired_key", "expired_value", -1);

    // Should return null (expired)
    const value = cache.get("expired_key");
    try std.testing.expect(value == null);
}
