// File Walker - Recursively walks directory and finds source files

const std = @import("std");
const types = @import("types.zig");

pub const Walker = struct {
    allocator: std.mem.Allocator,
    ignore_patterns: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Walker {
        return .{
            .allocator = allocator,
            .ignore_patterns = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *Walker) void {
        for (self.ignore_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.ignore_patterns.deinit(self.allocator);
    }

    /// Add ignore pattern (e.g., "node_modules", "target", ".git")
    pub fn addIgnorePattern(self: *Walker, pattern: []const u8) !void {
        const owned = try self.allocator.dupe(u8, pattern);
        try self.ignore_patterns.append(self.allocator, owned);
    }

    /// Add default ignore patterns
    pub fn addDefaultIgnores(self: *Walker) !void {
        const defaults = [_][]const u8{
            ".git",
            ".hg",
            ".svn",
            "node_modules",
            "target",
            "zig-cache",
            "zig-out",
            ".zig-cache",
            "build",
            "dist",
            "__pycache__",
            ".pytest_cache",
            ".venv",
            "venv",
            ".DS_Store",
        };

        for (defaults) |pattern| {
            try self.addIgnorePattern(pattern);
        }
    }

    /// Check if path should be ignored
    fn shouldIgnore(self: *Walker, path: []const u8) bool {
        for (self.ignore_patterns.items) |pattern| {
            if (std.mem.indexOf(u8, path, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Walk directory and collect source files
    pub fn walk(self: *Walker, root_path: []const u8) !std.ArrayList([]const u8) {
        var files = std.ArrayList([]const u8).empty;
        errdefer {
            for (files.items) |file| {
                self.allocator.free(file);
            }
            files.deinit(self.allocator);
        }

        try self.walkRecursive(root_path, &files);
        return files;
    }

    fn walkRecursive(self: *Walker, path: []const u8, files: *std.ArrayList([]const u8)) !void {
        // Check if should ignore
        if (self.shouldIgnore(path)) {
            return;
        }

        // Open directory
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            // Ignore permission errors, etc.
            if (err == error.AccessDenied) return;
            return err;
        };
        defer dir.close();

        // Iterate entries
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Build full path
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .directory => {
                    // Recurse into subdirectory
                    try self.walkRecursive(full_path, files);
                },
                .file => {
                    // Check if it's a source file
                    if (self.isSourceFile(entry.name)) {
                        const owned_path = try self.allocator.dupe(u8, full_path);
                        try files.append(self.allocator, owned_path);
                    }
                },
                else => {},
            }
        }
    }

    /// Check if file is a source file based on extension
    fn isSourceFile(self: *Walker, filename: []const u8) bool {
        _ = self;

        const ext = std.fs.path.extension(filename);
        const lang = types.Language.fromExtension(ext);
        return lang != .unknown;
    }
};

// Tests
test "Walker: add ignore patterns" {
    const allocator = std.testing.allocator;

    var walker = Walker.init(allocator);
    defer walker.deinit();

    try walker.addIgnorePattern("node_modules");
    try walker.addIgnorePattern(".git");

    try std.testing.expect(walker.shouldIgnore("./node_modules/package.json"));
    try std.testing.expect(walker.shouldIgnore(".git/config"));
    try std.testing.expect(!walker.shouldIgnore("src/main.zig"));
}

test "Walker: detect source files" {
    const allocator = std.testing.allocator;

    var walker = Walker.init(allocator);
    defer walker.deinit();

    try std.testing.expect(walker.isSourceFile("main.zig"));
    try std.testing.expect(walker.isSourceFile("app.rs"));
    try std.testing.expect(walker.isSourceFile("index.ts"));
    try std.testing.expect(!walker.isSourceFile("README.md"));
    try std.testing.expect(!walker.isSourceFile("config.toml"));
}
