// Codebase Index - Main coordinator for indexing and searching

const std = @import("std");
const types = @import("types.zig");
const Walker = @import("walker.zig").Walker;
const Parser = @import("parser.zig").Parser;
const Searcher = @import("searcher.zig").Searcher;
const SearchCache = @import("cache.zig").SearchCache;

pub const Index = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(types.IndexedFile),
    walker: Walker,
    parser: Parser,
    searcher: Searcher,
    cache: SearchCache,
    root_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) !Index {
        return Index{
            .allocator = allocator,
            .files = std.ArrayList(types.IndexedFile).empty,
            .walker = Walker.init(allocator),
            .parser = Parser.init(allocator),
            .searcher = Searcher.init(allocator),
            .cache = SearchCache.init(allocator),
            .root_path = try allocator.dupe(u8, root_path),
        };
    }

    pub fn deinit(self: *Index) void {
        for (self.files.items) |*file| {
            file.deinit(self.allocator);
        }
        self.files.deinit(self.allocator);
        self.walker.deinit();
        self.cache.deinit();
        self.allocator.free(self.root_path);
    }

    /// Build index for project
    pub fn buildIndex(self: *Index) !void {
        std.debug.print("Indexing project at: {s}\n", .{self.root_path});

        // Add default ignore patterns
        try self.walker.addDefaultIgnores();

        // Walk directory to find source files
        std.debug.print("Finding source files...\n", .{});
        var file_paths = try self.walker.walk(self.root_path);
        defer {
            for (file_paths.items) |path| {
                self.allocator.free(path);
            }
            file_paths.deinit(self.allocator);
        }

        std.debug.print("Found {} source files\n", .{file_paths.items.len});

        // Parse each file
        var parsed_count: usize = 0;
        for (file_paths.items) |path| {
            const ext = std.fs.path.extension(path);
            const language = types.Language.fromExtension(ext);

            if (language == .unknown) continue;

            std.debug.print("Parsing: {s}\n", .{path});

            const indexed_file = self.parser.parseFile(path, language) catch |err| {
                std.debug.print("  Warning: Failed to parse {s}: {}\n", .{ path, err });
                continue;
            };

            try self.files.append(self.allocator, indexed_file);
            parsed_count += 1;
        }

        std.debug.print("\nIndexing complete!\n", .{});
        std.debug.print("  Files indexed: {}\n", .{parsed_count});
        std.debug.print("  Total symbols: {}\n", .{self.getTotalSymbols()});
    }

    /// Update a single file in the index (incremental update)
    pub fn updateFile(self: *Index, file_path: []const u8) !void {
        const ext = std.fs.path.extension(file_path);
        const language = types.Language.fromExtension(ext);

        if (language == .unknown) return;

        // Find existing file in index
        var found_index: ?usize = null;
        for (self.files.items, 0..) |file, i| {
            if (std.mem.eql(u8, file.path, file_path)) {
                found_index = i;
                break;
            }
        }

        // Parse the file
        const indexed_file = self.parser.parseFile(file_path, language) catch |err| {
            std.debug.print("Warning: Failed to parse {s}: {}\n", .{ file_path, err });
            return err;
        };

        if (found_index) |idx| {
            // Replace existing file
            self.files.items[idx].deinit(self.allocator);
            self.files.items[idx] = indexed_file;
            std.debug.print("Updated file in index: {s}\n", .{file_path});
        } else {
            // Add new file
            try self.files.append(self.allocator, indexed_file);
            std.debug.print("Added file to index: {s}\n", .{file_path});
        }

        // Invalidate cache entries for this file
        self.cache.invalidateFile(file_path);
    }

    /// Remove a file from the index
    pub fn removeFile(self: *Index, file_path: []const u8) void {
        var i: usize = 0;
        while (i < self.files.items.len) {
            if (std.mem.eql(u8, self.files.items[i].path, file_path)) {
                var removed = self.files.orderedRemove(i);
                removed.deinit(self.allocator);
                std.debug.print("Removed file from index: {s}\n", .{file_path});

                // Invalidate cache entries for this file
                self.cache.invalidateFile(file_path);
                return;
            }
            i += 1;
        }
    }

    /// Check if file is already indexed
    pub fn containsFile(self: *Index, file_path: []const u8) bool {
        for (self.files.items) |file| {
            if (std.mem.eql(u8, file.path, file_path)) {
                return true;
            }
        }
        return false;
    }

    /// Search for symbols (with caching)
    pub fn search(self: *Index, query: []const u8, max_results: usize) !std.ArrayList(types.SearchResult) {
        // Try cache first
        if (self.cache.get(query)) |cached_results| {
            std.debug.print("🎯 Cache hit for query: {s}\n", .{query});
            var results = std.ArrayList(types.SearchResult).empty;

            // Return up to max_results from cache
            const count = @min(max_results, cached_results.len);
            for (cached_results[0..count]) |result| {
                try results.append(self.allocator, result);
            }

            return results;
        }

        // Cache miss - perform search
        std.debug.print("🔍 Cache miss for query: {s}\n", .{query});
        const results = try self.searcher.search(self.files.items, query, max_results);

        // Store in cache (don't store if results are empty)
        if (results.items.len > 0) {
            self.cache.put(query, results.items) catch |err| {
                std.debug.print("Warning: Failed to cache results: {}\n", .{err});
            };
        }

        return results;
    }

    /// Get cache statistics
    pub fn getCacheStats(self: *Index) @import("cache.zig").CacheStats {
        return self.cache.getStats();
    }

    /// Search by symbol kind
    pub fn searchByKind(self: *Index, kind: types.SymbolKind) !std.ArrayList(types.SearchResult) {
        return self.searcher.searchByKind(self.files.items, kind);
    }

    /// Find symbol by exact name
    pub fn findExact(self: *Index, name: []const u8) !?types.SearchResult {
        return self.searcher.findExact(self.files.items, name);
    }

    /// Get relevant context for a task
    pub fn getContextForTask(self: *Index, task_description: []const u8, max_files: usize) !std.ArrayList([]const u8) {
        return self.searcher.getContextForTask(self.files.items, task_description, max_files);
    }

    /// Get index statistics
    pub fn getStats(self: *Index) types.IndexStats {
        var languages = std.EnumMap(types.Language, usize).initFull(0);

        for (self.files.items) |file| {
            const count = languages.get(file.language) orelse 0;
            languages.put(file.language, count + 1);
        }

        return .{
            .total_files = self.files.items.len,
            .total_symbols = self.getTotalSymbols(),
            .languages = languages,
            .index_size_bytes = self.estimateSize(),
            .last_updated = std.time.timestamp(),
        };
    }

    /// Print index statistics
    pub fn printStats(self: *Index) void {
        var stats = self.getStats();
        const cache_stats = self.cache.getStats();

        std.debug.print("\n📊 Index Statistics\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("  Total files:   {}\n", .{stats.total_files});
        std.debug.print("  Total symbols: {}\n", .{stats.total_symbols});
        std.debug.print("  Index size:    {} bytes\n", .{stats.index_size_bytes});

        std.debug.print("\n  Languages:\n", .{});
        var lang_iter = stats.languages.iterator();
        while (lang_iter.next()) |entry| {
            if (entry.value.* > 0) {
                std.debug.print("    {s}: {} files\n", .{ @tagName(entry.key), entry.value.* });
            }
        }

        std.debug.print("\n  Cache:\n", .{});
        std.debug.print("    Entries:   {}\n", .{cache_stats.entries});
        std.debug.print("    Hits:      {}\n", .{cache_stats.hits});
        std.debug.print("    Misses:    {}\n", .{cache_stats.misses});
        std.debug.print("    Hit rate:  {d:.1}%\n", .{cache_stats.hit_rate * 100.0});
        std.debug.print("\n", .{});
    }

    /// Print search results
    pub fn printSearchResults(results: []const types.SearchResult, limit: usize) void {
        const display_count = @min(limit, results.len);

        std.debug.print("\n🔍 Search Results ({} matches)\n", .{results.len});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

        for (results[0..display_count]) |result| {
            std.debug.print("\n  {s} ", .{symbolKindIcon(result.symbol.kind)});
            std.debug.print("{s}\n", .{result.symbol.name});
            std.debug.print("    {s}:{}\n", .{ result.file_path, result.symbol.line });

            if (result.symbol.signature) |sig| {
                std.debug.print("    {s}\n", .{sig});
            }

            if (result.symbol.doc_comment) |doc| {
                std.debug.print("    /// {s}\n", .{doc});
            }

            std.debug.print("    Score: {d:.1}\n", .{result.relevance_score});
        }

        if (results.len > display_count) {
            std.debug.print("\n  ... and {} more results\n", .{results.len - display_count});
        }
        std.debug.print("\n", .{});
    }

    /// Get total number of symbols
    fn getTotalSymbols(self: *Index) usize {
        var count: usize = 0;
        for (self.files.items) |file| {
            count += file.symbols.items.len;
        }
        return count;
    }

    /// Estimate index size in bytes
    fn estimateSize(self: *Index) usize {
        var size: usize = 0;

        for (self.files.items) |file| {
            size += file.path.len;
            size += file.imports.items.len * @sizeOf([]const u8);
            size += file.exports.items.len * @sizeOf([]const u8);

            for (file.symbols.items) |symbol| {
                size += symbol.name.len;
                if (symbol.signature) |sig| size += sig.len;
                if (symbol.doc_comment) |doc| size += doc.len;
            }
        }

        return size;
    }

    /// Symbol kind to icon
    pub fn symbolKindIcon(kind: types.SymbolKind) []const u8 {
        return switch (kind) {
            .function => "ƒ",
            .struct_type => "⬡",
            .enum_type => "⊞",
            .constant => "π",
            .variable => "x",
            .class => "⬢",
            .method => "m",
            .interface => "◈",
            .type_alias => "τ",
            .module => "▣",
        };
    }
};

// Export all submodules
pub const IndexedFile = types.IndexedFile;
pub const Language = types.Language;
pub const Symbol = types.Symbol;
pub const SymbolKind = types.SymbolKind;
pub const SearchResult = types.SearchResult;
pub const IndexStats = types.IndexStats;
pub const CodeContext = types.CodeContext;

// Tests
test "Index: build and search" {
    // This would require a test directory with sample files
    // For now, just verify the module compiles
    _ = Index;
}
