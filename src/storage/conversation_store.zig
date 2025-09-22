const std = @import("std");
const Database = @import("database.zig").Database;
const Conversation = @import("database.zig").Conversation;
const Message = @import("database.zig").Message;
const zqlite = @import("zqlite");

pub const ConversationStore = struct {
    db: *Database,
    allocator: std.mem.Allocator,
    
    pub fn init(db: *Database, allocator: std.mem.Allocator) ConversationStore {
        return .{
            .db = db,
            .allocator = allocator,
        };
    }
    
    pub fn createConversation(self: *ConversationStore, provider: []const u8, model: []const u8) ![]const u8 {
        const id = try generateId(self.allocator);
        const now = std.time.timestamp();
        
        const stmt = try self.db.db.prepare(
            \\INSERT INTO conversations (id, provider, model, created_at, updated_at)
            \\VALUES (?, ?, ?, ?, ?);
        );
        defer stmt.finalize();
        
        try stmt.bind(1, id);
        try stmt.bind(2, provider);
        try stmt.bind(3, model);
        try stmt.bind(4, now);
        try stmt.bind(5, now);
        
        try stmt.step();
        return id;
    }
    
    pub fn addMessage(self: *ConversationStore, conversation_id: []const u8, role: []const u8, content: []const u8) !void {
        const id = try generateId(self.allocator);
        const now = std.time.timestamp();
        
        const stmt = try self.db.db.prepare(
            \\INSERT INTO messages (id, conversation_id, role, content, created_at)
            \\VALUES (?, ?, ?, ?, ?);
        );
        defer stmt.finalize();
        
        try stmt.bind(1, id);
        try stmt.bind(2, conversation_id);
        try stmt.bind(3, role);
        try stmt.bind(4, content);
        try stmt.bind(5, now);
        
        try stmt.step();
        
        // Update conversation updated_at
        const update_stmt = try self.db.db.prepare(
            \\UPDATE conversations SET updated_at = ? WHERE id = ?;
        );
        defer update_stmt.finalize();
        
        try update_stmt.bind(1, now);
        try update_stmt.bind(2, conversation_id);
        try update_stmt.step();
    }
    
    pub fn getConversation(self: *ConversationStore, id: []const u8) !?Conversation {
        const stmt = try self.db.db.prepare(
            \\SELECT id, provider, model, created_at, updated_at, metadata
            \\FROM conversations WHERE id = ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, id);
        
        if (try stmt.step()) {
            return Conversation{
                .id = try self.allocator.dupe(u8, try stmt.text(0)),
                .provider = try self.allocator.dupe(u8, try stmt.text(1)),
                .model = try self.allocator.dupe(u8, try stmt.text(2)),
                .created_at = try stmt.int64(3),
                .updated_at = try stmt.int64(4),
                .metadata = if (try stmt.textNull(5)) |text| try self.allocator.dupe(u8, text) else null,
            };
        }
        
        return null;
    }
    
    pub fn getMessages(self: *ConversationStore, conversation_id: []const u8) ![]Message {
        const stmt = try self.db.db.prepare(
            \\SELECT id, conversation_id, role, content, tokens, created_at
            \\FROM messages WHERE conversation_id = ? ORDER BY created_at ASC;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, conversation_id);
        
        var messages = std.ArrayList(Message).init(self.allocator);
        defer messages.deinit();
        
        while (try stmt.step()) {
            try messages.append(Message{
                .id = try self.allocator.dupe(u8, try stmt.text(0)),
                .conversation_id = try self.allocator.dupe(u8, try stmt.text(1)),
                .role = try self.allocator.dupe(u8, try stmt.text(2)),
                .content = try self.allocator.dupe(u8, try stmt.text(3)),
                .tokens = try stmt.intNull(4),
                .created_at = try stmt.int64(5),
            });
        }
        
        return messages.toOwnedSlice();
    }
    
    pub fn getRecentConversations(self: *ConversationStore, limit: u32) ![]Conversation {
        const stmt = try self.db.db.prepare(
            \\SELECT id, provider, model, created_at, updated_at, metadata
            \\FROM conversations ORDER BY updated_at DESC LIMIT ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, limit);
        
        var conversations = std.ArrayList(Conversation).init(self.allocator);
        defer conversations.deinit();
        
        while (try stmt.step()) {
            try conversations.append(Conversation{
                .id = try self.allocator.dupe(u8, try stmt.text(0)),
                .provider = try self.allocator.dupe(u8, try stmt.text(1)),
                .model = try self.allocator.dupe(u8, try stmt.text(2)),
                .created_at = try stmt.int64(3),
                .updated_at = try stmt.int64(4),
                .metadata = if (try stmt.textNull(5)) |text| try self.allocator.dupe(u8, text) else null,
            });
        }
        
        return conversations.toOwnedSlice();
    }
    
    pub fn deleteConversation(self: *ConversationStore, id: []const u8) !void {
        try self.db.beginTransaction();
        defer self.db.rollback() catch {};
        
        // Delete messages first
        const delete_messages = try self.db.db.prepare(
            \\DELETE FROM messages WHERE conversation_id = ?;
        );
        defer delete_messages.finalize();
        
        try delete_messages.bind(1, id);
        try delete_messages.step();
        
        // Delete conversation
        const delete_conv = try self.db.db.prepare(
            \\DELETE FROM conversations WHERE id = ?;
        );
        defer delete_conv.finalize();
        
        try delete_conv.bind(1, id);
        try delete_conv.step();
        
        try self.db.commit();
    }
    
    fn generateId(allocator: std.mem.Allocator) ![]const u8 {
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();
        
        var id_buf = try allocator.alloc(u8, 16);
        const charset = "abcdefghijklmnopqrstuvwxyz0123456789";
        
        for (id_buf) |*byte| {
            byte.* = charset[random.int(usize) % charset.len];
        }
        
        return id_buf;
    }
};