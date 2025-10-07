const std = @import("std");
const zqlite = @import("zqlite");

/// Routing preferences for a project
pub const RoutingPrefs = struct {
    project: []const u8,
    prefer_local: bool = true,
    max_cloud_cost_cents: ?u32 = 200,
    last_alias: ?[]const u8 = null,
    last_model: ?[]const u8 = null,
    escalation_threshold: []const u8 = "medium",
    updated_at: i64,
};

/// Routing decision stats
pub const RoutingStats = struct {
    request_id: ?[]const u8 = null,
    project: []const u8,
    alias: ?[]const u8 = null,
    model: []const u8,
    provider: []const u8,
    intent: []const u8 = "code",
    size_hint: []const u8 = "small",
    latency_ms: u32,
    total_duration_ms: u32,
    tokens_in: u32,
    tokens_out: u32,
    cost_cents: f64 = 0.0,
    success: bool = true,
    error_code: ?[]const u8 = null,
    escalated: bool = false,
    created_at: i64,
};

/// Model information
pub const Model = struct {
    id: []const u8,
    provider: []const u8,
    name: []const u8,
    display_name: ?[]const u8 = null,
    family: ?[]const u8 = null,
    parameter_size: ?[]const u8 = null,
    quantization: ?[]const u8 = null,
    context_length: u32 = 4096,
    capabilities: ?[]const u8 = null, // JSON array
    cost_per_1k_tokens_in: f64 = 0.0,
    cost_per_1k_tokens_out: f64 = 0.0,
    latency_avg_ms: ?u32 = null,
    success_rate: f64 = 1.0,
    available: bool = true,
    last_checked: i64,
    metadata: ?[]const u8 = null, // JSON blob
};

