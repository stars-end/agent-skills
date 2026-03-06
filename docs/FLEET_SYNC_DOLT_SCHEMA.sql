-- Fleet Sync V2.1 optional Dolt control schema
-- Scope: small control tables only (no embeddings/raw transcripts).

CREATE TABLE IF NOT EXISTS mcp_tool_manifest (
  tool_name VARCHAR(64) PRIMARY KEY,
  version VARCHAR(32) NOT NULL,
  install_cmd TEXT NOT NULL,
  health_cmd TEXT,
  config_schema_version INT DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_by VARCHAR(64)
);

CREATE TABLE IF NOT EXISTS tool_health (
  vm_id VARCHAR(32) NOT NULL,
  tool_name VARCHAR(64) NOT NULL,
  expected_version VARCHAR(32),
  detected_version VARCHAR(32),
  healthy BOOLEAN DEFAULT FALSE,
  last_ok TIMESTAMP NULL,
  last_fail TIMESTAMP NULL,
  error_summary VARCHAR(256),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (vm_id, tool_name)
);

CREATE TABLE IF NOT EXISTS memory_digest (
  digest_hash VARCHAR(64) PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  vm_id VARCHAR(32) NOT NULL,
  repo_scope VARCHAR(128) NOT NULL,
  summary TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ttl_expires TIMESTAMP NOT NULL,
  INDEX idx_memory_digest_scope (repo_scope),
  INDEX idx_memory_digest_ttl (ttl_expires)
);

-- Operational retention example (run via cron/systemd timer):
-- DELETE FROM memory_digest WHERE ttl_expires < NOW();
