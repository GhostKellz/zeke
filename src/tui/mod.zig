const std = @import("std");
const phantom = @import("phantom");
const zeke = @import("zeke");

pub const TuiApp = struct {
    allocator: std.mem.Allocator,
    zeke_instance: *zeke.Zeke,
    app: phantom.App,
    chat_history: std.ArrayList(ChatEntry),
    current_input: std.ArrayList(u8),
    selected_model: []const u8,
    
    // UI Components
    title_text: phantom.widgets.Text,
    chat_display: phantom.widgets.StreamingText,
    input_field: phantom.widgets.Input,
    model_selector: phantom.widgets.List,
    
    const Self = @This();
    
    const ChatEntry = struct {
        role: enum { user, assistant },
        content: []const u8,
        timestamp: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator, zeke_instance: *zeke.Zeke) !Self {
        // Initialize phantom app
        const app = try phantom.App.init(allocator, .{
            .title = "ZEKE - AI Dev Companion",
            .tick_rate_ms = 16, // 60 FPS
            .mouse_enabled = true,
        });
        
        // Simplified TUI initialization for now
        const title_text = phantom.widgets.Text.init();
        const chat_display = phantom.widgets.Text.init();
        
        // Create input field
        const input_field = try phantom.widgets.Input.init(allocator);
        input_field.setPlaceholder("Type your message...");
        
        // Create model selector
        const model_selector = try phantom.widgets.List.init(allocator);
        const models = [_][]const u8{
            "gpt-4",
            "gpt-3.5-turbo", 
            "claude-3-5-sonnet-20241022",
            "copilot-codex",
        };
        for (models) |model| {
            try model_selector.addItem(model);
        }
        
        return Self{
            .allocator = allocator,
            .zeke_instance = zeke_instance,
            .app = app,
            .chat_history = std.ArrayList(ChatEntry).init(allocator),
            .current_input = std.ArrayList(u8).init(allocator),
            .selected_model = zeke_instance.current_model,
            .title_text = title_text,
            .chat_display = chat_display,
            .input_field = input_field,
            .model_selector = model_selector,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.app.deinit();
        self.title_text.deinit();
        self.chat_display.deinit();
        self.input_field.deinit();
        self.model_selector.deinit();
        
        for (self.chat_history.items) |entry| {
            self.allocator.free(entry.content);
        }
        self.chat_history.deinit();
        self.current_input.deinit();
    }
    
    pub fn run(self: *Self) !void {
        // Add widgets to the app
        try self.app.addWidget(&self.title_text.widget);
        try self.app.addWidget(&self.chat_display.widget);
        try self.app.addWidget(&self.input_field.widget);
        
        // Set up event handlers
        try self.input_field.setOnSubmit(self, handleInputSubmit);
        try self.model_selector.setOnSelect(self, handleModelSelect);
        
        // Show welcome message
        try self.showWelcomeMessage();
        
        // Run the phantom app
        try self.app.run();
    }
    
    // Event handlers
    fn handleInputSubmit(self: *Self, input: []const u8) !void {
        if (input.len == 0) return;
        
        const user_message = try self.allocator.dupe(u8, input);
        
        // Add user message to history
        try self.chat_history.append(ChatEntry{
            .role = .user,
            .content = user_message,
            .timestamp = std.time.timestamp(),
        });
        
        // Clear input field
        try self.input_field.clear();
        
        // Show "thinking" indicator
        try self.showThinkingIndicator();
        
        // Get AI response
        const ai_response = try self.zeke_instance.chat(user_message);
        
        // Stream the AI response
        try self.chat_display.streamText(ai_response);
        
        // Add AI response to history
        try self.chat_history.append(ChatEntry{
            .role = .assistant,
            .content = ai_response,
            .timestamp = std.time.timestamp(),
        });
    }
    
    fn handleModelSelect(self: *Self, selected_model: []const u8) !void {
        try self.zeke_instance.setModel(selected_model);
        self.selected_model = selected_model;
        
        // Update title to show current model
        const title_text = try std.fmt.allocPrint(self.allocator, "⚡ ZEKE - AI Dev Companion (Model: {s})", .{selected_model});
        defer self.allocator.free(title_text);
        
        try self.title_text.setText(title_text);
    }
    
    fn showWelcomeMessage(self: *Self) !void {
        const welcome_text = "Welcome to ZEKE! I'm your AI coding companion. How can I help you today?";
        try self.chat_display.streamText(welcome_text);
        
        const welcome_entry = ChatEntry{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, welcome_text),
            .timestamp = std.time.timestamp(),
        };
        
        try self.chat_history.append(welcome_entry);
    }
    
    fn showThinkingIndicator(self: *Self) !void {
        const thinking_text = "🤔 Thinking...";
        try self.chat_display.streamText(thinking_text);
        
        // Add a small delay to show the thinking indicator
        std.time.sleep(500_000_000); // 0.5 seconds
    }
    
};