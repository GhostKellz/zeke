# 👻 Phantom TUI Integration Guide

This guide helps you integrate Phantom TUI into your Zig projects, specifically designed for terminal applications like ZEKE (AI assistant) and other interactive CLI tools.

## 🚀 Quick Start

### 1. Add Phantom as a Dependency

#### Method 1: Using `zig fetch` (Recommended)
```bash
zig fetch --save https://github.com/ghostkellz/phantom
```

#### Method 2: Manual `build.zig.zon` Setup
```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .phantom = .{
            .url = "https://github.com/ghostkellz/phantom/archive/main.tar.gz",
            // Update hash when fetching
            .hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        },
    },
}
```

### 2. Configure Your `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get phantom dependency
    const phantom_dep = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
    });
    const phantom_mod = phantom_dep.module("phantom");

    // Your executable
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add phantom module
    exe.root_module.addImport("phantom", phantom_mod);

    b.installArtifact(exe);
}
```

### 3. Basic Integration Example

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Phantom runtime
    phantom.runtime.initRuntime(allocator);
    defer phantom.runtime.deinitRuntime();

    // Create application
    var app = try phantom.App.init(allocator, phantom.AppConfig{
        .title = "My AI Assistant",
        .tick_rate_ms = 16, // 60 FPS
        .mouse_enabled = true,
    });
    defer app.deinit();

    // Add some widgets
    const title = try phantom.widgets.Text.initWithStyle(
        allocator, 
        "🤖 AI Assistant", 
        phantom.Style.withFg(phantom.Color.bright_cyan).withBold()
    );
    try app.addWidget(&title.widget);

    // Run the application
    try app.run();
}
```

## 🧩 Available Widgets

### Core Widgets
- **Text**: Styled text display with alignment
- **List**: Selectable, scrollable item lists
- **Block**: Container with borders and styling
- **Container**: Layout container for other widgets

### Interactive Widgets
- **Button**: Clickable buttons with hover states
- **Input**: Single-line text input fields
- **TextArea**: Multi-line text editing with scrolling

### Data Display Widgets
- **Table**: Column-based data display with sorting
- **ProgressBar**: Visual progress indicators

### Advanced Widgets
- **StreamingText**: Real-time text streaming (perfect for AI responses)
- **CodeBlock**: Syntax-highlighted code display

## 💡 Common Use Cases

### 1. AI Chat Interface (ZEKE Style)

```zig
const std = @import("std");
const phantom = @import("phantom");

pub fn createChatInterface(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "ZEKE AI Assistant",
        .tick_rate_ms = 30,
        .mouse_enabled = true,
    });

    // Chat history (StreamingText for AI responses)
    const chat_history = try phantom.widgets.StreamingText.init(allocator);
    chat_history.setAutoScroll(true);
    chat_history.setTypingSpeed(50); // Characters per second
    try app.addWidget(&chat_history.widget);

    // Input field for user messages
    const input_field = try phantom.widgets.Input.init(allocator);
    try input_field.setPlaceholder("Type your message...");
    input_field.setOnSubmit(onUserMessage);
    try app.addWidget(&input_field.widget);

    // Send button
    const send_button = try phantom.widgets.Button.init(allocator, "Send");
    send_button.setOnClick(onSendClick);
    try app.addWidget(&send_button.widget);

    return app;
}

fn onUserMessage(input: *phantom.widgets.Input, text: []const u8) void {
    // Handle user message submission
    std.debug.print("User: {s}\n", .{text});
    // Add to chat history, send to AI, etc.
}

fn onSendClick(button: *phantom.widgets.Button) void {
    // Handle send button click
    _ = button;
    // Trigger message send
}
```

### 2. Code Review Tool

```zig
pub fn createCodeReviewInterface(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "Code Review Tool",
        .tick_rate_ms = 16,
    });

    // Code display
    const code_sample = try std.fs.cwd().readFileAlloc(allocator, "src/main.zig", 1024 * 1024);
    const code_block = try phantom.widgets.CodeBlock.init(allocator, code_sample, .zig);
    code_block.setShowLineNumbers(true);
    try app.addWidget(&code_block.widget);

    // Review comments
    const comments = try phantom.widgets.TextArea.init(allocator);
    try comments.setPlaceholder("Enter your review comments...");
    comments.setShowLineNumbers(true);
    try app.addWidget(&comments.widget);

    return app;
}
```

### 3. Data Dashboard

```zig
pub fn createDashboard(allocator: std.mem.Allocator) !*phantom.App {
    var app = try phantom.App.init(allocator, .{
        .title = "Data Dashboard",
        .tick_rate_ms = 100, // Slower updates for data
    });

    // Metrics table
    const metrics_table = try phantom.widgets.Table.init(allocator);
    try metrics_table.addColumn(.{ .title = "Metric", .width = 20 });
    try metrics_table.addColumn(.{ .title = "Value", .width = 15 });
    try metrics_table.addColumn(.{ .title = "Status", .width = 10 });
    
    try metrics_table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "CPU Usage", "45%", "Normal" }));
    try metrics_table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "Memory", "2.1GB", "High" }));
    try metrics_table.addRow(phantom.widgets.Table.Row.init(&[_][]const u8{ "Network", "1.2MB/s", "Active" }));
    
    try app.addWidget(&metrics_table.widget);

    // Progress indicators
    const cpu_progress = try phantom.widgets.ProgressBar.init(allocator);
    try cpu_progress.setLabel("CPU");
    cpu_progress.setValue(45.0);
    try app.addWidget(&cpu_progress.widget);

    const memory_progress = try phantom.widgets.ProgressBar.init(allocator);
    try memory_progress.setLabel("Memory");
    memory_progress.setValue(75.0);
    try app.addWidget(&memory_progress.widget);

    return app;
}
```

