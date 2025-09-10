const std = @import("std");
const TuiApp = @import("src/tui/mod.zig").TuiApp;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Creating TUI app...\n", .{});
    
    var tui_app = try TuiApp.init(allocator, null);
    defer tui_app.deinit();
    
    std.debug.print("TUI app created successfully!\n", .{});
    std.debug.print("Chat history initialized with {} items\n", .{tui_app.chat_history.items.len});
    std.debug.print("Selected model: {s}\n", .{tui_app.selected_model});
}