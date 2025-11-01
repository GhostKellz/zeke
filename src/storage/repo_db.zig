const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Per-repository SQLite database stored in .zeke file
/// Stores project-specific metadata, cache, settings
pub const RepoDatabase = struct {
    allocator: std.mem.Allocator,
    db: ?*c.sqlite3,
    db_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, project_root: []const u8) !RepoDatabase {
        const db_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ project_root, ".zeke" },
        );

        var repo_db = RepoDatabase{
            .allocator = allocator,
            .db = null,
            .db_path = db_path,
        };

        try repo_db.open();
        try repo_db.createTables();

        return repo_db;
    }

    pub fn deinit(self: *RepoDatabase) void {
        self.close();
        self.allocator.free(self.db_path);
    }

    fn open(self: *RepoDatabase) !void {
        const result = c.sqlite3_open(self.db_path.ptr, &self.db);
        if (result != c.SQLITE_OK) {
            std.debug.print("Failed to open database: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.DatabaseOpenFailed;
        }

        std.debug.print("✅ Opened repo database: {s}\n", .{self.db_path});
    }

    fn close(self: *RepoDatabase) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    fn createTables(self: *RepoDatabase) !void {
        // Cache table
        const cache_sql =
            \\CREATE TABLE IF NOT EXISTS cache (
            \\    key TEXT PRIMARY KEY,
            \\    value BLOB,
            \\    expires_at INTEGER
            \\);
        ;

        try self.exec(cache_sql);

        // Settings table
        const settings_sql =
            \\CREATE TABLE IF NOT EXISTS settings (
            \\    key TEXT PRIMARY KEY,
            \\    value TEXT
            \\);
        ;

        try self.exec(settings_sql);

        // Index metadata table
        const index_meta_sql =
            \\CREATE TABLE IF NOT EXISTS index_metadata (
            \\    file_path TEXT PRIMARY KEY,
            \\    last_indexed INTEGER,
            \\    hash TEXT
            \\);
        ;

        try self.exec(index_meta_sql);

        // AI response history table
        const ai_history_sql =
            \\CREATE TABLE IF NOT EXISTS ai_responses (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    prompt TEXT,
            \\    response TEXT,
            \\    model TEXT,
            \\    timestamp INTEGER
            \\);
        ;

        try self.exec(ai_history_sql);
    }

    fn exec(self: *RepoDatabase, sql: []const u8) !void {
        var err_msg: [*c]u8 = null;
        const result = c.sqlite3_exec(self.db, sql.ptr, null, null, &err_msg);

        if (result != c.SQLITE_OK) {
            defer c.sqlite3_free(err_msg);
            std.debug.print("SQL error: {s}\n", .{err_msg});
            return error.SqlExecutionFailed;
        }
    }

    // === Cache Operations ===

    pub fn cacheGet(self: *RepoDatabase, key: []const u8) !?[]const u8 {
        const sql = "SELECT value, expires_at FROM cache WHERE key = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            // Check expiration
            const expires_at = c.sqlite3_column_int64(stmt, 1);
            const now = std.time.timestamp();

            if (now > expires_at) {
                // Expired - delete and return null
                try self.cacheDelete(key);
                return null;
            }

            // Get value
            const value_ptr = c.sqlite3_column_text(stmt, 0);
            const value_len = c.sqlite3_column_bytes(stmt, 0);
            const value = try self.allocator.dupe(u8, value_ptr[0..@intCast(value_len)]);
            return value;
        }

        return null;
    }

    pub fn cachePut(self: *RepoDatabase, key: []const u8, value: []const u8, ttl_seconds: i64) !void {
        const sql = "INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?, ?, ?)";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        const expires_at = std.time.timestamp() + ttl_seconds;

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_text(stmt, 2, value.ptr, @intCast(value.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_int64(stmt, 3, expires_at);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.ExecutionFailed;
        }
    }

    pub fn cacheDelete(self: *RepoDatabase, key: []const u8) !void {
        const sql = "DELETE FROM cache WHERE key = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.ExecutionFailed;
        }
    }

    // === Settings Operations ===

    pub fn settingGet(self: *RepoDatabase, key: []const u8) !?[]const u8 {
        const sql = "SELECT value FROM settings WHERE key = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const value_ptr = c.sqlite3_column_text(stmt, 0);
            const value_len = c.sqlite3_column_bytes(stmt, 0);
            const value = try self.allocator.dupe(u8, value_ptr[0..@intCast(value_len)]);
            return value;
        }

        return null;
    }

    pub fn settingPut(self: *RepoDatabase, key: []const u8, value: []const u8) !void {
        const sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, key.ptr, @intCast(key.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_text(stmt, 2, value.ptr, @intCast(value.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.ExecutionFailed;
        }
    }

    // === Index Metadata Operations ===

    pub fn indexMetaGet(self: *RepoDatabase, file_path: []const u8) !?IndexMetadata {
        const sql = "SELECT last_indexed, hash FROM index_metadata WHERE file_path = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, file_path.ptr, @intCast(file_path.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const last_indexed = c.sqlite3_column_int64(stmt, 0);
            const hash_ptr = c.sqlite3_column_text(stmt, 1);
            const hash_len = c.sqlite3_column_bytes(stmt, 1);
            const hash = try self.allocator.dupe(u8, hash_ptr[0..@intCast(hash_len)]);

            return IndexMetadata{
                .last_indexed = last_indexed,
                .hash = hash,
            };
        }

        return null;
    }

    pub fn indexMetaPut(self: *RepoDatabase, file_path: []const u8, metadata: IndexMetadata) !void {
        const sql = "INSERT OR REPLACE INTO index_metadata (file_path, last_indexed, hash) VALUES (?, ?, ?)";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, file_path.ptr, @intCast(file_path.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_int64(stmt, 2, metadata.last_indexed);
        _ = c.sqlite3_bind_text(stmt, 3, metadata.hash.ptr, @intCast(metadata.hash.len), c.SQLITE_TRANSIENT);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.ExecutionFailed;
        }
    }

    // === AI Response History ===

    pub fn aiResponseAdd(self: *RepoDatabase, prompt: []const u8, response: []const u8, model: []const u8) !void {
        const sql = "INSERT INTO ai_responses (prompt, response, model, timestamp) VALUES (?, ?, ?, ?)";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        const timestamp = std.time.timestamp();

        _ = c.sqlite3_bind_text(stmt, 1, prompt.ptr, @intCast(prompt.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_text(stmt, 2, response.ptr, @intCast(response.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_text(stmt, 3, model.ptr, @intCast(model.len), c.SQLITE_TRANSIENT);
        _ = c.sqlite3_bind_int64(stmt, 4, timestamp);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.ExecutionFailed;
        }
    }
};

pub const IndexMetadata = struct {
    last_indexed: i64,
    hash: []const u8,

    pub fn deinit(self: *IndexMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.hash);
    }
};
