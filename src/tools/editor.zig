const std = @import("std");
const phantom = @import("phantom");
const grove = @import("grove");

/// Advanced File Editor with multi-cursor support and AST-aware editing
/// Inspired by Gemini CLI's smart-edit and Claude Code's file editing capabilities
pub const FileEditor = struct {
    allocator: std.mem.Allocator,
    checkpointer: ?*Checkpointer = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Smart edit: context-aware file editing with diff generation
    /// Returns a diff that can be reviewed before applying
    pub fn smartEdit(
        self: *Self,
        file_path: []const u8,
        edit_request: EditRequest,
    ) !EditResult {
        // Read current file
        const file_content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            10 * 1024 * 1024, // 10MB max
        );
        defer self.allocator.free(file_content);

        // Parse file if it's a supported language
        const file_ext = std.fs.path.extension(file_path);
        const language = detectLanguage(file_ext);

        // Try to parse with Grove for AST-aware editing
        var ast_context: ?ASTContext = null;
        if (language != .unknown) {
            ast_context = try parseWithGrove(self.allocator, file_content, language);
        }
        defer if (ast_context) |*ctx| ctx.deinit(self.allocator);

        // Generate edited content based on request type
        const edited_content = switch (edit_request) {
            .replace => |r| try self.applyReplace(file_content, r),
            .insert => |i| try self.applyInsert(file_content, i),
            .delete => |d| try self.applyDelete(file_content, d),
            .refactor => |rf| try self.applyRefactor(file_content, rf, ast_context),
            .multi_cursor => |mc| try self.applyMultiCursor(file_content, mc),
        };
        defer self.allocator.free(edited_content);

        // Generate diff
        const diff = try generateDiff(self.allocator, file_content, edited_content, file_path);

        return EditResult{
            .original_content = try self.allocator.dupe(u8, file_content),
            .edited_content = try self.allocator.dupe(u8, edited_content),
            .diff = diff,
            .file_path = try self.allocator.dupe(u8, file_path),
            .language = language,
        };
    }

    /// Apply edit result to file with optional checkpoint
    pub fn applyEdit(
        self: *Self,
        result: EditResult,
        create_checkpoint: bool,
    ) !void {
        if (create_checkpoint and self.checkpointer != null) {
            try self.checkpointer.?.createCheckpoint(result.file_path);
        }

        // Write to file
        const file = try std.fs.cwd().createFile(result.file_path, .{});
        defer file.close();

        try file.writeAll(result.edited_content);
    }

    /// Multi-file editing operation
    pub fn editMultipleFiles(
        self: *Self,
        edits: []const FileEdit,
    ) ![]EditResult {
        var results = try self.allocator.alloc(EditResult, edits.len);
        errdefer {
            for (results) |*r| r.deinit(self.allocator);
            self.allocator.free(results);
        }

        for (edits, 0..) |edit, i| {
            results[i] = try self.smartEdit(edit.file_path, edit.request);
        }

        return results;
    }

    // ===== Private Implementation =====

    fn applyReplace(
        self: *Self,
        content: []const u8,
        replace: ReplaceEdit,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const before = content[0..replace.start];
        const after = content[replace.end..];

        try result.appendSlice(before);
        try result.appendSlice(replace.new_text);
        try result.appendSlice(after);

        return result.toOwnedSlice();
    }

    fn applyInsert(
        self: *Self,
        content: []const u8,
        insert: InsertEdit,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const before = content[0..insert.position];
        const after = content[insert.position..];

        try result.appendSlice(before);
        try result.appendSlice(insert.text);
        try result.appendSlice(after);

        return result.toOwnedSlice();
    }

    fn applyDelete(
        self: *Self,
        content: []const u8,
        delete: DeleteEdit,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const before = content[0..delete.start];
        const after = content[delete.end..];

        try result.appendSlice(before);
        try result.appendSlice(after);

        return result.toOwnedSlice();
    }

    fn applyRefactor(
        self: *Self,
        content: []const u8,
        refactor: RefactorEdit,
        ast_context: ?ASTContext,
    ) ![]const u8 {
        _ = ast_context; // Will use AST info for intelligent refactoring

        // For now, basic implementation - TODO: Use Grove AST
        return switch (refactor.kind) {
            .rename_symbol => try self.renameSymbol(content, refactor.old_name, refactor.new_name),
            .extract_function => try self.extractFunction(content, refactor.start, refactor.end, refactor.name),
            .inline_variable => try self.inlineVariable(content, refactor.symbol),
        };
    }

    fn applyMultiCursor(
        self: *Self,
        content: []const u8,
        multi: MultiCursorEdit,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Sort cursors by position (descending to apply from end to start)
        const cursors = try self.allocator.dupe(CursorEdit, multi.cursors);
        defer self.allocator.free(cursors);

        std.sort.heap(CursorEdit, cursors, {}, cursorCompare);

        // Apply edits from end to start to maintain positions
        var current_content = try self.allocator.dupe(u8, content);
        defer self.allocator.free(current_content);

        for (cursors) |cursor| {
            const new_content = try self.applyCursorEdit(current_content, cursor);
            self.allocator.free(current_content);
            current_content = new_content;
        }

        return current_content;
    }

    fn applyCursorEdit(
        self: *Self,
        content: []const u8,
        cursor: CursorEdit,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        const before = content[0..cursor.position];
        const after = content[cursor.position..];

        try result.appendSlice(before);
        try result.appendSlice(cursor.text);
        try result.appendSlice(after);

        return result.toOwnedSlice();
    }

    fn renameSymbol(
        self: *Self,
        content: []const u8,
        old_name: []const u8,
        new_name: []const u8,
    ) ![]const u8 {
        // Simple replace all - TODO: Use AST for scope-aware renaming
        const result = try std.mem.replaceOwned(
            u8,
            self.allocator,
            content,
            old_name,
            new_name,
        );
        return result;
    }

    fn extractFunction(
        self: *Self,
        content: []const u8,
        start: usize,
        end: usize,
        name: []const u8,
    ) ![]const u8 {
        _ = start;
        _ = end;
        _ = name;
        // TODO: Implement function extraction with Grove
        return try self.allocator.dupe(u8, content);
    }

    fn inlineVariable(
        self: *Self,
        content: []const u8,
        symbol: []const u8,
    ) ![]const u8 {
        _ = symbol;
        // TODO: Implement variable inlining with Grove
        return try self.allocator.dupe(u8, content);
    }
};

