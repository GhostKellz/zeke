const std = @import("std");
const phantom = @import("phantom");
const gcode = @import("gcode");

/// Ghost Hacker Blue Theme - Custom vivid Tokyo Night variant
/// Based on: archive/vivid/ghost-hacker-blue.yml
/// Features: Vivid teals, aquas, and mint greens with deep blue backgrounds
pub const TokyoNight = struct {
    // Background colors (ghost-hacker-blue theme)
    pub const bg = "\x1b[48;2;34;36;54m";              // #222436 (main bg)
    pub const bg_dark = "\x1b[48;2;45;63;118m";        // #2d3f76 (darker panels/bg_visual)
    pub const bg_highlight = "\x1b[48;2;68;74;115m";   // #444a73 (terminal_black)
    pub const bg_visual = "\x1b[48;2;45;63;118m";      // #2d3f76

    // Text colors
    pub const fg = "\x1b[38;2;200;211;245m";           // #c8d3f5 (main text)
    pub const fg_dark = "\x1b[38;2;192;202;245m";      // #c0caf5 (blue_moon)
    pub const comment = "\x1b[38;2;99;109;166m";       // #636da6 (comments)

    // Primary accent colors - VIVID teals and aquas
    pub const teal = "\x1b[38;2;79;214;190m";          // #4fd6be (teal/green2) - PRIMARY
    pub const mint = "\x1b[38;2;102;255;194m";         // #66ffc2 (mint) - ACCENT
    pub const aqua_tealish = "\x1b[38;2;102;255;224m"; // #66ffe0 (aqua_tealish)
    pub const blue1 = "\x1b[38;2;180;249;248m";        // #b4f9f8 (blue6/icy)
    pub const blue2 = "\x1b[38;2;13;185;215m";         // #0db9d7 (blue2/info)
    pub const cyan = "\x1b[38;2;137;221;255m";         // #89ddff (blue5)
    pub const green = "\x1b[38;2;195;232;141m";        // #c3e88d (green1)
    pub const green1 = "\x1b[38;2;79;214;190m";        // #4fd6be (same as teal)

    // Supporting colors
    pub const blue = "\x1b[38;2;130;170;255m";         // #82aaff (blue6 from YAML)
    pub const blue_moon = "\x1b[38;2;192;202;245m";    // #c0caf5
    pub const purple = "\x1b[38;2;192;153;255m";       // #c099ff (magenta)
    pub const magenta = "\x1b[38;2;192;153;255m";      // #c099ff
    pub const pink = "\x1b[38;2;252;167;234m";         // #fca7ea (purple in YAML)
    pub const red = "\x1b[38;2;197;59;83m";            // #c53b53 (red1/error)
    pub const red2 = "\x1b[38;2;255;117;127m";         // #ff757f
    pub const orange = "\x1b[38;2;255;150;108m";       // #ff966c
    pub const yellow = "\x1b[38;2;255;199;119m";       // #ffc777
    pub const goldish = "\x1b[38;2;212;175;55m";       // #d4af37

    // Border colors (using vivid teal theme)
    pub const border = "\x1b[38;2;34;36;54m";          // #222436 (bg color)
    pub const border_highlight = "\x1b[38;2;79;214;190m"; // #4fd6be (teal)

    // Special formatting
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim_text = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";

    // Semantic color assignments for ZEKE (Ghost Hacker Blue style)
    pub const logo_primary = teal;         // Vivid teal for ⚡ ZEKE
    pub const logo_accent = mint;          // Bright mint green for accents
    pub const border_color = teal;         // Teal borders (signature color)
    pub const active_element = mint;       // Mint for active/success states
    pub const header_text = cyan;          // Bright cyan for headers
    pub const prompt_symbol = aqua_tealish;// Aqua-teal for > prompt
    pub const status_active = mint;        // Mint for "Thinking..."
    pub const status_info = teal;          // Teal for info messages
    pub const divider_color = comment;     // Dim dividers

    // UI-specific semantic colors
    pub const bg_primary = bg;             // Primary background
    pub const bg_secondary = bg_dark;      // Secondary/panel background
    pub const text_primary = fg;           // Primary text
    pub const text_secondary = fg_dark;    // Secondary/dimmed text
    pub const text_dim = comment;          // Very dimmed text (comments)
};

