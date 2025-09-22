const std = @import("std");
const Database = @import("database.zig").Database;
const ContextCache = @import("database.zig").ContextCache;
const zqlite = @import("zqlite");

pub const ContextStore = struct {
    db: *Database,
    allocator: std.mem.Allocator,
    
    pub fn init(db: *Database, allocator: std.mem.Allocator) ContextStore {
        return .{
            .db = db,
            .allocator = allocator,
        };
    }
    
    pub fn cacheFile(self: *ContextStore, file_path: []const u8, content: []const u8, language: ?[]const u8) !void {
        const id = try generateId(self.allocator);
        const now = std.time.timestamp();
        
        // Check if file already cached
        const existing = try self.getByPath(file_path);
        if (existing) |ctx| {
            // Update existing
            const stmt = try self.db.db.prepare(
                \\UPDATE context_cache 
                \\SET content = ?, language = ?, last_modified = ?
                \\WHERE file_path = ?;
            );
            defer stmt.finalize();
            
            try stmt.bind(1, content);
            try stmt.bind(2, language orelse "unknown");
            try stmt.bind(3, now);
            try stmt.bind(4, file_path);
            
            try stmt.step();
            self.allocator.free(ctx.id);
            self.allocator.free(ctx.file_path);
            self.allocator.free(ctx.content);
            if (ctx.language) |lang| self.allocator.free(lang);
        } else {
            // Insert new
            const stmt = try self.db.db.prepare(
                \\INSERT INTO context_cache (id, file_path, content, language, last_modified, created_at)
                \\VALUES (?, ?, ?, ?, ?, ?);
            );
            defer stmt.finalize();
            
            try stmt.bind(1, id);
            try stmt.bind(2, file_path);
            try stmt.bind(3, content);
            try stmt.bind(4, language orelse "unknown");
            try stmt.bind(5, now);
            try stmt.bind(6, now);
            
            try stmt.step();
        }
    }
    
    pub fn getByPath(self: *ContextStore, file_path: []const u8) !?ContextCache {
        const stmt = try self.db.db.prepare(
            \\SELECT id, file_path, content, embeddings, language, last_modified, created_at
            \\FROM context_cache WHERE file_path = ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, file_path);
        
        if (try stmt.step()) {
            return ContextCache{
                .id = try self.allocator.dupe(u8, try stmt.text(0)),
                .file_path = try self.allocator.dupe(u8, try stmt.text(1)),
                .content = try self.allocator.dupe(u8, try stmt.text(2)),
                .embeddings = if (try stmt.blobNull(3)) |blob| try self.allocator.dupe(u8, blob) else null,
                .language = if (try stmt.textNull(4)) |text| try self.allocator.dupe(u8, text) else null,
                .last_modified = try stmt.int64(5),
                .created_at = try stmt.int64(6),
            };
        }
        
        return null;
    }
    
    pub fn searchByContent(self: *ContextStore, query: []const u8, limit: u32) ![]ContextCache {
        const stmt = try self.db.db.prepare(
            \\SELECT id, file_path, content, embeddings, language, last_modified, created_at
            \\FROM context_cache 
            \\WHERE content LIKE '%' || ? || '%'
            \\ORDER BY last_modified DESC
            \\LIMIT ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, query);
        try stmt.bind(2, limit);
        
        var results = std.ArrayList(ContextCache).init(self.allocator);
        defer results.deinit();
        
        while (try stmt.step()) {
            try results.append(ContextCache{
                .id = try self.allocator.dupe(u8, try stmt.text(0)),
                .file_path = try self.allocator.dupe(u8, try stmt.text(1)),
                .content = try self.allocator.dupe(u8, try stmt.text(2)),
                .embeddings = if (try stmt.blobNull(3)) |blob| try self.allocator.dupe(u8, blob) else null,
                .language = if (try stmt.textNull(4)) |text| try self.allocator.dupe(u8, text) else null,
                .last_modified = try stmt.int64(5),
                .created_at = try stmt.int64(6),
            });
        }
        
        return results.toOwnedSlice();
    }
    
    pub fn updateEmbeddings(self: *ContextStore, file_path: []const u8, embeddings: []const u8) !void {
        const stmt = try self.db.db.prepare(
            \\UPDATE context_cache SET embeddings = ? WHERE file_path = ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, embeddings);
        try stmt.bind(2, file_path);
        
        try stmt.step();
    }
    
    pub fn clearCache(self: *ContextStore) !void {
        try self.db.db.exec("DELETE FROM context_cache;");
    }
    
    pub fn clearOldCache(self: *ContextStore, days_old: i64) !void {
        const cutoff = std.time.timestamp() - (days_old * 24 * 60 * 60);
        
        const stmt = try self.db.db.prepare(
            \\DELETE FROM context_cache WHERE last_modified < ?;
        );
        defer stmt.finalize();
        
        try stmt.bind(1, cutoff);
        try stmt.step();
    }
    
    pub fn getCacheSize(self: *ContextStore) !usize {
        const stmt = try self.db.db.prepare(
            \\SELECT SUM(LENGTH(content) + COALESCE(LENGTH(embeddings), 0)) FROM context_cache;
        );
        defer stmt.finalize();
        
        if (try stmt.step()) {
            return @intCast(try stmt.int64(0));
        }
        
        return 0;
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