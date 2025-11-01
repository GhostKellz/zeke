const std = @import("std");

/// AI response cache entry
pub const CacheEntry = struct {
    prompt_hash: u64,
    response: []const u8,
    model: []const u8,
    timestamp: i64,
    access_count: usize,

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.response);
        allocator.free(self.model);
    }
};

/// LRU cache for AI responses to save API calls and money
pub const AiResponseCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_entries: usize,
    max_age_seconds: i64,
    hits: usize,
    misses: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize, max_age_seconds: i64) AiResponseCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_entries = max_entries,
            .max_age_seconds = max_age_seconds,
            .hits = 0,
            .misses = 0,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *AiResponseCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_entry = entry.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    /// Get cached response for a prompt
    pub fn get(self: *AiResponseCache, prompt: []const u8, model: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key = self.makeKey(prompt, model) catch return null;
        defer self.allocator.free(key);

        if (self.entries.getPtr(key)) |entry| {
            const now = std.time.timestamp();
            const age = now - entry.timestamp;

            // Check if entry is stale
            if (age > self.max_age_seconds) {
                self.evict(key);
                self.misses += 1;
                return null;
            }

            // Update access count
            entry.access_count += 1;

            self.hits += 1;
            return entry.response;
        }

        self.misses += 1;
        return null;
    }

    /// Cache an AI response
    pub fn put(self: *AiResponseCache, prompt: []const u8, model: []const u8, response: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we need to evict
        if (self.entries.count() >= self.max_entries) {
            try self.evictLRU();
        }

        const key = try self.makeKey(prompt, model);
        errdefer self.allocator.free(key);

        const entry = CacheEntry{
            .prompt_hash = self.hashPrompt(prompt),
            .response = try self.allocator.dupe(u8, response),
            .model = try self.allocator.dupe(u8, model),
            .timestamp = std.time.timestamp(),
            .access_count = 0,
        };

        // Remove old entry if exists
        if (self.entries.fetchRemove(key)) |old_kv| {
            self.allocator.free(old_kv.key);
            var mut_old = old_kv.value;
            mut_old.deinit(self.allocator);
        }

        try self.entries.put(key, entry);
    }

    /// Invalidate cache for a specific model
    pub fn invalidateModel(self: *AiResponseCache, model: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var to_remove = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch return;
        defer to_remove.deinit(self.allocator);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.model, model)) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            self.evict(key);
        }
    }

    /// Clear all cached entries
    pub fn clear(self: *AiResponseCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_entry = entry.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();

        self.hits = 0;
        self.misses = 0;
    }

    /// Get cache statistics
    pub fn getStats(self: *AiResponseCache) CacheStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const total_requests = self.hits + self.misses;
        const hit_rate = if (total_requests > 0)
            @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total_requests))
        else
            0.0;

        return .{
            .entries = self.entries.count(),
            .max_entries = self.max_entries,
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = hit_rate,
        };
    }

    /// Print cache statistics
    pub fn printStats(self: *AiResponseCache) void {
        const stats = self.getStats();
        std.debug.print(
            \\
            \\📊 AI Response Cache Statistics:
            \\  Entries: {}/{} ({d:.1}% full)
            \\  Hits: {}
            \\  Misses: {}
            \\  Hit Rate: {d:.1}%
            \\  Estimated Savings: ~${d:.2} (assuming $0.01/request)
            \\
        , .{
            stats.entries,
            stats.max_entries,
            @as(f32, @floatFromInt(stats.entries)) / @as(f32, @floatFromInt(stats.max_entries)) * 100.0,
            stats.hits,
            stats.misses,
            stats.hit_rate * 100.0,
            @as(f32, @floatFromInt(stats.hits)) * 0.01,
        });
    }

    // === Private Methods ===

    fn makeKey(self: *AiResponseCache, prompt: []const u8, model: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ model, prompt });
    }

    fn hashPrompt(self: *AiResponseCache, prompt: []const u8) u64 {
        _ = self;
        return std.hash.Wyhash.hash(0, prompt);
    }

    fn evict(self: *AiResponseCache, key: []const u8) void {
        if (self.entries.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            var mut_entry = kv.value;
            mut_entry.deinit(self.allocator);
        }
    }

    fn evictLRU(self: *AiResponseCache) !void {
        // Find entry with lowest access count and oldest timestamp
        var lru_key: ?[]const u8 = null;
        var lru_score: f32 = std.math.floatMax(f32);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Calculate LRU score (lower is more likely to be evicted)
            // Score = access_count / age_in_hours
            const now = std.time.timestamp();
            const age_hours = @as(f32, @floatFromInt(now - value.timestamp)) / 3600.0;
            const score = if (age_hours > 0)
                @as(f32, @floatFromInt(value.access_count)) / age_hours
            else
                @as(f32, @floatFromInt(value.access_count));

            if (score < lru_score) {
                lru_score = score;
                lru_key = key;
            }
        }

        if (lru_key) |key| {
            std.debug.print("🗑️  Evicting LRU cache entry (score: {d:.2})\n", .{lru_score});
            self.evict(key);
        }
    }
};