/// ZEKE Logo ASCII Art
pub const ZekeLogo = struct {
    pub const lightning = "⚡";

    pub const simple =
        \\  ⚡ ZEKE
    ;

    pub const boxed =
        \\┌─────────────┐
        \\│  ⚡  ZEKE   │
        \\└─────────────┘
    ;

    pub const banner =
        \\╔═══════════════════════════════╗
        \\║     ⚡  Z E K E  v0.3.3       ║
        \\╚═══════════════════════════════╝
    ;
};

/// Helper to write N spaces
fn writeSpaces(writer: anytype, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeAll(" ");
    }
}

/// Calculate visual display width of text using gcode (skips ANSI escape codes)
fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        // Skip ANSI escape sequences (ESC [ ... m)
        if (i < text.len and text[i] == 0x1B) {
            // Found ESC, skip until we find 'm'
            i += 1;
            while (i < text.len and text[i] != 'm') : (i += 1) {}
            if (i < text.len) i += 1; // Skip the 'm'
            continue;
        }

        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + cp_len > text.len) break;

        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
            i += 1;
            width += 1;
            continue;
        };

        width += gcode.getWidth(@intCast(cp));
        i += cp_len;
    }
    return width;
}

/// Truncate text to fit max_width with ellipsis if needed
fn truncateToWidth(allocator: std.mem.Allocator, text: []const u8, max_width: usize) ![]const u8 {
    const text_width = displayWidth(text);
    if (text_width <= max_width) {
        return try allocator.dupe(u8, text);
    }

    // Need to truncate - calculate how much to keep
    var width: usize = 0;
    var i: usize = 0;
    const ellipsis = "...";
    const ellipsis_width: usize = 3;

    while (i < text.len and width + ellipsis_width < max_width) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + cp_len > text.len) break;

        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
            i += 1;
            width += 1;
            continue;
        };

        const char_width = gcode.getWidth(@intCast(cp));
        if (width + char_width + ellipsis_width > max_width) break;

        width += char_width;
        i += cp_len;
    }

    // Build truncated string with ellipsis
    const result = try allocator.alloc(u8, i + ellipsis.len);
    @memcpy(result[0..i], text[0..i]);
    @memcpy(result[i..], ellipsis);
    return result;
}

