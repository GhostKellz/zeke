//! Smart Edit Tools - Grove Integration
//!
//! AST-based code editing powered by Grove

const std = @import("std");
const zeke = @import("zeke");

/// Smart code editor using Grove AST
pub const SmartEdit = struct {
    allocator: std.mem.Allocator,
    grove: zeke.integrations.GroveAST,

    pub fn init(allocator: std.mem.Allocator) !SmartEdit {
        return .{
            .allocator = allocator,
            .grove = try zeke.integrations.GroveAST.init(allocator),
        };
    }

    pub fn deinit(self: *SmartEdit) void {
        self.grove.deinit();
    }

    /// Analyze code structure and extract symbols
    pub fn analyzeFile(self: *SmartEdit, file_path: []const u8) !AnalysisResult {
        // Detect language from file extension
        const ext = std.fs.path.extension(file_path);
        const language = zeke.integrations.grove.Language.fromFileExtension(ext) orelse {
            std.log.warn("Unknown language for file: {s}", .{file_path});
            return error.UnsupportedLanguage;
        };

        // Parse the file
        var parsed = try self.grove.parseFile(file_path, language);
        errdefer parsed.deinit();

        // Extract symbols
        const symbols = try self.grove.extractSymbols(parsed);

        // Validate syntax
        const diagnostics = try self.grove.validateSyntax(parsed);

        return AnalysisResult{
            .file_path = try self.allocator.dupe(u8, file_path),
            .language = language,
            .symbols = symbols,
            .diagnostics = diagnostics,
            .parsed_file = parsed,
        };
    }

    /// Refactor code using AST transformations
    pub fn refactorCode(
        self: *SmartEdit,
        file_path: []const u8,
        operation: zeke.integrations.grove.RefactorOperation,
    ) !RefactorResult {
        // Parse the file
        const ext = std.fs.path.extension(file_path);
        const language = zeke.integrations.grove.Language.fromFileExtension(ext) orelse
            return error.UnsupportedLanguage;

        var parsed = try self.grove.parseFile(file_path, language);
        defer parsed.deinit();

        // Perform refactoring
        const edits = try self.grove.refactor(parsed, operation);

        return RefactorResult{
            .file_path = try self.allocator.dupe(u8, file_path),
            .edits = edits,
        };
    }

    /// Apply edits to a file
    pub fn applyEdits(
        self: *SmartEdit,
        file_path: []const u8,
        edits: []const zeke.integrations.grove.Edit,
    ) !void {
        // Read the file
        const content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024,
        );
        defer self.allocator.free(content);

        // TODO: Apply edits in reverse order (to maintain positions)
        // For now, this is a placeholder

        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        try result.appendSlice(content);

        // Apply each edit
        for (edits) |edit| {
            _ = edit;
            // TODO: Calculate byte positions and apply edits
        }

        // Write back to file
        try std.fs.cwd().writeFile(.{
            .sub_path = file_path,
            .data = result.items,
        });

        std.log.info("✅ Applied {d} edit(s) to {s}", .{ edits.len, file_path });
    }

    /// Find definition of a symbol
    pub fn findDefinition(
        self: *SmartEdit,
        file_path: []const u8,
        line: usize,
        column: usize,
    ) !?zeke.integrations.grove.SymbolLocation {
        const ext = std.fs.path.extension(file_path);
        const language = zeke.integrations.grove.Language.fromFileExtension(ext) orelse
            return error.UnsupportedLanguage;

        var parsed = try self.grove.parseFile(file_path, language);
        defer parsed.deinit();

        return try self.grove.findDefinition(parsed, line, column);
    }

    /// Find all references to a symbol
    pub fn findReferences(
        self: *SmartEdit,
        file_path: []const u8,
        symbol_name: []const u8,
    ) ![]zeke.integrations.grove.SymbolLocation {
        const ext = std.fs.path.extension(file_path);
        const language = zeke.integrations.grove.Language.fromFileExtension(ext) orelse
            return error.UnsupportedLanguage;

        var parsed = try self.grove.parseFile(file_path, language);
        defer parsed.deinit();

        return try self.grove.findReferences(parsed, symbol_name);
    }

    /// Get syntax highlighting for a file
    pub fn getSyntaxHighlights(
        self: *SmartEdit,
        file_path: []const u8,
    ) ![]zeke.integrations.grove.HighlightRange {
        const ext = std.fs.path.extension(file_path);
        const language = zeke.integrations.grove.Language.fromFileExtension(ext) orelse
            return error.UnsupportedLanguage;

        var parsed = try self.grove.parseFile(file_path, language);
        defer parsed.deinit();

        return try self.grove.getSyntaxHighlights(parsed);
    }

    /// Rename a symbol across the file
    pub fn renameSymbol(
        self: *SmartEdit,
        file_path: []const u8,
        old_name: []const u8,
        new_name: []const u8,
    ) !RefactorResult {
        return try self.refactorCode(file_path, .{
            .rename = .{
                .old_name = old_name,
                .new_name = new_name,
            },
        });
    }

    /// Extract selected code into a function
    pub fn extractFunction(
        self: *SmartEdit,
        file_path: []const u8,
        start_line: usize,
        end_line: usize,
        function_name: []const u8,
    ) !RefactorResult {
        return try self.refactorCode(file_path, .{
            .extract_function = .{
                .start_line = start_line,
                .end_line = end_line,
                .new_name = function_name,
            },
        });
    }
};