fn cursorCompare(_: void, a: CursorEdit, b: CursorEdit) bool {
    return a.position > b.position;
}

/// Checkpointing system for safe file modifications
pub const Checkpointer = struct {
    allocator: std.mem.Allocator,
    checkpoint_dir: []const u8,
    git_enabled: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, checkpoint_dir: []const u8) !Self {
        // Create checkpoint directory if it doesn't exist
        std.fs.cwd().makeDir(checkpoint_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Check if we're in a git repo
        const git_enabled = checkGitRepo();

        return .{
            .allocator = allocator,
            .checkpoint_dir = try allocator.dupe(u8, checkpoint_dir),
            .git_enabled = git_enabled,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.checkpoint_dir);
    }

    /// Create a checkpoint for a file before modifying it
    pub fn createCheckpoint(self: *Self, file_path: []const u8) !void {
        const timestamp = std.time.timestamp();
        const checkpoint_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.{d}.checkpoint",
            .{ self.checkpoint_dir, std.fs.path.basename(file_path), timestamp },
        );
        defer self.allocator.free(checkpoint_name);

        // Copy original file to checkpoint
        try std.fs.cwd().copyFile(file_path, std.fs.cwd(), checkpoint_name, .{});

        // If git enabled, also create a git stash
        if (self.git_enabled) {
            try createGitCheckpoint(self.allocator, file_path);
        }
    }

    /// Restore from checkpoint
    pub fn restoreCheckpoint(self: *Self, file_path: []const u8, checkpoint_name: []const u8) !void {
        const full_checkpoint_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.checkpoint_dir, checkpoint_name },
        );
        defer self.allocator.free(full_checkpoint_path);

        try std.fs.cwd().copyFile(full_checkpoint_path, std.fs.cwd(), file_path, .{});
    }

    /// List available checkpoints for a file
    pub fn listCheckpoints(self: *Self, file_path: []const u8) ![][]const u8 {
        var checkpoints = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (checkpoints.items) |cp| self.allocator.free(cp);
            checkpoints.deinit();
        }

        const basename = std.fs.path.basename(file_path);
        const pattern = try std.fmt.allocPrint(self.allocator, "{s}.", .{basename});
        defer self.allocator.free(pattern);

        var dir = try std.fs.cwd().openDir(self.checkpoint_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, pattern)) {
                try checkpoints.append(try self.allocator.dupe(u8, entry.name));
            }
        }

        return checkpoints.toOwnedSlice();
    }
};

fn checkGitRepo() bool {
    std.fs.cwd().access(".git", .{}) catch return false;
    return true;
}

fn createGitCheckpoint(allocator: std.mem.Allocator, file_path: []const u8) !void {
    _ = allocator;
    _ = file_path;
    // TODO: Integrate with git stash
}

