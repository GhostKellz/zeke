const std = @import("std");
const zqlite = @import("zqlite");

pub const StorageError = error{
    DatabaseInitFailed,
    ConnectionFailed,
    QueryFailed,
    TransactionFailed,
};

pub const ConversationEntry = struct {
    id: i64,
    timestamp: i64,
    provider: []const u8,
    model: []const u8,
    role: []const u8,
    content: []const u8,
    tokens: i32,
    response_time_ms: i64,
};

pub const ProjectContext = struct {
    id: i64,
    project_path: []const u8,
    file_path: []const u8,
    content_hash: []const u8,
    analysis: []const u8,
    last_updated: i64,
};

pub const StorageManager = struct {
    allocator: std.mem.Allocator,
    connection: ?*zqlite.Connection,
    db_path: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8, password: ?[]const u8) !Self {
        var manager = Self{
            .allocator = allocator,
            .connection = null,
            .db_path = db_path,
        };
        
        try manager.initDatabase(password);
        return manager;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.connection) |conn| {
            conn.close();
        }
    }
    
    fn initDatabase(self: *Self, password: ?[]const u8) !void {
        _ = password; // TODO: Implement encryption when zqlite adds support
        
        // Open database connection
        self.connection = try zqlite.open(self.allocator, self.db_path);
        
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        // Create tables
        try self.createTables(conn);
    }
    
    fn createTables(_: *Self, conn: *zqlite.Connection) !void {
        // Conversations table
        const conversations_sql =
            \\CREATE TABLE IF NOT EXISTS conversations (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    timestamp INTEGER NOT NULL,
            \\    provider TEXT NOT NULL,
            \\    model TEXT NOT NULL,
            \\    role TEXT NOT NULL,
            \\    content TEXT,
            \\    tokens INTEGER,
            \\    response_time_ms INTEGER,
            \\    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            \\);
        ;
        try conn.execute(conversations_sql);
        
        // Project context table
        const context_sql =
            \\CREATE TABLE IF NOT EXISTS project_context (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    project_path TEXT NOT NULL,
            \\    file_path TEXT NOT NULL,
            \\    content_hash TEXT NOT NULL,
            \\    analysis TEXT,
            \\    last_updated INTEGER NOT NULL,
            \\    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            \\    UNIQUE(project_path, file_path)
            \\);
        ;
        try conn.execute(context_sql);
        
        // Provider metrics table
        const metrics_sql =
            \\CREATE TABLE IF NOT EXISTS provider_metrics (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    provider TEXT NOT NULL,
            \\    timestamp INTEGER NOT NULL,
            \\    success_count INTEGER DEFAULT 0,
            \\    error_count INTEGER DEFAULT 0,
            \\    avg_response_time_ms INTEGER,
            \\    total_tokens INTEGER DEFAULT 0,
            \\    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            \\);
        ;
        try conn.execute(metrics_sql);
        
        // Create indexes for performance
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_conversations_timestamp ON conversations(timestamp);");
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_context_project ON project_context(project_path);");
        try conn.execute("CREATE INDEX IF NOT EXISTS idx_metrics_provider ON provider_metrics(provider, timestamp);");
    }
    
    pub fn saveConversation(self: *Self, entry: ConversationEntry) !void {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO conversations (timestamp, provider, model, role, content, tokens, response_time_ms)
            \\VALUES ({}, '{}', '{}', '{}', '{}', {}, {})
        , .{ entry.timestamp, entry.provider, entry.model, entry.role, entry.content, entry.tokens, entry.response_time_ms });
        defer self.allocator.free(sql);
        
        try conn.execute(sql);
    }
    
    pub fn getRecentConversations(self: *Self, limit: u32) ![]ConversationEntry {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT id, timestamp, provider, model, role, content, tokens, response_time_ms
            \\FROM conversations
            \\ORDER BY timestamp DESC
            \\LIMIT {}
        , .{limit});
        defer self.allocator.free(sql);
        
        // For now, return empty array as zqlite query API is still evolving
        // TODO: Implement when zqlite adds proper query result handling
        _ = conn;
        
        return try self.allocator.alloc(ConversationEntry, 0);
    }
    
    pub fn saveProjectContext(self: *Self, context: ProjectContext) !void {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT OR REPLACE INTO project_context (project_path, file_path, content_hash, analysis, last_updated)
            \\VALUES ('{}', '{}', '{}', '{}', {})
        , .{ context.project_path, context.file_path, context.content_hash, context.analysis, context.last_updated });
        defer self.allocator.free(sql);
        
        try conn.execute(sql);
    }
    
    pub fn getProjectContext(self: *Self, project_path: []const u8, file_path: []const u8) !?ProjectContext {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT id, project_path, file_path, content_hash, analysis, last_updated
            \\FROM project_context
            \\WHERE project_path = '{}' AND file_path = '{}'
        , .{ project_path, file_path });
        defer self.allocator.free(sql);
        
        // For now, return null as zqlite query API is still evolving
        // TODO: Implement when zqlite adds proper query result handling
        _ = conn;
        
        return null;
    }
    
    pub fn updateProviderMetrics(self: *Self, provider: []const u8, success: bool, response_time_ms: i64, tokens: i32) !void {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const timestamp = std.time.timestamp();
        const hour_timestamp = timestamp - (timestamp % 3600);
        
        // For simplified implementation, just insert new metrics
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO provider_metrics (provider, timestamp, success_count, error_count, avg_response_time_ms, total_tokens)
            \\VALUES ('{}', {}, {}, {}, {}, {})
        , .{ 
            provider, 
            hour_timestamp, 
            if (success) @as(i32, 1) else @as(i32, 0),
            if (!success) @as(i32, 1) else @as(i32, 0),
            response_time_ms,
            tokens
        });
        defer self.allocator.free(sql);
        
        try conn.execute(sql);
    }
    
    pub fn getProviderMetrics(self: *Self, provider: []const u8, hours: u32) ![]const u8 {
        const conn = self.connection orelse return StorageError.ConnectionFailed;
        
        const since_timestamp = std.time.timestamp() - (hours * 3600);
        
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT 
            \\    SUM(success_count) as total_success,
            \\    SUM(error_count) as total_errors,
            \\    AVG(avg_response_time_ms) as avg_response_time,
            \\    SUM(total_tokens) as total_tokens
            \\FROM provider_metrics
            \\WHERE provider = '{}' AND timestamp >= {}
        , .{ provider, since_timestamp });
        defer self.allocator.free(sql);
        
        // For now, return mock metrics
        _ = conn;
        
        return try std.fmt.allocPrint(self.allocator,
            \\Provider: {s}
            \\Metrics collection in progress...
        , .{provider});
    }
};