## 🎨 Styling and Themes

### Colors
```zig
const style = phantom.Style{
    .fg = phantom.Color.bright_cyan,
    .bg = phantom.Color.black,
    .bold = true,
    .italic = false,
    .underline = true,
};

// Or use builder pattern
const style2 = phantom.Style.default()
    .withFg(phantom.Color.red)
    .withBg(phantom.Color.white)
    .withBold();
```

### Available Colors
- Basic: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`
- Bright: `bright_black`, `bright_red`, `bright_green`, etc.
- Custom: `Color.rgb(r, g, b)` or `Color.indexed(index)`

## 🔧 Advanced Features

### Event Handling
```zig
// Custom event handler
fn myEventHandler(event: phantom.Event) !bool {
    switch (event) {
        .key => |key| {
            switch (key) {
                .ctrl_c => {
                    std.debug.print("Graceful shutdown\n", .{});
                    return true; // Exit
                },
                .f1 => {
                    showHelp();
                    return true;
                },
                else => {},
            }
        },
        .mouse => |mouse| {
            handleMouseEvent(mouse);
        },
        else => {},
    }
    return false;
}

// Add to event loop
try app.event_loop.addHandler(myEventHandler);
```

### Layout Management
```zig
// Use layout constraints for responsive design
const layout = phantom.layout.Layout.init(allocator);
defer layout.deinit();

// Split screen horizontally
const areas = layout.split(.horizontal, &[_]phantom.layout.Constraint{
    .{ .percentage = 30 }, // Sidebar
    .{ .percentage = 70 }, // Main content
});

// Split main content vertically
const main_areas = layout.split(.vertical, &[_]phantom.layout.Constraint{
    .{ .min = 3 },         // Header
    .{ .percentage = 80 }, // Content
    .{ .min = 3 },         // Footer
});
```

## 🧪 Testing

### Widget Testing
```zig
const std = @import("std");
const phantom = @import("phantom");

test "button interaction" {
    const allocator = std.testing.allocator;
    
    const button = try phantom.widgets.Button.init(allocator, "Test");
    defer button.widget.deinit();
    
    // Test button state
    try std.testing.expect(!button.is_pressed);
    
    // Simulate click
    button.click();
    
    // Add assertions for expected behavior
}
```

### Integration Testing
```zig
test "full app integration" {
    const allocator = std.testing.allocator;
    
    var app = try phantom.App.init(allocator, .{});
    defer app.deinit();
    
    // Add widgets
    const text = try phantom.widgets.Text.init(allocator, "Test");
    try app.addWidget(&text.widget);
    
    // Test widget was added
    try std.testing.expect(app.widgets.items.len == 1);
}
```

## 🚀 Performance Tips

### 1. Optimize Render Frequency
```zig
// For data dashboards - slower updates
var app = try phantom.App.init(allocator, .{
    .tick_rate_ms = 100, // 10 FPS
});

// For interactive apps - smooth updates
var app = try phantom.App.init(allocator, .{
    .tick_rate_ms = 16, // 60 FPS
});
```

### 2. Efficient Text Updates
```zig
// Use StreamingText for incremental updates
const streaming = try phantom.widgets.StreamingText.init(allocator);
streaming.setTypingSpeed(100); // Adjust for performance

// Batch text updates
try streaming.addChunk("First part ");
try streaming.addChunk("Second part ");
try streaming.addChunk("Final part");
```

### 3. Memory Management
```zig
// Always defer cleanup
var app = try phantom.App.init(allocator, .{});
defer app.deinit(); // Cleans up all widgets

// Use arena allocator for temporary widgets
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp_allocator = arena.allocator();
```

## 🔍 Debugging

### Enable Debug Mode
```zig
const app = try phantom.App.init(allocator, .{
    .title = "Debug App",
    .tick_rate_ms = 16,
    .debug_mode = true, // Enable debugging
});
```

### Common Issues

1. **Widget Not Displaying**: Check if `addWidget()` was called
2. **Events Not Working**: Verify event handlers are registered
3. **Performance Issues**: Check tick rate and widget complexity
4. **Memory Leaks**: Ensure all widgets are properly deinitialized

## 📚 Examples

Check out the comprehensive examples in the `examples/` directory:

- `basic_demo.zig` - Simple text and list widgets
- `advanced_demo.zig` - Advanced features showcase
- `comprehensive_demo.zig` - All widgets demonstration

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Add tests for new features
4. Submit a pull request

## 📜 License

MIT License - See LICENSE file for details

## 🆘 Support

- GitHub Issues: https://github.com/ghostkellz/phantom/issues
- Documentation: https://github.com/ghostkellz/phantom/wiki
- Examples: https://github.com/ghostkellz/phantom/tree/main/examples

---

**Ready to build amazing TUI applications with Phantom? Start with the quick start guide above and check out the examples!** 👻✨