/// Inline Diff View for code changes
pub const DiffView = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    old_content: []const u8,
    new_content: []const u8,

    const Self = @This();

    pub const DiffLine = struct {
        line_type: enum { added, removed, unchanged },
        content: []const u8,
        line_num_old: ?usize,
        line_num_new: ?usize,
    };

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8, old_content: []const u8, new_content: []const u8) Self {
        return Self{
            .allocator = allocator,
            .file_path = file_path,
            .old_content = old_content,
            .new_content = new_content,
        };
    }

    pub fn render(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

        // Title
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writer.writeAll("┌─ Diff: ");
        try writer.writeAll(c.cyan);
        try writer.writeAll(self.file_path);
        try writer.writeAll(c.border_color);
        try writeSpaces(writer, 65 - self.file_path.len);
        try writer.writeAll("─┐\n");

        // Render unified diff
        try self.renderUnifiedDiff(writer);

        // Footer
        try writer.writeAll(c.border_color);
        try writer.writeAll("└");
        try writeSpaces(writer, 77);
        try writer.writeAll("┘\n");
        try writer.writeAll(c.reset);
    }

    fn renderUnifiedDiff(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

        var old_lines = std.mem.split(u8, self.old_content, "\n");
        var new_lines = std.mem.split(u8, self.new_content, "\n");

        var old_line_num: usize = 1;
        var new_line_num: usize = 1;

        // Simple line-by-line diff (could be enhanced with LCS algorithm)
        var old_list = std.ArrayList([]const u8){};
        defer old_list.deinit(self.allocator);
        var new_list = std.ArrayList([]const u8){};
        defer new_list.deinit(self.allocator);

        while (old_lines.next()) |line| {
            try old_list.append(self.allocator, line);
        }
        while (new_lines.next()) |line| {
            try new_list.append(self.allocator, line);
        }

        const max_lines = @max(old_list.items.len, new_list.items.len);
        var i: usize = 0;
        while (i < max_lines and i < 15) : (i += 1) {
            const old_line = if (i < old_list.items.len) old_list.items[i] else null;
            const new_line = if (i < new_list.items.len) new_list.items[i] else null;

            if (old_line != null and new_line != null and std.mem.eql(u8, old_line.?, new_line.?)) {
                // Unchanged line
                try writer.writeAll(c.bg_primary);
                try writer.writeAll(c.border_color);
                try writer.writeAll("│ ");
                try writer.writeAll(c.text_dim);

                const line_num_str = try std.fmt.allocPrint(self.allocator, "{d:4} ", .{old_line_num});
                defer self.allocator.free(line_num_str);
                try writer.writeAll(line_num_str);

                try writer.writeAll(c.fg_dark);
                const truncated = if (old_line.?.len > 70) old_line.?[0..70] else old_line.?;
                try writer.writeAll(truncated);
                try writeSpaces(writer, 70 - truncated.len);
                try writer.writeAll(c.border_color);
                try writer.writeAll(" │\n");

                old_line_num += 1;
                new_line_num += 1;
            } else if (old_line != null and (new_line == null or !std.mem.eql(u8, old_line.?, new_line.?))) {
                // Removed line
                try writer.writeAll(c.bg_primary);
                try writer.writeAll(c.border_color);
                try writer.writeAll("│ ");
                try writer.writeAll(c.red);
                try writer.writeAll("-");

                const line_num_str = try std.fmt.allocPrint(self.allocator, "{d:4} ", .{old_line_num});
                defer self.allocator.free(line_num_str);
                try writer.writeAll(line_num_str);

                const truncated = if (old_line.?.len > 69) old_line.?[0..69] else old_line.?;
                try writer.writeAll(truncated);
                try writeSpaces(writer, 69 - truncated.len);
                try writer.writeAll(c.border_color);
                try writer.writeAll(" │\n");

                old_line_num += 1;
            }

            if (new_line != null and (old_line == null or !std.mem.eql(u8, old_line.?, new_line.?))) {
                // Added line
                try writer.writeAll(c.bg_primary);
                try writer.writeAll(c.border_color);
                try writer.writeAll("│ ");
                try writer.writeAll(c.green);
                try writer.writeAll("+");

                const line_num_str = try std.fmt.allocPrint(self.allocator, "{d:4} ", .{new_line_num});
                defer self.allocator.free(line_num_str);
                try writer.writeAll(line_num_str);

                const truncated = if (new_line.?.len > 69) new_line.?[0..69] else new_line.?;
                try writer.writeAll(truncated);
                try writeSpaces(writer, 69 - truncated.len);
                try writer.writeAll(c.border_color);
                try writer.writeAll(" │\n");

                new_line_num += 1;
            }
        }

        try writer.writeAll(c.reset);
    }
};

