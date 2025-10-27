const std = @import("std");

pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        try showUsage();
        return error.InvalidArguments;
    }

    const target = args[0];

    // Determine if target is file or directory
    const stat = try std.fs.cwd().statFile(target);
    const is_dir = stat.kind == .directory;

    var progress = @import("progress.zig").Progress.init(if (is_dir) "Analyzing directory" else "Analyzing file");
    try progress.start();

    if (is_dir) {
        try analyzeDirectory(allocator, target);
    } else {
        _ = try analyzeFile(allocator, target);
    }

    try progress.finish();
}

fn analyzeDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var file_count: usize = 0;
    var total_lines: usize = 0;
    var issues: std.ArrayList(Issue) = .{};
    defer issues.deinit(allocator);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);

        const file_issues = try analyzeFile(allocator, full_path);
        try issues.appendSlice(allocator, file_issues);
        allocator.free(file_issues);

        file_count += 1;

        // Count lines in file
        const content = std.fs.cwd().readFileAlloc(full_path, allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024))) catch continue;
        defer allocator.free(content);
        var line_iter = std.mem.splitScalar(u8, content, '\n');
        while (line_iter.next()) |_| total_lines += 1;
    }

    // Print summary
    std.debug.print("\n" ++ "═" ** 60 ++ "\n", .{});
    std.debug.print("📊 Analysis Summary\n", .{});
    std.debug.print("═" ** 60 ++ "\n\n", .{});
    std.debug.print("Files analyzed: {d}\n", .{file_count});
    std.debug.print("Total lines: {d}\n", .{total_lines});
    std.debug.print("Issues found: {d}\n\n", .{issues.items.len});

    printIssuesByCategory(issues.items);
}

fn analyzeFile(allocator: std.mem.Allocator, file_path: []const u8) ![]Issue {
    const content = try std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024)));
    defer allocator.free(content);

    var issues: std.ArrayList(Issue) = .{};

    // Detect language
    const ext = std.fs.path.extension(file_path);
    const lang = detectLanguage(ext);

    // Run analysis based on language
    switch (lang) {
        .zig => try analyzeZig(allocator, content, &issues),
        .rust => try analyzeRust(allocator, content, &issues),
        .javascript, .typescript => try analyzeJS(allocator, content, &issues),
        else => try analyzeGeneric(allocator, content, &issues),
    }

    // Print file-specific results
    std.debug.print("\n📄 {s}\n", .{file_path});
    if (issues.items.len == 0) {
        std.debug.print("  ✓ No issues found\n", .{});
    } else {
        for (issues.items) |issue| {
            printIssue(issue);
        }
    }

    return try issues.toOwnedSlice(allocator);
}

const Language = enum { zig, rust, javascript, typescript, python, go, c, cpp, unknown };

fn detectLanguage(ext: []const u8) Language {
    if (std.mem.eql(u8, ext, ".zig")) return .zig;
    if (std.mem.eql(u8, ext, ".rs")) return .rust;
    if (std.mem.eql(u8, ext, ".js")) return .javascript;
    if (std.mem.eql(u8, ext, ".ts")) return .typescript;
    if (std.mem.eql(u8, ext, ".py")) return .python;
    if (std.mem.eql(u8, ext, ".go")) return .go;
    if (std.mem.eql(u8, ext, ".c")) return .c;
    if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc")) return .cpp;
    return .unknown;
}

const IssueCategory = enum { performance, security, style, complexity, duplication, documentation };

const Issue = struct {
    line: usize,
    category: IssueCategory,
    severity: enum { low, medium, high },
    message: []const u8,
    suggestion: ?[]const u8 = null,
};

fn analyzeZig(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    var line_num: usize = 1;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| : (line_num += 1) {
        // Check for common issues
        if (std.mem.indexOf(u8, line, "TODO")) |_| {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .documentation,
                .severity = .low,
                .message = "TODO comment found",
                .suggestion = "Consider creating a tracking issue",
            });
        }

        if (std.mem.indexOf(u8, line, "FIXME")) |_| {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .complexity,
                .severity = .medium,
                .message = "FIXME comment found",
                .suggestion = "Address this issue",
            });
        }

        // Check for long lines
        if (line.len > 120) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Line exceeds 120 characters",
                .suggestion = "Consider breaking into multiple lines",
            });
        }
    }
}

fn analyzeRust(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    _ = allocator;
    _ = content;
    _ = issues;
    // TODO: Implement Rust-specific analysis
}

fn analyzeJS(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    _ = allocator;
    _ = content;
    _ = issues;
    // TODO: Implement JS-specific analysis
}

fn analyzeGeneric(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    var line_num: usize = 1;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| : (line_num += 1) {
        if (line.len > 120) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Long line",
            });
        }
    }
}

fn printIssue(issue: Issue) void {
    const severity_icon = switch (issue.severity) {
        .low => "ℹ️ ",
        .medium => "⚠️ ",
        .high => "🔴",
    };

    const category_name = @tagName(issue.category);

    std.debug.print("  {s} Line {d}: [{s}] {s}\n", .{
        severity_icon,
        issue.line,
        category_name,
        issue.message,
    });

    if (issue.suggestion) |sug| {
        std.debug.print("     💡 {s}\n", .{sug});
    }
}

fn printIssuesByCategory(issues: []const Issue) void {
    var by_category = std.EnumArray(IssueCategory, usize).initFill(0);

    for (issues) |issue| {
        by_category.set(issue.category, by_category.get(issue.category) + 1);
    }

    std.debug.print("By Category:\n", .{});
    inline for (@typeInfo(IssueCategory).@"enum".fields) |field| {
        const category: IssueCategory = @enumFromInt(field.value);
        const count = by_category.get(category);
        if (count > 0) {
            std.debug.print("  {s}: {d}\n", .{ field.name, count });
        }
    }
}

fn showUsage() !void {
    std.debug.print(
        \\Usage: zeke analyze <file|directory>
        \\
        \\Analyze code quality, security, and style issues.
        \\
        \\Examples:
        \\  zeke analyze src/main.zig
        \\  zeke analyze src/
        \\  zeke analyze . --verbose
        \\
    , .{});
}
