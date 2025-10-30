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
    var issues = std.ArrayList(Issue){};
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

    var issues = std.ArrayList(Issue){};

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
        const trimmed = std.mem.trim(u8, line, " \t");

        // Check for TODO/FIXME comments
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

        // Check for unreachable code
        if (std.mem.indexOf(u8, trimmed, "unreachable") != null and
            std.mem.indexOf(u8, trimmed, "//") != 0) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "unreachable encountered - may panic in safe builds",
                .suggestion = "Ensure this code path is truly unreachable",
            });
        }

        // Check for @panic
        if (std.mem.indexOf(u8, line, "@panic(") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "Explicit @panic call",
                .suggestion = "Consider returning error instead of panicking",
            });
        }

        // Check for try with unused error
        if (std.mem.indexOf(u8, trimmed, "_ = try") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .low,
                .message = "Discarding error return value",
                .suggestion = "Consider handling or propagating the error properly",
            });
        }

        // Check for catch unreachable (potential panic)
        if (std.mem.indexOf(u8, line, "catch unreachable") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .medium,
                .message = "catch unreachable - will panic on error",
                .suggestion = "Handle errors properly or document why error is impossible",
            });
        }

        // Check for @intCast without bounds checking comment
        if (std.mem.indexOf(u8, line, "@intCast") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .medium,
                .message = "Integer cast - potential overflow/truncation",
                .suggestion = "Ensure bounds are checked or use @intFromFloat with validation",
            });
        }

        // Check for @ptrCast (type punning)
        if (std.mem.indexOf(u8, line, "@ptrCast") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "Pointer cast detected - type safety bypassed",
                .suggestion = "Document why cast is necessary and ensure alignment/size requirements",
            });
        }

        // Check for @ptrFromInt (creating pointers from integers)
        if (std.mem.indexOf(u8, line, "@ptrFromInt") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "Creating pointer from integer",
                .suggestion = "Ensure pointer validity and document hardware access or FFI context",
            });
        }

        // Check for inline assembly
        if (std.mem.indexOf(u8, line, "asm volatile") != null or
            std.mem.indexOf(u8, line, "asm (") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .complexity,
                .severity = .medium,
                .message = "Inline assembly usage",
                .suggestion = "Document assembly code and ensure platform-specific guards",
            });
        }

        // Check for comptime blocks that might be complex
        if (std.mem.indexOf(u8, trimmed, "comptime {") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .complexity,
                .severity = .low,
                .message = "Comptime block - may increase compile time",
                .suggestion = "Ensure comptime computation is necessary",
            });
        }

        // Check for anytype usage (less type safety)
        if (std.mem.indexOf(u8, line, "anytype") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "anytype parameter - reduced type checking",
                .suggestion = "Consider using explicit type constraints or type unions",
            });
        }

        // Check for std.debug.print (should use std.log in production)
        if (std.mem.indexOf(u8, line, "std.debug.print") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Debug print statement",
                .suggestion = "Use std.log for production code or remove debug prints",
            });
        }

        // Check for manual memory management without defer
        if (std.mem.indexOf(u8, line, "allocator.alloc(") != null or
            std.mem.indexOf(u8, line, "allocator.create(") != null) {
            // Look ahead for defer in next few lines
            const remaining = content[std.mem.indexOf(u8, content, line).?..];
            const lookahead = if (remaining.len > 200) remaining[0..200] else remaining;

            if (std.mem.indexOf(u8, lookahead, "defer") == null) {
                try issues.append(allocator, .{
                    .line = line_num,
                    .category = .security,
                    .severity = .medium,
                    .message = "Memory allocation without visible defer",
                    .suggestion = "Ensure memory is freed with defer or transferred ownership is clear",
                });
            }
        }

        // Check for error set without documentation
        if (std.mem.indexOf(u8, trimmed, "error{") != null and
            std.mem.indexOf(u8, trimmed, "pub const") != null) {
            // Look backward for doc comment
            var found_doc = false;
            if (line_num > 1) {
                const prev_line_idx = std.mem.lastIndexOf(u8, content[0..std.mem.indexOf(u8, content, line).?], "\n");
                if (prev_line_idx) |idx| {
                    const prev_line = std.mem.trim(u8, content[idx+1..std.mem.indexOf(u8, content, line).?], " \t\n");
                    if (std.mem.indexOf(u8, prev_line, "///") != null or
                        std.mem.indexOf(u8, prev_line, "//!") != null) {
                        found_doc = true;
                    }
                }
            }

            if (!found_doc) {
                try issues.append(allocator, .{
                    .line = line_num,
                    .category = .documentation,
                    .severity = .low,
                    .message = "Error set without documentation",
                    .suggestion = "Add /// doc comments explaining when errors occur",
                });
            }
        }

        // Check for @import("std") multiple times (should be const at top)
        if (std.mem.indexOf(u8, line, "@import(\"std\")") != null and
            std.mem.indexOf(u8, line, "const std =") == null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .low,
                .message = "Inline @import without const binding",
                .suggestion = "Import once at file scope: const std = @import(\"std\")",
            });
        }

        // Check for long lines (Zig convention is 100 chars)
        if (line.len > 100) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Line exceeds 100 characters (Zig convention)",
                .suggestion = "Break into multiple lines for readability",
            });
        }

        // Check for noreturn without @panic or unreachable
        if (std.mem.indexOf(u8, line, "noreturn") != null) {
            const remaining = content[std.mem.indexOf(u8, content, line).?..];
            const lookahead = if (remaining.len > 300) remaining[0..300] else remaining;

            if (std.mem.indexOf(u8, lookahead, "@panic") == null and
                std.mem.indexOf(u8, lookahead, "unreachable") == null) {
                try issues.append(allocator, .{
                    .line = line_num,
                    .category = .complexity,
                    .severity = .medium,
                    .message = "noreturn function without visible terminator",
                    .suggestion = "Ensure function ends with @panic, unreachable, or infinite loop",
                });
            }
        }
    }
}

