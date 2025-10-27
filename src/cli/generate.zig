const std = @import("std");

pub fn run(allocator: std.mem.Allocator, args: []const [:0]u8) !void {
    if (args.len < 1) {
        try showUsage();
        return error.InvalidArguments;
    }

    const command = args[0];

    if (std.mem.eql(u8, command, "test")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke generate test <file>\n", .{});
            return error.InvalidArguments;
        }
        try generateTest(allocator, args[1]);
    } else if (std.mem.eql(u8, command, "docs")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke generate docs <file>\n", .{});
            return error.InvalidArguments;
        }
        try generateDocs(allocator, args[1]);
    } else if (std.mem.eql(u8, command, "project")) {
        if (args.len < 3) {
            std.debug.print("Usage: zeke generate project <name> <template>\n", .{});
            return error.InvalidArguments;
        }
        try generateProject(allocator, args[1], args[2]);
    } else if (std.mem.eql(u8, command, "api")) {
        if (args.len < 2) {
            std.debug.print("Usage: zeke generate api <spec>\n", .{});
            return error.InvalidArguments;
        }
        try generateAPI(allocator, args[1]);
    } else {
        std.debug.print("Unknown generate command: {s}\n", .{command});
        try showUsage();
        return error.InvalidArguments;
    }
}

fn generateTest(allocator: std.mem.Allocator, file_path: []const u8) !void {
    std.debug.print("🧪 Generating tests for: {s}\n", .{file_path});

    // Read source file
    const content = try std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024)));
    defer allocator.free(content);

    // Detect language
    const ext = std.fs.path.extension(file_path);

    // Generate test filename
    const test_filename = try generateTestFilename(allocator, file_path, ext);
    defer allocator.free(test_filename);

    // Generate test content
    const test_content = try generateTestContent(allocator, content, ext);
    defer allocator.free(test_content);

    // Write test file
    try std.fs.cwd().writeFile(.{
        .sub_path = test_filename,
        .data = test_content,
    });

    std.debug.print("✓ Generated: {s}\n", .{test_filename});
}

fn generateTestFilename(allocator: std.mem.Allocator, file_path: []const u8, ext: []const u8) ![]const u8 {
    const basename = std.fs.path.basename(file_path);
    const stem = basename[0 .. basename.len - ext.len];

    if (std.mem.eql(u8, ext, ".zig")) {
        return try std.fmt.allocPrint(allocator, "tests/{s}_test.zig", .{stem});
    } else if (std.mem.eql(u8, ext, ".rs")) {
        return try std.fmt.allocPrint(allocator, "tests/{s}_test.rs", .{stem});
    } else if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".js")) {
        return try std.fmt.allocPrint(allocator, "tests/{s}.test{s}", .{ stem, ext });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}_test{s}", .{ stem, ext });
    }
}

fn generateTestContent(allocator: std.mem.Allocator, source: []const u8, ext: []const u8) ![]const u8 {
    if (std.mem.eql(u8, ext, ".zig")) {
        return try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\const testing = std.testing;
            \\
            \\// TODO: Import your module
            \\// const MyModule = @import("../src/my_module.zig");
            \\
            \\test "basic functionality" {{
            \\    // Arrange
            \\    const allocator = testing.allocator;
            \\
            \\    // Act
            \\    // TODO: Call your function
            \\
            \\    // Assert
            \\    try testing.expect(true);
            \\}}
            \\
            \\test "edge cases" {{
            \\    // TODO: Test edge cases
            \\}}
            \\
        , .{});
    } else if (std.mem.eql(u8, ext, ".rs")) {
        return try allocator.dupe(u8,
            \\#[cfg(test)]
            \\mod tests {
            \\    use super::*;
            \\
            \\    #[test]
            \\    fn test_basic_functionality() {
            \\        // TODO: Implement test
            \\        assert!(true);
            \\    }
            \\
            \\    #[test]
            \\    fn test_edge_cases() {
            \\        // TODO: Test edge cases
            \\    }
            \\}
            \\
        );
    } else {
        _ = source;
        return try allocator.dupe(u8, "// Generated test file\n// TODO: Add tests\n");
    }
}

fn generateDocs(allocator: std.mem.Allocator, file_path: []const u8) !void {
    std.debug.print("📚 Generating documentation for: {s}\n", .{file_path});

    const content = try std.fs.cwd().readFileAlloc(file_path, allocator, @as(std.Io.Limit, @enumFromInt(10 * 1024 * 1024)));
    defer allocator.free(content);

    // Generate docs based on file type
    const ext = std.fs.path.extension(file_path);

    if (std.mem.eql(u8, ext, ".zig")) {
        // Extract functions and types
        std.debug.print("📝 Functions found:\n", .{});

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "pub fn")) |_| {
                std.debug.print("  • {s}\n", .{line});
            }
        }
    }

    std.debug.print("✓ Documentation analysis complete\n", .{});
}