/// Interactive TUI Session
pub const InteractiveTUI = struct {
    allocator: std.mem.Allocator,
    username: []const u8,
    model: []const u8,
    current_dir: []const u8,
    input_buffer: std.ArrayList(u8),
    chat_history: std.ArrayList(ChatMessage),
    running: bool,

    // New: Enhanced state tracking
    scroll_offset: usize = 0,
    thinking_mode: bool = false,
    show_model_menu: bool = false,
    total_tokens: u32 = 0,
    prompt_tokens: u32 = 0,
    completion_tokens: u32 = 0,
    estimated_cost: f32 = 0.0,
    streaming_response: std.ArrayList(u8),
    is_streaming: bool = false,

    const Self = @This();

    pub const ChatMessage = struct {
        role: enum { user, assistant },
        content: []const u8,
        tokens: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, username: []const u8, model: []const u8, current_dir: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .username = username,
            .model = model,
            .current_dir = current_dir,
            .input_buffer = std.ArrayList(u8){},
            .chat_history = std.ArrayList(ChatMessage){},
            .running = true,
            .streaming_response = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_buffer.deinit(self.allocator);
        self.streaming_response.deinit(self.allocator);
        for (self.chat_history.items) |msg| {
            self.allocator.free(msg.content);
        }
        self.chat_history.deinit(self.allocator);
    }

    pub fn handleInput(self: *Self, key: u8) !void {
        switch (key) {
            '\n', '\r' => try self.submitCommand(),
            127, 8 => try self.backspace(), // Backspace/Delete
            3 => self.running = false, // Ctrl+C
            27 => self.running = false, // ESC
            32...126 => try self.input_buffer.append(self.allocator, key), // Printable chars
            else => {},
        }
    }

    pub fn submitCommand(self: *Self) !void {
        if (self.input_buffer.items.len == 0) return;

        const command = try self.allocator.dupe(u8, self.input_buffer.items);
        try self.chat_history.append(self.allocator, .{
            .role = .user,
            .content = command,
        });

        // Clear input buffer
        self.input_buffer.clearRetainingCapacity();
    }

    fn backspace(self: *Self) !void {
        if (self.input_buffer.items.len > 0) {
            _ = self.input_buffer.pop();
        }
    }

    // NEW: Scrolling support
    pub fn scrollUp(self: *Self) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    pub fn scrollDown(self: *Self) void {
        const max_scroll = if (self.chat_history.items.len > 10)
            self.chat_history.items.len - 10
        else
            0;
        if (self.scroll_offset < max_scroll) {
            self.scroll_offset += 1;
        }
    }

    // NEW: Streaming support
    pub fn startStreaming(self: *Self) !void {
        self.is_streaming = true;
        self.streaming_response.clearRetainingCapacity();
    }

    pub fn appendStreamChunk(self: *Self, chunk: []const u8) !void {
        try self.streaming_response.appendSlice(self.allocator, chunk);
    }

    pub fn finishStreaming(self: *Self) !void {
        self.is_streaming = false;
        if (self.streaming_response.items.len > 0) {
            const content = try self.allocator.dupe(u8, self.streaming_response.items);
            try self.chat_history.append(self.allocator, .{
                .role = .assistant,
                .content = content,
                .tokens = @intCast(self.streaming_response.items.len / 4), // Rough estimate
            });
            self.streaming_response.clearRetainingCapacity();
        }
    }

    // NEW: Token tracking
    pub fn addTokens(self: *Self, prompt: u32, completion: u32) void {
        self.prompt_tokens += prompt;
        self.completion_tokens += completion;
        self.total_tokens = self.prompt_tokens + self.completion_tokens;

        // Rough cost estimate: $3/M input, $15/M output for Sonnet 4.5
        const input_cost = @as(f32, @floatFromInt(self.prompt_tokens)) * 3.0 / 1_000_000.0;
        const output_cost = @as(f32, @floatFromInt(self.completion_tokens)) * 15.0 / 1_000_000.0;
        self.estimated_cost = input_cost + output_cost;
    }

    pub fn render(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

        // Clear screen
        try writer.writeAll("\x1b[2J\x1b[H");

        // Title bar
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writer.writeAll("┌");
        try writeSpaces(writer, 77);
        try writer.writeAll("┐\n│");
        try writeSpaces(writer, 30);
        try writer.writeAll(c.header_text);
        try writer.writeAll(c.bold);
        try writer.writeAll("⚡ ZEKE Interactive");
        try writer.writeAll(c.reset);
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writeSpaces(writer, 28);
        try writer.writeAll("│\n├");
        try writeSpaces(writer, 77);
        try writer.writeAll("┤\n");

        // Chat history area
        try self.renderChatHistory(writer);

        // Input area
        try self.renderInputArea(writer);

        // Footer with enhanced info
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll(c.text_dim);
        try writer.writeAll("? help");
        try writeSpaces(writer, 5);
        try writer.writeAll(c.yellow);

        // Token and cost display
        const stats = try std.fmt.allocPrint(
            self.allocator,
            "Tokens: {d} | Cost: ${d:.4}",
            .{ self.total_tokens, self.estimated_cost },
        );
        defer self.allocator.free(stats);
        try writer.writeAll(stats);

        const stats_remaining = 60 - stats.len;
        if (stats_remaining > 0) {
            try writeSpaces(writer, stats_remaining);
        }

        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n└");
        try writeSpaces(writer, 77);
        try writer.writeAll("┘\n");

        try writer.writeAll(c.reset);
    }

    fn renderChatHistory(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;
        const max_messages = 10;

        // Show last N messages
        const start_idx = if (self.chat_history.items.len > max_messages)
            self.chat_history.items.len - max_messages
        else
            0;

        for (self.chat_history.items[start_idx..]) |msg| {
            try writer.writeAll(c.bg_primary);
            try writer.writeAll(c.border_color);
            try writer.writeAll("│ ");

            if (msg.role == .user) {
                try writer.writeAll(c.cyan);
                try writer.writeAll("> ");
                try writer.writeAll(c.fg);
            } else {
                try writer.writeAll(c.green);
                try writer.writeAll("< ");
                try writer.writeAll(c.fg);
            }

            // Truncate long messages to fit
            const max_len: usize = 70;
            const display_content = if (msg.content.len > max_len) msg.content[0..max_len] else msg.content;
            try writer.writeAll(display_content);
            const remaining_space = 73 - display_content.len;
            if (remaining_space > 0) {
                try writeSpaces(writer, remaining_space);
            }
            try writer.writeAll(c.border_color);
            try writer.writeAll(" │\n");
        }

        // Fill remaining space
        const shown = self.chat_history.items.len - start_idx;
        var i: usize = shown;
        while (i < 10) : (i += 1) {
            try writer.writeAll(c.bg_primary);
            try writer.writeAll(c.border_color);
            try writer.writeAll("│");
            try writeSpaces(writer, 77);
            try writer.writeAll("│\n");
        }
        try writer.writeAll(c.reset);
    }

    fn renderInputArea(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("├");
        try writeSpaces(writer, 77);
        try writer.writeAll("┤\n│ ");
        try writer.writeAll(c.cyan);
        try writer.writeAll("> ");
        try writer.writeAll(c.fg);
        try writer.writeAll(self.input_buffer.items);

        const remaining = 73 - self.input_buffer.items.len;
        if (remaining > 0) {
            try writeSpaces(writer, remaining);
        }

        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");
        try writer.writeAll(c.reset);
    }
};