pub const CacheStats = struct {
    entries: usize,
    max_entries: usize,
    hits: usize,
    misses: usize,
    hit_rate: f32,
};

// === Tests ===

test "ai cache init/deinit" {
    const allocator = std.testing.allocator;

    var cache = AiResponseCache.init(allocator, 100, 3600);
    defer cache.deinit();

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.entries);
    try std.testing.expectEqual(@as(usize, 0), stats.hits);
    try std.testing.expectEqual(@as(usize, 0), stats.misses);
}

test "ai cache put and get" {
    const allocator = std.testing.allocator;

    var cache = AiResponseCache.init(allocator, 100, 3600);
    defer cache.deinit();

    // Cache a response
    try cache.put("What is 2+2?", "gpt-4", "The answer is 4.");

    // Retrieve cached response
    const cached = cache.get("What is 2+2?", "gpt-4");
    try std.testing.expect(cached != null);
    try std.testing.expectEqualStrings("The answer is 4.", cached.?);

    // Check stats
    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.entries);
    try std.testing.expectEqual(@as(usize, 1), stats.hits);
}

test "ai cache miss" {
    const allocator = std.testing.allocator;

    var cache = AiResponseCache.init(allocator, 100, 3600);
    defer cache.deinit();

    // Try to get non-existent entry
    const result = cache.get("What is 2+2?", "gpt-4");
    try std.testing.expect(result == null);

    // Check stats
    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
}

test "ai cache LRU eviction" {
    const allocator = std.testing.allocator;

    var cache = AiResponseCache.init(allocator, 3, 3600); // Max 3 entries
    defer cache.deinit();

    // Fill cache
    try cache.put("prompt1", "gpt-4", "response1");
    try cache.put("prompt2", "gpt-4", "response2");
    try cache.put("prompt3", "gpt-4", "response3");

    try std.testing.expectEqual(@as(usize, 3), cache.entries.count());

    // Add 4th entry (should evict least recently used)
    try cache.put("prompt4", "gpt-4", "response4");

    try std.testing.expectEqual(@as(usize, 3), cache.entries.count());
}

test "ai cache clear" {
    const allocator = std.testing.allocator;

    var cache = AiResponseCache.init(allocator, 100, 3600);
    defer cache.deinit();

    try cache.put("prompt1", "gpt-4", "response1");
    try cache.put("prompt2", "gpt-4", "response2");

    try std.testing.expectEqual(@as(usize, 2), cache.entries.count());

    cache.clear();

    try std.testing.expectEqual(@as(usize, 0), cache.entries.count());
    try std.testing.expectEqual(@as(usize, 0), cache.hits);
    try std.testing.expectEqual(@as(usize, 0), cache.misses);
}
