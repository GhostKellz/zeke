//! Grove Integration - AST-Based Code Intelligence
//!
//! This module integrates Grove (github.com/ghostkellz/grove) to provide
//! advanced code parsing and manipulation capabilities:
//! - AST-based code analysis
//! - Syntax-aware code editing
//! - Semantic code understanding
//! - Refactoring operations
//! - Symbol extraction and navigation

const std = @import("std");
// TODO: Re-enable when grove is fixed
// const grove = @import("grove");

/// Grove AST integration wrapper
pub const GroveAST = struct {
    allocator: std.mem.Allocator,
    parser_pool: ?ParserPool,

    const ParserPool = struct {
        parsers: std.ArrayList(*anyopaque),
        max_size: usize,

        fn init(allocator: std.mem.Allocator, max_size: usize) ParserPool {
            return .{
                .parsers = std.ArrayList(*anyopaque).init(allocator),
                .max_size = max_size,
            };
        }

        fn deinit(self: *ParserPool) void {
            for (self.parsers.items) |parser| {
                parser.deinit();
            }
            self.parsers.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) !GroveAST {
        return .{
            .allocator = allocator,
            .parser_pool = null,
        };
    }

    pub fn deinit(self: *GroveAST) void {
        if (self.parser_pool) |*pool| {
            pool.deinit();
        }
    }

    /// Parse source code into an AST
    pub fn parseFile(
        self: *GroveAST,
        file_path: []const u8,
        language: Language,
    ) !*ParsedFile {
        const source = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024, // 10MB max
        );
        errdefer self.allocator.free(source);

        return try self.parseSource(source, language);
    }

    /// Parse source code string into an AST
    pub fn parseSource(
        self: *GroveAST,
        source: []const u8,
        language: Language,
    ) !*ParsedFile {
        const parsed = try self.allocator.create(ParsedFile);
        errdefer self.allocator.destroy(parsed);

        // TODO: Use Grove's parser to create actual AST
        // For now, create a placeholder structure

        parsed.* = .{
            .source = try self.allocator.dupe(u8, source),
            .language = language,
            .tree = null, // Will be populated by grove.Parser
            .allocator = self.allocator,
        };

        return parsed;
    }

    /// Extract symbols (functions, types, variables) from AST
    pub fn extractSymbols(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]Symbol {
        var symbols = std.ArrayList(Symbol).init(self.allocator);
        errdefer symbols.deinit();

        // TODO: Use Grove queries to extract symbols from AST
        // For now, provide basic regex-based extraction as fallback

        const patterns = [_]struct { pattern: []const u8, kind: Symbol.Kind }{
            .{ .pattern = "pub fn", .kind = .function },
            .{ .pattern = "pub const", .kind = .constant },
            .{ .pattern = "pub var", .kind = .variable },
            .{ .pattern = "const", .kind = .constant },
            .{ .pattern = "var", .kind = .variable },
        };

        var line_iter = std.mem.splitScalar(u8, parsed.source, '\n');
        var line_no: usize = 1;
        while (line_iter.next()) |line| : (line_no += 1) {
            for (patterns) |p| {
                if (std.mem.indexOf(u8, line, p.pattern)) |pos| {
                    // Extract symbol name (simplified)
                    const after = line[pos + p.pattern.len ..];
                    const name_end = std.mem.indexOfAny(u8, after, " (=:") orelse after.len;
                    const name = std.mem.trim(u8, after[0..name_end], " ");

                    if (name.len > 0) {
                        try symbols.append(.{
                            .name = try self.allocator.dupe(u8, name),
                            .kind = p.kind,
                            .line = line_no,
                            .column = pos,
                        });
                    }
                }
            }
        }

        return try symbols.toOwnedSlice();
    }

    /// Perform AST-based code refactoring
    pub fn refactor(
        self: *GroveAST,
        parsed: *ParsedFile,
        operation: RefactorOperation,
    ) ![]Edit {
        _ = parsed;

        var edits = std.ArrayList(Edit).init(self.allocator);
        errdefer edits.deinit();

        // TODO: Use Grove's AST manipulation to perform refactorings
        // For now, return empty edits

        switch (operation) {
            .rename => |rename_op| {
                // Find all references to the symbol and create edit operations
                _ = rename_op;
            },
            .extract_function => |extract_op| {
                // Extract selected code into a new function
                _ = extract_op;
            },
            .inline_function => |inline_op| {
                // Inline function calls
                _ = inline_op;
            },
            .extract_variable => |extract_op| {
                // Extract expression into a variable
                _ = extract_op;
            },
        }

        return try edits.toOwnedSlice();
    }

    /// Find definition of a symbol at a given position
    pub fn findDefinition(
        self: *GroveAST,
        parsed: *ParsedFile,
        line: usize,
        column: usize,
    ) !?SymbolLocation {
        _ = self;
        _ = parsed;
        _ = line;
        _ = column;

        // TODO: Use Grove's AST queries to find definitions
        return null;
    }

    /// Find all references to a symbol
    pub fn findReferences(
        self: *GroveAST,
        parsed: *ParsedFile,
        symbol_name: []const u8,
    ) ![]SymbolLocation {
        _ = parsed;
        _ = symbol_name;

        var refs = std.ArrayList(SymbolLocation).init(self.allocator);
        errdefer refs.deinit();

        // TODO: Use Grove's AST queries to find all references

        return try refs.toOwnedSlice();
    }

    /// Validate syntax and return diagnostics
    pub fn validateSyntax(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]Diagnostic {
        _ = parsed;

        var diagnostics = std.ArrayList(Diagnostic).init(self.allocator);
        errdefer diagnostics.deinit();

        // TODO: Use Grove's error reporting

        return try diagnostics.toOwnedSlice();
    }

    /// Get syntax highlighting ranges
    pub fn getSyntaxHighlights(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]HighlightRange {
        _ = parsed;

        var ranges = std.ArrayList(HighlightRange).init(self.allocator);
        errdefer ranges.deinit();

        // TODO: Use Grove's Highlight module

        return try ranges.toOwnedSlice();
    }
};

