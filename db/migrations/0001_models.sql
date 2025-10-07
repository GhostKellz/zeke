-- Models table - cache available models from all providers
-- Populated by `zeke doctor` and refreshed periodically
-- Path: db/migrations/0001_models.sql

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS models (
  id TEXT PRIMARY KEY,                    -- e.g., "ollama:deepseek-coder:33b"
  provider TEXT NOT NULL,                 -- "ollama", "anthropic", "openai", "azure"
  name TEXT NOT NULL,                     -- "deepseek-coder:33b"
  display_name TEXT,                      -- Human-friendly name
  family TEXT,                            -- "llama", "qwen2", "claude", etc.
  parameter_size TEXT,                    -- "33B", "8.0B", etc.
  quantization TEXT,                      -- "Q4_0", "Q4_K_M", null for cloud
  context_length INTEGER DEFAULT 4096,    -- Max context window
  capabilities TEXT,                      -- JSON: ["code", "chat", "vision", "tools"]
  cost_per_1k_tokens_in REAL DEFAULT 0.0, -- For cloud models
  cost_per_1k_tokens_out REAL DEFAULT 0.0,
  latency_avg_ms INTEGER,                 -- Rolling average from routing_stats
  success_rate REAL DEFAULT 1.0,          -- 0.0-1.0
  available INTEGER NOT NULL DEFAULT 1,   -- 0=offline, 1=online
  last_checked INTEGER NOT NULL,          -- Unix timestamp
  metadata TEXT                           -- JSON blob for extra data
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_models_provider ON models(provider);
CREATE INDEX IF NOT EXISTS idx_models_available ON models(available, provider);
CREATE INDEX IF NOT EXISTS idx_models_family ON models(family);
