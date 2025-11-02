const std = @import("std");

/// File editing tool with diff preview and backup
pub const FileEditorTool = struct {
    allocator: std.mem.Allocator,
    backup_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, backup_dir: []const u8) FileEditorTool {
        return .{
            .allocator = allocator,
            .backup_dir = backup_dir,
        };
    }

    /// File edit operation
    pub const Edit = struct {
        file_path: []const u8,
        old_content: ?[]const u8 = null, // null = new file
        new_content: []const u8,
        create_backup: bool = true,

        pub fn deinit(self: *Edit, allocator: std.mem.Allocator) void {
            if (self.old_content) |old| {
                allocator.free(old);
            }
            allocator.free(self.file_path);
            allocator.free(self.new_content);
        }
    };

    /// Execute a file edit
    pub fn execute(self: *FileEditorTool, edit: Edit) !void {
        // Create backup directory if it doesn't exist
        if (edit.create_backup) {
            std.fs.cwd().makePath(self.backup_dir) catch {};
        }

        // Read current content if file exists
        const current_content = std.fs.cwd().readFileAlloc(
            self.allocator,
            edit.file_path,
            10 * 1024 * 1024, // 10MB max
        ) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        defer if (current_content) |content| self.allocator.free(content);

        // Create backup
        if (edit.create_backup and current_content != null) {
            try self.createBackup(edit.file_path, current_content.?);
        }

        // Ensure parent directory exists
        if (std.fs.path.dirname(edit.file_path)) |dir| {
            try std.fs.cwd().makePath(dir);
        }

        // Write new content
        const file = try std.fs.cwd().createFile(edit.file_path, .{});
        defer file.close();
        try file.writeAll(edit.new_content);
    }

    /// Create a backup of a file
    fn createBackup(self: *FileEditorTool, file_path: []const u8, content: []const u8) !void {
        // Generate backup filename with timestamp
        const timestamp = std.time.timestamp();
        const basename = std.fs.path.basename(file_path);

        const backup_filename = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.{d}.backup",
            .{ self.backup_dir, basename, timestamp },
        );
        defer self.allocator.free(backup_filename);

        const backup_file = try std.fs.cwd().createFile(backup_filename, .{});
        defer backup_file.close();
        try backup_file.writeAll(content);
    }

    /// Preview edit as unified diff
    pub fn preview(self: *FileEditorTool, edit: Edit) ![]const u8 {
        const old = edit.old_content orelse "";
        return try self.generateDiff(edit.file_path, old, edit.new_content);
    }

    /// Generate unified diff
    fn generateDiff(
        self: *FileEditorTool,
        file_path: []const u8,
        old_content: []const u8,
        new_content: []const u8,
    ) ![]const u8 {
        var diff = std.ArrayList(u8).init(self.allocator);
        defer diff.deinit();

        // Header
        try diff.appendSlice("--- ");
        try diff.appendSlice(file_path);
        try diff.appendSlice("\n+++ ");
        try diff.appendSlice(file_path);
        try diff.appendSlice("\n");

        // Simple line-by-line diff
        var old_lines = std.mem.splitScalar(u8, old_content, '\n');
        var new_lines = std.mem.splitScalar(u8, new_content, '\n');

        var old_line_num: usize = 0;
        var new_line_num: usize = 0;

        while (old_lines.next()) |old_line| {
            old_line_num += 1;
            const new_line = new_lines.next() orelse {
                // Old content has more lines - deletion
                try diff.appendSlice("-");
                try diff.appendSlice(old_line);
                try diff.appendSlice("\n");
                continue;
            };
            new_line_num += 1;

            if (std.mem.eql(u8, old_line, new_line)) {
                // Unchanged
                try diff.appendSlice(" ");
                try diff.appendSlice(old_line);
                try diff.appendSlice("\n");
            } else {
                // Changed
                try diff.appendSlice("-");
                try diff.appendSlice(old_line);
                try diff.appendSlice("\n+");
                try diff.appendSlice(new_line);
                try diff.appendSlice("\n");
            }
        }

        // New content has more lines - additions
        while (new_lines.next()) |new_line| {
            new_line_num += 1;
            try diff.appendSlice("+");
            try diff.appendSlice(new_line);
            try diff.appendSlice("\n");
        }

        return try diff.toOwnedSlice();
    }

    /// Validate edit operation
    pub fn validate(edit: Edit) !void {
        // Check file path is not empty
        if (edit.file_path.len == 0) {
            return error.EmptyFilePath;
        }

        // Check for absolute paths or path traversal
        if (std.mem.indexOf(u8, edit.file_path, "..") != null) {
            return error.PathTraversalNotAllowed;
        }

        // Check content size
        if (edit.new_content.len > 10 * 1024 * 1024) {
            return error.ContentTooLarge;
        }
    }
};

// Tests
test "file editor basic edit" {
    const allocator = std.testing.allocator;

    const editor = FileEditorTool.init(allocator, ".zeke_backups");
    _ = editor;

    const edit = FileEditorTool.Edit{
        .file_path = try allocator.dupe(u8, "test_file.txt"),
        .new_content = try allocator.dupe(u8, "Hello, World!"),
        .create_backup = false,
    };
    defer {
        allocator.free(edit.file_path);
        allocator.free(edit.new_content);
    }

    // Validate
    try FileEditorTool.validate(edit);
}

test "diff generation" {
    const allocator = std.testing.allocator;

    var editor = FileEditorTool.init(allocator, ".zeke_backups");

    const old = "line1\nline2\nline3";
    const new = "line1\nmodified\nline3\nline4";

    const diff = try editor.generateDiff("test.txt", old, new);
    defer allocator.free(diff);

    try std.testing.expect(std.mem.indexOf(u8, diff, "-line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "+modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff, "+line4") != null);
}

test "validate path traversal" {
    const edit = FileEditorTool.Edit{
        .file_path = "../../../etc/passwd",
        .new_content = "malicious",
    };

    try std.testing.expectError(error.PathTraversalNotAllowed, FileEditorTool.validate(edit));
}