pub const RoutingDB = struct {
    db: *zqlite.Connection,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !RoutingDB {
        const db = try zqlite.open(allocator, db_path);
        errdefer db.close();

        var self = RoutingDB{
            .db = db,
            .allocator = allocator,
        };

        // Run migrations
        try self.runMigrations();

        return self;
    }

    pub fn deinit(self: *RoutingDB) void {
        self.db.close();
    }

    fn runMigrations(self: *RoutingDB) !void {
        // Inline migration SQL (can't use @embedFile for files outside package)
        const models_migration =
            \\PRAGMA journal_mode=WAL;
            \\PRAGMA foreign_keys=ON;
            \\CREATE TABLE IF NOT EXISTS models (
            \\  id TEXT PRIMARY KEY,
            \\  provider TEXT NOT NULL,
            \\  name TEXT NOT NULL,
            \\  display_name TEXT,
            \\  family TEXT,
            \\  parameter_size TEXT,
            \\  quantization TEXT,
            \\  context_length INTEGER DEFAULT 4096,
            \\  capabilities TEXT,
            \\  cost_per_1k_tokens_in REAL DEFAULT 0.0,
            \\  cost_per_1k_tokens_out REAL DEFAULT 0.0,
            \\  latency_avg_ms INTEGER,
            \\  success_rate REAL DEFAULT 1.0,
            \\  available INTEGER NOT NULL DEFAULT 1,
            \\  last_checked INTEGER NOT NULL,
            \\  metadata TEXT
            \\);
            \\CREATE INDEX IF NOT EXISTS idx_models_provider ON models(provider);
            \\CREATE INDEX IF NOT EXISTS idx_models_available ON models(available, provider);
            \\CREATE INDEX IF NOT EXISTS idx_models_family ON models(family);
        ;

        const routing_migration =
            \\PRAGMA journal_mode=WAL;
            \\PRAGMA foreign_keys=ON;
            \\CREATE TABLE IF NOT EXISTS routing_prefs (
            \\  project TEXT PRIMARY KEY,
            \\  prefer_local INTEGER NOT NULL DEFAULT 1,
            \\  max_cloud_cost_cents INTEGER DEFAULT 200,
            \\  last_alias TEXT,
            \\  last_model TEXT,
            \\  escalation_threshold TEXT DEFAULT 'medium',
            \\  updated_at INTEGER NOT NULL
            \\);
            \\CREATE TABLE IF NOT EXISTS routing_stats (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  request_id TEXT,
            \\  project TEXT NOT NULL,
            \\  alias TEXT,
            \\  model TEXT,
            \\  provider TEXT,
            \\  intent TEXT,
            \\  size_hint TEXT,
            \\  latency_ms INTEGER,
            \\  total_duration_ms INTEGER,
            \\  tokens_in INTEGER,
            \\  tokens_out INTEGER,
            \\  cost_cents REAL DEFAULT 0.0,
            \\  success INTEGER NOT NULL DEFAULT 1,
            \\  error_code TEXT,
            \\  escalated INTEGER DEFAULT 0,
            \\  created_at INTEGER NOT NULL
            \\);
            \\CREATE TABLE IF NOT EXISTS routing_trace (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  request_id TEXT NOT NULL,
            \\  project TEXT,
            \\  trace TEXT,
            \\  decision_reason TEXT,
            \\  candidates TEXT,
            \\  created_at INTEGER NOT NULL
            \\);
            \\CREATE INDEX IF NOT EXISTS idx_stats_project_time ON routing_stats(project, created_at DESC);
            \\CREATE INDEX IF NOT EXISTS idx_stats_model ON routing_stats(model);
            \\CREATE INDEX IF NOT EXISTS idx_stats_provider ON routing_stats(provider);
            \\CREATE INDEX IF NOT EXISTS idx_stats_request_id ON routing_stats(request_id);
            \\CREATE INDEX IF NOT EXISTS idx_trace_request_id ON routing_trace(request_id);
            \\CREATE INDEX IF NOT EXISTS idx_trace_project_time ON routing_trace(project, created_at DESC);
        ;

        // Execute migrations
        _ = try self.db.exec(models_migration);
        _ = try self.db.exec(routing_migration);
    }

    /// Upsert routing preferences for a project
    pub fn upsertPrefs(self: *RoutingDB, prefs: RoutingPrefs) !void {
        const sql = try std.fmt.allocPrint(
            self.allocator,
            \\INSERT INTO routing_prefs(project, prefer_local, max_cloud_cost_cents, last_alias, last_model, escalation_threshold, updated_at)
            \\VALUES ('{s}', {d}, {d}, '{s}', '{s}', '{s}', {d})
            \\ON CONFLICT(project) DO UPDATE SET
            \\  prefer_local=excluded.prefer_local,
            \\  max_cloud_cost_cents=COALESCE(excluded.max_cloud_cost_cents, routing_prefs.max_cloud_cost_cents),
            \\  last_alias=COALESCE(excluded.last_alias, routing_prefs.last_alias),
            \\  last_model=COALESCE(excluded.last_model, routing_prefs.last_model),
            \\  escalation_threshold=excluded.escalation_threshold,
            \\  updated_at=excluded.updated_at
        ,
            .{
                prefs.project,
                @intFromBool(prefs.prefer_local),
                prefs.max_cloud_cost_cents orelse 200,
                prefs.last_alias orelse "",
                prefs.last_model orelse "",
                prefs.escalation_threshold,
                prefs.updated_at,
            },
        );
        defer self.allocator.free(sql);
        _ = try self.db.exec(sql);
    }

    /// Record a routing decision
    pub fn recordStats(self: *RoutingDB, stats: RoutingStats) !void {
        const sql = try std.fmt.allocPrint(
            self.allocator,
            \\INSERT INTO routing_stats(
            \\  request_id, project, alias, model, provider, intent, size_hint,
            \\  latency_ms, total_duration_ms, tokens_in, tokens_out, cost_cents,
            \\  success, error_code, escalated, created_at
            \\) VALUES ('{s}', '{s}', '{s}', '{s}', '{s}', '{s}', '{s}', {d}, {d}, {d}, {d}, {d}, {d}, '{s}', {d}, {d})
        ,
            .{
                stats.request_id orelse "",
                stats.project,
                stats.alias orelse "",
                stats.model,
                stats.provider,
                stats.intent,
                stats.size_hint,
                stats.latency_ms,
                stats.total_duration_ms,
                stats.tokens_in,
                stats.tokens_out,
                stats.cost_cents,
                @intFromBool(stats.success),
                stats.error_code orelse "",
                @intFromBool(stats.escalated),
                stats.created_at,
            },
        );
        defer self.allocator.free(sql);
        _ = try self.db.exec(sql);
    }

    /// Upsert a model entry
    pub fn upsertModel(self: *RoutingDB, model: Model) !void {
        const sql = try std.fmt.allocPrint(
            self.allocator,
            \\INSERT INTO models(
            \\  id, provider, name, display_name, family, parameter_size, quantization,
            \\  context_length, capabilities, cost_per_1k_tokens_in, cost_per_1k_tokens_out,
            \\  latency_avg_ms, success_rate, available, last_checked, metadata
            \\) VALUES ('{s}', '{s}', '{s}', '{s}', '{s}', '{s}', '{s}', {d}, '{s}', {d}, {d}, {d}, {d}, {d}, {d}, '{s}')
            \\ON CONFLICT(id) DO UPDATE SET
            \\  display_name=excluded.display_name,
            \\  family=excluded.family,
            \\  parameter_size=excluded.parameter_size,
            \\  quantization=excluded.quantization,
            \\  context_length=excluded.context_length,
            \\  capabilities=excluded.capabilities,
            \\  cost_per_1k_tokens_in=excluded.cost_per_1k_tokens_in,
            \\  cost_per_1k_tokens_out=excluded.cost_per_1k_tokens_out,
            \\  latency_avg_ms=excluded.latency_avg_ms,
            \\  success_rate=excluded.success_rate,
            \\  available=excluded.available,
            \\  last_checked=excluded.last_checked,
            \\  metadata=excluded.metadata
        ,
            .{
                model.id,
                model.provider,
                model.name,
                model.display_name orelse "",
                model.family orelse "",
                model.parameter_size orelse "",
                model.quantization orelse "",
                model.context_length,
                model.capabilities orelse "[]",
                model.cost_per_1k_tokens_in,
                model.cost_per_1k_tokens_out,
                model.latency_avg_ms orelse 0,
                model.success_rate,
                @intFromBool(model.available),
                model.last_checked,
                model.metadata orelse "{}",
            },
        );
        defer self.allocator.free(sql);
        _ = try self.db.exec(sql);
    }
};

// Simplified implementations - return empty for now
pub fn getModelsByProvider(db: *RoutingDB, allocator: std.mem.Allocator, provider: []const u8) ![]Model {
    _ = db;
    _ = allocator;
    _ = provider;
    const empty: []Model = &[_]Model{};
    return empty;
}

pub fn getPrefs(db: *RoutingDB, allocator: std.mem.Allocator, project: []const u8) !?RoutingPrefs {
    _ = db;
    _ = allocator;
    _ = project;
    return null;
}

pub fn getRecentStats(db: *RoutingDB, allocator: std.mem.Allocator, project: ?[]const u8, limit: u32) ![]RoutingStats {
    _ = db;
    _ = allocator;
    _ = project;
    _ = limit;
    const empty: []RoutingStats = &[_]RoutingStats{};
    return empty;
}
