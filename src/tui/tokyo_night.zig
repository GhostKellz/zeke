const std = @import("std");
const phantom = @import("phantom");

/// Tokyo Night Color Palette - Official Night Theme
/// Source: https://github.com/folke/tokyonight.nvim
pub const TokyoNight = struct {
    // Background colors (official Tokyo Night Night theme)
    pub const bg = "\x1b[48;2;26;27;38m";              // #1a1b26 (main bg)
    pub const bg_dark = "\x1b[48;2;22;22;30m";         // #16161e (darker panels)
    pub const bg_highlight = "\x1b[48;2;41;46;66m";    // #292e42
    pub const bg_visual = "\x1b[48;2;40;52;87m";       // #283457

    // Text colors
    pub const fg = "\x1b[38;2;192;202;245m";           // #c0caf5 (main text)
    pub const fg_dark = "\x1b[38;2;169;177;214m";      // #a9b1d6 (dimmed)
    pub const comment = "\x1b[38;2;86;95;137m";        // #565f89 (comments)

    // Primary accent colors (replacing orange with teal/green)
    pub const blue1 = "\x1b[38;2;42;195;222m";         // #2ac3de (TEAL - our primary)
    pub const blue2 = "\x1b[38;2;13;185;215m";         // #0db9d7 (darker teal)
    pub const cyan = "\x1b[38;2;125;207;255m";         // #7dcfff (bright cyan)
    pub const green = "\x1b[38;2;158;206;106m";        // #9ece6a (MINTY GREEN - our secondary)
    pub const green1 = "\x1b[38;2;115;218;202m";       // #73daca (teal-green hybrid)
    pub const teal = "\x1b[38;2;26;188;156m";          // #1abc9c (pure teal)

    // Supporting colors
    pub const blue = "\x1b[38;2;122;162;247m";         // #7aa2f7 (standard blue)
    pub const purple = "\x1b[38;2;187;154;247m";       // #bb9af7
    pub const magenta = "\x1b[38;2;187;154;247m";      // #bb9af7
    pub const red = "\x1b[38;2;247;118;142m";          // #f7768e (soft red)
    pub const orange = "\x1b[38;2;255;158;100m";       // #ff9e64 (REPLACED by green in UI)
    pub const yellow = "\x1b[38;2;224;175;104m";       // #e0af68

    // Border colors (using our teal/cyan theme)
    pub const border = "\x1b[38;2;21;22;30m";          // #15161e (subtle)
    pub const border_highlight = "\x1b[38;2;39;161;185m"; // #27a1b9 (active teal)

    // Special formatting
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim_text = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";

    // Semantic color assignments for ZEKE
    pub const logo_primary = blue1;        // Teal for ⚡ ZEKE
    pub const logo_accent = green;         // Minty green for accents
    pub const border_color = blue1;        // Teal borders (replaces Claude's orange)
    pub const active_element = green;      // Minty green for active/success states
    pub const header_text = cyan;          // Bright cyan for headers
    pub const prompt_symbol = cyan;        // Cyan for > prompt
    pub const status_active = green;       // Green for "Thinking..."
    pub const status_info = blue1;         // Teal for info messages
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
        \\║     ⚡  Z E K E  v0.3.2       ║
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

    const Self = @This();

    pub const ChatMessage = struct {
        role: enum { user, assistant },
        content: []const u8,
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
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_buffer.deinit(self.allocator);
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

        // Footer
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll(c.text_dim);
        try writer.writeAll("Ctrl+C or ESC to exit");
        try writeSpaces(writer, 30);
        try writer.writeAll(c.text_secondary);
        try writer.writeAll(self.model);
        try writeSpaces(writer, 5);
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

            try writer.writeAll(msg.content);
            try writeSpaces(writer, 73 - msg.content.len);
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

/// Welcome Screen Layout
pub const WelcomeScreen = struct {
    allocator: std.mem.Allocator,
    username: []const u8,
    model: []const u8,
    current_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, username: []const u8, model: []const u8, current_dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .username = username,
            .model = model,
            .current_dir = current_dir,
        };
    }

    pub fn render(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

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
        _ = self;
        const c = TokyoNight;

        // Top border with title
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writer.writeAll("┌");
        try writer.writeAll("─" ** 77);
        try writer.writeAll("┐\n");

        // Title: "⚡ ZEKE v0.3.2" centered
        try writer.writeAll("│");
        try writer.writeAll(" " ** 28);
        try writer.writeAll(c.logo_primary);
        try writer.writeAll("⚡ ");
        try writer.writeAll(c.header_text);
        try writer.writeAll(c.bold);
        try writer.writeAll("ZEKE v0.3.2");
        try writer.writeAll(c.reset);
        try writer.writeAll(c.bg);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" " ** 36);
        try writer.writeAll("│\n");

        // Separator
        try writer.writeAll("├");
        try writer.writeAll("─" ** 77);
        try writer.writeAll("┤\n");
        try writer.writeAll(c.reset);
    }

    fn renderContentPanels(self: *const Self, writer: anytype) !void {
        const c = TokyoNight;

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
        const c = TokyoNight;

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
        try writer.writeAll(" " ** 24);
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
                try writer.writeAll(" " ** 24);
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
                try writer.writeAll(" " ** 13);
            } else if (i == 1) {
                try writer.writeAll(c.text_secondary);
                try writer.writeAll("  with instructions for Zeke.");
                try writer.writeAll(" " ** 18);
            } else {
                try writer.writeAll(" " ** 49);
            }

            try writer.writeAll(c.bg_primary);
            try writer.writeAll(c.border_color);
            try writer.writeAll(" │\n");
        }

        // Row 5: Model info
        try writer.writeAll("│ ");
        try writer.writeAll(c.bg_secondary);
        try writer.writeAll(c.text_secondary);

        const model_line = try std.fmt.allocPrint(self.allocator, "  {s}", .{self.model});
        defer self.allocator.free(model_line);

        try writer.writeAll(model_line);
        if (model_line.len < 24) {
            const padding2 = 24 - model_line.len;
            try writeSpaces(writer, padding2);
        }

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(c.yellow);
        try writer.writeAll("  Recent activity");
        try writer.writeAll(" " ** 32);
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
        try writer.writeAll(" " ** 30);
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
        _ = self;
        const c = TokyoNight;

        // Empty line
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(" " ** 77);
        try writer.writeAll("│\n");

        // Command prompt line
        try writer.writeAll("│ ");
        try writer.writeAll(c.cyan);
        try writer.writeAll("> ");
        try writer.writeAll(c.text_primary);
        try writer.writeAll("Try \"edit <filepath> to ...\"");
        try writer.writeAll(" " ** 46);
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Empty line
        try writer.writeAll("│");
        try writer.writeAll(" " ** 77);
        try writer.writeAll("│\n");

        try writer.writeAll(c.reset);
    }

    fn renderFooter(self: *const Self, writer: anytype) !void {
        _ = self;
        const c = TokyoNight;

        // Footer line
        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│ ");
        try writer.writeAll(c.text_dim);
        try writer.writeAll("? for shortcuts");
        try writer.writeAll(" " ** 36);
        try writer.writeAll(c.text_secondary);
        try writer.writeAll("Thinking off (tab to toggle)");
        try writer.writeAll(" ");
        try writer.writeAll(c.border_color);
        try writer.writeAll(" │\n");

        // Bottom border
        try writer.writeAll("└");
        try writer.writeAll("─" ** 77);
        try writer.writeAll("┘\n");

        try writer.writeAll(c.reset);
    }
};
