const std = @import("std");
const phantom = @import("phantom");

/// Simplified cell buffer for ZEKE TUI
/// Uses a 2D grid of cells with RGB colors
pub const CellBuffer = struct {
    allocator: std.mem.Allocator,
    cells: []Cell,
    width: usize,
    height: usize,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !CellBuffer {
        const total = width * height;
        const cells = try allocator.alloc(Cell, total);

        // Initialize all cells to empty
        for (cells) |*cell| {
            cell.* = Cell.empty();
        }

        return .{
            .allocator = allocator,
            .cells = cells,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *CellBuffer) void {
        self.allocator.free(self.cells);
    }

    /// Clear the entire buffer
    pub fn clear(self: *CellBuffer) void {
        for (self.cells) |*cell| {
            cell.* = Cell.empty();
        }
    }

    /// Set a cell at (x, y)
    pub fn setCell(self: *CellBuffer, x: usize, y: usize, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        self.cells[idx] = cell;
    }

    /// Get a cell at (x, y)
    pub fn getCell(self: *const CellBuffer, x: usize, y: usize) Cell {
        if (x >= self.width or y >= self.height) return Cell.empty();
        const idx = y * self.width + x;
        return self.cells[idx];
    }

    /// Write text at position with colors
    pub fn writeText(self: *CellBuffer, x: usize, y: usize, text: []const u8, fg: RGB, bg: RGB) usize {
        if (y >= self.height) return 0;

        var col = x;
        var i: usize = 0;
        while (i < text.len and col < self.width) {
            const ch = text[i];

            // Handle UTF-8 multibyte characters
            const len = std.unicode.utf8ByteSequenceLength(ch) catch 1;
            if (i + len > text.len) break;

            const cell = Cell{
                .char = ch,
                .fg = fg,
                .bg = bg,
            };
            self.setCell(col, y, cell);

            col += 1;
            i += len;
        }

        return col - x; // Return width written
    }

    /// Fill a region with a character
    pub fn fillRect(self: *CellBuffer, x: usize, y: usize, width: usize, height: usize, ch: u8, fg: RGB, bg: RGB) void {
        var row: usize = y;
        while (row < y + height and row < self.height) : (row += 1) {
            var col: usize = x;
            while (col < x + width and col < self.width) : (col += 1) {
                self.setCell(col, row, Cell{ .char = ch, .fg = fg, .bg = bg });
            }
        }
    }

    /// Render the buffer with ANSI codes using the provided writer
    pub fn render(self: *const CellBuffer, writer: anytype) !void {
        // Clear screen and move cursor to top-left
        _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[2J\x1b[H");

        var y: usize = 0;
        while (y < self.height) : (y += 1) {
            var x: usize = 0;
            var last_fg: ?RGB = null;
            var last_bg: ?RGB = null;

            while (x < self.width) : (x += 1) {
                const cell = self.getCell(x, y);

                // Only emit ANSI codes when colors change
                if (last_fg == null or !cell.fg.eq(last_fg.?)) {
                    var buf: [32]u8 = undefined;
                    const code = try std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ cell.fg.r, cell.fg.g, cell.fg.b });
                    _ = try std.posix.write(std.posix.STDOUT_FILENO, code);
                    last_fg = cell.fg;
                }
                if (last_bg == null or !cell.bg.eq(last_bg.?)) {
                    var buf: [32]u8 = undefined;
                    const code = try std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ cell.bg.r, cell.bg.g, cell.bg.b });
                    _ = try std.posix.write(std.posix.STDOUT_FILENO, code);
                    last_bg = cell.bg;
                }

                // Write the character
                _ = try std.posix.write(std.posix.STDOUT_FILENO, &[_]u8{cell.char});
            }

            // Reset at end of line and move to next line
            _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[0m\r\n");
        }

        // Reset colors
        _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[0m");
        _ = writer; // Keep for interface compatibility
    }
};

/// Individual cell with character and colors
pub const Cell = struct {
    char: u8,
    fg: RGB,
    bg: RGB,

    pub fn empty() Cell {
        return .{
            .char = ' ',
            .fg = RGB.init(192, 202, 245), // Default fg
            .bg = RGB.init(26, 27, 38),     // Default bg
        };
    }
};

/// RGB color
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn eq(self: RGB, other: RGB) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }

    /// Parse hex color like "c8d3f5" or "#c8d3f5"
    pub fn fromHex(hex: []const u8) !RGB {
        const color_str = if (std.mem.startsWith(u8, hex, "#")) hex[1..] else hex;
        if (color_str.len != 6) return error.InvalidHex;

        const r = try std.fmt.parseInt(u8, color_str[0..2], 16);
        const g = try std.fmt.parseInt(u8, color_str[2..4], 16);
        const b = try std.fmt.parseInt(u8, color_str[4..6], 16);

        return RGB.init(r, g, b);
    }
};