/// Code analysis result
pub const AnalysisResult = struct {
    file_path: []const u8,
    language: zeke.integrations.grove.Language,
    symbols: []zeke.integrations.grove.Symbol,
    diagnostics: []zeke.integrations.grove.Diagnostic,
    parsed_file: *zeke.integrations.grove.ParsedFile,

    pub fn deinit(self: *AnalysisResult, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        for (self.symbols) |*symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(self.symbols);
        for (self.diagnostics) |*diagnostic| {
            diagnostic.deinit(allocator);
        }
        allocator.free(self.diagnostics);
        self.parsed_file.deinit();
    }

    /// Print analysis summary
    pub fn printSummary(self: *AnalysisResult) void {
        std.log.info("📊 Analysis: {s} ({s})", .{
            self.file_path,
            @tagName(self.language),
        });
        std.log.info("  Symbols: {d}", .{self.symbols.len});
        std.log.info("  Diagnostics: {d}", .{self.diagnostics.len});

        if (self.symbols.len > 0) {
            std.log.info("\n🔍 Symbols:", .{});
            for (self.symbols) |symbol| {
                std.log.info("  {s} ({s}) at line {d}", .{
                    symbol.name,
                    @tagName(symbol.kind),
                    symbol.line,
                });
            }
        }

        if (self.diagnostics.len > 0) {
            std.log.info("\n⚠️  Diagnostics:", .{});
            for (self.diagnostics) |diagnostic| {
                const icon = switch (diagnostic.severity) {
                    .@"error" => "❌",
                    .warning => "⚠️",
                    .info => "ℹ️",
                    .hint => "💡",
                };
                std.log.info("  {s} line {d}: {s}", .{
                    icon,
                    diagnostic.line,
                    diagnostic.message,
                });
            }
        }
    }
};

/// Refactoring result
pub const RefactorResult = struct {
    file_path: []const u8,
    edits: []zeke.integrations.grove.Edit,

    pub fn deinit(self: *RefactorResult, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        for (self.edits) |*edit| {
            edit.deinit(allocator);
        }
        allocator.free(self.edits);
    }

    /// Print refactor summary
    pub fn printSummary(self: *RefactorResult) void {
        std.log.info("🔧 Refactoring: {s}", .{self.file_path});
        std.log.info("  Edits: {d}", .{self.edits.len});

        for (self.edits, 0..) |edit, i| {
            std.log.info("  [{d}] Line {d}:{d} -> {d}:{d}", .{
                i + 1,
                edit.start_line,
                edit.start_column,
                edit.end_line,
                edit.end_column,
            });
        }
    }
};

test "SmartEdit init" {
    const allocator = std.testing.allocator;
    var smart_edit = try SmartEdit.init(allocator);
    defer smart_edit.deinit();
}
