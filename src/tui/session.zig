const std = @import("std");
const permissions = @import("permissions.zig");

/// Message role in conversation
pub const MessageRole = enum {
    user,
    assistant,
    system,
};

/// Single message in conversation
pub const Message = struct {
    role: MessageRole,
    content: []const u8,
    timestamp: i64,
    tokens: ?u32 = null,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// Streaming state for AI responses
pub const StreamingState = enum {
    idle,
    thinking,
    streaming,
    waiting_for_permission,
    tool_executing,
    error_state,
};

/// TUI session state
pub const Session = struct {
    allocator: std.mem.Allocator,
    history: std.array_list.AlignedManaged(Message, null),
    thinking_mode: bool,
    current_provider: []const u8,
    current_model: []const u8,
    total_tokens: u32,
    estimated_cost: f32,
    streaming_state: StreamingState,
    streaming_buffer: std.array_list.AlignedManaged(u8, null),
    permission_manager: permissions.PermissionManager,

    pub fn init(allocator: std.mem.Allocator, provider: []const u8, model: []const u8) !Session {
        return Session{
            .allocator = allocator,
            .history = std.array_list.AlignedManaged(Message, null).init(allocator),
            .thinking_mode = false,
            .current_provider = try allocator.dupe(u8, provider),
            .current_model = try allocator.dupe(u8, model),
            .total_tokens = 0,
            .estimated_cost = 0.0,
            .streaming_state = .idle,
            .streaming_buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
            .permission_manager = permissions.PermissionManager.init(allocator),
        };
    }

    pub fn deinit(self: *Session) void {
        // Free all messages
        for (self.history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.history.deinit();

        // Free provider/model strings
        self.allocator.free(self.current_provider);
        self.allocator.free(self.current_model);

        // Free streaming buffer
        self.streaming_buffer.deinit();

        // Free permission manager
        self.permission_manager.deinit();
    }

    /// Add a message to history
    pub fn addMessage(self: *Session, role: MessageRole, content: []const u8) !void {
        const owned_content = try self.allocator.dupe(u8, content);
        const message = Message{
            .role = role,
            .content = owned_content,
            .timestamp = std.time.timestamp(),
            .tokens = null,
        };
        try self.history.append(message);
    }

    /// Start streaming a response
    pub fn startStreaming(self: *Session) !void {
        self.streaming_state = .streaming;
        self.streaming_buffer.clearRetainingCapacity();
    }

    /// Append chunk to streaming buffer
    pub fn appendChunk(self: *Session, chunk: []const u8) !void {
        try self.streaming_buffer.appendSlice(chunk);
    }

    /// Finish streaming and add to history
    pub fn finishStreaming(self: *Session) !void {
        if (self.streaming_buffer.items.len > 0) {
            try self.addMessage(.assistant, self.streaming_buffer.items);
        }
        self.streaming_state = .idle;
        self.streaming_buffer.clearRetainingCapacity();
    }

    /// Cancel streaming
    pub fn cancelStreaming(self: *Session) void {
        self.streaming_state = .idle;
        self.streaming_buffer.clearRetainingCapacity();
    }

    /// Switch provider and model
    pub fn switchProvider(self: *Session, provider: []const u8, model: []const u8) !void {
        // Free old strings
        self.allocator.free(self.current_provider);
        self.allocator.free(self.current_model);

        // Set new values
        self.current_provider = try self.allocator.dupe(u8, provider);
        self.current_model = try self.allocator.dupe(u8, model);
    }

    /// Switch model only (keep current provider)
    pub fn switchModel(self: *Session, model: []const u8) !void {
        // Free old model
        self.allocator.free(self.current_model);

        // Set new model
        self.current_model = try self.allocator.dupe(u8, model);
    }

    /// Toggle thinking mode
    pub fn toggleThinking(self: *Session) void {
        self.thinking_mode = !self.thinking_mode;
    }

    /// Update token count
    pub fn addTokens(self: *Session, tokens: u32) void {
        self.total_tokens += tokens;
        // Simple cost estimation (rough average: $0.01 per 1000 tokens)
        self.estimated_cost = @as(f32, @floatFromInt(self.total_tokens)) / 1000.0 * 0.01;
    }

    /// Get the last N messages for context
    pub fn getRecentMessages(self: *const Session, n: usize) []const Message {
        const count = @min(n, self.history.items.len);
        const start = self.history.items.len - count;
        return self.history.items[start..];
    }

    /// Clear all history
    pub fn clearHistory(self: *Session) void {
        for (self.history.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.history.clearRetainingCapacity();
        self.total_tokens = 0;
        self.estimated_cost = 0.0;
    }
};

// Tests
test "session init and deinit" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "ollama", "llama3.2:3b");
    defer session.deinit();

    try std.testing.expectEqualStrings("ollama", session.current_provider);
    try std.testing.expectEqualStrings("llama3.2:3b", session.current_model);
    try std.testing.expect(session.thinking_mode == false);
}

test "add message" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "ollama", "llama3.2:3b");
    defer session.deinit();

    try session.addMessage(.user, "Hello");
    try session.addMessage(.assistant, "Hi there!");

    try std.testing.expectEqual(@as(usize, 2), session.history.items.len);
    try std.testing.expectEqualStrings("Hello", session.history.items[0].content);
    try std.testing.expectEqualStrings("Hi there!", session.history.items[1].content);
}

test "streaming" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "ollama", "llama3.2:3b");
    defer session.deinit();

    try session.startStreaming();
    try std.testing.expectEqual(StreamingState.streaming, session.streaming_state);

    try session.appendChunk("Hello");
    try session.appendChunk(" ");
    try session.appendChunk("world");

    try session.finishStreaming();
    try std.testing.expectEqual(StreamingState.idle, session.streaming_state);
    try std.testing.expectEqual(@as(usize, 1), session.history.items.len);
    try std.testing.expectEqualStrings("Hello world", session.history.items[0].content);
}

test "toggle thinking" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "ollama", "llama3.2:3b");
    defer session.deinit();

    try std.testing.expect(session.thinking_mode == false);
    session.toggleThinking();
    try std.testing.expect(session.thinking_mode == true);
    session.toggleThinking();
    try std.testing.expect(session.thinking_mode == false);
}

test "switch provider" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator, "ollama", "llama3.2:3b");
    defer session.deinit();

    try session.switchProvider("anthropic", "claude-opus-4");
    try std.testing.expectEqualStrings("anthropic", session.current_provider);
    try std.testing.expectEqualStrings("claude-opus-4", session.current_model);
}
