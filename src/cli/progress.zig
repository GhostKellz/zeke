const std = @import("std");

/// Simple progress indicator for long operations
pub const Progress = struct {
    message: []const u8,
    spinner_chars: []const u8 = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏",
    current_index: usize = 0,
    use_color: bool,
    stdout_file: std.fs.File,
    buffer: [4096]u8 = undefined,
    writer_struct: std.fs.File.Writer = undefined,

    pub fn init(message: []const u8) Progress {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const config = std.Io.tty.detectConfig(stdout_file);
        const use_color = config != .no_color;

        var progress = Progress{
            .message = message,
            .use_color = use_color,
            .stdout_file = stdout_file,
        };
        progress.writer_struct = stdout_file.writer(&progress.buffer);
        return progress;
    }

    /// Start showing progress (non-blocking)
    pub fn start(self: *Progress) !void {
        const stdout = &self.writer_struct.interface;
        if (self.use_color) {
            try stdout.writeAll("\x1b[?25l"); // Hide cursor
            try stdout.print("\x1b[34m{u} {s}...\x1b[0m", .{ self.spinner_chars[0], self.message });
        } else {
            try stdout.print("{u} {s}...", .{ self.spinner_chars[0], self.message });
        }
        try stdout.flush();
    }

    /// Update spinner animation
    pub fn update(self: *Progress) !void {
        const stdout = &self.writer_struct.interface;
        self.current_index = (self.current_index + 1) % self.spinner_chars.len;

        // Move cursor to beginning of line
        try stdout.writeAll("\r");

        if (self.use_color) {
            try stdout.print("\x1b[34m{u} {s}...\x1b[0m", .{ self.spinner_chars[self.current_index], self.message });
        } else {
            try stdout.print("{u} {s}...", .{ self.spinner_chars[self.current_index], self.message });
        }
        try stdout.flush();
    }

    /// Finish with success
    pub fn finish(self: *Progress) !void {
        const stdout = &self.writer_struct.interface;

        // Clear line
        try stdout.writeAll("\r\x1b[K");

        if (self.use_color) {
            try stdout.print("\x1b[32m✓ {s}\x1b[0m\n", .{self.message});
            try stdout.writeAll("\x1b[?25h"); // Show cursor
        } else {
            try stdout.print("✓ {s}\n", .{self.message});
        }
        try stdout.flush();
    }

    /// Finish with error
    pub fn fail(self: *Progress, error_msg: []const u8) !void {
        const stdout = &self.writer_struct.interface;

        // Clear line
        try stdout.writeAll("\r\x1b[K");

        if (self.use_color) {
            try stdout.print("\x1b[31m✗ {s}: {s}\x1b[0m\n", .{ self.message, error_msg });
            try stdout.writeAll("\x1b[?25h"); // Show cursor
        } else {
            try stdout.print("✗ {s}: {s}\n", .{ self.message, error_msg });
        }
        try stdout.flush();
    }
};

/// Show a simple spinner for a long operation
/// Usage:
///   var progress = Progress.init("Loading models");
///   try progress.start();
///   // Do work...
///   try progress.finish();
pub fn withProgress(comptime message: []const u8, operation: anytype) !void {
    var progress = Progress.init(message);
    try progress.start();

    // Run operation
    operation() catch |err| {
        try progress.fail(@errorName(err));
        return err;
    };

    try progress.finish();
}

/// Progress bar (for operations with known size)
pub const ProgressBar = struct {
    total: usize,
    current: usize = 0,
    message: []const u8,
    use_color: bool,
    bar_width: usize = 40,
    stdout_file: std.fs.File,
    buffer: [4096]u8 = undefined,
    writer_struct: std.fs.File.Writer = undefined,

    pub fn init(message: []const u8, total: usize) ProgressBar {
        const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        const config = std.Io.tty.detectConfig(stdout_file);
        const use_color = config != .no_color;

        var bar = ProgressBar{
            .message = message,
            .total = total,
            .use_color = use_color,
            .stdout_file = stdout_file,
        };
        bar.writer_struct = stdout_file.writer(&bar.buffer);
        return bar;
    }

    pub fn update(self: *ProgressBar, current: usize) !void {
        self.current = current;
        try self.render();
    }

    pub fn increment(self: *ProgressBar) !void {
        self.current +%= 1;
        if (self.current > self.total) self.current = self.total;
        try self.render();
    }

    fn render(self: *ProgressBar) !void {
        const stdout = &self.writer_struct.interface;

        const percent = if (self.total > 0)
            @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total)) * 100.0
        else
            0.0;

        const filled = if (self.total > 0)
            (self.current * self.bar_width) / self.total
        else
            0;

        // Clear line and move to beginning
        try stdout.print("\r\x1b[K", .{});

        if (self.use_color) {
            try stdout.print("\x1b[34m{s}\x1b[0m [", .{self.message});

            // Draw filled portion
            var i: usize = 0;
            while (i < self.bar_width) : (i += 1) {
                if (i < filled) {
                    try stdout.print("\x1b[32m█\x1b[0m", .{});
                } else {
                    try stdout.print("░", .{});
                }
            }

            try stdout.print("] \x1b[36m{d:.1}%\x1b[0m ({d}/{d})", .{ percent, self.current, self.total });
        } else {
            try stdout.print("{s} [", .{self.message});

            var i: usize = 0;
            while (i < self.bar_width) : (i += 1) {
                if (i < filled) {
                    try stdout.print("█", .{});
                } else {
                    try stdout.print("░", .{});
                }
            }

            try stdout.print("] {d:.1}% ({d}/{d})", .{ percent, self.current, self.total });
        }

        try stdout.flush();
    }

    pub fn finish(self: *ProgressBar) !void {
        const stdout = &self.writer_struct.interface;
        try stdout.writeAll("\n");
        try stdout.flush();
    }
};
