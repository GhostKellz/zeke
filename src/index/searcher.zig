// Symbol Searcher - Finds symbols by keyword/fuzzy matching

const std = @import("std");
const types = @import("types.zig");

pub const Searcher = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Searcher {
        return .{ .allocator = allocator };
    }

    /// Search for symbols matching query
    pub fn search(
        self: *Searcher,
        indexed_files: []const types.IndexedFile,
        query: []const u8,
        max_results: usize,
    ) !std.ArrayList(types.SearchResult) {
        var results = std.ArrayList(types.SearchResult).empty;

        // Collect all matching symbols with relevance scores
        for (indexed_files) |file| {
            for (file.symbols.items) |symbol| {
                if (self.calculateRelevance(symbol, query)) |score| {
                    if (score > 0.0) {
                        try results.append(self.allocator, .{
                            .file_path = file.path,
                            .symbol = symbol,
                            .relevance_score = score,
                            .file_mtime = file.last_modified,
                        });
                    }
                }
            }
        }

        // Sort by relevance (highest first)
        std.mem.sort(types.SearchResult, results.items, {}, types.SearchResult.lessThan);

        // Limit to max results
        if (results.items.len > max_results) {
            results.shrinkRetainingCapacity(max_results);
        }

        return results;
    }

    /// Search by symbol kind (e.g., all functions, all structs)
    pub fn searchByKind(
        self: *Searcher,
        indexed_files: []const types.IndexedFile,
        kind: types.SymbolKind,
    ) !std.ArrayList(types.SearchResult) {
        var results = std.ArrayList(types.SearchResult).empty;

        for (indexed_files) |file| {
            for (file.symbols.items) |symbol| {
                if (symbol.kind == kind) {
                    try results.append(self.allocator, .{
                        .file_path = file.path,
                        .symbol = symbol,
                        .relevance_score = 1.0,
                        .file_mtime = file.last_modified,
                    });
                }
            }
        }

        return results;
    }

    /// Find symbol by exact name
    pub fn findExact(
        self: *Searcher,
        indexed_files: []const types.IndexedFile,
        name: []const u8,
    ) !?types.SearchResult {
        _ = self;
        for (indexed_files) |file| {
            for (file.symbols.items) |symbol| {
                if (std.mem.eql(u8, symbol.name, name)) {
                    return types.SearchResult{
                        .file_path = file.path,
                        .symbol = symbol,
                        .relevance_score = 1.0,
                        .file_mtime = file.last_modified,
                    };
                }
            }
        }
        return null;
    }

    /// Find all files importing a specific module
    pub fn findImporters(
        self: *Searcher,
        indexed_files: []const types.IndexedFile,
        module_name: []const u8,
    ) !std.ArrayList([]const u8) {
        var importers = std.ArrayList([]const u8).empty;

        for (indexed_files) |file| {
            for (file.imports.items) |import| {
                if (std.mem.indexOf(u8, import, module_name) != null) {
                    try importers.append(self.allocator, file.path);
                    break;
                }
            }
        }

        return importers;
    }

    /// Get context files relevant to a task description
    pub fn getContextForTask(
        self: *Searcher,
        indexed_files: []const types.IndexedFile,
        task_description: []const u8,
        max_files: usize,
    ) !std.ArrayList([]const u8) {
        var file_scores = std.StringHashMap(f32).init(self.allocator);
        defer file_scores.deinit();

        // Extract keywords from task description
        var keywords = std.ArrayList([]const u8).empty;
        defer keywords.deinit(self.allocator);

        var words = std.mem.tokenizeAny(u8, task_description, " \t\n,.");
        while (words.next()) |word| {
            if (word.len > 3) { // Skip short words
                try keywords.append(self.allocator, word);
            }
        }

        // Score each file based on keyword matches
        for (indexed_files) |file| {
            var score: f32 = 0.0;

            // Check symbols
            for (file.symbols.items) |symbol| {
                for (keywords.items) |keyword| {
                    if (self.fuzzyMatch(symbol.name, keyword)) {
                        score += 2.0; // Symbol match is highly relevant
                    }
                    if (symbol.signature) |sig| {
                        if (self.fuzzyMatch(sig, keyword)) {
                            score += 1.0;
                        }
                    }
                }
            }

            // Check file path
            for (keywords.items) |keyword| {
                if (self.fuzzyMatch(file.path, keyword)) {
                    score += 0.5;
                }
            }

            if (score > 0.0) {
                try file_scores.put(file.path, score);
            }
        }

        // Sort files by score
        var scored_files = std.ArrayList(struct { path: []const u8, score: f32 }).empty;
        defer scored_files.deinit(self.allocator);

        var iter = file_scores.iterator();
        while (iter.next()) |entry| {
            try scored_files.append(self.allocator, .{ .path = entry.key_ptr.*, .score = entry.value_ptr.* });
        }

        std.mem.sort(@TypeOf(scored_files.items[0]), scored_files.items, {}, struct {
            fn lessThan(_: void, a: @TypeOf(scored_files.items[0]), b: @TypeOf(scored_files.items[0])) bool {
                return a.score > b.score;
            }
        }.lessThan);

        // Return top N files
        var context_files = std.ArrayList([]const u8).empty;
        const limit = @min(max_files, scored_files.items.len);
        for (scored_files.items[0..limit]) |item| {
            try context_files.append(self.allocator, item.path);
        }

        return context_files;
    }

    /// Calculate relevance score for a symbol given a query
    fn calculateRelevance(self: *Searcher, symbol: types.Symbol, query: []const u8) ?f32 {
        _ = self;

        var score: f32 = 0.0;

        // Exact match
        if (std.mem.eql(u8, symbol.name, query)) {
            return 100.0;
        }

        // Case-insensitive exact match
        if (std.ascii.eqlIgnoreCase(symbol.name, query)) {
            return 90.0;
        }

        // Prefix match
        if (std.mem.startsWith(u8, symbol.name, query)) {
            score += 50.0;
        } else if (std.ascii.startsWithIgnoreCase(symbol.name, query)) {
            score += 40.0;
        }

        // Contains match
        if (std.mem.indexOf(u8, symbol.name, query) != null) {
            score += 30.0;
        } else if (std.ascii.indexOfIgnoreCase(symbol.name, query) != null) {
            score += 20.0;
        }

        // Fuzzy match (subsequence)
        if (fuzzyMatchScore(symbol.name, query)) |fuzzy_score| {
            score += fuzzy_score;
        }

        return if (score > 0.0) score else null;
    }

    /// Simple fuzzy matching
    fn fuzzyMatch(self: *Searcher, haystack: []const u8, needle: []const u8) bool {
        _ = self;
        return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
    }

    /// Calculate fuzzy match score (subsequence matching)
    fn fuzzyMatchScore(haystack: []const u8, needle: []const u8) ?f32 {
        if (needle.len == 0) return null;
        if (needle.len > haystack.len) return null;

        var needle_idx: usize = 0;
        var score: f32 = 0.0;

        for (haystack, 0..) |char, i| {
            if (needle_idx >= needle.len) break;

            if (std.ascii.toLower(char) == std.ascii.toLower(needle[needle_idx])) {
                // Consecutive match bonus
                if (needle_idx > 0 and i > 0) {
                    score += 2.0;
                } else {
                    score += 1.0;
                }
                needle_idx += 1;
            }
        }

        return if (needle_idx == needle.len) score else null;
    }
};

