const std = @import("std");
const zqlite = @import("zqlite");

pub const Database = struct {
    db: *zqlite.Database,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Database {
        const db = try zqlite.Database.open(allocator, path, .{
            .mode = .read_write_create,
            .thread_safe = true,
        });
        
        return Database{
            .db = db,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Database) void {
        self.db.close();
    }
    
    pub fn createTables(self: *Database) !void {
        // Conversations table
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS conversations (
            \\    id TEXT PRIMARY KEY,
            \\    provider TEXT NOT NULL,
            \\    model TEXT NOT NULL,
            \\    created_at INTEGER NOT NULL,
            \\    updated_at INTEGER NOT NULL,
            \\    metadata TEXT
            \\);
        );
        
        // Messages table
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS messages (
            \\    id TEXT PRIMARY KEY,
            \\    conversation_id TEXT NOT NULL,
            \\    role TEXT NOT NULL,
            \\    content TEXT NOT NULL,
            \\    tokens INTEGER,
            \\    created_at INTEGER NOT NULL,
            \\    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            \\);
        );
        
        // Context cache table
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS context_cache (
            \\    id TEXT PRIMARY KEY,
            \\    file_path TEXT NOT NULL,
            \\    content TEXT NOT NULL,
            \\    embeddings BLOB,
            \\    language TEXT,
            \\    last_modified INTEGER NOT NULL,
            \\    created_at INTEGER NOT NULL
            \\);
        );
        
        // Model configurations table
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS model_configs (
            \\    id TEXT PRIMARY KEY,
            \\    provider TEXT NOT NULL,
            \\    model TEXT NOT NULL,
            \\    temperature REAL,
            \\    max_tokens INTEGER,
            \\    system_prompt TEXT,
            \\    config_json TEXT,
            \\    created_at INTEGER NOT NULL,
            \\    updated_at INTEGER NOT NULL
            \\);
        );
        
        // API keys table (encrypted)
        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS api_keys (
            \\    id TEXT PRIMARY KEY,
            \\    provider TEXT NOT NULL UNIQUE,
            \\    encrypted_key TEXT NOT NULL,
            \\    salt TEXT NOT NULL,
            \\    created_at INTEGER NOT NULL,
            \\    updated_at INTEGER NOT NULL
            \\);
        );
        
        // Create indexes for better performance
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);");
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_context_cache_path ON context_cache(file_path);");
        try self.db.exec("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);");
    }
    
    pub fn beginTransaction(self: *Database) !void {
        try self.db.exec("BEGIN TRANSACTION;");
    }
    
    pub fn commit(self: *Database) !void {
        try self.db.exec("COMMIT;");
    }
    
    pub fn rollback(self: *Database) !void {
        try self.db.exec("ROLLBACK;");
    }
};

pub const Conversation = struct {
    id: []const u8,
    provider: []const u8,
    model: []const u8,
    created_at: i64,
    updated_at: i64,
    metadata: ?[]const u8,
};

pub const Message = struct {
    id: []const u8,
    conversation_id: []const u8,
    role: []const u8,
    content: []const u8,
    tokens: ?i32,
    created_at: i64,
};

pub const ContextCache = struct {
    id: []const u8,
    file_path: []const u8,
    content: []const u8,
    embeddings: ?[]const u8,
    language: ?[]const u8,
    last_modified: i64,
    created_at: i64,
};

pub const ModelConfig = struct {
    id: []const u8,
    provider: []const u8,
    model: []const u8,
    temperature: ?f32,
    max_tokens: ?i32,
    system_prompt: ?[]const u8,
    config_json: ?[]const u8,
    created_at: i64,
    updated_at: i64,
};