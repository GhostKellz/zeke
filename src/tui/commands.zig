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
                \\Context commands:
                \\  /context add <path>    - Add file/dir to context
                \\  /context remove <path> - Remove from context
                \\  /context list          - List context items
                \\  /context clear         - Clear all context
                \\  /context stats         - Show token usage stats
                \\
                \\Git commands:
                \\  /git status            - Show git status
                \\  /git diff [file]       - Show git diff
                \\  /git commit [msg]      - Create commit (AI-generated if no msg)
                \\  /git add <file>        - Stage file
                \\  /git branch            - Show current branch
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

        // /git command
        if (std.mem.eql(u8, self.name, "git")) {
            var args_iter = std.mem.splitScalar(u8, self.args, ' ');
            const subcommand = args_iter.next() orelse {
                return try allocator.dupe(u8, "Usage: /git <status|diff|commit|add|branch> [args]");
            };

            if (std.mem.eql(u8, subcommand, "status")) {
                const files = session.git_ops.getStatus() catch |err| {
                    return try std.fmt.allocPrint(allocator, "Git status failed: {}", .{err});
                };
                defer {
                    for (files) |*file| {
                        file.deinit(allocator);
                    }
                    allocator.free(files);
                }

                if (files.len == 0) {
                    return try allocator.dupe(u8, "No changes");
                }

                var result = std.array_list.AlignedManaged(u8, null).init(allocator);
                defer result.deinit();

                try result.appendSlice("Git Status:\n");
                for (files) |file| {
                    const status_str = switch (file.status) {
                        .modified => "M",
                        .added => "A",
                        .deleted => "D",
                        .renamed => "R",
                        .untracked => "?",
                        .staged => "S",
                    };
                    const line = try std.fmt.allocPrint(allocator, "{s} {s}\n", .{status_str, file.path});
                    defer allocator.free(line);
                    try result.appendSlice(line);
                }

                return try result.toOwnedSlice();
            } else if (std.mem.eql(u8, subcommand, "diff")) {
                const file_path = args_iter.rest();
                const file_arg = if (file_path.len > 0) file_path else null;

                const diff = session.git_ops.getDiff(file_arg) catch |err| {
                    return try std.fmt.allocPrint(allocator, "Git diff failed: {}", .{err});
                };

                if (diff.len == 0) {
                    allocator.free(diff);
                    return try allocator.dupe(u8, "No changes to show");
                }

                return diff;
            } else if (std.mem.eql(u8, subcommand, "add")) {
                const file_path = args_iter.rest();
                if (file_path.len == 0) {
                    return try allocator.dupe(u8, "Usage: /git add <file_path>");
                }

                session.git_ops.addFile(file_path) catch |err| {
                    return try std.fmt.allocPrint(allocator, "Git add failed: {}", .{err});
                };

                return try std.fmt.allocPrint(allocator, "Staged: {s}", .{file_path});
            } else if (std.mem.eql(u8, subcommand, "commit")) {
                const message = args_iter.rest();

                const commit_msg = if (message.len > 0)
                    message
                else
                    "Auto-commit"; // TODO: Generate AI message based on diff

                session.git_ops.commit(commit_msg) catch |err| {
                    return try std.fmt.allocPrint(allocator, "Git commit failed: {}", .{err});
                };

                return try std.fmt.allocPrint(allocator, "Committed: {s}", .{commit_msg});
            } else if (std.mem.eql(u8, subcommand, "branch")) {
                const branch = session.git_ops.getCurrentBranch() catch |err| {
                    return try std.fmt.allocPrint(allocator, "Failed to get branch: {}", .{err});
                };
                return branch;
            } else {
                return try std.fmt.allocPrint(allocator, "Unknown git subcommand: {s}", .{subcommand});
            }
        }

        // /context command
        if (std.mem.eql(u8, self.name, "context")) {
            var args_iter = std.mem.splitScalar(u8, self.args, ' ');
            const subcommand = args_iter.next() orelse {
                return try allocator.dupe(u8, "Usage: /context <add|remove|list|clear|stats> [args]");
            };

            if (std.mem.eql(u8, subcommand, "add")) {
                const path = args_iter.rest();
                if (path.len == 0) {
                    return try allocator.dupe(u8, "Usage: /context add <file_or_directory_path>");
                }

                // Check if it's a directory
                const stat = std.fs.cwd().statFile(path) catch |err| {
                    return try std.fmt.allocPrint(allocator, "Error: Could not access '{s}': {}", .{path, err});
                };

                if (stat.kind == .directory) {
                    session.context_manager.addDirectory(path, 3) catch |err| {
                        return try std.fmt.allocPrint(allocator, "Error adding directory: {}", .{err});
                    };
                    return try std.fmt.allocPrint(allocator, "Added directory to context: {s}", .{path});
                } else {
                    session.context_manager.addFile(path) catch |err| {
                        return try std.fmt.allocPrint(allocator, "Error adding file: {}", .{err});
                    };
                    return try std.fmt.allocPrint(allocator, "Added file to context: {s}", .{path});
                }
            } else if (std.mem.eql(u8, subcommand, "remove")) {
                const path = args_iter.rest();
                if (path.len == 0) {
                    return try allocator.dupe(u8, "Usage: /context remove <path>");
                }

                session.context_manager.remove(path) catch |err| {
                    return try std.fmt.allocPrint(allocator, "Error removing from context: {}", .{err});
                };
                return try std.fmt.allocPrint(allocator, "Removed from context: {s}", .{path});
            } else if (std.mem.eql(u8, subcommand, "list")) {
                const items = session.context_manager.list();
                if (items.len == 0) {
                    return try allocator.dupe(u8, "No items in context");
                }

                var result = std.array_list.AlignedManaged(u8, null).init(allocator);
                defer result.deinit();

                try result.appendSlice("Context Items:\n");
                for (items, 0..) |item, i| {
                    const type_str = switch (item.type) {
                        .file => "File",
                        .directory => "Dir",
                        .text => "Text",
                        .url => "URL",
                    };
                    const line = try std.fmt.allocPrint(
                        allocator,
                        "[{d}] {s}: {s} ({d} tokens)\n",
                        .{i + 1, type_str, item.path, item.token_count},
                    );
                    defer allocator.free(line);
                    try result.appendSlice(line);
                }

                return try result.toOwnedSlice();
            } else if (std.mem.eql(u8, subcommand, "clear")) {
                session.context_manager.clear();
                return try allocator.dupe(u8, "Context cleared");
            } else if (std.mem.eql(u8, subcommand, "stats")) {
                const stats = session.context_manager.getStats();
                return try std.fmt.allocPrint(
                    allocator,
                    "Context Stats:\n  Items: {d}\n  Tokens: {d} / {d}\n  Usage: {d:.1}%",
                    .{stats.items, stats.tokens, stats.max_tokens, stats.usage_percent},
                );
            } else {
                return try std.fmt.allocPrint(allocator, "Unknown context subcommand: {s}", .{subcommand});
            }
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
