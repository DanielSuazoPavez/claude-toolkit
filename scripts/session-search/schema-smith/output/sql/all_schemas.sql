-- ========================================

-- UNIFIED CROSS-SCHEMA SQL GENERATION

-- ========================================

-- Total schemas: 1

-- Total tables: 3

-- ========================================

-- STEP 2: CREATE ALL SCHEMAS

-- ========================================

CREATE SCHEMA IF NOT EXISTS session_index;

-- ========================================

-- STEP 2.5: CREATE ENUM TYPES

-- ========================================

CREATE TYPE session_index.event_type AS ENUM ('user', 'assistant', 'tool_use', 'tool_result', 'progress', 'skill');

COMMENT ON TYPE session_index.event_type IS 'Type of event in the session timeline';

CREATE TYPE session_index.action_type AS ENUM ('command', 'file_change', 'file_read', 'search', 'glob', 'web', 'agent', 'skill');

COMMENT ON TYPE session_index.action_type IS 'Subcategory for tool_use events — maps tool name to semantic action';

-- ========================================

-- STEP 3: CREATE ALL TABLES

-- ========================================

-- SCHEMA: session_index

-- Definition for table session_index.projects
-- Dimension table for project identity
CREATE TABLE IF NOT EXISTS session_index.projects (
    "id" BIGSERIAL PRIMARY KEY,
    "name" VARCHAR(128) NOT NULL,
    "dir_name" TEXT NOT NULL,
    "session_count" INTEGER DEFAULT 0,
    "first_seen" TIMESTAMP WITH TIME ZONE,
    "last_seen" TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_projects_name UNIQUE ("name")
);

COMMENT ON TABLE session_index.projects IS 'Dimension table for project identity';

COMMENT ON COLUMN session_index.projects."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN session_index.projects."name" IS 'Human-readable project name (extracted from encoded dir)';

COMMENT ON COLUMN session_index.projects."dir_name" IS 'Encoded directory name (e.g. -home-hata-projects-personal-claude-toolkit)';

COMMENT ON COLUMN session_index.projects."session_count" IS 'Number of sessions for this project (maintained during indexing)';

COMMENT ON COLUMN session_index.projects."first_seen" IS 'Earliest observed timestamp';

COMMENT ON COLUMN session_index.projects."last_seen" IS 'Latest observed timestamp';

-- Definition for table session_index.sessions
-- One row per Claude Code session (identified by UUID)
CREATE TABLE IF NOT EXISTS session_index.sessions (
    "session_id" VARCHAR(36) PRIMARY KEY,
    "project_id" BIGINT NOT NULL,
    "source_dir" TEXT NOT NULL,
    "first_ts" TIMESTAMP WITH TIME ZONE,
    "last_ts" TIMESTAMP WITH TIME ZONE,
    "git_branch" VARCHAR(256),
    "model" VARCHAR(64),
    "event_count" INTEGER DEFAULT 0,
    "input_tokens" INTEGER DEFAULT 0,
    "output_tokens" INTEGER DEFAULT 0,
    "cache_create_tokens" INTEGER DEFAULT 0,
    "cache_read_tokens" INTEGER DEFAULT 0,
    "file_mtime" DOUBLE PRECISION NOT NULL,
    "file_size" INTEGER NOT NULL,
    "indexed_at" TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT fk_sessions_project_id_projects_id FOREIGN KEY ("project_id")
        REFERENCES session_index.projects("id") ON DELETE RESTRICT
);

COMMENT ON TABLE session_index.sessions IS 'One row per Claude Code session (identified by UUID)';

COMMENT ON COLUMN session_index.sessions."session_id" IS 'UUID from JSONL filename';

COMMENT ON COLUMN session_index.sessions."project_id" IS 'FK to projects dimension';

COMMENT ON COLUMN session_index.sessions."source_dir" IS 'Source directory path (backup or live)';

COMMENT ON COLUMN session_index.sessions."first_ts" IS 'Earliest timestamp in session';

COMMENT ON COLUMN session_index.sessions."last_ts" IS 'Latest timestamp in session';

COMMENT ON COLUMN session_index.sessions."git_branch" IS 'Git branch at session start';