fn analyzeRust(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    var line_num: usize = 1;
    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_unsafe_block = false;

    while (lines.next()) |line| : (line_num += 1) {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Track unsafe blocks
        if (std.mem.indexOf(u8, trimmed, "unsafe") != null) {
            if (std.mem.indexOf(u8, trimmed, "{") != null) {
                in_unsafe_block = true;
            }
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "Unsafe code detected",
                .suggestion = "Ensure unsafe code is well-documented and minimized",
            });
        }
        if (in_unsafe_block and std.mem.indexOf(u8, trimmed, "}") != null) {
            in_unsafe_block = false;
        }

        // Check for unwrap() calls - can panic
        if (std.mem.indexOf(u8, line, ".unwrap()") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .medium,
                .message = "Use of .unwrap() can cause panic",
                .suggestion = "Consider using .expect() with message or proper error handling",
            });
        }

        // Check for expect() without meaningful message
        if (std.mem.indexOf(u8, line, ".expect(\"\")") != null or
            std.mem.indexOf(u8, line, ".expect(\"\")") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .documentation,
                .severity = .low,
                .message = "Empty expect() message",
                .suggestion = "Provide meaningful error context in expect() calls",
            });
        }

        // Check for clone() usage - potential performance issue
        if (std.mem.indexOf(u8, line, ".clone()") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .low,
                .message = "Clone operation detected",
                .suggestion = "Consider borrowing instead of cloning if possible",
            });
        }

        // Check for Arc<Mutex<T>> - common concurrency pattern
        if (std.mem.indexOf(u8, line, "Arc<Mutex<") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .complexity,
                .severity = .low,
                .message = "Arc<Mutex<T>> pattern found",
                .suggestion = "Consider if RwLock or message passing would be more appropriate",
            });
        }

        // Check for Box::new without reason
        if (std.mem.indexOf(u8, line, "Box::new") != null and
            std.mem.indexOf(u8, line, "dyn") == null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .low,
                .message = "Unnecessary heap allocation with Box::new",
                .suggestion = "Only use Box for trait objects or recursive types",
            });
        }

        // Check for println! in non-test code
        if (std.mem.indexOf(u8, line, "println!") != null and
            std.mem.indexOf(u8, content, "#[test]") == null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "println! macro usage",
                .suggestion = "Consider using proper logging (log crate) instead of println!",
            });
        }

        // Check for transmute - extremely unsafe
        if (std.mem.indexOf(u8, line, "transmute") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "mem::transmute detected - highly dangerous",
                .suggestion = "Avoid transmute unless absolutely necessary; document extensively",
            });
        }

        // Check for as conversions that might truncate
        if (std.mem.indexOf(u8, line, " as u") != null or
            std.mem.indexOf(u8, line, " as i") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .medium,
                .message = "Potentially unsafe type cast with 'as'",
                .suggestion = "Consider using try_into() or checked conversions",
            });
        }

        // Check for #[allow(dead_code)] or similar suppressions
        if (std.mem.indexOf(u8, line, "#[allow(") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Lint suppression detected",
                .suggestion = "Ensure suppression is justified and documented",
            });
        }

        // Check for TODO/FIXME
        if (std.mem.indexOf(u8, line, "TODO") != null or
            std.mem.indexOf(u8, line, "todo!()") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .documentation,
                .severity = .medium,
                .message = "TODO/unimplemented code",
                .suggestion = "Complete implementation or create tracking issue",
            });
        }

        // Check for panic! or unreachable!
        if (std.mem.indexOf(u8, line, "panic!(") != null or
            std.mem.indexOf(u8, line, "unreachable!()") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .medium,
                .message = "Explicit panic detected",
                .suggestion = "Consider returning Result instead of panicking",
            });
        }

        // Check for long lines
        if (line.len > 100) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Line exceeds 100 characters (Rust convention)",
                .suggestion = "Break into multiple lines for readability",
            });
        }
    }
}

