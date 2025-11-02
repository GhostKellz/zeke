const std = @import("std");

/// Command type determines how input is processed
pub const CommandType = enum {
    chat,           // Regular chat message
    slash,          // Slash command (/help, /clear, /model, etc.)
    empty,          // Empty input
};

/// Parsed command with type and data
pub const Command = union(CommandType) {
    chat: []const u8,
    slash: SlashCommand,
    empty: void,

    /// Parse user input into a Command
    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Command {
        const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);

        if (trimmed.len == 0) {
            return Command{ .empty = {} };
        }

        // Check for slash command
        if (trimmed[0] == '/') {
            return Command{ .slash = try SlashCommand.parse(allocator, trimmed[1..]) };
        }

        // Regular chat message - dupe for ownership
        const owned = try allocator.dupe(u8, trimmed);
        return Command{ .chat = owned };
    }

    /// Free any allocated memory
    pub fn deinit(self: Command, allocator: std.mem.Allocator) void {
        switch (self) {
            .chat => |msg| allocator.free(msg),
            .slash => |cmd| cmd.deinit(allocator),
            .empty => {},
        }
    }
};

/// Slash command with name and optional arguments
pub const SlashCommand = struct {
    name: []const u8,
    args: []const u8,

    /// Parse slash command (input without leading '/')
    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !SlashCommand {
        var iter = std.mem.splitScalar(u8, input, ' ');
        const name_raw = iter.next() orelse return error.EmptyCommand;
        const name = try allocator.dupe(u8, name_raw);

        const rest = iter.rest();
        const args = if (rest.len > 0) try allocator.dupe(u8, rest) else "";

        return SlashCommand{
            .name = name,
            .args = args,
        };
    }

    pub fn deinit(self: SlashCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.args.len > 0) {
            allocator.free(self.args);
        }
    }

    /// Execute a slash command and return result message
    pub fn execute(self: SlashCommand, allocator: std.mem.Allocator, session: anytype) ![]const u8 {
        // /help command
        if (std.mem.eql(u8, self.name, "help")) {
            return try allocator.dupe(u8,
                \\Available commands:
                \\  /help              - Show this help message
                \\  /clear             - Clear the screen
                \\  /model [name]      - Switch AI model (or show current)
                \\  /provider [name]   - Switch provider (or show current)
                \\  /thinking          - Toggle thinking mode
                \\  /exit              - Exit TUI
                \\  /history           - Show message history
                \\
                \\Keyboard shortcuts:
                \\  Tab                - Toggle thinking mode
                \\  Ctrl+C / Ctrl+D    - Exit
                \\  Arrow Up/Down      - Navigate history
                \\  Enter              - Send message
            );
        }

        // /clear command
        if (std.mem.eql(u8, self.name, "clear")) {
            // Signal to clear screen (handled by caller)
            return try allocator.dupe(u8, "[CLEAR_SCREEN]");
        }

        // /model command
        if (std.mem.eql(u8, self.name, "model")) {
            if (self.args.len > 0) {
                // Switch model directly if name provided
                try session.switchModel(self.args);
                return try std.fmt.allocPrint(allocator, "Switched to model: {s}", .{self.args});
            } else {
                // Show current model (or open model selector if interactive)
                return try std.fmt.allocPrint(allocator, "Current model: {s}\nTip: Use '/model <name>' to switch", .{session.current_model});
            }
        }

        // /provider command
        if (std.mem.eql(u8, self.name, "provider")) {
            if (self.args.len > 0) {
                // Parse provider[:model] format
                var parts = std.mem.splitScalar(u8, self.args, ':');
                const provider = parts.next() orelse return error.InvalidProvider;
                const model = parts.next();

                if (model) |m| {
                    try session.switchProvider(provider, m);
                    return try std.fmt.allocPrint(allocator, "Switched to {s} with model: {s}", .{ provider, m });
                } else {
                    // Just switch provider, keep current model format
                    try session.switchProvider(provider, session.current_model);
                    return try std.fmt.allocPrint(allocator, "Switched to provider: {s}", .{provider});
                }
            } else {
                // Show current provider
                return try std.fmt.allocPrint(
                    allocator,
                    "Current provider: {s}\nCurrent model: {s}\nTip: Use '/provider <name>' or '/provider <name>:<model>' to switch",
                    .{ session.current_provider, session.current_model },
                );
            }
        }

        // /thinking command
        if (std.mem.eql(u8, self.name, "thinking")) {
            const new_state = !session.thinking_mode;
            const status = if (new_state) "enabled" else "disabled";
            return try std.fmt.allocPrint(allocator, "Thinking mode {s}", .{status});
        }

        // /exit command
        if (std.mem.eql(u8, self.name, "exit") or std.mem.eql(u8, self.name, "quit")) {
            return try allocator.dupe(u8, "[EXIT]");
        }

        // /history command
        if (std.mem.eql(u8, self.name, "history")) {
            var result = std.array_list.AlignedManaged(u8, null).init(allocator);
            defer result.deinit();

            try result.appendSlice("Message History:\n");
            for (session.history.items, 0..) |msg, i| {
                const role = switch (msg.role) {
                    .user => "You",
                    .assistant => "AI",
                    .system => "System",
                };
                const line = try std.fmt.allocPrint(allocator, "[{d}] {s}: {s}\n", .{i + 1, role, msg.content});
                defer allocator.free(line);
                try result.appendSlice(line);
            }

            return try result.toOwnedSlice();
        }

        // Unknown command
        return try std.fmt.allocPrint(allocator, "Unknown command: /{s}\nType /help for available commands", .{self.name});
    }
};

// Tests
test "parse chat message" {
    const allocator = std.testing.allocator;

    const cmd = try Command.parse(allocator, "Hello world");
    defer cmd.deinit(allocator);

    try std.testing.expect(cmd == .chat);
    try std.testing.expectEqualStrings("Hello world", cmd.chat);
}

test "parse slash command" {
    const allocator = std.testing.allocator;

    const cmd = try Command.parse(allocator, "/help");
    defer cmd.deinit(allocator);

    try std.testing.expect(cmd == .slash);
    try std.testing.expectEqualStrings("help", cmd.slash.name);
    try std.testing.expectEqualStrings("", cmd.slash.args);
}

test "parse slash command with args" {
    const allocator = std.testing.allocator;

    const cmd = try Command.parse(allocator, "/model claude-opus-4");
    defer cmd.deinit(allocator);

    try std.testing.expect(cmd == .slash);
    try std.testing.expectEqualStrings("model", cmd.slash.name);
    try std.testing.expectEqualStrings("claude-opus-4", cmd.slash.args);
}

test "parse empty input" {
    const allocator = std.testing.allocator;

    const cmd = try Command.parse(allocator, "   ");
    defer cmd.deinit(allocator);

    try std.testing.expect(cmd == .empty);
}
