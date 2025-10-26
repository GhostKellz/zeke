const std = @import("std");
const phantom = @import("phantom");
const zsync = @import("zsync");

/// Enhanced TUI with Phantom v0.6.3 features
/// Uses Container, Stack, Tabs, and new event loop flexibility
pub const EnhancedTuiApp = struct {
    allocator: std.mem.Allocator,
    zeke_instance: ?*anyopaque,
    app: phantom.App,

    // Layout system using v0.6.3 widgets
    main_container: *phantom.widgets.container.Container,
    tabs: *phantom.widgets.tabs.Tabs,
    stack: *phantom.widgets.stack.Stack,

    // UI Components
    chat_view: *ChatView,
    file_editor_view: *FileEditorView,
    tools_view: *ToolsView,
    settings_view: *SettingsView,

    // State
    active_tab: usize = 0,
    runtime: *zsync.Runtime,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, zeke_instance: ?*anyopaque) !Self {
        // Initialize zsync runtime with optimal settings
        const runtime = try allocator.create(zsync.Runtime);
        runtime.* = try zsync.Runtime.init(allocator, .{
            .execution_model = .auto,
        });

        // Initialize phantom app with v0.6.3 event loop flexibility
        const app = try phantom.App.init(allocator, .{
            .title = "⚡ ZEKE - Next-Gen AI Dev Companion",
            .tick_rate_ms = 50,
            .mouse_enabled = true,
            .add_default_handler = true, // v0.6.3: Enable default Escape/Ctrl+C quit
        });

        // Create main container (v0.6.1)
        const main_container = try phantom.widgets.container.Container.init(allocator, .{
            .layout = .vertical,
            .gap = 1,
            .padding = .{ .horizontal = 2, .vertical = 1 },
        });

        // Create tabs widget (v0.6.1) for multi-view interface
        const tabs = try phantom.widgets.tabs.Tabs.init(allocator, .{
            .tab_position = .top,
            .closeable = false,
        });

        // Add tab views
        try tabs.addTab("💬 Chat", null);
        try tabs.addTab("📝 Editor", null);
        try tabs.addTab("🛠️ Tools", null);
        try tabs.addTab("⚙️ Settings", null);

        // Create stack widget (v0.6.1) for modal overlays
        const stack = try phantom.widgets.stack.Stack.init(allocator);

        // Create view components
        const chat_view = try ChatView.init(allocator);
        const file_editor_view = try FileEditorView.init(allocator);
        const tools_view = try ToolsView.init(allocator);
        const settings_view = try SettingsView.init(allocator);

        return Self{
            .allocator = allocator,
            .zeke_instance = zeke_instance,
            .app = app,
            .main_container = main_container,
            .tabs = tabs,
            .stack = stack,
            .chat_view = chat_view,
            .file_editor_view = file_editor_view,
            .tools_view = tools_view,
            .settings_view = settings_view,
            .runtime = runtime,
        };
    }

    pub fn deinit(self: *Self) void {
        self.chat_view.deinit();
        self.file_editor_view.deinit();
        self.tools_view.deinit();
        self.settings_view.deinit();

        self.stack.widget.deinit();
        self.tabs.widget.deinit();
        self.main_container.widget.deinit();

        self.app.deinit();
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
    }

    pub fn run(self: *Self) !void {
        // Set up event handlers using v0.6.3 event loop
        try self.app.event_loop.addHandler(self.handleEvent);

        // Add widgets to container hierarchy
        try self.main_container.addChild(&self.tabs.widget);

        // Set active tab content
        try self.updateActiveTab();

        // Run the app
        try self.app.run();
    }

    fn handleEvent(self: *Self, event: phantom.Event) bool {
        // Handle tab switching
        if (event == .key) {
            switch (event.key) {
                .tab => {
                    self.active_tab = (self.active_tab + 1) % 4;
                    self.tabs.setActiveTab(self.active_tab) catch {};
                    self.updateActiveTab() catch {};
                    return true;
                },
                .char => |c| {
                    // Ctrl+1/2/3/4 for direct tab access
                    if (c >= '1' and c <= '4') {
                        const tab_idx = @as(usize, c - '1');
                        self.active_tab = tab_idx;
                        self.tabs.setActiveTab(tab_idx) catch {};
                        self.updateActiveTab() catch {};
                        return true;
                    }
                },
                else => {},
            }
        }

        // Delegate to active view
        return switch (self.active_tab) {
            0 => self.chat_view.handleEvent(event),
            1 => self.file_editor_view.handleEvent(event),
            2 => self.tools_view.handleEvent(event),
            3 => self.settings_view.handleEvent(event),
            else => false,
        };
    }

    fn updateActiveTab(self: *Self) !void {
        // Update tab content based on active tab
        const content_widget = switch (self.active_tab) {
            0 => &self.chat_view.widget,
            1 => &self.file_editor_view.widget,
            2 => &self.tools_view.widget,
            3 => &self.settings_view.widget,
            else => unreachable,
        };

        try self.tabs.setContent(self.active_tab, content_widget);
    }

    /// Show modal dialog using Stack widget
    pub fn showModal(self: *Self, modal: *phantom.Widget) !void {
        try self.stack.addLayer(modal, .{ .modal = true });
        try self.stack.bringToFront(modal);
    }

    /// Hide modal dialog
    pub fn hideModal(self: *Self, modal: *phantom.Widget) void {
        self.stack.removeLayer(modal) catch {};
    }
};