/// Parsed file with AST
pub const ParsedFile = struct {
    source: []const u8,
    language: Language,
    tree: ?*anyopaque, // grove.Tree pointer (opaque for now)
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedFile) void {
        self.allocator.free(self.source);
        // TODO: Free grove.Tree if allocated
    }
};

/// Programming language
pub const Language = enum {
    zig,
    rust,
    go,
    javascript,
    typescript,
    python,
    c,
    cpp,
    json,
    markdown,
    ghostlang,

    pub fn fromFileExtension(ext: []const u8) ?Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        if (std.mem.eql(u8, ext, ".js")) return .javascript;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".c")) return .c;
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc")) return .cpp;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".md")) return .markdown;
        if (std.mem.eql(u8, ext, ".gza") or std.mem.eql(u8, ext, ".ghost")) return .ghostlang;
        return null;
    }
};

/// Symbol in the AST
pub const Symbol = struct {
    name: []const u8,
    kind: Kind,
    line: usize,
    column: usize,

    pub const Kind = enum {
        function,
        variable,
        constant,
        type,
        interface,
        class,
        module,
        parameter,
        field,
    };

    pub fn deinit(self: *Symbol, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// Location of a symbol in source code
pub const SymbolLocation = struct {
    file_path: []const u8,
    line: usize,
    column: usize,
    end_line: usize,
    end_column: usize,
};

/// Code edit operation
pub const Edit = struct {
    start_line: usize,
    start_column: usize,
    end_line: usize,
    end_column: usize,
    new_text: []const u8,

    pub fn deinit(self: *Edit, allocator: std.mem.Allocator) void {
        allocator.free(self.new_text);
    }
};

/// Refactoring operations
pub const RefactorOperation = union(enum) {
    rename: struct {
        old_name: []const u8,
        new_name: []const u8,
    },
    extract_function: struct {
        start_line: usize,
        end_line: usize,
        new_name: []const u8,
    },
    inline_function: struct {
        function_name: []const u8,
    },
    extract_variable: struct {
        expression_line: usize,
        expression_column: usize,
        new_name: []const u8,
    },
};

/// Syntax diagnostic
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    line: usize,
    column: usize,

    pub const Severity = enum {
        @"error",
        warning,
        info,
        hint,
    };

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// Syntax highlighting range
pub const HighlightRange = struct {
    start_line: usize,
    start_column: usize,
    end_line: usize,
    end_column: usize,
    token_type: TokenType,

    pub const TokenType = enum {
        keyword,
        function_name,
        variable_name,
        type_name,
        string_literal,
        number_literal,
        comment,
        operator,
        punctuation,
    };
};

test "GroveAST init" {
    const allocator = std.testing.allocator;
    var grove_ast = try GroveAST.init(allocator);
    defer grove_ast.deinit();
}

test "Language.fromFileExtension" {
    try std.testing.expectEqual(Language.zig, Language.fromFileExtension(".zig").?);
    try std.testing.expectEqual(Language.rust, Language.fromFileExtension(".rs").?);
    try std.testing.expectEqual(Language.ghostlang, Language.fromFileExtension(".gza").?);
    try std.testing.expectEqual(@as(?Language, null), Language.fromFileExtension(".unknown"));
}