/// Color Palette - holds runtime theme colors
pub const ColorPalette = struct {
    // All color fields from TokyoNight
    bg: []const u8,
    bg_dark: []const u8,
    bg_highlight: []const u8,
    bg_visual: []const u8,
    fg: []const u8,
    fg_dark: []const u8,
    comment: []const u8,
    teal: []const u8,
    mint: []const u8,
    aqua_tealish: []const u8,
    blue1: []const u8,
    blue2: []const u8,
    cyan: []const u8,
    green: []const u8,
    green1: []const u8,
    blue: []const u8,
    blue_moon: []const u8,
    purple: []const u8,
    magenta: []const u8,
    pink: []const u8,
    red: []const u8,
    red2: []const u8,
    orange: []const u8,
    yellow: []const u8,
    goldish: []const u8,
    border: []const u8,
    border_highlight: []const u8,
    reset: []const u8,
    bold: []const u8,
    dim_text: []const u8,
    italic: []const u8,
    underline: []const u8,
    logo_primary: []const u8,
    logo_accent: []const u8,
    border_color: []const u8,
    active_element: []const u8,
    header_text: []const u8,
    prompt_symbol: []const u8,
    status_active: []const u8,
    status_info: []const u8,
    divider_color: []const u8,
    bg_primary: []const u8,
    bg_secondary: []const u8,
    text_primary: []const u8,
    text_secondary: []const u8,
    text_dim: []const u8,

    /// Create palette from static TokyoNight struct (for compatibility)
    pub fn fromStatic() ColorPalette {
        return .{
            .bg = TokyoNight.bg,
            .bg_dark = TokyoNight.bg_dark,
            .bg_highlight = TokyoNight.bg_highlight,
            .bg_visual = TokyoNight.bg_visual,
            .fg = TokyoNight.fg,
            .fg_dark = TokyoNight.fg_dark,
            .comment = TokyoNight.comment,
            .teal = TokyoNight.teal,
            .mint = TokyoNight.mint,
            .aqua_tealish = TokyoNight.aqua_tealish,
            .blue1 = TokyoNight.blue1,
            .blue2 = TokyoNight.blue2,
            .cyan = TokyoNight.cyan,
            .green = TokyoNight.green,
            .green1 = TokyoNight.green1,
            .blue = TokyoNight.blue,
            .blue_moon = TokyoNight.blue_moon,
            .purple = TokyoNight.purple,
            .magenta = TokyoNight.magenta,
            .pink = TokyoNight.pink,
            .red = TokyoNight.red,
            .red2 = TokyoNight.red2,
            .orange = TokyoNight.orange,
            .yellow = TokyoNight.yellow,
            .goldish = TokyoNight.goldish,
            .border = TokyoNight.border,
            .border_highlight = TokyoNight.border_highlight,
            .reset = TokyoNight.reset,
            .bold = TokyoNight.bold,
            .dim_text = TokyoNight.dim_text,
            .italic = TokyoNight.italic,
            .underline = TokyoNight.underline,
            .logo_primary = TokyoNight.logo_primary,
            .logo_accent = TokyoNight.logo_accent,
            .border_color = TokyoNight.border_color,
            .active_element = TokyoNight.active_element,
            .header_text = TokyoNight.header_text,
            .prompt_symbol = TokyoNight.prompt_symbol,
            .status_active = TokyoNight.status_active,
            .status_info = TokyoNight.status_info,
            .divider_color = TokyoNight.divider_color,
            .bg_primary = TokyoNight.bg_primary,
            .bg_secondary = TokyoNight.bg_secondary,
            .text_primary = TokyoNight.text_primary,
            .text_secondary = TokyoNight.text_secondary,
            .text_dim = TokyoNight.text_dim,
        };
    }
};

