// CLI commands for codebase indexing

const std = @import("std");
const index_mod = @import("../index/index.zig");
const Index = index_mod.Index;

pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "build") or std.mem.eql(u8, subcommand, "create")) {
        try handleBuild(allocator, if (args.len > 1) args[1] else ".");
    } else if (std.mem.eql(u8, subcommand, "search")) {
        if (args.len < 2) {
            std.debug.print("Error: search requires a query\n", .{});
            std.debug.print("Usage: zeke index search <query>\n", .{});
            return;
        }
        try handleSearch(allocator, ".", args[1], 20);
    } else if (std.mem.eql(u8, subcommand, "find")) {
        if (args.len < 2) {
            std.debug.print("Error: find requires a symbol name\n", .{});
            std.debug.print("Usage: zeke index find <name>\n", .{});
            return;
        }
        try handleFind(allocator, ".", args[1]);
    } else if (std.mem.eql(u8, subcommand, "context")) {
        if (args.len < 2) {
            std.debug.print("Error: context requires a task description\n", .{});
            std.debug.print("Usage: zeke index context \"task description\"\n", .{});
            return;
        }
        try handleContext(allocator, ".", args[1], 10);
    } else if (std.mem.eql(u8, subcommand, "stats")) {
        try handleStats(allocator, if (args.len > 1) args[1] else ".");
    } else if (std.mem.eql(u8, subcommand, "functions")) {
        try handleKindSearch(allocator, ".", .function);
    } else if (std.mem.eql(u8, subcommand, "structs")) {
        try handleKindSearch(allocator, ".", .struct_type);
    } else if (std.mem.eql(u8, subcommand, "classes")) {
        try handleKindSearch(allocator, ".", .class);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        showHelp();
    } else {
        std.debug.print("Unknown subcommand: {s}\n\n", .{subcommand});
        showHelp();
    }
}

fn handleBuild(allocator: std.mem.Allocator, root_path: []const u8) !void {
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    const start_time = std.time.milliTimestamp();

    try idx.buildIndex();

    const elapsed = std.time.milliTimestamp() - start_time;

    idx.printStats();
    std.debug.print("⚡ Indexing completed in {}ms\n\n", .{elapsed});
}

fn handleSearch(allocator: std.mem.Allocator, root_path: []const u8, query: []const u8, limit: usize) !void {
    // First, check if index exists and build if needed
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    std.debug.print("🔍 Searching for: {s}\n", .{query});
    try idx.buildIndex();

    var results = try idx.search(query, 100);
    defer results.deinit(allocator);

    if (results.items.len > limit) {
        const truncated_results = results.items[0..limit];
        Index.printSearchResults(truncated_results, limit);
        std.debug.print("\n  💡 Showing {} of {} results (sorted by relevance & recency)\n", .{ limit, results.items.len });
        std.debug.print("     Use a more specific query to narrow results\n\n", .{});
    } else {
        Index.printSearchResults(results.items, limit);
    }
}

fn handleFind(allocator: std.mem.Allocator, root_path: []const u8, name: []const u8) !void {
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    std.debug.print("🔍 Finding exact match: {s}\n", .{name});
    try idx.buildIndex();

    if (try idx.findExact(name)) |result| {
        std.debug.print("\n✓ Found!\n", .{});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("  {s} {s}\n", .{ Index.symbolKindIcon(result.symbol.kind), result.symbol.name });
        std.debug.print("    {s}:{}\n", .{ result.file_path, result.symbol.line });

        if (result.symbol.signature) |sig| {
            std.debug.print("    {s}\n", .{sig});
        }

        if (result.symbol.doc_comment) |doc| {
            std.debug.print("    /// {s}\n", .{doc});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("\n✗ Symbol '{s}' not found\n\n", .{name});
    }
}

fn handleContext(allocator: std.mem.Allocator, root_path: []const u8, task: []const u8, max_files: usize) !void {
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    std.debug.print("🎯 Finding relevant context for: {s}\n", .{task});
    try idx.buildIndex();

    var context_files = try idx.getContextForTask(task, max_files);
    defer context_files.deinit(allocator);

    std.debug.print("\n📁 Relevant Files ({} files)\n", .{context_files.items.len});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    for (context_files.items, 0..) |file, i| {
        std.debug.print("  {}. {s}\n", .{ i + 1, file });
    }
    std.debug.print("\n", .{});
}

fn handleStats(allocator: std.mem.Allocator, root_path: []const u8) !void {
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    try idx.buildIndex();
    idx.printStats();
}

fn handleKindSearch(allocator: std.mem.Allocator, root_path: []const u8, kind: index_mod.SymbolKind) !void {
    var idx = try Index.init(allocator, root_path);
    defer idx.deinit();

    const kind_name = @tagName(kind);
    std.debug.print("🔍 Finding all {s}s\n", .{kind_name});

    try idx.buildIndex();

    var results = try idx.searchByKind(kind);
    defer results.deinit(allocator);

    std.debug.print("\n📋 Found {} {s}(s)\n", .{ results.items.len, kind_name });
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    for (results.items, 0..) |result, i| {
        if (i >= 50) {
            std.debug.print("\n  ... and {} more\n", .{results.items.len - 50});
            break;
        }

        std.debug.print("  {s} {s}\n", .{ Index.symbolKindIcon(result.symbol.kind), result.symbol.name });
        std.debug.print("    {s}:{}\n", .{ result.file_path, result.symbol.line });

        if (result.symbol.signature) |sig| {
            // Truncate long signatures
            if (sig.len > 80) {
                std.debug.print("    {s}...\n", .{sig[0..77]});
            } else {
                std.debug.print("    {s}\n", .{sig});
            }
        }

        if (i < results.items.len - 1) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n", .{});
}

fn showHelp() void {
    std.debug.print(
        \\
        \\📚 Codebase Indexing
        \\
        \\USAGE:
        \\    zeke index <command> [options]
        \\
        \\COMMANDS:
        \\    build [path]          Build index for project (default: current directory)
        \\    search <query>        Search for symbols matching query
        \\    find <name>           Find symbol by exact name
        \\    context <task>        Get relevant files for a task description
        \\    stats [path]          Show index statistics
        \\
        \\    functions             List all functions in project
        \\    structs               List all structs in project
        \\    classes               List all classes in project
        \\
        \\EXAMPLES:
        \\    # Index current project
        \\    zeke index build
        \\
        \\    # Index specific directory
        \\    zeke index build /path/to/project
        \\
        \\    # Search for symbols
        \\    zeke index search "calculateTotal"
        \\    zeke index search "auth"
        \\
        \\    # Find exact symbol
        \\    zeke index find "handleRequest"
        \\
        \\    # Get context for a task
        \\    zeke index context "implement user authentication"
        \\    zeke index context "fix memory leak in server"
        \\
        \\    # List all functions
        \\    zeke index functions
        \\
        \\    # Show statistics
        \\    zeke index stats
        \\
        \\FEATURES:
        \\    • Fast file walking with ignore patterns
        \\    • Multi-language support (Zig, Rust, JS/TS, Python, Go, C/C++)
        \\    • Symbol extraction (functions, structs, classes, enums)
        \\    • Fuzzy search with relevance scoring
        \\    • Context gathering for AI prompts
        \\    • Incremental updates (future)
        \\
        \\
    , .{});
}
