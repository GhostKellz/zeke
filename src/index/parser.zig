// Symbol Parser - Extracts symbols (functions, structs, etc.) from source files

const std = @import("std");
const types = @import("types.zig");

pub const Parser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{ .allocator = allocator };
    }

    /// Parse file and extract symbols
    pub fn parseFile(self: *Parser, path: []const u8, language: types.Language) !types.IndexedFile {
        // Read file content
        const content = try std.fs.cwd().readFileAlloc(path, self.allocator, std.Io.Limit.limited(10 * 1024 * 1024)); // 10MB max
        defer self.allocator.free(content);

        // Get file stats for last_modified
        const stat = try std.fs.cwd().statFile(path);
        const last_modified: i64 = @intCast(@divFloor(stat.mtime, 1_000_000_000)); // ns to seconds

        // Calculate hash
        const hash = std.hash.Wyhash.hash(0, content);

        var indexed_file = types.IndexedFile{
            .path = try self.allocator.dupe(u8, path),
            .language = language,
            .symbols = std.ArrayList(types.Symbol).empty,
            .imports = std.ArrayList([]const u8).empty,
            .exports = std.ArrayList([]const u8).empty,
            .last_modified = last_modified,
            .hash = hash,
        };

        // Parse based on language
        switch (language) {
            .zig => try self.parseZig(content, &indexed_file),
            .rust => try self.parseRust(content, &indexed_file),
            .javascript, .typescript => try self.parseJavaScript(content, &indexed_file),
            .python => try self.parsePython(content, &indexed_file),
            else => {}, // Unsupported languages - just index the file
        }

        return indexed_file;
    }

    /// Parse Zig source code
    fn parseZig(self: *Parser, content: []const u8, file: *types.IndexedFile) !void {
        var line_num: usize = 1;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| : (line_num += 1) {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Function definitions: pub fn name(
            if (std.mem.indexOf(u8, trimmed, "fn ") != null) {
                if (try self.extractZigFunction(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Struct definitions: pub const Name = struct {
            if (std.mem.indexOf(u8, trimmed, "= struct") != null) {
                if (try self.extractZigStruct(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Enum definitions: pub const Name = enum {
            if (std.mem.indexOf(u8, trimmed, "= enum") != null) {
                if (try self.extractZigEnum(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Imports: const name = @import("...");
            if (std.mem.indexOf(u8, trimmed, "@import") != null) {
                if (try self.extractZigImport(trimmed)) |import| {
                    try file.imports.append(self.allocator, import);
                }
            }
        }
    }

    fn extractZigFunction(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        // Find "fn " keyword
        const fn_idx = std.mem.indexOf(u8, line, "fn ") orelse return null;

        // Extract function name
        const after_fn = line[fn_idx + 3 ..];
        const paren_idx = std.mem.indexOf(u8, after_fn, "(") orelse return null;
        const name = std.mem.trim(u8, after_fn[0..paren_idx], &std.ascii.whitespace);

        if (name.len == 0) return null;

        // Extract full signature
        const sig_end = std.mem.indexOf(u8, after_fn, "{") orelse after_fn.len;
        const signature = std.mem.trim(u8, after_fn[0..sig_end], &std.ascii.whitespace);

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .function,
            .line = line_num,
            .column = fn_idx,
            .signature = try self.allocator.dupe(u8, signature),
            .doc_comment = null, // TODO: Extract doc comments
        };
    }

    fn extractZigStruct(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        // Pattern: "const Name = struct" or "pub const Name = struct"
        const struct_idx = std.mem.indexOf(u8, line, "= struct") orelse return null;

        // Work backwards to find name
        var name_end = struct_idx;
        while (name_end > 0 and std.ascii.isWhitespace(line[name_end - 1])) {
            name_end -= 1;
        }

        var name_start = name_end;
        while (name_start > 0 and (std.ascii.isAlphanumeric(line[name_start - 1]) or line[name_start - 1] == '_')) {
            name_start -= 1;
        }

        const name = line[name_start..name_end];
        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .struct_type,
            .line = line_num,
            .column = name_start,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractZigEnum(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        // Similar to struct extraction
        const enum_idx = std.mem.indexOf(u8, line, "= enum") orelse return null;

        var name_end = enum_idx;
        while (name_end > 0 and std.ascii.isWhitespace(line[name_end - 1])) {
            name_end -= 1;
        }

        var name_start = name_end;
        while (name_start > 0 and (std.ascii.isAlphanumeric(line[name_start - 1]) or line[name_start - 1] == '_')) {
            name_start -= 1;
        }

        const name = line[name_start..name_end];
        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .enum_type,
            .line = line_num,
            .column = name_start,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractZigImport(self: *Parser, line: []const u8) !?[]const u8 {
        // Extract import path from: const name = @import("path");
        const import_idx = std.mem.indexOf(u8, line, "@import(\"") orelse return null;
        const start = import_idx + 9; // Length of @import("

        const end_idx = std.mem.indexOf(u8, line[start..], "\"") orelse return null;
        const import_path = line[start .. start + end_idx];

        return try self.allocator.dupe(u8, import_path);
    }

    /// Parse Rust source code
    fn parseRust(self: *Parser, content: []const u8, file: *types.IndexedFile) !void {
        var line_num: usize = 1;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| : (line_num += 1) {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Function: fn name(
            if (std.mem.indexOf(u8, trimmed, "fn ") != null) {
                if (try self.extractRustFunction(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Struct: struct Name {
            if (std.mem.indexOf(u8, trimmed, "struct ") != null) {
                if (try self.extractRustStruct(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Enum: enum Name {
            if (std.mem.indexOf(u8, trimmed, "enum ") != null) {
                if (try self.extractRustEnum(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Impl: impl Name {
            if (std.mem.indexOf(u8, trimmed, "impl ") != null) {
                if (try self.extractRustImpl(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Use/imports: use path::to::item;
            if (std.mem.indexOf(u8, trimmed, "use ") != null) {
                if (try self.extractRustUse(trimmed)) |import| {
                    try file.imports.append(self.allocator, import);
                }
            }
        }
    }

    fn extractRustFunction(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        const fn_idx = std.mem.indexOf(u8, line, "fn ") orelse return null;
        const after_fn = line[fn_idx + 3 ..];
        const paren_idx = std.mem.indexOf(u8, after_fn, "(") orelse return null;
        const name = std.mem.trim(u8, after_fn[0..paren_idx], &std.ascii.whitespace);

        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .function,
            .line = line_num,
            .column = fn_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractRustStruct(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        const struct_idx = std.mem.indexOf(u8, line, "struct ") orelse return null;
        const after_struct = line[struct_idx + 7 ..];

        // Find name (until { or ;)
        const brace_idx = std.mem.indexOf(u8, after_struct, "{") orelse std.mem.indexOf(u8, after_struct, ";") orelse after_struct.len;
        const name = std.mem.trim(u8, after_struct[0..brace_idx], &std.ascii.whitespace);

        // Remove generic parameters if present
        const generic_idx = std.mem.indexOf(u8, name, "<");
        const clean_name = if (generic_idx) |idx| name[0..idx] else name;

        if (clean_name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, clean_name),
            .kind = .struct_type,
            .line = line_num,
            .column = struct_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractRustEnum(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        const enum_idx = std.mem.indexOf(u8, line, "enum ") orelse return null;
        const after_enum = line[enum_idx + 5 ..];

        const brace_idx = std.mem.indexOf(u8, after_enum, "{") orelse after_enum.len;
        const name = std.mem.trim(u8, after_enum[0..brace_idx], &std.ascii.whitespace);

        const generic_idx = std.mem.indexOf(u8, name, "<");
        const clean_name = if (generic_idx) |idx| name[0..idx] else name;

        if (clean_name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, clean_name),
            .kind = .enum_type,
            .line = line_num,
            .column = enum_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractRustImpl(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        _ = line_num;
        _ = line;
        _ = self;
        // TODO: Implement impl extraction
        return null;
    }

    fn extractRustUse(self: *Parser, line: []const u8) !?[]const u8 {
        const use_idx = std.mem.indexOf(u8, line, "use ") orelse return null;
        const after_use = line[use_idx + 4 ..];

        const semi_idx = std.mem.indexOf(u8, after_use, ";") orelse after_use.len;
        const import_path = std.mem.trim(u8, after_use[0..semi_idx], &std.ascii.whitespace);

        if (import_path.len == 0) return null;
        return try self.allocator.dupe(u8, import_path);
    }

    /// Parse JavaScript/TypeScript
    fn parseJavaScript(self: *Parser, content: []const u8, file: *types.IndexedFile) !void {
        var line_num: usize = 1;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| : (line_num += 1) {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Function: function name(
            if (std.mem.indexOf(u8, trimmed, "function ") != null) {
                if (try self.extractJsFunction(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Arrow function: const name = (
            if (std.mem.indexOf(u8, trimmed, "const ") != null or std.mem.indexOf(u8, trimmed, "let ") != null) {
                if (std.mem.indexOf(u8, trimmed, "=>") != null) {
                    if (try self.extractJsArrowFunction(trimmed, line_num)) |symbol| {
                        try file.symbols.append(self.allocator, symbol);
                    }
                }
            }

            // Class: class Name {
            if (std.mem.indexOf(u8, trimmed, "class ") != null) {
                if (try self.extractJsClass(trimmed, line_num)) |symbol| {
                    try file.symbols.append(self.allocator, symbol);
                }
            }

            // Import: import { } from '...';
            if (std.mem.indexOf(u8, trimmed, "import ") != null) {
                if (try self.extractJsImport(trimmed)) |import| {
                    try file.imports.append(self.allocator, import);
                }
            }
        }
    }

    fn extractJsFunction(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        const fn_idx = std.mem.indexOf(u8, line, "function ") orelse return null;
        const after_fn = line[fn_idx + 9 ..];
        const paren_idx = std.mem.indexOf(u8, after_fn, "(") orelse return null;
        const name = std.mem.trim(u8, after_fn[0..paren_idx], &std.ascii.whitespace);

        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .function,
            .line = line_num,
            .column = fn_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractJsArrowFunction(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        // Pattern: const name = (...) =>
        _ = std.mem.indexOf(u8, line, "=>") orelse return null;

        // Find const/let
        const const_idx = std.mem.indexOf(u8, line, "const ") orelse std.mem.indexOf(u8, line, "let ") orelse return null;
        const after_const = line[const_idx + 6 ..]; // "const " is 6 chars

        const eq_idx = std.mem.indexOf(u8, after_const, "=") orelse return null;
        const name = std.mem.trim(u8, after_const[0..eq_idx], &std.ascii.whitespace);

        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .function,
            .line = line_num,
            .column = const_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractJsClass(self: *Parser, line: []const u8, line_num: usize) !?types.Symbol {
        const class_idx = std.mem.indexOf(u8, line, "class ") orelse return null;
        const after_class = line[class_idx + 6 ..];

        const brace_idx = std.mem.indexOf(u8, after_class, "{") orelse std.mem.indexOf(u8, after_class, "extends") orelse after_class.len;
        const name = std.mem.trim(u8, after_class[0..brace_idx], &std.ascii.whitespace);

        if (name.len == 0) return null;

        return types.Symbol{
            .name = try self.allocator.dupe(u8, name),
            .kind = .class,
            .line = line_num,
            .column = class_idx,
            .signature = null,
            .doc_comment = null,
        };
    }

    fn extractJsImport(self: *Parser, line: []const u8) !?[]const u8 {
        // Extract from: import ... from 'path';
        const from_idx = std.mem.indexOf(u8, line, "from ") orelse return null;
        const after_from = line[from_idx + 5 ..];

        // Find quote (single or double)
        const quote_idx = std.mem.indexOf(u8, after_from, "'") orelse std.mem.indexOf(u8, after_from, "\"") orelse return null;
        const after_quote = after_from[quote_idx + 1 ..];

        const end_quote_idx = std.mem.indexOf(u8, after_quote, "'") orelse std.mem.indexOf(u8, after_quote, "\"") orelse return null;
        const import_path = after_quote[0..end_quote_idx];

        if (import_path.len == 0) return null;
        return try self.allocator.dupe(u8, import_path);
    }

    /// Parse Python
    fn parsePython(self: *Parser, content: []const u8, file: *types.IndexedFile) !void {
        _ = content;
        _ = file;
        _ = self;
        // TODO: Implement Python parsing
    }
};
