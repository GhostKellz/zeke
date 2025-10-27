const std = @import("std");
// Note: Don't import full zeke module from CLI to avoid circular deps
// const FileEditor = @import("../tools/editor.zig").FileEditor;

/// CLI interface for the edit command
pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        try showUsage();
        return error.InvalidArguments;
    }

    const file_path = args[0];
    const instruction = if (args.len > 1) args[1] else "";

    // Check if file exists
    const file_exists = blk: {
        std.fs.cwd().access(file_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!file_exists) {
        std.debug.print("Error: File '{s}' not found\n", .{file_path});
        return error.FileNotFound;
    }

    // Parse additional flags
    var interactive = true;
    var backup = true;
    var diff_only = false;

    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--no-interactive") or std.mem.eql(u8, arg, "-y")) {
            interactive = false;
        } else if (std.mem.eql(u8, arg, "--no-backup")) {
            backup = false;
        } else if (std.mem.eql(u8, arg, "--diff")) {
            diff_only = true;
        }
    }

    var progress = @import("progress.zig").Progress.init("Analyzing file");
    try progress.start();

    // TODO: Initialize editor when tools are fully integrated
    // var editor = FileEditor.init(allocator);
    // defer editor.deinit();

    // Read original content
    const original = try std.fs.cwd().readFileAlloc(
        file_path,
        allocator,
        @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024)),
    );
    defer allocator.free(original);

    // If no instruction, enter interactive mode
    if (instruction.len == 0) {
        try progress.finish();
        std.debug.print("\n📝 Interactive Edit Mode\n", .{});
        std.debug.print("File: {s}\n", .{file_path});
        std.debug.print("\nWhat would you like to do?\n", .{});
        std.debug.print("1. Add error handling\n", .{});
        std.debug.print("2. Add documentation\n", .{});
        std.debug.print("3. Refactor for clarity\n", .{});
        std.debug.print("4. Custom instruction\n", .{});
        std.debug.print("\nEnter choice (1-4) or custom instruction: ", .{});

        // TODO: Implement interactive prompt
        return;
    }

    try progress.update();

    // Generate AI edit suggestion
    // For now, this is a placeholder - in reality this would call the AI
    const edited = try generateEdit(allocator, original, instruction);
    defer allocator.free(edited);

    try progress.finish();

    // Show diff
    try showDiff(allocator, file_path, original, edited);

    if (diff_only) {
        return;
    }

    // Ask for confirmation if interactive
    if (interactive) {
        std.debug.print("\nApply changes? [Y/n/d(iff again)]: ", .{});

        // Read user input
        const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
        var buf: [128]u8 = undefined;
        const bytes_read = try stdin_file.read(&buf);
        const response = std.mem.trimRight(u8, buf[0..bytes_read], &std.ascii.whitespace);

        if (response.len > 0) {
            const choice = std.ascii.toLower(response[0]);
            if (choice == 'n') {
                std.debug.print("Changes discarded.\n", .{});
                return;
            } else if (choice == 'd') {
                // Show diff again with more context
                try showDiff(allocator, file_path, original, edited);
                return run(allocator, args);
            }
        }
    }

    // Create backup if requested
    if (backup) {
        const backup_path = try std.fmt.allocPrint(
            allocator,
            "{s}.backup.{d}",
            .{ file_path, std.time.timestamp() },
        );
        defer allocator.free(backup_path);

        try std.fs.cwd().copyFile(file_path, std.fs.cwd(), backup_path, .{});
        std.debug.print("✓ Backup saved: {s}\n", .{backup_path});
    }

    // Write edited content
    try std.fs.cwd().writeFile(.{
        .sub_path = file_path,
        .data = edited,
    });

    std.debug.print("✓ File updated: {s}\n", .{file_path});
}

fn generateEdit(allocator: std.mem.Allocator, original: []const u8, instruction: []const u8) ![]const u8 {
    // This is a placeholder - in reality, this would:
    // 1. Call the AI with the file content and instruction
    // 2. Parse the AI response
    // 3. Apply the edits

    // For now, just return a simple transformation
    _ = instruction;

    // Example: Add a comment at the top
    const comment = "// AI-edited file\n";
    const new_content = try std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ comment, original },
    );

    return new_content;
}

fn showDiff(allocator: std.mem.Allocator, file_path: []const u8, original: []const u8, edited: []const u8) !void {
    _ = allocator;

    std.debug.print("\n" ++ "─" ** 60 ++ "\n", .{});
    std.debug.print("📄 Diff Preview: {s}\n", .{file_path});
    std.debug.print("─" ** 60 ++ "\n\n", .{});

    // Simple line-by-line diff
    var orig_lines = std.mem.splitScalar(u8, original, '\n');
    var edit_lines = std.mem.splitScalar(u8, edited, '\n');

    var line_num: usize = 1;
    while (true) {
        const orig_line = orig_lines.next();
        const edit_line = edit_lines.next();

        if (orig_line == null and edit_line == null) break;

        if (orig_line) |o| {
            if (edit_line) |e| {
                if (!std.mem.eql(u8, o, e)) {
                    // Changed line
                    std.debug.print("\x1b[31m- {d:4} | {s}\x1b[0m\n", .{ line_num, o });
                    std.debug.print("\x1b[32m+ {d:4} | {s}\x1b[0m\n", .{ line_num, e });
                }
            } else {
                // Deleted line
                std.debug.print("\x1b[31m- {d:4} | {s}\x1b[0m\n", .{ line_num, o });
            }
        } else if (edit_line) |e| {
            // Added line
            std.debug.print("\x1b[32m+ {d:4} | {s}\x1b[0m\n", .{ line_num, e });
        }

        line_num += 1;
    }

    std.debug.print("\n" ++ "─" ** 60 ++ "\n", .{});
}

fn showUsage() !void {
    std.debug.print(
        \\Usage: zeke edit <file> [instruction] [options]
        \\
        \\Edit files with AI assistance and preview changes before applying.
        \\
        \\Options:
        \\  -y, --no-interactive    Apply changes without confirmation
        \\  --no-backup             Don't create backup files
        \\  --diff                  Show diff only, don't apply
        \\
        \\Examples:
        \\  zeke edit main.zig "add error handling"
        \\  zeke edit server.rs "refactor for clarity"
        \\  zeke edit api.ts --diff "add JSDoc comments"
        \\
    , .{});
}
