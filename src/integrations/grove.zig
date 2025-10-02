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
const grove = @import("grove");

/// Grove AST integration wrapper
pub const GroveAST = struct {
    allocator: std.mem.Allocator,
    parser_pool: ?ParserPool,

    const ParserPool = struct {
        parsers: std.ArrayList(*anyopaque),
        allocator: std.mem.Allocator,
        max_size: usize,

        fn init(allocator: std.mem.Allocator, max_size: usize) ParserPool {
            return .{
                .parsers = .{},
                .allocator = allocator,
                .max_size = max_size,
            };
        }

        fn deinit(self: *ParserPool) void {
            // TODO: Properly type parsers and call deinit
            // for (self.parsers.items) |parser| {
            //     parser.deinit();
            // }
            self.parsers.deinit(self.allocator);
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
        // Read file with allocator
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const max_bytes = 10 * 1024 * 1024;
        const stat = try file.stat();
        const file_size = @min(stat.size, max_bytes);

        const source = try self.allocator.alloc(u8, file_size);
        errdefer self.allocator.free(source);

        const bytes_read = try file.readAll(source);
        if (bytes_read != file_size) {
            self.allocator.free(source);
            return error.UnexpectedEof;
        }

        // parseSource takes ownership of source, so don't free on error after this point
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

        // Get Grove bundled language and convert to Language
        const bundled = switch (language) {
            .zig => grove.Languages.zig,
            .json => grove.Languages.json,
            .ghostlang => grove.Languages.ghostlang,
            // These languages are declared but not compiled in Grove
            .rust, .go, .javascript, .typescript, .python, .c, .cpp, .markdown => return error.UnsupportedLanguage,
        };

        const grove_lang = bundled.get() catch {
            return error.LanguageLoadFailed;
        };

        // Create parser
        var parser = grove.Parser.init(self.allocator) catch {
            return error.ParserInitFailed;
        };
        errdefer parser.deinit();

        // Set language
        parser.setLanguage(grove_lang) catch {
            return error.LanguageUnsupported;
        };

        // Parse the source
        const tree = parser.parseUtf8(null, source) catch {
            return error.ParseFailed;
        };

        parsed.* = .{
            .source = try self.allocator.dupe(u8, source),
            .language = language,
            .tree = tree,
            .parser = parser,
            .allocator = self.allocator,
        };

        return parsed;
    }

    /// Extract symbols (functions, types, variables) from AST
    pub fn extractSymbols(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]Symbol {
        var symbols: std.ArrayList(Symbol) = .{};
        errdefer symbols.deinit(self.allocator);

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
                        try symbols.append(self.allocator, .{
                            .name = try self.allocator.dupe(u8, name),
                            .kind = p.kind,
                            .line = line_no,
                            .column = pos,
                        });
                    }
                }
            }
        }

        return try symbols.toOwnedSlice(self.allocator);
    }

    /// Perform AST-based code refactoring
    pub fn refactor(
        self: *GroveAST,
        parsed: *ParsedFile,
        operation: RefactorOperation,
    ) ![]Edit {
        _ = parsed;

        var edits: std.ArrayList(Edit) = .{};
        errdefer edits.deinit(self.allocator);

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

        return try edits.toOwnedSlice(self.allocator);
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

        var refs: std.ArrayList(SymbolLocation) = .{};
        errdefer refs.deinit(self.allocator);

        // TODO: Use Grove's AST queries to find all references

        return try refs.toOwnedSlice(self.allocator);
    }

    /// Validate syntax and return diagnostics
    pub fn validateSyntax(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]Diagnostic {
        _ = parsed;

        var diagnostics: std.ArrayList(Diagnostic) = .{};
        errdefer diagnostics.deinit(self.allocator);

        // TODO: Use Grove's error reporting

        return try diagnostics.toOwnedSlice(self.allocator);
    }

    /// Get syntax highlighting ranges
    pub fn getSyntaxHighlights(
        self: *GroveAST,
        parsed: *ParsedFile,
    ) ![]HighlightRange {
        _ = parsed;

        var ranges: std.ArrayList(HighlightRange) = .{};
        errdefer ranges.deinit(self.allocator);

        // TODO: Use Grove's Highlight module

        return try ranges.toOwnedSlice(self.allocator);
    }
};

/// Parsed file with AST
pub const ParsedFile = struct {
    source: []const u8,
    language: Language,
    tree: grove.Tree,
    parser: grove.Parser,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedFile) void {
        self.allocator.free(self.source);
        self.tree.deinit();
        self.parser.deinit();
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
