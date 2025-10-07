const std = @import("std");
const zeke = @import("zeke");
const mcp = zeke.mcp;
const config = zeke.config;

/// Run glyph subcommands
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "ls") or std.mem.eql(u8, subcommand, "list")) {
        try listTools(allocator);
    } else if (std.mem.eql(u8, subcommand, "read")) {
        if (args.len < 2) {
            std.debug.print("Error: 'read' requires a file path\n", .{});
            std.debug.print("Usage: zeke glyph read <file>\n", .{});
            return error.MissingArgument;
        }
        try readFile(allocator, args[1]);
    } else if (std.mem.eql(u8, subcommand, "diff")) {
        if (args.len < 3) {
            std.debug.print("Error: 'diff' requires two file paths\n", .{});
            std.debug.print("Usage: zeke glyph diff <old> <new>\n", .{});
            return error.MissingArgument;
        }
        try generateDiff(allocator, args[1], args[2]);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        printHelp();
    } else {
        std.debug.print("Error: Unknown subcommand '{s}'\n", .{subcommand});
        printHelp();
        return error.UnknownSubcommand;
    }
}

fn printHelp() void {
    std.debug.print(
        \\
        \\zeke glyph - Direct MCP (Model Context Protocol) tool access
        \\
        \\Usage:
        \\  zeke glyph <subcommand> [args...]
        \\
        \\Subcommands:
        \\  ls, list              List available MCP tools
        \\  read <file>           Read file contents via MCP
        \\  diff <old> <new>      Generate diff between two files
        \\  help                  Show this help message
        \\
        \\Examples:
        \\  zeke glyph ls
        \\  zeke glyph read src/main.zig
        \\  zeke glyph diff old.txt new.txt
        \\
    , .{});
}

fn listTools(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 Available MCP Tools\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const tools = [_]struct {
        name: []const u8,
        description: []const u8,
    }{
        .{ .name = "fs.read", .description = "Read file contents" },
        .{ .name = "fs.write", .description = "Write file contents" },
        .{ .name = "fs.list", .description = "List directory contents" },
        .{ .name = "diff.generate", .description = "Generate unified diff" },
        .{ .name = "diff.apply", .description = "Apply unified diff to file" },
        .{ .name = "ping", .description = "Test MCP connection" },
    };

    for (tools) |tool| {
        std.debug.print("  • {s: <20} {s}\n", .{ tool.name, tool.description });
    }

    std.debug.print("\n", .{});

    // Try to connect to Glyph and list actual tools
    var mcp_client = try getMcpClient(allocator);
    defer mcp_client.deinit();

    std.debug.print("✅ Connected to Glyph MCP server\n\n", .{});
}

fn readFile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    std.debug.print("📖 Reading file via MCP: {s}\n\n", .{file_path});

    var mcp_client = try getMcpClient(allocator);
    defer mcp_client.deinit();

    const result = try mcp_client.readFile(file_path);
    defer result.deinit();

    if (result.is_error) {
        std.debug.print("❌ Error: {s}\n", .{result.content});
        return error.McpToolError;
    }

    std.debug.print("{s}\n", .{result.content});
}

fn generateDiff(allocator: std.mem.Allocator, old_path: []const u8, new_path: []const u8) !void {
    std.debug.print("🔍 Generating diff via MCP\n", .{});
    std.debug.print("  Old: {s}\n", .{old_path});
    std.debug.print("  New: {s}\n\n", .{new_path});

    var mcp_client = try getMcpClient(allocator);
    defer mcp_client.deinit();

    // Read old file
    const old_result = try mcp_client.readFile(old_path);
    defer old_result.deinit();

    if (old_result.is_error) {
        std.debug.print("❌ Error reading old file: {s}\n", .{old_result.content});
        return error.McpToolError;
    }

    // Read new file
    const new_result = try mcp_client.readFile(new_path);
    defer new_result.deinit();

    if (new_result.is_error) {
        std.debug.print("❌ Error reading new file: {s}\n", .{new_result.content});
        return error.McpToolError;
    }

    // Generate diff
    const diff_result = try mcp_client.generateDiff(old_result.content, new_result.content);
    defer diff_result.deinit();

    if (diff_result.is_error) {
        std.debug.print("❌ Error generating diff: {s}\n", .{diff_result.content});
        return error.McpToolError;
    }

    std.debug.print("{s}\n", .{diff_result.content});
}

fn getMcpClient(allocator: std.mem.Allocator) !mcp.McpClient {
    // Load config
    var cfg = config.loadConfig(allocator) catch {
        std.debug.print("❌ Failed to load config. Make sure ~/.config/zeke/config.json exists.\n", .{});
        std.debug.print("💡 Copy config.example.json to ~/.config/zeke/config.json\n", .{});
        return error.ConfigNotFound;
    };
    defer cfg.deinit();

    // Check if Glyph is configured
    if (cfg.services.glyph == null) {
        std.debug.print("❌ Glyph MCP service not configured\n", .{});
        std.debug.print("💡 Add 'services.glyph' section to config.json\n", .{});
        return error.GlyphNotConfigured;
    }

    const glyph_config = cfg.services.glyph.?;
    if (!glyph_config.enabled) {
        std.debug.print("❌ Glyph service is disabled\n", .{});
        std.debug.print("💡 Set 'services.glyph.enabled' to true in config.json\n", .{});
        return error.GlyphDisabled;
    }

    // Initialize MCP client
    return try mcp.McpClient.initFromConfig(allocator, glyph_config);
}