COMMENT ON COLUMN session_index.sessions."model" IS 'Claude model used (e.g. claude-opus-4-6)';

COMMENT ON COLUMN session_index.sessions."event_count" IS 'Total events indexed for this session';

COMMENT ON COLUMN session_index.sessions."input_tokens" IS 'Total input tokens consumed';

COMMENT ON COLUMN session_index.sessions."output_tokens" IS 'Total output tokens generated';

COMMENT ON COLUMN session_index.sessions."cache_create_tokens" IS 'Total cache creation input tokens';

COMMENT ON COLUMN session_index.sessions."cache_read_tokens" IS 'Total cache read input tokens';

COMMENT ON COLUMN session_index.sessions."file_mtime" IS 'Source file mtime at indexing time (for incremental updates)';

COMMENT ON COLUMN session_index.sessions."file_size" IS 'Source file size at indexing time (for incremental updates)';

COMMENT ON COLUMN session_index.sessions."indexed_at" IS 'When this session was last indexed';

CREATE INDEX IF NOT EXISTS idx_sessions_last_ts ON session_index.sessions ("last_ts");

-- Auto-generated foreign_key index
CREATE INDEX IF NOT EXISTS idx_fk_sessions_project_id_projects_id ON session_index.sessions ("project_id");

-- Definition for table session_index.events
-- Full session timeline — every JSONL record becomes an event row
CREATE TABLE IF NOT EXISTS session_index.events (
    "id" BIGSERIAL PRIMARY KEY,
    "session_id" VARCHAR(36) NOT NULL,
    "project_id" BIGINT NOT NULL,
    "seq" INTEGER NOT NULL,
    "timestamp" TIMESTAMP WITH TIME ZONE,
    "date" VARCHAR(10),
    "event_type" session_index.event_type NOT NULL,
    "tool" VARCHAR(32),
    "action_type" session_index.action_type,
    "detail" TEXT NOT NULL,
    "output_tokens" INTEGER DEFAULT 0,
    "subagent_id" VARCHAR(64),
    CONSTRAINT fk_events_session_id_sessions_session_id FOREIGN KEY ("session_id")
        REFERENCES session_index.sessions("session_id") ON DELETE CASCADE,
    CONSTRAINT fk_events_project_id_projects_id FOREIGN KEY ("project_id")
        REFERENCES session_index.projects("id") ON DELETE RESTRICT
);

COMMENT ON TABLE session_index.events IS 'Full session timeline — every JSONL record becomes an event row';

COMMENT ON COLUMN session_index.events."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN session_index.events."session_id" IS 'FK to sessions';

COMMENT ON COLUMN session_index.events."project_id" IS 'FK to projects (denormalized for query performance)';

COMMENT ON COLUMN session_index.events."seq" IS 'Ordering within session (line number in JSONL)';

COMMENT ON COLUMN session_index.events."timestamp" IS 'Event timestamp from JSONL record';

COMMENT ON COLUMN session_index.events."date" IS 'YYYY-MM-DD extracted from timestamp for range filtering';

COMMENT ON COLUMN session_index.events."event_type" IS 'Category of event (user, assistant, tool_use, etc.)';

COMMENT ON COLUMN session_index.events."tool" IS 'Tool name for tool_use events (Bash, Read, Write, etc.)';

COMMENT ON COLUMN session_index.events."action_type" IS 'Semantic action for tool_use events (command, file_change, etc.)';

COMMENT ON COLUMN session_index.events."detail" IS 'Searchable content — command, file path, message text, etc.';

COMMENT ON COLUMN session_index.events."output_tokens" IS 'Output tokens for this turn; proportionally attributed for tool_use events';

COMMENT ON COLUMN session_index.events."subagent_id" IS 'Non-null for events from subagent transcripts';

CREATE INDEX IF NOT EXISTS idx_events_project_date ON session_index.events ("project_id", "date");

CREATE INDEX IF NOT EXISTS idx_events_event_type ON session_index.events ("event_type");

CREATE INDEX IF NOT EXISTS idx_events_action_type ON session_index.events ("action_type") WHERE action_type IS NOT NULL;

-- Auto-generated foreign_key index
CREATE INDEX IF NOT EXISTS idx_fk_events_session_id_sessions_session_id ON session_index.events ("session_id");
