// Context Gatherer - Combines LSP, Index, and Treesitter for AI context

const std = @import("std");
const lsp = @import("../lsp/lsp.zig");
const Index = @import("../index/index.zig").Index;
const types = @import("../index/types.zig");
const tree = @import("../index/tree.zig");

/// Context source types
pub const ContextSource = enum {
    index,
    lsp,
    treesitter,
    file_content,
};

/// Context item from a specific source
pub const ContextItem = struct {
    source: ContextSource,
    file_path: []const u8,
    content: []const u8,
    relevance: f32,
    metadata: ?[]const u8, // Additional info (e.g., symbol name, diagnostic message)

    pub fn deinit(self: *ContextItem, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.content);
        if (self.metadata) |meta| {
            allocator.free(meta);
        }
    }
};

/// Unified context for AI commands
pub const Context = struct {
    items: std.ArrayList(ContextItem),
    tree_view: ?[]const u8,
    total_chars: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .items = std.ArrayList(ContextItem).empty,
            .tree_view = null,
            .total_chars = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Context) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        if (self.tree_view) |view| {
            self.allocator.free(view);
        }
    }

    pub fn addItem(self: *Context, item: ContextItem) !void {
        self.total_chars += item.content.len;
        try self.items.append(self.allocator, item);
    }

    /// Sort items by relevance (highest first)
    pub fn sortByRelevance(self: *Context) void {
        std.mem.sort(ContextItem, self.items.items, {}, struct {
            fn lessThan(_: void, a: ContextItem, b: ContextItem) bool {
                return a.relevance > b.relevance;
            }
        }.lessThan);
    }

    /// Truncate to fit within max_chars
    pub fn truncate(self: *Context, max_chars: usize) void {
        if (self.total_chars <= max_chars) return;

        self.sortByRelevance();

        var current_chars: usize = 0;
        var keep_count: usize = 0;

        for (self.items.items) |item| {
            if (current_chars + item.content.len > max_chars) break;
            current_chars += item.content.len;
            keep_count += 1;
        }

        // Free items we're removing
        for (self.items.items[keep_count..]) |*item| {
            item.deinit(self.allocator);
        }

        self.items.shrinkRetainingCapacity(keep_count);
        self.total_chars = current_chars;
    }
};

