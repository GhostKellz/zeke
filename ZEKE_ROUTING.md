How Zeke uses this

Resolve alias → provider/model/tags.

Merge with per-command tags (e.g., intent="tests" for :ZekeTest).

Send to OMEN as OpenAI-compat payload with a tags object (and pass-through headers).

Minimal request example Zeke sends

{
  "model": "auto",
  "messages": [{ "role": "user", "content": "Refactor this function…" }],
  "stream": true,
  "tags": { "intent": "code", "project": "grim", "latency": "low", "budget": "frugal", "size_hint": "small" }
}

db/migrations/0001_routing.sql
-- Client-side zqlite tables (Zeke local cache)
-- Path suggestion: db/migrations/0001_routing.sql

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS routing_prefs (
  project TEXT PRIMARY KEY,
  prefer_local INTEGER NOT NULL DEFAULT 1,
  max_cloud_cost_cents INTEGER DEFAULT 200,
  last_alias TEXT,
  last_model TEXT,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS routing_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project TEXT NOT NULL,
  alias TEXT,
  model TEXT,
  provider TEXT,
  intent TEXT,
  size_hint TEXT,
  latency_ms INTEGER,
  tokens_in INTEGER,
  tokens_out INTEGER,
  success INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);

-- Optional: store last routing decision explanation from OMEN
CREATE TABLE IF NOT EXISTS routing_trace (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT,
  project TEXT,
  trace TEXT,              -- JSON blob from X-OMEN-Trace headers or body
  created_at INTEGER NOT NULL
);

db/migrations/0002_indexes.sql
-- Helpful indexes for quick lookups

CREATE INDEX IF NOT EXISTS idx_stats_project_time
  ON routing_stats(project, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stats_model
  ON routing_stats(model);

CREATE INDEX IF NOT EXISTS idx_stats_provider
  ON routing_stats(provider);

CREATE INDEX IF NOT EXISTS idx_trace_project_time
  ON routing_trace(project, created_at DESC);

src/db/routing_prefs.zig (tiny helper, optional)
const std = @import("std");
const zqlite = @import("zqlite"); // you said Zeke already uses this

pub const RoutingPrefs = struct {
    pub fn upsert(
        db: *zqlite.DB,
        project: []const u8,
        prefer_local: bool,
        max_cloud_cost_cents: ?u32,
        last_alias: ?[]const u8,
        last_model: ?[]const u8,
        now_epoch: i64,
    ) !void {
        try db.exec(
            \\INSERT INTO routing_prefs(project, prefer_local, max_cloud_cost_cents, last_alias, last_model, updated_at)
            \\VALUES (?1, ?2, COALESCE(?3, max_cloud_cost_cents), COALESCE(?4, last_alias), COALESCE(?5, last_model), ?6)
            \\ON CONFLICT(project) DO UPDATE SET
            \\  prefer_local=excluded.prefer_local,
            \\  max_cloud_cost_cents=COALESCE(excluded.max_cloud_cost_cents, routing_prefs.max_cloud_cost_cents),
            \\  last_alias=COALESCE(excluded.last_alias, routing_prefs.last_alias),
            \\  last_model=COALESCE(excluded.last_model, routing_prefs.last_model),
            \\  updated_at=excluded.updated_at
        , .{ project, @intFromBool(prefer_local), max_cloud_cost_cents, last_alias, last_model, now_epoch });
    }

    pub fn recordStat(
        db: *zqlite.DB,
        project: []const u8,
        alias: []const u8,
        model: []const u8,
        provider: []const u8,
        intent: []const u8,
        size_hint: []const u8,
        latency_ms: u32,
        tokens_in: u32,
        tokens_out: u32,
        success: bool,
        now_epoch: i64,
    ) !void {
        try db.exec(
            \\INSERT INTO routing_stats(project, alias, model, provider, intent, size_hint, latency_ms, tokens_in, tokens_out, success, created_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        , .{ project, alias, model, provider, intent, size_hint, latency_ms, tokens_in, tokens_out, @intFromBool(success), now_epoch });
    }
};

Quick wire-up in Zeke

Env (client):

export ZEKE_API_BASE="http://127.0.0.1:8080/v1"
export OLLAMA_HOST="http://127.0.0.1:11434"


Request (pseudo):

POST ${ZEKE_API_BASE}/chat/completions
{
  "model": "auto",
  "messages": [...],
  "stream": true,
  "tags": { "intent": "code", "project": "grim", "latency": "low", "budget": "frugal", "size_hint": "small" }
}


Read back X-OMEN-Trace-* response headers (if enabled) and store into routing_trace for observability.
