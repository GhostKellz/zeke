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

        // Title: "ZEKE v0.3.2" centered
        try writer.writeAll("│");
        try writer.writeAll(" " ** 30);
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
        try writer.writeAll("─" ** 24);
        try writer.writeAll("┬");
        try writer.writeAll("─" ** 49);
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
        try writer.writeAll("─" ** 24);
        try writer.writeAll("┴");
        try writer.writeAll("─" ** 49);
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
        const padding1 = 24 - welcome.len;
        try writer.writeAll(" " ** @min(padding1, 24));

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
                try writer.writeAll("  with instructions for Claude.");
                try writer.writeAll(" " ** 17);
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
        const padding2 = 24 - model_line.len;
        try writer.writeAll(" " ** @min(padding2, 24));

        try writer.writeAll(c.bg_primary);
        try writer.writeAll(c.border_color);
        try writer.writeAll("│");
        try writer.writeAll(c.orange);
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
        const padding3 = 24 - truncated.len;
        try writer.writeAll(" " ** @min(padding3, 24));

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
