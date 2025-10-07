-- Routing tables - track preferences, decisions, and performance
-- Path: db/migrations/0002_routing_core.sql

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- Routing preferences per project/context
CREATE TABLE IF NOT EXISTS routing_prefs (
  project TEXT PRIMARY KEY,               -- Project identifier (cwd hash or name)
  prefer_local INTEGER NOT NULL DEFAULT 1, -- 1=prefer local, 0=cloud-first
  max_cloud_cost_cents INTEGER DEFAULT 200, -- Monthly budget in cents
  last_alias TEXT,                        -- Last used alias (e.g., "code-fast")
  last_model TEXT,                        -- Last used model ID
  escalation_threshold TEXT DEFAULT 'medium', -- 'low', 'medium', 'high'
  updated_at INTEGER NOT NULL             -- Unix timestamp
);

-- Routing decisions log - every AI request records here
CREATE TABLE IF NOT EXISTS routing_stats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT,                        -- UUID for correlation
  project TEXT NOT NULL,                  -- Project identifier
  alias TEXT,                             -- Alias used (e.g., "code-fast")
  model TEXT,                             -- Actual model ID
  provider TEXT,                          -- "ollama", "anthropic", etc.
  intent TEXT,                            -- "code", "reason", "completion"
  size_hint TEXT,                         -- "tiny", "small", "medium", "large"
  latency_ms INTEGER,                     -- Time to first token
  total_duration_ms INTEGER,              -- Total request time
  tokens_in INTEGER,                      -- Input tokens
  tokens_out INTEGER,                     -- Output tokens
  cost_cents REAL DEFAULT 0.0,            -- Calculated cost
  success INTEGER NOT NULL DEFAULT 1,     -- 1=success, 0=failure
  error_code TEXT,                        -- Error code if failed
  escalated INTEGER DEFAULT 0,            -- 1=escalated to cloud
  created_at INTEGER NOT NULL             -- Unix timestamp
);

-- Routing trace - stores detailed routing decisions from OMEN
CREATE TABLE IF NOT EXISTS routing_trace (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,               -- Correlates to routing_stats.request_id
  project TEXT,                           -- Project identifier
  trace TEXT,                             -- JSON blob from X-OMEN-Trace-* headers
  decision_reason TEXT,                   -- Human-readable explanation
  candidates TEXT,                        -- JSON: [{"model": "...", "score": 0.9}]
  created_at INTEGER NOT NULL             -- Unix timestamp
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_stats_project_time
  ON routing_stats(project, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stats_model
  ON routing_stats(model);
CREATE INDEX IF NOT EXISTS idx_stats_provider
  ON routing_stats(provider);
CREATE INDEX IF NOT EXISTS idx_stats_request_id
  ON routing_stats(request_id);
CREATE INDEX IF NOT EXISTS idx_trace_request_id
  ON routing_trace(request_id);
CREATE INDEX IF NOT EXISTS idx_trace_project_time
  ON routing_trace(project, created_at DESC);