// Tests
test "Searcher: exact match" {
    const allocator = std.testing.allocator;

    var searcher = Searcher.init(allocator);

    var symbols = std.ArrayList(types.Symbol).empty;
    defer symbols.deinit(allocator);

    try symbols.append(allocator, .{
        .name = try allocator.dupe(u8, "calculateTotal"),
        .kind = .function,
        .line = 10,
        .column = 0,
        .signature = null,
        .doc_comment = null,
    });

    var indexed_files = [_]types.IndexedFile{.{
        .path = try allocator.dupe(u8, "test.zig"),
        .language = .zig,
        .symbols = symbols,
        .imports = std.ArrayList([]const u8).empty,
        .exports = std.ArrayList([]const u8).empty,
        .last_modified = 0,
        .hash = 0,
    }};

    const result = try searcher.findExact(&indexed_files, "calculateTotal");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("calculateTotal", result.?.symbol.name);

    // Cleanup
    for (indexed_files[0].symbols.items) |*sym| {
        sym.deinit(allocator);
    }
    indexed_files[0].symbols.deinit(allocator);
    indexed_files[0].imports.deinit(allocator);
    indexed_files[0].exports.deinit(allocator);
    allocator.free(indexed_files[0].path);
}

test "Searcher: fuzzy match" {
    const allocator = std.testing.allocator;

    var searcher = Searcher.init(allocator);

    try std.testing.expect(searcher.fuzzyMatch("calculateTotal", "calc"));
    try std.testing.expect(searcher.fuzzyMatch("getUserById", "user"));
    try std.testing.expect(!searcher.fuzzyMatch("hello", "xyz"));
}