/// Chat View - AI conversation interface
const ChatView = struct {
    allocator: std.mem.Allocator,
    widget: phantom.Widget,
    container: *phantom.widgets.container.Container,
    streaming_text: *phantom.widgets.StreamingText,
    input_field: *phantom.widgets.Input,
    chat_history: std.ArrayList(ChatMessage),

    fn init(allocator: std.mem.Allocator) !*ChatView {
        const self = try allocator.create(ChatView);

        // Create layout container
        const container = try phantom.widgets.container.Container.init(allocator, .{
            .layout = .vertical,
            .gap = 1,
        });

        // Create streaming text widget for AI responses
        const streaming_text = try phantom.widgets.StreamingText.init(allocator);
        streaming_text.setTypingSpeed(30);
        streaming_text.setAutoScroll(true);

        // Create input field
        const input_field = try phantom.widgets.Input.init(allocator);
        try input_field.setPlaceholder("Type your message...");

        // Add widgets to container
        try container.addChild(&streaming_text.widget);
        try container.addChild(&input_field.widget);

        self.* = .{
            .allocator = allocator,
            .widget = container.widget,
            .container = container,
            .streaming_text = streaming_text,
            .input_field = input_field,
            .chat_history = std.ArrayList(ChatMessage).init(allocator),
        };

        return self;
    }

    fn deinit(self: *ChatView) void {
        for (self.chat_history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.chat_history.deinit();

        self.streaming_text.widget.deinit();
        self.input_field.widget.deinit();
        self.container.widget.deinit();

        self.allocator.destroy(self);
    }

    fn handleEvent(self: *ChatView, event: phantom.Event) bool {
        _ = self;
        _ = event;
        return false;
    }
};

/// File Editor View - Multi-file editing with tabs
const FileEditorView = struct {
    allocator: std.mem.Allocator,
    widget: phantom.Widget,
    container: *phantom.widgets.container.Container,
    file_tabs: *phantom.widgets.tabs.Tabs,
    editor: *phantom.widgets.textarea.TextArea,
    open_files: std.ArrayList(OpenFile),

    fn init(allocator: std.mem.Allocator) !*FileEditorView {
        const self = try allocator.create(FileEditorView);

        const container = try phantom.widgets.container.Container.init(allocator, .{
            .layout = .vertical,
        });

        // File tabs for multi-file editing
        const file_tabs = try phantom.widgets.tabs.Tabs.init(allocator, .{
            .tab_position = .top,
            .closeable = true,
        });

        // Text editor
        const editor = try phantom.widgets.textarea.TextArea.init(allocator);
        editor.setLineNumbers(true);
        editor.setSyntaxHighlighting(true);

        try container.addChild(&file_tabs.widget);
        try container.addChild(&editor.widget);

        self.* = .{
            .allocator = allocator,
            .widget = container.widget,
            .container = container,
            .file_tabs = file_tabs,
            .editor = editor,
            .open_files = std.ArrayList(OpenFile).init(allocator),
        };

        return self;
    }

    fn deinit(self: *FileEditorView) void {
        for (self.open_files.items) |*file| {
            file.deinit(self.allocator);
        }
        self.open_files.deinit();

        self.editor.widget.deinit();
        self.file_tabs.widget.deinit();
        self.container.widget.deinit();

        self.allocator.destroy(self);
    }

    fn handleEvent(self: *FileEditorView, event: phantom.Event) bool {
        _ = self;
        _ = event;
        return false;
    }
};

/// Tools View - Tool registry and execution
const ToolsView = struct {
    allocator: std.mem.Allocator,
    widget: phantom.Widget,
    container: *phantom.widgets.container.Container,
    tool_list: *phantom.widgets.list_view.ListView,
    tool_output: *phantom.widgets.Text,

    fn init(allocator: std.mem.Allocator) !*ToolsView {
        const self = try allocator.create(ToolsView);

        const container = try phantom.widgets.container.Container.init(allocator, .{
            .layout = .horizontal,
            .gap = 2,
        });

        // Tool list
        const tool_list = try phantom.widgets.list_view.ListView.init(allocator);

        // Tool output
        const tool_output = try phantom.widgets.Text.init(allocator, "Tool output will appear here");

        try container.addChild(&tool_list.widget);
        try container.addChild(&tool_output.widget);

        self.* = .{
            .allocator = allocator,
            .widget = container.widget,
            .container = container,
            .tool_list = tool_list,
            .tool_output = tool_output,
        };

        return self;
    }

    fn deinit(self: *ToolsView) void {
        self.tool_list.widget.deinit();
        self.tool_output.widget.deinit();
        self.container.widget.deinit();

        self.allocator.destroy(self);
    }

    fn handleEvent(self: *ToolsView, event: phantom.Event) bool {
        _ = self;
        _ = event;
        return false;
    }
};

/// Settings View - Configuration and preferences
const SettingsView = struct {
    allocator: std.mem.Allocator,
    widget: phantom.Widget,
    container: *phantom.widgets.container.Container,
    settings_list: *phantom.widgets.List,

    fn init(allocator: std.mem.Allocator) !*SettingsView {
        const self = try allocator.create(SettingsView);

        const container = try phantom.widgets.container.Container.init(allocator, .{
            .layout = .vertical,
            .gap = 1,
        });

        const settings_list = try phantom.widgets.List.init(allocator);
        try settings_list.addItemText("🎨 Theme");
        try settings_list.addItemText("🤖 Default Model");
        try settings_list.addItemText("⚡ Performance");
        try settings_list.addItemText("🔐 API Keys");

        try container.addChild(&settings_list.widget);

        self.* = .{
            .allocator = allocator,
            .widget = container.widget,
            .container = container,
            .settings_list = settings_list,
        };

        return self;
    }

    fn deinit(self: *SettingsView) void {
        self.settings_list.widget.deinit();
        self.container.widget.deinit();

        self.allocator.destroy(self);
    }

    fn handleEvent(self: *SettingsView, event: phantom.Event) bool {
        _ = self;
        _ = event;
        return false;
    }
};

// ===== Helper Types =====

const ChatMessage = struct {
    role: enum { user, assistant },
    content: []const u8,
    timestamp: i64,

    fn deinit(self: *ChatMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

const OpenFile = struct {
    path: []const u8,
    content: []const u8,
    modified: bool = false,

    fn deinit(self: *OpenFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
    }
};