// ===== Types =====

pub const EditRequest = union(enum) {
    replace: ReplaceEdit,
    insert: InsertEdit,
    delete: DeleteEdit,
    refactor: RefactorEdit,
    multi_cursor: MultiCursorEdit,
};

pub const ReplaceEdit = struct {
    start: usize,
    end: usize,
    new_text: []const u8,
};

pub const InsertEdit = struct {
    position: usize,
    text: []const u8,
};

pub const DeleteEdit = struct {
    start: usize,
    end: usize,
};

pub const RefactorEdit = struct {
    kind: RefactorKind,
    old_name: []const u8 = "",
    new_name: []const u8 = "",
    start: usize = 0,
    end: usize = 0,
    name: []const u8 = "",
    symbol: []const u8 = "",
};

pub const RefactorKind = enum {
    rename_symbol,
    extract_function,
    inline_variable,
};

pub const MultiCursorEdit = struct {
    cursors: []const CursorEdit,
};

pub const CursorEdit = struct {
    position: usize,
    text: []const u8,
};

pub const FileEdit = struct {
    file_path: []const u8,
    request: EditRequest,
};

pub const EditResult = struct {
    original_content: []const u8,
    edited_content: []const u8,
    diff: []const u8,
    file_path: []const u8,
    language: Language,

    pub fn deinit(self: *EditResult, allocator: std.mem.Allocator) void {
        allocator.free(self.original_content);
        allocator.free(self.edited_content);
        allocator.free(self.diff);
        allocator.free(self.file_path);
    }
};

pub const Language = enum {
    zig,
    rust,
    go,
    javascript,
    typescript,
    python,
    c,
    cpp,
    unknown,
};

fn detectLanguage(ext: []const u8) Language {
    const ext_map = std.StaticStringMap(Language).initComptime(.{
        .{ ".zig", .zig },
        .{ ".rs", .rust },
        .{ ".go", .go },
        .{ ".js", .javascript },
        .{ ".ts", .typescript },
        .{ ".tsx", .typescript },
        .{ ".jsx", .javascript },
        .{ ".py", .python },
        .{ ".c", .c },
        .{ ".cpp", .cpp },
        .{ ".cc", .cpp },
        .{ ".cxx", .cpp },
    });

    return ext_map.get(ext) orelse .unknown;
}

const ASTContext = struct {
    // TODO: Grove AST integration
    dummy: void = {},

    pub fn deinit(self: *ASTContext, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

fn parseWithGrove(allocator: std.mem.Allocator, content: []const u8, language: Language) !ASTContext {
    _ = allocator;
    _ = content;
    _ = language;
    // TODO: Integrate with Grove tree-sitter parsers
    return ASTContext{};
}

fn generateDiff(
    allocator: std.mem.Allocator,
    original: []const u8,
    edited: []const u8,
    file_path: []const u8,
) ![]const u8 {
    // Simple unified diff format
    var diff = std.ArrayList(u8).init(allocator);
    errdefer diff.deinit();

    const writer = diff.writer();

    try writer.print("--- {s}\n", .{file_path});
    try writer.print("+++ {s}\n", .{file_path});

    // Split into lines and compare
    var orig_lines = std.mem.tokenizeScalar(u8, original, '\n');
    var edit_lines = std.mem.tokenizeScalar(u8, edited, '\n');

    var line_num: usize = 1;
    while (true) {
        const orig_line = orig_lines.next();
        const edit_line = edit_lines.next();

        if (orig_line == null and edit_line == null) break;

        if (orig_line) |ol| {
            if (edit_line) |el| {
                if (!std.mem.eql(u8, ol, el)) {
                    try writer.print("@@ -{d} +{d} @@\n", .{ line_num, line_num });
                    try writer.print("-{s}\n", .{ol});
                    try writer.print("+{s}\n", .{el});
                }
            } else {
                try writer.print("@@ -{d} @@\n", .{line_num});
                try writer.print("-{s}\n", .{ol});
            }
        } else if (edit_line) |el| {
            try writer.print("@@ +{d} @@\n", .{line_num});
            try writer.print("+{s}\n", .{el});
        }

        line_num += 1;
    }

    return diff.toOwnedSlice();
}

test "FileEditor - basic replace" {
    const allocator = std.testing.allocator;

    var editor = FileEditor.init(allocator);
    defer editor.deinit();

    const content = "Hello, World!";
    const replace = ReplaceEdit{
        .start = 7,
        .end = 13,
        .new_text = "Zig",
    };

    const result = try editor.applyReplace(content, replace);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello, Zig", result);
}
