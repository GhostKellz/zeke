const std = @import("std");

/// Terminal dimensions
pub const Dimensions = struct {
    width: usize,
    height: usize,

    /// Get current terminal dimensions via ioctl
    pub fn get() !Dimensions {
        var ws: std.posix.winsize = undefined;
        const result = std.c.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, &ws);
        if (result == -1) {
            return error.IoctlFailed;
        }

        return Dimensions{
            .width = ws.col,
            .height = ws.row,
        };
    }
};

/// Screen layout manager
pub const Layout = struct {
    dims: Dimensions,
    status_bar_height: usize,
    input_area_height: usize,
    message_area_height: usize,

    pub fn init(dims: Dimensions) Layout {
        const status_bar_height = 1;
        const input_area_height = 2; // Prompt + input line
        const message_area_height = if (dims.height > status_bar_height + input_area_height)
            dims.height - status_bar_height - input_area_height
        else
            1;

        return Layout{
            .dims = dims,
            .status_bar_height = status_bar_height,
            .input_area_height = input_area_height,
            .message_area_height = message_area_height,
        };
    }

    /// Update layout on terminal resize
    pub fn resize(self: *Layout, new_dims: Dimensions) void {
        self.dims = new_dims;
        const total_fixed = self.status_bar_height + self.input_area_height;
        self.message_area_height = if (new_dims.height > total_fixed)
            new_dims.height - total_fixed
        else
            1;
    }

    /// Clear entire screen
    pub fn clearScreen(stdout: std.posix.fd_t) !void {
        _ = try std.posix.write(stdout, "\x1b[2J\x1b[H");
    }

    /// Move cursor to position (1-indexed)
    pub fn moveCursor(stdout: std.posix.fd_t, row: usize, col: usize) !void {
        var buf: [32]u8 = undefined;
        const cmd = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row, col });
        _ = try std.posix.write(stdout, cmd);
    }

    /// Hide cursor
    pub fn hideCursor(stdout: std.posix.fd_t) !void {
        _ = try std.posix.write(stdout, "\x1b[?25l");
    }

    /// Show cursor
    pub fn showCursor(stdout: std.posix.fd_t) !void {
        _ = try std.posix.write(stdout, "\x1b[?25h");
    }
};

// Tests
test "dimensions get" {
    // This test might fail in non-TTY environments
    const dims = Dimensions.get() catch {
        // Skip test if not in terminal
        return;
    };

    try std.testing.expect(dims.width > 0);
    try std.testing.expect(dims.height > 0);
}

test "layout init" {
    const dims = Dimensions{ .width = 80, .height = 24 };
    const layout = Layout.init(dims);

    try std.testing.expectEqual(@as(usize, 80), layout.dims.width);
    try std.testing.expectEqual(@as(usize, 24), layout.dims.height);
    try std.testing.expectEqual(@as(usize, 1), layout.status_bar_height);
    try std.testing.expectEqual(@as(usize, 2), layout.input_area_height);
    try std.testing.expectEqual(@as(usize, 21), layout.message_area_height);
}

test "layout resize" {
    const dims = Dimensions{ .width = 80, .height = 24 };
    var layout = Layout.init(dims);

    layout.resize(Dimensions{ .width = 120, .height = 40 });

    try std.testing.expectEqual(@as(usize, 120), layout.dims.width);
    try std.testing.expectEqual(@as(usize, 40), layout.dims.height);
    try std.testing.expectEqual(@as(usize, 37), layout.message_area_height);
}