/// Welcome Screen Layout
pub const WelcomeScreen = struct {
    allocator: std.mem.Allocator,
    username: []const u8,
    model: []const u8,
    current_dir: []const u8,
    colors: ColorPalette,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, username: []const u8, model: []const u8, current_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .username = username,
            .model = model,
            .current_dir = current_dir,
            .colors = ColorPalette.fromStatic(), // Use hardcoded ghost-hacker-blue for now
        };
    }

    pub fn render(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Clear screen and move to top
        try writer.writeAll("\x1b[2J\x1b[H");

        // Title bar
        try self.renderTitleBar(writer);

        // Main content area
        try self.renderContentPanels(writer);

        // Command input area
        try self.renderCommandInput(writer);

        // Footer
        try self.renderFooter(writer);

        try writer.writeAll(c.reset);
    }

    fn renderTitleBar(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Top border with title
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writer.writeAll("┌");
        var i: usize = 0;
        while (i < 77) : (i += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");

        // Title: "⚡ ZEKE v0.3.2" centered
        try writer.writeAll("│");
        try writeSpaces(writer, 28);
        try writer.writeAll(c.logo_primary);
        try writer.writeAll("⚡ ");
        try writer.writeAll(c.header_text);
        try writer.writeAll(c.bold);
        try writer.writeAll("ZEKE v0.3.2");
        try writer.writeAll(c.reset);
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writeSpaces(writer, 36);
        try writer.writeAll("│\n");

        // Separator
        try writer.writeAll("├");
        var j: usize = 0;
        while (j < 77) : (j += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("┤\n");
        try writer.writeAll(c.reset);
    }

    fn renderContentPanels(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Panel top border
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll("┌");
        try writeSpaces(writer, 24);
        try writer.writeAll("┬");
        try writeSpaces(writer, 49);
        try writer.writeAll("┐");
        try writer.writeAll(" │\n");

        // Left panel: Welcome + Logo
        try self.renderLeftPanel(writer);

        // Right panel: Tips
        try self.renderRightPanel(writer);

        // Panel bottom border
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll("└");
        try writeSpaces(writer, 24);
        try writer.writeAll("┴");
        try writeSpaces(writer, 49);
        try writer.writeAll("┘");
        try writer.writeAll(" │\n");
        try writer.writeAll(c.reset);
    }

    fn renderLeftPanel(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Row 1: Welcome message
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll(c.bg_secondary);
        try writer.writeAll(c.cyan);

        const welcome = try std.fmt.allocPrint(self.allocator, "  Welcome back {s}!", .{self.username});
        defer self.allocator.free(welcome);

        try writer.writeAll(welcome);
        if (welcome.len < 24) {
            const padding1 = 24 - welcome.len;
            try writeSpaces(writer, padding1);
        }

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(c.text_primary);
        try writer.writeAll("  Tips for getting started");
        try writeSpaces(writer, 24);
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Row 2-4: Logo area
        for (0..3) |i| {
            try writer.writeAll("│ ");
            try writer.writeAll(c.bg_secondary);

            if (i == 1) {
                // Center the logo
                try writer.writeAll("      ");
                try writer.writeAll(c.teal);
                try writer.writeAll(c.bold);
                try writer.writeAll("⚡ ZEKE");
                try writer.writeAll(c.reset);
                try writer.writeAll(c.bg_secondary);
                try writer.writeAll("       ");
            } else {
                try writeSpaces(writer, 24);
            }

            try writer.writeAll(c.bg_primary);
            try writer.writeAll(c.border_color);
            try writer.writeAll("│");

            // Right panel content
            if (i == 0) {
                try writer.writeAll(c.text_secondary);
                try writer.writeAll("  Run ");
                try writer.writeAll(c.cyan);
                try writer.writeAll("/init");
                try writer.writeAll(c.text_secondary);
                try writer.writeAll(" to create a ZEKE.md file");
                try writeSpaces(writer, 13);
            } else if (i == 1) {
                try writer.writeAll(c.text_secondary);
                try writer.writeAll("  with instructions for Zeke.");
                try writeSpaces(writer, 18);
            } else {
                try writeSpaces(writer, 49);
            }

            try writer.writeAll(c.bg_primary);
            try writer.writeAll(c.border_color);
            try writer.writeAll(" │\n");
        }

        // Row 5: Model info
        try writer.writeAll("│ ");
        try writer.writeAll(c.bg_secondary);
        try writer.writeAll(c.text_secondary);

        // Clamp model name to max 20 chars to fit in 24-char box with "  " prefix
        var model_display = self.model;
        if (model_display.len > 20) {
            model_display = model_display[0..17]; // Leave room for "..."
            const temp = try std.fmt.allocPrint(self.allocator, "{s}...", .{model_display});
            defer self.allocator.free(temp);
            model_display = temp;
        }

        try writer.writeAll("  ");
        try writer.writeAll(model_display);

        // Pad to 24 chars total (including "  " prefix)
        const used_len = 2 + model_display.len;
        if (used_len < 24) {
            try writeSpaces(writer, 24 - used_len);
        }

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(c.yellow);
        try writer.writeAll("  Recent activity");
        try writeSpaces(writer, 32);
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Row 6: Directory
        try writer.writeAll("│ ");
        try writer.writeAll(c.bg_secondary);
        try writer.writeAll(c.text_dim);

        const dir_line = try std.fmt.allocPrint(self.allocator, "  {s}", .{self.current_dir});
        defer self.allocator.free(dir_line);

        const truncated = if (dir_line.len > 24) dir_line[0..24] else dir_line;
        try writer.writeAll(truncated);
        if (truncated.len < 24) {
            const padding3 = 24 - truncated.len;
            try writeSpaces(writer, padding3);
        }

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(c.text_dim);
        try writer.writeAll("  No recent activity");
        try writeSpaces(writer, 30);
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        try writer.writeAll(c.reset);
    }

    fn renderRightPanel(self: *const Self, writer: anytype) !void {
        _ = self;
        _ = writer;
        // Right panel content rendered in renderLeftPanel for now
    }

    fn renderCommandInput(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Empty line
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writeSpaces(writer, 77);
        try writer.writeAll("│\n");

        // Command prompt line
        try writer.writeAll("│ ");
        try writer.writeAll(c.cyan);
        try writer.writeAll("> ");
        try writer.writeAll(c.text_primary);
        try writer.writeAll("Try \"edit <filepath> to ...\"");
        try writeSpaces(writer, 46);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Empty line
        try writer.writeAll("│");
        try writeSpaces(writer, 77);
        try writer.writeAll("│\n");

        try writer.writeAll(c.reset);
    }

    fn renderFooter(self: *const Self, writer: anytype) !void {
        const c = self.colors;

        // Footer line
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll(c.text_dim);
        try writer.writeAll("? for shortcuts");
        try writeSpaces(writer, 36);
        try writer.writeAll(c.text_secondary);
        try writer.writeAll("Thinking off (tab to toggle)");
        try writer.writeAll(" ");
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Bottom border
        try writer.writeAll("└");
        var k: usize = 0;
        while (k < 77) : (k += 1) {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘\n");

        try writer.writeAll(c.reset);
    }
};
