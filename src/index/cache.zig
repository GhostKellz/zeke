// Search Result Cache - LRU cache for search results

const std = @import("std");
const types = @import("types.zig");

/// Cache entry for search results
const CacheEntry = struct {
    query: []const u8,
    results: []types.SearchResult,
    timestamp: i64,
    access_count: usize,

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        for (self.results) |result| {
            // SearchResult owns file_path and symbol name
            allocator.free(result.file_path);
            allocator.free(result.symbol.name);
            if (result.symbol.signature) |sig| {
                allocator.free(sig);
            }
            if (result.symbol.doc_comment) |doc| {
                allocator.free(doc);
            }
        }
        allocator.free(self.results);
    }
};

/// LRU cache for search results
pub const SearchCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_entries: usize,
    max_age_seconds: i64,
    mutex: std.Thread.Mutex,
    hits: usize,
    misses: usize,

    pub fn init(allocator: std.mem.Allocator) SearchCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_entries = 100, // Cache up to 100 queries
            .max_age_seconds = 300, // 5 minutes
            .mutex = .{},
            .hits = 0,
            .misses = 0,
        };
    }

    pub fn deinit(self: *SearchCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            var e = entry.value_ptr.*;
            e.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    /// Get cached results for a query
    pub fn get(self: *SearchCache, query: []const u8) ?[]types.SearchResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entries.getPtr(query)) |entry| {
            const now = std.time.timestamp();
            const age = now - entry.timestamp;

            // Check if entry is still valid
            if (age > self.max_age_seconds) {
                // Expired, remove it
                self.evict(query);
                self.misses += 1;
                return null;
            }

            // Update access count
            entry.access_count += 1;
            self.hits += 1;

            // Return copy of results (caller doesn't own them)
            return entry.results;
        }

        self.misses += 1;
        return null;
    }

    /// Store search results in cache
    pub fn put(
        self: *SearchCache,
        query: []const u8,
        results: []const types.SearchResult,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we need to evict entries
        if (self.entries.count() >= self.max_entries) {
            try self.evictLRU();
        }

        // Make owned copies of query and results
        const owned_query = try self.allocator.dupe(u8, query);
        errdefer self.allocator.free(owned_query);

        var owned_results = try self.allocator.alloc(types.SearchResult, results.len);
        errdefer self.allocator.free(owned_results);

        for (results, 0..) |result, i| {
            owned_results[i] = .{
                .file_path = try self.allocator.dupe(u8, result.file_path),
                .symbol = .{
                    .name = try self.allocator.dupe(u8, result.symbol.name),
                    .kind = result.symbol.kind,
                    .line = result.symbol.line,
                    .column = result.symbol.column,
                    .signature = if (result.symbol.signature) |sig|
                        try self.allocator.dupe(u8, sig)
                    else
                        null,
                    .doc_comment = if (result.symbol.doc_comment) |doc|
                        try self.allocator.dupe(u8, doc)
                    else
                        null,
                },
                .relevance_score = result.relevance_score,
                .file_mtime = result.file_mtime,
            };
        }

        const entry = CacheEntry{
            .query = owned_query,
            .results = owned_results,
            .timestamp = std.time.timestamp(),
            .access_count = 0,
        };

        try self.entries.put(owned_query, entry);
    }

    /// Invalidate all cache entries (called when index is updated)
    pub fn invalidateAll(self: *SearchCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            var e = entry.value_ptr.*;
            e.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.clearAndFree();

        std.debug.print("SearchCache: Invalidated all entries\n", .{});
    }

    /// Invalidate cache entries related to a specific file
    pub fn invalidateFile(self: *SearchCache, file_path: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_remove = std.ArrayList([]const u8).empty;
        defer to_remove.deinit(self.allocator);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            // Check if any result contains this file
            for (entry.value_ptr.results) |result| {
                if (std.mem.eql(u8, result.file_path, file_path)) {
                    to_remove.append(self.allocator, entry.key_ptr.*) catch break;
                    break;
                }
            }
        }

        // Remove entries
        for (to_remove.items) |query| {
            self.evict(query);
        }

        if (to_remove.items.len > 0) {
            std.debug.print("SearchCache: Invalidated {} entries for {s}\n", .{ to_remove.items.len, file_path });
        }
    }

    /// Get cache statistics
    pub fn getStats(self: *SearchCache) CacheStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const total = self.hits + self.misses;
        const hit_rate = if (total > 0) @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total)) else 0.0;

        return .{
            .entries = self.entries.count(),
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
        };
    }

    /// Evict a specific entry (assumes mutex is held)
    fn evict(self: *SearchCache, query: []const u8) void {
        if (self.entries.fetchRemove(query)) |kv| {
            var entry = kv.value;
            entry.deinit(self.allocator);
            self.allocator.free(kv.key);
        }
    }

    /// Evict least recently used entry (assumes mutex is held)
    fn evictLRU(self: *SearchCache) !void {
        var oldest_query: ?[]const u8 = null;
        var oldest_time: i64 = std.math.maxInt(i64);
        var lowest_access: usize = std.math.maxInt(usize);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            // Prefer evicting entries with lower access count
            // Then by oldest timestamp
            if (entry.value_ptr.access_count < lowest_access or
                (entry.value_ptr.access_count == lowest_access and
                entry.value_ptr.timestamp < oldest_time))
            {
                oldest_query = entry.key_ptr.*;
                oldest_time = entry.value_ptr.timestamp;
                lowest_access = entry.value_ptr.access_count;
            }
        }

        if (oldest_query) |query| {
            self.evict(query);
            std.debug.print("SearchCache: Evicted LRU entry: {s}\n", .{query});
        }
    }
};

pub const CacheStats = struct {
    entries: usize,
    hits: usize,
    misses: usize,
    hit_rate: f64,
};

// Tests
test "SearchCache: basic operations" {
    const allocator = std.testing.allocator;

    var cache = SearchCache.init(allocator);
    defer cache.deinit();

    // Create test results
    const test_results = [_]types.SearchResult{
        .{
            .file_path = "test.zig",
            .symbol = .{
                .name = "testFunc",
                .kind = .function,
                .line = 10,
                .column = 5,
                .signature = "fn testFunc() void",
            },
            .relevance_score = 95.0,
            .file_mtime = 1234567890,
        },
    };

    // Store in cache
    try cache.put("test query", &test_results);

    // Retrieve from cache
    const cached = cache.get("test query");
    try std.testing.expect(cached != null);
    try std.testing.expectEqual(@as(usize, 1), cached.?.len);

    // Check stats
    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses); // First get was a miss
}

test "SearchCache: invalidation" {
    const allocator = std.testing.allocator;

    var cache = SearchCache.init(allocator);
    defer cache.deinit();

    const test_results = [_]types.SearchResult{
        .{
            .file_path = "test.zig",
            .symbol = .{
                .name = "testFunc",
                .kind = .function,
                .line = 10,
                .column = 5,
                .signature = null,
            },
            .relevance_score = 95.0,
            .file_mtime = 1234567890,
        },
    };

    try cache.put("test", &test_results);

    // Invalidate specific file
    cache.invalidateFile("test.zig");

    // Should be gone
    const cached = cache.get("test");
    try std.testing.expect(cached == null);
}