/// Context gatherer that combines multiple sources
pub const ContextGatherer = struct {
    allocator: std.mem.Allocator,
    index: *Index,
    lsp_manager: ?*lsp.LspManager,
    max_context_chars: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        index: *Index,
        lsp_manager: ?*lsp.LspManager,
    ) ContextGatherer {
        return .{
            .allocator = allocator,
            .index = index,
            .lsp_manager = lsp_manager,
            .max_context_chars = 50000, // 50K chars default
        };
    }

    /// Gather context for a task description
    pub fn gatherForTask(
        self: *ContextGatherer,
        task_description: []const u8,
        current_file: ?[]const u8,
    ) !Context {
        var context = Context.init(self.allocator);
        errdefer context.deinit();

        // 1. Search index for relevant symbols
        try self.addIndexContext(&context, task_description);

        // 2. Add current file context (if provided)
        if (current_file) |file_path| {
            try self.addFileContext(&context, file_path);
        }

        // 3. Add directory tree for project structure
        try self.addTreeContext(&context);

        // 4. Add LSP diagnostics if available
        if (self.lsp_manager != null and current_file != null) {
            try self.addLspContext(&context, current_file.?);
        }

        // Sort and truncate to fit max chars
        context.sortByRelevance();
        context.truncate(self.max_context_chars);

        return context;
    }

    /// Gather context for a specific file position
    pub fn gatherForPosition(
        self: *ContextGatherer,
        file_path: []const u8,
        line: u32,
        character: u32,
    ) !Context {
        var context = Context.init(self.allocator);
        errdefer context.deinit();

        // 1. Add file content around position
        try self.addFileContextAround(&context, file_path, line, 20); // 20 lines before/after

        // 2. Get LSP hover info if available
        if (self.lsp_manager) |manager| {
            const root_path = self.index.root_path;
            if (try manager.getHoverForPosition(file_path, root_path, line, character)) |hover_info| {
                const metadata = try std.fmt.allocPrint(
                    self.allocator,
                    "Hover at {}:{}",
                    .{ line, character },
                );

                try context.addItem(.{
                    .source = .lsp,
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .content = try self.allocator.dupe(u8, hover_info.contents),
                    .relevance = 100.0,
                    .metadata = metadata,
                });
            }
        }

        return context;
    }

    /// Add relevant symbols from index
    fn addIndexContext(self: *ContextGatherer, context: *Context, query: []const u8) !void {
        var results = try self.index.search(query, 10);
        defer results.deinit(self.allocator);

        for (results.items) |result| {
            const content = try std.fmt.allocPrint(
                self.allocator,
                "{s} {s} at line {}\n{s}",
                .{
                    @tagName(result.symbol.kind),
                    result.symbol.name,
                    result.symbol.line,
                    result.symbol.signature orelse "",
                },
            );

            try context.addItem(.{
                .source = .index,
                .file_path = try self.allocator.dupe(u8, result.file_path),
                .content = content,
                .relevance = result.relevance_score,
                .metadata = try self.allocator.dupe(u8, result.symbol.name),
            });
        }
    }

    /// Add full file content
    fn addFileContext(self: *ContextGatherer, context: *Context, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // Max 1MB
        errdefer self.allocator.free(content);

        try context.addItem(.{
            .source = .file_content,
            .file_path = try self.allocator.dupe(u8, file_path),
            .content = content,
            .relevance = 90.0, // High relevance for current file
            .metadata = null,
        });
    }

    /// Add file content around a specific line
    fn addFileContextAround(
        self: *ContextGatherer,
        context: *Context,
        file_path: []const u8,
        target_line: u32,
        context_lines: u32,
    ) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: u32 = 1;
        var start_line = if (target_line > context_lines) target_line - context_lines else 1;
        var end_line = target_line + context_lines;

        var excerpt = std.ArrayList(u8).empty;
        defer excerpt.deinit(self.allocator);

        while (lines.next()) |line| : (line_num += 1) {
            if (line_num >= start_line and line_num <= end_line) {
                try excerpt.writer().print("{}| {s}\n", .{ line_num, line });
            }
            if (line_num > end_line) break;
        }

        const metadata = try std.fmt.allocPrint(
            self.allocator,
            "Lines {}-{} of {}",
            .{ start_line, end_line, file_path },
        );

        try context.addItem(.{
            .source = .file_content,
            .file_path = try self.allocator.dupe(u8, file_path),
            .content = try excerpt.toOwnedSlice(self.allocator),
            .relevance = 95.0,
            .metadata = metadata,
        });
    }

    /// Add directory tree view
    fn addTreeContext(self: *ContextGatherer, context: *Context) !void {
        // Get all indexed files
        var file_paths = std.ArrayList([]const u8).empty;
        defer file_paths.deinit(self.allocator);

        for (self.index.files.items) |file| {
            try file_paths.append(self.allocator, file.path);
        }

        if (file_paths.items.len == 0) return;

        // Generate tree view
        const tree_view = try tree.generateContextTree(
            self.allocator,
            file_paths.items,
            4, // max depth
        );

        context.tree_view = tree_view;
    }

    /// Add LSP diagnostics and hover info
    fn addLspContext(self: *ContextGatherer, context: *Context, file_path: []const u8) !void {
        if (self.lsp_manager == null) return;

        const manager = self.lsp_manager.?;
        const root_path = self.index.root_path;

        // Get diagnostics
        const diagnostics = try manager.getDiagnosticsForFile(file_path, root_path);
        defer self.allocator.free(diagnostics);

        if (diagnostics.len > 0) {
            var diag_text = std.ArrayList(u8).empty;
            defer diag_text.deinit(self.allocator);

            for (diagnostics) |diag| {
                try diag_text.writer().print(
                    "{s} at line {}: {s}\n",
                    .{ @tagName(diag.severity), diag.range.start.line, diag.message },
                );
            }

            try context.addItem(.{
                .source = .lsp,
                .file_path = try self.allocator.dupe(u8, file_path),
                .content = try diag_text.toOwnedSlice(self.allocator),
                .relevance = 85.0,
                .metadata = try std.fmt.allocPrint(
                    self.allocator,
                    "{} diagnostics",
                    .{diagnostics.len},
                ),
            });
        }
    }
};

// Tests
test "ContextGatherer: basic usage" {
    const allocator = std.testing.allocator;

    var index = try Index.init(allocator, "/tmp/test");
    defer index.deinit();

    var gatherer = ContextGatherer.init(allocator, &index, null);
    _ = gatherer;
}