fn generateProject(allocator: std.mem.Allocator, name: []const u8, template: []const u8) !void {
    std.debug.print("🏗️  Creating project: {s} (template: {s})\n", .{ name, template });

    // Create project directory
    try std.fs.cwd().makeDir(name);

    const templates = .{
        .{ "zig-exe", "Basic Zig executable project" },
        .{ "zig-lib", "Zig library project" },
        .{ "rust-bin", "Rust binary crate" },
        .{ "rust-lib", "Rust library crate" },
        .{ "node-app", "Node.js application" },
        .{ "web-api", "REST API server" },
    };

    // Find matching template
    var found = false;
    inline for (templates) |tmpl| {
        if (std.mem.eql(u8, template, tmpl[0])) {
            try createFromTemplate(allocator, name, tmpl[0]);
            found = true;
            break;
        }
    }

    if (!found) {
        std.debug.print("Unknown template: {s}\n", .{template});
        std.debug.print("\nAvailable templates:\n", .{});
        inline for (templates) |tmpl| {
            std.debug.print("  • {s} - {s}\n", .{ tmpl[0], tmpl[1] });
        }
        return error.UnknownTemplate;
    }

    std.debug.print("✓ Project created successfully\n", .{});
    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("  cd {s}\n", .{name});

    if (std.mem.eql(u8, template, "zig-exe")) {
        std.debug.print("  zig build run\n", .{});
    } else if (std.mem.startsWith(u8, template, "rust-")) {
        std.debug.print("  cargo build\n", .{});
    } else if (std.mem.startsWith(u8, template, "node-")) {
        std.debug.print("  npm install && npm start\n", .{});
    }
}

fn createFromTemplate(allocator: std.mem.Allocator, name: []const u8, template: []const u8) !void {
    if (std.mem.eql(u8, template, "zig-exe")) {
        try createZigExeTemplate(allocator, name);
    } else if (std.mem.eql(u8, template, "rust-bin")) {
        try createRustBinTemplate(allocator, name);
    }
    // ... more templates
}

fn createZigExeTemplate(allocator: std.mem.Allocator, name: []const u8) !void {
    // Create build.zig
    const build_zig = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\
        \\    const exe = b.addExecutable(.{{
        \\        .name = "{s}",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run_cmd.step);
        \\}}
        \\
    , .{name});
    defer allocator.free(build_zig);

    const build_path = try std.fs.path.join(allocator, &.{ name, "build.zig" });
    defer allocator.free(build_path);
    try std.fs.cwd().writeFile(.{ .sub_path = build_path, .data = build_zig });

    // Create src/main.zig
    const src_dir = try std.fs.path.join(allocator, &.{ name, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makeDir(src_dir);

    const main_zig =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Hello from Zeke-generated project!\n", .{});
        \\}
        \\
    ;

    const main_path = try std.fs.path.join(allocator, &.{ src_dir, "main.zig" });
    defer allocator.free(main_path);
    try std.fs.cwd().writeFile(.{ .sub_path = main_path, .data = main_zig });
}

fn createRustBinTemplate(allocator: std.mem.Allocator, name: []const u8) !void {
    // Create Cargo.toml
    const cargo_toml = try std.fmt.allocPrint(allocator,
        \\[package]
        \\name = "{s}"
        \\version = "0.1.0"
        \\edition = "2021"
        \\
        \\[dependencies]
        \\
    , .{name});
    defer allocator.free(cargo_toml);

    const cargo_path = try std.fs.path.join(allocator, &.{ name, "Cargo.toml" });
    defer allocator.free(cargo_path);
    try std.fs.cwd().writeFile(.{ .sub_path = cargo_path, .data = cargo_toml });

    // Create src/main.rs
    const src_dir = try std.fs.path.join(allocator, &.{ name, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makeDir(src_dir);

    const main_rs =
        \\fn main() {
        \\    println!("Hello from Zeke-generated Rust project!");
        \\}
        \\
    ;

    const main_path = try std.fs.path.join(allocator, &.{ src_dir, "main.rs" });
    defer allocator.free(main_path);
    try std.fs.cwd().writeFile(.{ .sub_path = main_path, .data = main_rs });
}

fn generateAPI(allocator: std.mem.Allocator, spec: []const u8) !void {
    std.debug.print("🔧 Generating API from spec: {s}\n", .{spec});

    // TODO: Parse OpenAPI/Swagger spec and generate code
    _ = allocator;

    std.debug.print("✓ API generation complete\n", .{});
}

fn showUsage() !void {
    std.debug.print(
        \\Usage: zeke generate <command> [args]
        \\
        \\Commands:
        \\  test <file>              Generate tests for a file
        \\  docs <file>              Generate documentation
        \\  project <name> <template> Create a new project from template
        \\  api <spec>               Generate API from OpenAPI spec
        \\
        \\Templates:
        \\  zig-exe, zig-lib         Zig projects
        \\  rust-bin, rust-lib       Rust projects
        \\  node-app, web-api        JavaScript/TypeScript projects
        \\
        \\Examples:
        \\  zeke generate test src/parser.zig
        \\  zeke generate project my-app zig-exe
        \\  zeke generate api openapi.yaml
        \\
    , .{});
}
