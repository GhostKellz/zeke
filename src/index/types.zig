// Codebase Indexing Types
// Core data structures for indexing and searching code

const std = @import("std");

/// File entry in the index
pub const IndexedFile = struct {
    path: []const u8,
    language: Language,
    symbols: std.ArrayList(Symbol),
    imports: std.ArrayList([]const u8),
    exports: std.ArrayList([]const u8),
    last_modified: i64,
    hash: u64, // For change detection

    pub fn deinit(self: *IndexedFile, allocator: std.mem.Allocator) void {
        for (self.symbols.items) |*symbol| {
            symbol.deinit(allocator);
        }
        self.symbols.deinit(allocator);

        for (self.imports.items) |import| {
            allocator.free(import);
        }
        self.imports.deinit(allocator);

        for (self.exports.items) |export_name| {
            allocator.free(export_name);
        }
        self.exports.deinit(allocator);

        allocator.free(self.path);
    }
};

/// Programming language
pub const Language = enum {
    zig,
    rust,
    javascript,
    typescript,
    python,
    go,
    c,
    cpp,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return .javascript;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp") or std.mem.eql(u8, ext, ".cc")) return .cpp;
        return .unknown;
    }
};

/// Symbol type
pub const SymbolKind = enum {
    function,
    struct_type,
    enum_type,
    constant,
    variable,
    class,
    method,
    interface,
    type_alias,
    module,
};

/// Code symbol (function, struct, etc.)
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    line: usize,
    column: usize,
    signature: ?[]const u8, // For functions: full signature
    doc_comment: ?[]const u8,

    pub fn deinit(self: *Symbol, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.signature) |sig| allocator.free(sig);
        if (self.doc_comment) |doc| allocator.free(doc);
    }
};

/// Search result
pub const SearchResult = struct {
    file_path: []const u8,
    symbol: Symbol,
    relevance_score: f32,
    file_mtime: i64, // For recency-based ranking

    pub fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
        // If scores are very close (within 5%), use mtime as tiebreaker
        const score_diff = @abs(a.relevance_score - b.relevance_score);
        if (score_diff < 5.0) {
            // More recent files first
            return a.file_mtime > b.file_mtime;
        }
        return a.relevance_score > b.relevance_score; // Higher score first
    }
};

/// Index statistics
pub const IndexStats = struct {
    total_files: usize,
    total_symbols: usize,
    languages: std.EnumMap(Language, usize),
    index_size_bytes: usize,
    last_updated: i64,
};

/// Context for AI prompts
pub const CodeContext = struct {
    relevant_files: std.ArrayList([]const u8),
    symbols: std.ArrayList(Symbol),
    estimated_tokens: usize,

    pub fn deinit(self: *CodeContext, allocator: std.mem.Allocator) void {
        for (self.relevant_files.items) |file| {
            allocator.free(file);
        }
        self.relevant_files.deinit(allocator);

        for (self.symbols.items) |*symbol| {
            symbol.deinit(allocator);
        }
        self.symbols.deinit(allocator);
    }
};
