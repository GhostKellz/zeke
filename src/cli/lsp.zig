// CLI commands for LSP integration

const std = @import("std");
const lsp = @import("../lsp/lsp.zig");

pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "servers")) {
        try handleServers(allocator);
    } else if (std.mem.eql(u8, subcommand, "check")) {
        if (args.len < 2) {
            std.debug.print("Error: check requires a file path\n", .{});
            std.debug.print("Usage: zeke lsp check <file>\n", .{});
            return;
        }
        try handleCheck(allocator, args[1]);
    } else if (std.mem.eql(u8, subcommand, "hover")) {
        if (args.len < 4) {
            std.debug.print("Error: hover requires file, line, and column\n", .{});
            std.debug.print("Usage: zeke lsp hover <file> <line> <column>\n", .{});
            return;
        }
        const line = try std.fmt.parseInt(u32, args[2], 10);
        const col = try std.fmt.parseInt(u32, args[3], 10);
        try handleHover(allocator, args[1], line, col);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        showHelp();
    } else {
        std.debug.print("Unknown subcommand: {s}\n\n", .{subcommand});
        showHelp();
    }
}

fn handleServers(allocator: std.mem.Allocator) !void {
    std.debug.print("📡 Available LSP Servers\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    const servers = try lsp.getAvailableServers(allocator);
    defer {
        for (servers) |server| {
            allocator.free(server);
        }
        allocator.free(servers);
    }

    if (servers.len == 0) {
        std.debug.print("No LSP servers found on system.\n\n", .{});
        std.debug.print("Install language servers for your languages:\n", .{});
        std.debug.print("  • Zig:        zls\n", .{});
        std.debug.print("  • Rust:       rust-analyzer\n", .{});
        std.debug.print("  • TypeScript: typescript-language-server\n", .{});
        std.debug.print("  • Python:     pyright-langserver\n", .{});
        std.debug.print("  • Go:         gopls\n", .{});
        std.debug.print("  • C/C++:      clangd\n", .{});
        std.debug.print("\n", .{});
        return;
    }

    for (servers, 0..) |server, i| {
        std.debug.print("  {}. ✓ {s}\n", .{ i + 1, server });
    }
    std.debug.print("\n", .{});
}

fn handleCheck(allocator: std.mem.Allocator, file_path: []const u8) !void {
    std.debug.print("🔍 Checking file: {s}\n\n", .{file_path});

    // Get absolute path
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, file_path);
    defer allocator.free(abs_path);

    // Get root directory (current directory for now)
    const root_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var manager = try lsp.LspManager.init(allocator);
    defer manager.deinit();

    std.debug.print("Connecting to LSP server...\n", .{});

    const diagnostics = manager.getDiagnosticsForFile(abs_path, root_path) catch |err| {
        std.debug.print("❌ Failed to get diagnostics: {}\n\n", .{err});
        std.debug.print("Possible reasons:\n", .{});
        std.debug.print("  • LSP server not installed\n", .{});
        std.debug.print("  • LSP server doesn't support this file type\n", .{});
        std.debug.print("  • File path is invalid\n\n", .{});
        std.debug.print("Run 'zeke lsp servers' to see available servers.\n\n", .{});
        return;
    };
    defer allocator.free(diagnostics);

    if (diagnostics.len == 0) {
        std.debug.print("✓ No diagnostics found. Code looks good!\n\n", .{});
        return;
    }

    std.debug.print("📋 Diagnostics ({} issues)\n", .{diagnostics.len});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    for (diagnostics) |diag| {
        const severity_icon = switch (diag.severity orelse .hint) {
            .@"error" => "❌",
            .warning => "⚠️ ",
            .information => "ℹ️ ",
            .hint => "💡",
        };

        const severity_text = switch (diag.severity orelse .hint) {
            .@"error" => "Error",
            .warning => "Warning",
            .information => "Info",
            .hint => "Hint",
        };

        std.debug.print("{s} {s} at line {}:{}\n", .{
            severity_icon,
            severity_text,
            diag.range.start.line + 1,
            diag.range.start.character + 1,
        });

        std.debug.print("   {s}\n", .{diag.message});

        if (diag.source) |source| {
            std.debug.print("   Source: {s}\n", .{source});
        }

        std.debug.print("\n", .{});
    }

    // Shutdown LSP servers
    try manager.shutdownAll();
}

fn handleHover(allocator: std.mem.Allocator, file_path: []const u8, line: u32, col: u32) !void {
    std.debug.print("📖 Getting hover info for {s} at {}:{}\n\n", .{ file_path, line, col });

    // Get absolute path
    const abs_path = try std.fs.cwd().realpathAlloc(allocator, file_path);
    defer allocator.free(abs_path);

    // Get root directory
    const root_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var manager = try lsp.LspManager.init(allocator);
    defer manager.deinit();

    std.debug.print("Connecting to LSP server...\n", .{});

    const hover = manager.getHoverForPosition(abs_path, root_path, line - 1, col - 1) catch |err| {
        std.debug.print("❌ Failed to get hover info: {}\n\n", .{err});
        return;
    };

    if (hover) |h| {
        defer {
            var mut_h = h;
            mut_h.deinit(allocator);
        }

        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
        std.debug.print("{s}\n", .{h.contents});
        std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});
    } else {
        std.debug.print("No hover information available at this position.\n\n", .{});
    }

    // Shutdown LSP servers
    try manager.shutdownAll();
}

fn showHelp() void {
    std.debug.print(
        \\
        \\📡 LSP Integration
        \\
        \\USAGE:
        \\    zeke lsp <command> [options]
        \\
        \\COMMANDS:
        \\    servers              List available LSP servers on system
        \\    check <file>         Get diagnostics for a file
        \\    hover <file> <line> <col>  Get hover information at position
        \\
        \\EXAMPLES:
        \\    # List available LSP servers
        \\    zeke lsp servers
        \\
        \\    # Check a file for errors
        \\    zeke lsp check src/main.zig
        \\    zeke lsp check src/lib.rs
        \\
        \\    # Get hover info at specific position
        \\    zeke lsp hover src/main.zig 10 5
        \\
        \\SUPPORTED LANGUAGE SERVERS:
        \\    • zls                  Zig Language Server
        \\    • rust-analyzer        Rust Language Server
        \\    • typescript-language-server  TypeScript/JavaScript
        \\    • pyright-langserver   Python Language Server
        \\    • gopls                Go Language Server
        \\    • clangd               C/C++ Language Server
        \\
        \\FEATURES:
        \\    • Diagnostics (errors, warnings, hints)
        \\    • Hover information (documentation, types)
        \\    • Multi-language support
        \\    • Automatic server detection
        \\    • LSP protocol 3.17 compatible
        \\
        \\
    , .{});
}
