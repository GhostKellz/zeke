const std = @import("std");
const CellBuffer = @import("cell_buffer.zig").CellBuffer;
const RGB = @import("cell_buffer.zig").RGB;

/// Welcome screen using proper cell buffer architecture
pub const WelcomeScreen = struct {
    allocator: std.mem.Allocator,
    buffer: CellBuffer,
    username: []const u8,
    model: []const u8,
    current_dir: []const u8,

    // Ghost Hacker Blue colors
    const colors = struct {
        const bg = RGB.init(34, 36, 54);           // #222436
        const bg_dark = RGB.init(45, 63, 118);     // #2d3f76
        const fg = RGB.init(200, 211, 245);        // #c8d3f5
        const teal = RGB.init(79, 214, 190);       // #4fd6be
        const mint = RGB.init(102, 255, 194);      // #66ffc2
        const cyan = RGB.init(137, 221, 255);      // #89ddff
        const yellow = RGB.init(255, 199, 119);    // #ffc777
        const text_dim = RGB.init(99, 109, 166);   // #636da6
    };

    const WIDTH: usize = 79;
    const HEIGHT: usize = 20;

    pub fn init(allocator: std.mem.Allocator, username: []const u8, model: []const u8, current_dir: []const u8) !WelcomeScreen {
        return .{
            .allocator = allocator,
            .buffer = try CellBuffer.init(allocator, WIDTH, HEIGHT),
            .username = username,
            .model = model,
            .current_dir = current_dir,
        };
    }

    pub fn deinit(self: *WelcomeScreen) void {
        self.buffer.deinit();
    }

    /// Build the welcome screen into the cell buffer
    pub fn build(self: *WelcomeScreen) !void {
        // Clear buffer
        self.buffer.clear();

        // Fill background
        self.buffer.fillRect(0, 0, WIDTH, HEIGHT, ' ', colors.fg, colors.bg);

        // Draw border
        try self.drawBorder();

        // Draw title
        try self.drawTitle();

        // Draw content panels
        try self.drawContentPanels();

        // Draw command input area
        try self.drawCommandInput();

        // Draw footer
        try self.drawFooter();
    }

    fn drawBorder(self: *WelcomeScreen) !void {
        const c = colors;

        // Top border
        self.buffer.setCell(0, 0, .{ .char = '+', .fg = c.teal, .bg = c.bg });
        var x: usize = 1;
        while (x < WIDTH - 1) : (x += 1) {
            self.buffer.setCell(x, 0, .{ .char = '-', .fg = c.teal, .bg = c.bg });
        }
        self.buffer.setCell(WIDTH - 1, 0, .{ .char = '+', .fg = c.teal, .bg = c.bg });

        // Bottom border
        self.buffer.setCell(0, HEIGHT - 1, .{ .char = '+', .fg = c.teal, .bg = c.bg });
        x = 1;
        while (x < WIDTH - 1) : (x += 1) {
            self.buffer.setCell(x, HEIGHT - 1, .{ .char = '-', .fg = c.teal, .bg = c.bg });
        }
        self.buffer.setCell(WIDTH - 1, HEIGHT - 1, .{ .char = '+', .fg = c.teal, .bg = c.bg });

        // Side borders
        var y: usize = 1;
        while (y < HEIGHT - 1) : (y += 1) {
            self.buffer.setCell(0, y, .{ .char = '|', .fg = c.teal, .bg = c.bg });
            self.buffer.setCell(WIDTH - 1, y, .{ .char = '|', .fg = c.teal, .bg = c.bg });
        }
    }

    fn drawTitle(self: *WelcomeScreen) !void {
        const c = colors;
        const title = "ZEKE v0.3.3";
        const x = (WIDTH - title.len) / 2;
        _ = self.buffer.writeText(x, 2, title, c.cyan, c.bg);
    }

    fn drawContentPanels(self: *WelcomeScreen) !void {
        const c = colors;

        // Welcome message
        var welcome_buf: [100]u8 = undefined;
        const welcome = try std.fmt.bufPrint(&welcome_buf, "  Welcome back {s}!", .{self.username});
        _ = self.buffer.writeText(4, 5, welcome, c.cyan, c.bg);

        // Logo
        _ = self.buffer.writeText(10, 7, "ZEKE", c.teal, c.bg);

        // Model info
        var model_buf: [100]u8 = undefined;
        const model_text = try std.fmt.bufPrint(&model_buf, "Model: {s}", .{self.model});
        const model_display = if (model_text.len > 30) model_text[0..27] ++ "..." else model_text;
        _ = self.buffer.writeText(4, 9, model_display, c.text_dim, c.bg);

        // Directory
        var dir_buf: [100]u8 = undefined;
        const dir_text = try std.fmt.bufPrint(&dir_buf, "Dir: {s}", .{self.current_dir});
        const dir_display = if (dir_text.len > 30) dir_text[0..27] ++ "..." else dir_text;
        _ = self.buffer.writeText(4, 10, dir_display, c.text_dim, c.bg);

        // Tips
        _ = self.buffer.writeText(45, 5, "Tips:", c.yellow, c.bg);
        _ = self.buffer.writeText(45, 6, "  - Type /help for commands", c.fg, c.bg);
        _ = self.buffer.writeText(45, 7, "  - Tab to toggle thinking mode", c.fg, c.bg);
        _ = self.buffer.writeText(45, 8, "  - Ctrl+C to exit", c.fg, c.bg);
    }

    fn drawCommandInput(self: *WelcomeScreen) !void {
        const c = colors;
        _ = self.buffer.writeText(2, 14, "> ", c.cyan, c.bg);
        _ = self.buffer.writeText(4, 14, "Type a command...", c.text_dim, c.bg);
    }

    fn drawFooter(self: *WelcomeScreen) !void {
        const c = colors;
        _ = self.buffer.writeText(2, HEIGHT - 2, "? for help", c.text_dim, c.bg);
        _ = self.buffer.writeText(WIDTH - 30, HEIGHT - 2, "Thinking: OFF (tab to toggle)", c.text_dim, c.bg);
    }

    /// Render the buffer to stdout
    pub fn render(self: *const WelcomeScreen, writer: anytype) !void {
        try self.buffer.render(writer);
    }
};
