const std = @import("std");
const phantom = @import("phantom");
const zsync = @import("zsync");

pub const TuiApp = struct {
    allocator: std.mem.Allocator,
    zeke_instance: ?*anyopaque, // Use anyopaque to avoid circular dependency
    app: phantom.App,
    
    // UI Components
    streaming_text: *phantom.widgets.StreamingText,
    input_field: *phantom.widgets.Input,
    model_selector: *phantom.widgets.List,
    
    // State
    chat_history: std.ArrayList(ChatEntry),
    current_input: std.ArrayList(u8),
    selected_model: []const u8,
    
    // Async runtime
    runtime: *zsync.Runtime,
    
    const Self = @This();
    
    const ChatEntry = struct {
        role: enum { user, assistant },
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
            .title = "⚡ ZEKE - AI Dev Companion",
            .tick_rate_ms = 50,
            .mouse_enabled = true,
        });
        
        // Create UI components
        const streaming_text = try phantom.widgets.StreamingText.init(allocator);
        const input_field = try phantom.widgets.Input.init(allocator);
        const model_selector = try phantom.widgets.List.init(allocator);
        
        // Configure streaming text
        streaming_text.setTypingSpeed(50);
        streaming_text.setAutoScroll(true);
        streaming_text.setShowCursor(true);
        streaming_text.setTextStyle(phantom.Style.default().withFg(phantom.Color.white));
        streaming_text.setStreamingStyle(phantom.Style.default().withFg(phantom.Color.cyan));
        
        // Configure input field
        try input_field.setPlaceholder("Type your message... (Enter to send, Tab for models)");
        input_field.setMaxLength(512);
        
        // Configure model selector
        try model_selector.addItemText("🤖 gpt-4");
        try model_selector.addItemText("🤖 claude-3-5-sonnet-20241022");
        try model_selector.addItemText("🤖 gpt-3.5-turbo");
        try model_selector.addItemText("🤖 copilot-codex");
        
        model_selector.setSelectedStyle(
            phantom.Style.default().withFg(phantom.Color.white).withBg(phantom.Color.bright_blue)
        );
        
        return Self{
            .allocator = allocator,
            .zeke_instance = zeke_instance,
            .app = app,
            .streaming_text = streaming_text,
            .input_field = input_field,
            .model_selector = model_selector,
            .chat_history = std.ArrayList(ChatEntry){},
            .current_input = std.ArrayList(u8){},
            .selected_model = "gpt-4",
            .runtime = runtime,
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up UI components
        self.streaming_text.widget.deinit();
        self.input_field.widget.deinit();
        self.model_selector.widget.deinit();
        self.app.deinit();
        
        // Clean up runtime
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
        
        // Clean up chat history
        for (self.chat_history.items) |entry| {
            self.allocator.free(entry.content);
        }
        self.chat_history.deinit(self.allocator);
        self.current_input.deinit(self.allocator);
    }
    
    pub fn run(self: *Self) !void {
        // Set global reference for event handling
        current_tui_app = self;
        defer current_tui_app = null;
        
        // Add widgets to the app
        try self.app.addWidget(&self.streaming_text.widget);
        try self.app.addWidget(&self.input_field.widget);
        
        // Set up event handlers  
        self.input_field.setOnSubmit(handleInputSubmitWrapper);
        
        // Show welcome message
        try self.showWelcomeMessage();
        
        // Run the phantom app with zsync integration
        try self.app.run();
    }
    
    // Global reference to current TUI app instance for event handling
    var current_tui_app: ?*TuiApp = null;
    
    // Wrapper function for input submission
    fn handleInputSubmitWrapper(input_widget: *phantom.widgets.Input, text: []const u8) void {
        if (current_tui_app) |app| {
            app.handleUserInput(text) catch |err| {
                std.log.err("Error handling input: {}", .{err});
            };
        } else {
            std.log.info("Input submitted: {s}", .{text});
        }
        input_widget.clear();
    }
    
    fn handleUserInput(self: *Self, input: []const u8) !void {
        if (input.len == 0) return;
        
        const user_message = try self.allocator.dupe(u8, input);
        
        // Add user message to history
        try self.chat_history.append(self.allocator, ChatEntry{
            .role = .user,
            .content = user_message,
            .timestamp = std.time.timestamp(),
        });
        
        // Display user message in streaming text
        const user_text = try std.fmt.allocPrint(self.allocator, "\n👤 You: {s}\n", .{input});
        defer self.allocator.free(user_text);
        
        const current_text = self.streaming_text.getText();
        const new_text = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ current_text, user_text });
        defer self.allocator.free(new_text);
        
        try self.streaming_text.setText(new_text);
        
        // Start async AI response with streaming
        try self.streamAIResponse(input);
    }
    
    fn streamAIResponse(self: *Self, input: []const u8) !void {
        // Start streaming
        self.streaming_text.startStreaming();
        
        // Simulate AI response with streaming
        const ai_response = try std.fmt.allocPrint(self.allocator, 
            "🤖 ZEKE: I received your message: \"{s}\". This is now powered by phantom TUI v0.3.3 with zsync integration! The streaming text widget is working beautifully with true async support.", 
            .{input});
        defer self.allocator.free(ai_response);
        
        // Stream the response in chunks
        const chunk_size = 8;
        var pos: usize = 0;
        
        while (pos < ai_response.len) {
            const end = @min(pos + chunk_size, ai_response.len);
            const chunk = ai_response[pos..end];
            
            try self.streaming_text.addChunk(chunk);
            pos = end;
            
            // Small delay for streaming effect
            std.Thread.sleep(80 * std.time.ns_per_ms);
        }
        
        // Add to chat history
        try self.chat_history.append(self.allocator, ChatEntry{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, ai_response),
            .timestamp = std.time.timestamp(),
        });
        
        // Stop streaming
        self.streaming_text.stopStreaming();
    }
    
    fn showWelcomeMessage(self: *Self) !void {
        const welcome_text = "🤖 ZEKE: Welcome to ZEKE! I'm your AI coding companion powered by phantom TUI v0.3.3 with zsync integration.\n\n✨ Features:\n• Real-time streaming responses\n• Beautiful terminal interface\n• Async runtime with zsync\n• 256-color & true color support\n\nType your messages below and press Enter to send!";
        
        // Set the initial welcome text in streaming text widget
        try self.streaming_text.setText(welcome_text);
        
        const welcome_entry = ChatEntry{
            .role = .assistant,
            .content = try self.allocator.dupe(u8, welcome_text),
            .timestamp = std.time.timestamp(),
        };
        
        try self.chat_history.append(self.allocator, welcome_entry);
    }
    
};