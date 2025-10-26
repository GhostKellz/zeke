/// Enhanced TUI module leveraging Phantom v0.5.0 features
/// - TextEditor widget for chat interface with multi-cursor support
/// - FontManager for ligatures and Nerd Font icons
/// - Unicode-aware text processing with gcode
/// - GPU-ready rendering architecture
const std = @import("std");
const phantom = @import("phantom");
const zsync = @import("zsync");

pub const EnhancedTuiApp = struct {
    allocator: std.mem.Allocator,
    zeke_instance: ?*anyopaque,
    app: phantom.App,

    // Enhanced UI Components (Phantom v0.5.0)
    chat_editor: *phantom.widgets.editor.TextEditor,
    code_editor: ?*phantom.widgets.editor.TextEditor,
    font_manager: *phantom.font.FontManager,

    // State
    chat_history: std.ArrayList(ChatEntry),
    selected_model: []const u8,

    // Async runtime
    runtime: *zsync.Runtime,

    const Self = @This();

    const ChatEntry = struct {
        role: enum { user, assistant, system },
        content: []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator, zeke_instance: ?*anyopaque) !Self {
        // Initialize zsync runtime
        const runtime = try zsync.Runtime.init(allocator, .{
            .execution_model = .auto,
        });

        // Initialize phantom app
        const app = try phantom.App.init(allocator, .{
            .title = "⚡ ZEKE v0.5.0 - AI Dev Companion",
            .tick_rate_ms = 50,
            .mouse_enabled = true,
        });

        // Initialize FontManager with Phantom v0.5.0 features
        const font_config = phantom.font.FontManager.FontConfig{
            .primary_font_family = "JetBrains Mono",
            .fallback_families = &.{ "Fira Code", "Cascadia Code", "monospace" },
            .font_size = 12.0,
            .enable_ligatures = true, // Programming ligatures (==, =>, ->, !=)
            .enable_nerd_font_icons = true, // File type icons
            .terminal_optimized = true,
        };

        var font_manager = try phantom.font.FontManager.init(allocator, font_config);

        // Create TextEditor for chat interface
        const chat_config = phantom.widgets.editor.TextEditor.EditorConfig{
            .show_line_numbers = false, // Clean chat interface
            .line_wrap = true, // Wrap long AI responses
            .enable_ligatures = true, // Better code snippets in chat
            .auto_indent = false, // Natural chat formatting
            .tab_size = 4,
        };

        const chat_editor = try phantom.widgets.editor.TextEditor.init(allocator, chat_config);

        // Load welcome message
        const welcome =
            \\🤖 ZEKE v0.5.0: Welcome! Powered by Phantom TUI v0.5.0
            \\
            \\✨ New Features:
            \\• TextEditor with multi-cursor editing (VSCode-style)
            \\• Programming ligatures for better code readability
            \\• Nerd Font icons for file types
            \\• 3-15x faster Unicode processing
            \\• Rope data structure for large files
            \\
            \\Type your messages below and press Enter to send!
            \\
        ;
        try chat_editor.buffer.loadFromString(welcome);

        return Self{
            .allocator = allocator,
            .zeke_instance = zeke_instance,
            .app = app,
            .chat_editor = chat_editor,
            .code_editor = null,
            .font_manager = font_manager,
            .chat_history = std.ArrayList(ChatEntry).init(allocator),
            .selected_model = "claude-3-5-sonnet-20241022",
            .runtime = runtime,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up UI components
        self.chat_editor.widget.vtable.deinit(&self.chat_editor.widget);
        if (self.code_editor) |editor| {
            editor.widget.vtable.deinit(&editor.widget);
        }
        self.font_manager.deinit();
        self.app.deinit();

        // Clean up runtime
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);

        // Clean up chat history
        for (self.chat_history.items) |entry| {
            self.allocator.free(entry.content);
        }
        self.chat_history.deinit();
    }

    pub fn run(self: *Self) !void {
        // Add chat editor to the app
        try self.app.addWidget(&self.chat_editor.widget);

        // Run the phantom app with zsync integration
        try self.app.run();
    }

    /// Handle user input with multi-cursor support for batch operations
    pub fn handleUserInput(self: *Self, input: []const u8) !void {
        if (input.len == 0) return;

        const user_message = try self.allocator.dupe(u8, input);

        // Add user message to history
        try self.chat_history.append(ChatEntry{
            .role = .user,
            .content = user_message,
            .timestamp = std.time.timestamp(),
        });

        // Display user message in chat editor
        const user_text = try std.fmt.allocPrint(self.allocator, "\n👤 You: {s}\n", .{input});
        defer self.allocator.free(user_text);

        try self.chat_editor.insertText(user_text);

        // Start async AI response
        try self.streamAIResponse(input);
    }

    /// Stream AI response using TextEditor's efficient rope buffer
    fn streamAIResponse(self: *Self, input: []const u8) !void {
        const ai_response = try std.fmt.allocPrint(
            self.allocator,
            \\🤖 ZEKE: Received "{s}".
            \\
            \\This response demonstrates Phantom v0.5.0 features:
            \\• TextEditor with rope data structure for efficiency
            \\• Multi-cursor support for batch code modifications
            \\• Unicode-aware text width calculation
            \\• Programming ligatures: == => -> != >= <=
            \\
            \\Try code snippets with ligatures!
        ,
            .{input},
        );
        defer self.allocator.free(ai_response);

        // Stream the response in chunks using TextEditor's buffer
        const chunk_size = 16;
        var pos: usize = 0;

        while (pos < ai_response.len) {
            const end = @min(pos + chunk_size, ai_response.len);
            const chunk = ai_response[pos..end];

            try self.chat_editor.insertText(chunk);
            pos = end;

            // Small delay for streaming effect
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }

        // Add to chat history
        try self.chat_history.append(ChatEntry{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, ai_response),
            .timestamp = std.time.timestamp(),
        });
    }

    /// Apply batch refactoring using multi-cursor editing
    /// This demonstrates Phantom v0.5.0's multi-cursor capabilities
    pub fn applyBatchRefactoring(
        self: *Self,
        changes: []const CodeChange,
    ) !void {
        if (self.code_editor == null) {
            // Create code editor on demand
            const code_config = phantom.widgets.editor.TextEditor.EditorConfig{
                .show_line_numbers = true,
                .relative_line_numbers = true, // Vim-style
                .enable_ligatures = true,
                .auto_indent = true,
                .tab_size = 4,
            };

            self.code_editor = try phantom.widgets.editor.TextEditor.init(self.allocator, code_config);
        }

        const editor = self.code_editor.?;

        // Clear existing cursors
        editor.cursors.clearRetainingCapacity();

        // Add cursor for each change location
        for (changes) |change| {
            try editor.addCursor(.{
                .line = change.line,
                .col = change.column,
            });
        }

        // Apply AI-generated refactoring at all positions simultaneously
        for (changes) |change| {
            try editor.insertText(change.new_code);
        }
    }

    /// Display file list with Unicode-aware width calculation
    /// Demonstrates Phantom v0.5.0's enhanced Unicode processing
    pub fn displayFileList(self: *Self, files: []const []const u8) !void {
        var max_width: u16 = 0;

        // Calculate max width with Unicode-aware measurement
        for (files) |file| {
            const width = try phantom.unicode.getStringWidth(file);
            max_width = @max(max_width, width);
        }

        // Render aligned file list with Nerd Font icons
        for (files) |file| {
            const width = try phantom.unicode.getStringWidth(file);
            const padding = max_width - width;

            // Get appropriate icon for file type
            const icon = if (self.font_manager.hasNerdFontIcons())
                self.getFileIcon(file)
            else
                "📄";

            const display = try std.fmt.allocPrint(
                self.allocator,
                "{s} {s}{s}",
                .{ icon, file, " " ** padding },
            );
            defer self.allocator.free(display);

            try self.chat_editor.insertText(display);
            try self.chat_editor.insertText("\n");
        }
    }

    /// Get Nerd Font icon for file type
    fn getFileIcon(self: *Self, filename: []const u8) []const u8 {
        if (std.mem.endsWith(u8, filename, ".zig")) return "";
        if (std.mem.endsWith(u8, filename, ".rs")) return "";
        if (std.mem.endsWith(u8, filename, ".js")) return "";
        if (std.mem.endsWith(u8, filename, ".ts")) return "";
        if (std.mem.endsWith(u8, filename, ".py")) return "";
        if (std.mem.endsWith(u8, filename, ".md")) return "";
        return "";
    }

    pub const CodeChange = struct {
        line: usize,
        column: usize,
        old_code: []const u8,
        new_code: []const u8,
    };
};

/// Example: Batch AI refactoring workflow
pub fn exampleBatchRefactoring(app: *EnhancedTuiApp) !void {
    // Example changes from AI code analysis
    const changes = [_]EnhancedTuiApp.CodeChange{
        .{ .line = 10, .column = 5, .old_code = "var", .new_code = "const" },
        .{ .line = 15, .column = 5, .old_code = "var", .new_code = "const" },
        .{ .line = 22, .column = 5, .old_code = "var", .new_code = "const" },
    };

    // Apply all changes simultaneously with multi-cursor
    try app.applyBatchRefactoring(&changes);
}

/// Example: Display watched files with Unicode support
pub fn exampleFileDisplay(app: *EnhancedTuiApp) !void {
    const files = [_][]const u8{
        "src/main.zig",
        "src/providers/claude.zig",
        "src/api/客户端.zig", // Unicode filename
        "docs/README.md",
        "build.zig",
    };

    try app.displayFileList(&files);
}
