const std = @import("std");

/// CLI interface for the refactor command
pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        try showUsage();
        return error.InvalidArguments;
    }

    const instruction = args[0];

    // Parse flags
    var target_path: []const u8 = ".";
    var file_pattern: ?[]const u8 = null;
    var interactive = true;
    var preview = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "-p")) {
            if (i + 1 < args.len) {
                i += 1;
                target_path = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--pattern")) {
            if (i + 1 < args.len) {
                i += 1;
                file_pattern = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--no-interactive")) {
            interactive = false;
        } else if (std.mem.eql(u8, arg, "--preview")) {
            preview = true;
        }
    }

    var progress = @import("progress.zig").Progress.init("Scanning project");
    try progress.start();

    // Scan for files to refactor
    const files = try scanFiles(allocator, target_path, file_pattern);
    defer {
        for (files) |file| allocator.free(file);
        allocator.free(files);
    }

    try progress.finish();

    std.debug.print("\n🔍 Found {d} files matching criteria\n", .{files.len});

    if (files.len == 0) {
        std.debug.print("No files to refactor.\n", .{});
        return;
    }

    // Preview files
    std.debug.print("\nFiles to refactor:\n", .{});
    for (files, 0..) |file, idx| {
        std.debug.print("  {d}. {s}\n", .{ idx + 1, file });
        if (idx >= 9) {
            std.debug.print("  ... and {d} more\n", .{files.len - 10});
            break;
        }
    }

    if (preview) {
        std.debug.print("\nPreview mode - no changes will be made.\n", .{});
        return;
    }

    if (interactive) {
        std.debug.print("\nProceed with refactoring? [Y/n]: ", .{});
        const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
        var buf: [128]u8 = undefined;
        const bytes_read = try stdin_file.read(&buf);
        const response = std.mem.trimRight(u8, buf[0..bytes_read], &std.ascii.whitespace);

        if (response.len > 0 and std.ascii.toLower(response[0]) == 'n') {
            std.debug.print("Refactoring cancelled.\n", .{});
            return;
        }
    }

    // Process each file
    var success_count: usize = 0;
    var error_count: usize = 0;

    for (files) |file| {
        std.debug.print("\n📝 Refactoring: {s}\n", .{file});

        refactorFile(allocator, file, instruction) catch |err| {
            std.debug.print("  ❌ Error: {}\n", .{err});
            error_count += 1;
            continue;
        };

        std.debug.print("  ✓ Success\n", .{});
        success_count += 1;
    }

    std.debug.print("\n" ++ "─" ** 60 ++ "\n", .{});
    std.debug.print("✓ Refactored {d} files\n", .{success_count});
    if (error_count > 0) {
        std.debug.print("❌ Failed: {d} files\n", .{error_count});
    }
}

fn scanFiles(allocator: std.mem.Allocator, root_path: []const u8, pattern: ?[]const u8) ![][]const u8 {
    var files: std.ArrayList([]const u8) = .{};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    // Simple implementation: just scan directory
    var dir = try std.fs.cwd().openDir(root_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        // Check pattern if provided
        if (pattern) |p| {
            if (!matchesPattern(entry.name, p)) continue;
        }

        const full_path = try std.fs.path.join(allocator, &.{ root_path, entry.name });
        try files.append(allocator, full_path);
    }

    return try files.toOwnedSlice(allocator);
}

fn matchesPattern(name: []const u8, pattern: []const u8) bool {
    // Simple glob matching - just check extension for now
    if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
        const suffix = pattern[star_pos + 1 ..];
        return std.mem.endsWith(u8, name, suffix);
    }
    return std.mem.eql(u8, name, pattern);
}

fn refactorFile(allocator: std.mem.Allocator, file_path: []const u8, instruction: []const u8) !void {
    // Read file
    const content = try std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024)));
    defer allocator.free(content);

    // Apply refactoring (placeholder)
    const refactored = try applyRefactoring(allocator, content, instruction);
    defer allocator.free(refactored);

    // Write back
    try std.fs.cwd().writeFile(.{
        .sub_path = file_path,
        .data = refactored,
    });
}

fn applyRefactoring(allocator: std.mem.Allocator, content: []const u8, instruction: []const u8) ![]const u8 {
    // Placeholder - would call AI for actual refactoring
    _ = instruction;
    return try allocator.dupe(u8, content);
}

fn showUsage() !void {
    std.debug.print(
        \\Usage: zeke refactor <instruction> [options]
        \\
        \\Refactor multiple files across your codebase with AI assistance.
        \\
        \\Options:
        \\  -p, --path <PATH>       Directory to refactor (default: current directory)
        \\  --pattern <PATTERN>     File pattern to match (e.g., "*.zig")
        \\  -y, --no-interactive    Apply without confirmation
        \\  --preview               Preview files without refactoring
        \\
        \\Examples:
        \\  zeke refactor "rename function parseConfig to loadConfig"
        \\  zeke refactor "add error handling" --path src --pattern "*.zig"
        \\  zeke refactor "extract common code" --preview
        \\
    , .{});
}