fn analyzeJS(allocator: std.mem.Allocator, content: []const u8, issues: *std.ArrayList(Issue)) !void {
    var line_num: usize = 1;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| : (line_num += 1) {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Check for var usage (should use let/const)
        if (std.mem.indexOf(u8, trimmed, "var ") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .medium,
                .message = "Use of 'var' keyword (deprecated)",
                .suggestion = "Use 'const' or 'let' instead of 'var'",
            });
        }

        // Check for == instead of ===
        if (std.mem.indexOf(u8, line, " == ") != null or
            std.mem.indexOf(u8, line, " != ") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .medium,
                .message = "Loose equality operator (== or !=)",
                .suggestion = "Use strict equality (=== or !==) to avoid type coercion",
            });
        }

        // Check for console.log (should use proper logging)
        if (std.mem.indexOf(u8, line, "console.log") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "console.log usage",
                .suggestion = "Consider using proper logging library or remove debug logs",
            });
        }

        // Check for eval() - major security risk
        if (std.mem.indexOf(u8, line, "eval(") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "eval() usage - critical security risk",
                .suggestion = "Avoid eval(); use safer alternatives like JSON.parse or Function constructor",
            });
        }

        // Check for setTimeout/setInterval with string (uses eval internally)
        if ((std.mem.indexOf(u8, line, "setTimeout(\"") != null or
            std.mem.indexOf(u8, line, "setInterval(\"") != null)) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "String argument to setTimeout/setInterval",
                .suggestion = "Pass function reference instead of string to avoid eval",
            });
        }

        // Check for document.write (bad practice)
        if (std.mem.indexOf(u8, line, "document.write") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .medium,
                .message = "document.write usage",
                .suggestion = "Use DOM manipulation methods instead of document.write",
            });
        }

        // Check for innerHTML with potential XSS
        if (std.mem.indexOf(u8, line, ".innerHTML") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .security,
                .severity = .high,
                .message = "innerHTML usage - potential XSS vulnerability",
                .suggestion = "Use textContent or createElement/appendChild for user input",
            });
        }

        // Check for any type in TypeScript
        if (std.mem.indexOf(u8, line, ": any") != null or
            std.mem.indexOf(u8, line, "<any>") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .medium,
                .message = "TypeScript 'any' type defeats type safety",
                .suggestion = "Use specific types or 'unknown' instead of 'any'",
            });
        }

        // Check for @ts-ignore or @ts-expect-error
        if (std.mem.indexOf(u8, line, "@ts-ignore") != null or
            std.mem.indexOf(u8, line, "@ts-expect-error") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "TypeScript error suppression",
                .suggestion = "Fix the type error instead of suppressing it",
            });
        }

        // Check for promise without catch
        if (std.mem.indexOf(u8, line, ".then(") != null and
            std.mem.indexOf(u8, line, ".catch(") == null) {
            // Look ahead in content for .catch
            const remaining = content[std.mem.indexOf(u8, content, line).?..];
            const next_newline = std.mem.indexOf(u8, remaining, "\n") orelse remaining.len;
            const next_line_start = if (next_newline < remaining.len) next_newline + 1 else remaining.len;
            const lookahead = if (next_line_start + 50 < remaining.len) remaining[0..next_line_start + 50] else remaining[0..];

            if (std.mem.indexOf(u8, lookahead, ".catch(") == null) {
                try issues.append(allocator, .{
                    .line = line_num,
                    .category = .performance,
                    .severity = .medium,
                    .message = "Promise without .catch() handler",
                    .suggestion = "Add .catch() or use async/await with try-catch",
                });
            }
        }

        // Check for nested callbacks (callback hell)
        var indent_count: usize = 0;
        for (line) |char| {
            if (char == ' ') indent_count += 1 else break;
        }
        if (indent_count > 16 and std.mem.indexOf(u8, line, "function") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .complexity,
                .severity = .medium,
                .message = "Deeply nested callback (callback hell)",
                .suggestion = "Refactor using Promises or async/await",
            });
        }

        // Check for synchronous fs operations in Node.js
        if (std.mem.indexOf(u8, line, "fs.readFileSync") != null or
            std.mem.indexOf(u8, line, "fs.writeFileSync") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .medium,
                .message = "Synchronous file system operation",
                .suggestion = "Use async fs methods or fs/promises for better performance",
            });
        }

        // Check for mutation of const objects/arrays
        if (std.mem.indexOf(u8, line, "const ") != null and
            (std.mem.indexOf(u8, line, ".push(") != null or
            std.mem.indexOf(u8, line, ".pop(") != null or
            std.mem.indexOf(u8, line, ".splice(") != null)) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Mutating const array/object",
                .suggestion = "Consider using immutable operations or let if mutation is needed",
            });
        }

        // Check for missing await
        if (std.mem.indexOf(u8, line, "async ") != null and
            std.mem.indexOf(u8, line, "await ") == null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .performance,
                .severity = .low,
                .message = "async function without await",
                .suggestion = "Remove async if not using await, or ensure await is used",
            });
        }

        // Check for TODO/FIXME
        if (std.mem.indexOf(u8, line, "TODO") != null or
            std.mem.indexOf(u8, line, "FIXME") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .documentation,
                .severity = .low,
                .message = "TODO/FIXME comment",
                .suggestion = "Complete implementation or create tracking issue",
            });
        }

        // Check for debugger statement
        if (std.mem.indexOf(u8, line, "debugger") != null) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .medium,
                .message = "debugger statement in code",
                .suggestion = "Remove debugger statement before committing",
            });
        }

        // Check for long lines
        if (line.len > 100) {
            try issues.append(allocator, .{
                .line = line_num,
                .category = .style,
                .severity = .low,
                .message = "Line exceeds 100 characters",
                .suggestion = "Break into multiple lines for readability",
            });
        }
    }
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
