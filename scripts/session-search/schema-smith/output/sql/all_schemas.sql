-- ========================================

-- UNIFIED CROSS-SCHEMA SQL GENERATION

-- ========================================

-- Total schemas: 2

-- Total tables: 8

-- ========================================

-- STEP 2: CREATE ALL SCHEMAS

-- ========================================

CREATE SCHEMA IF NOT EXISTS lessons;

CREATE SCHEMA IF NOT EXISTS session_index;

-- ========================================

-- STEP 2.5: CREATE ENUM TYPES

-- ========================================

CREATE TYPE lessons.lesson_tier AS ENUM ('recent', 'key', 'historical');

COMMENT ON TYPE lessons.lesson_tier IS 'Lifecycle stage: recent (new, under review), key (validated, eligible for surfacing), historical (archived, searchable only)';

CREATE TYPE lessons.tag_status AS ENUM ('active', 'deprecated', 'merged');

COMMENT ON TYPE lessons.tag_status IS 'Tag lifecycle: active (in use), deprecated (being phased out), merged (consolidated into another tag)';

CREATE TYPE session_index.event_type AS ENUM ('user', 'assistant', 'tool_use', 'tool_result', 'progress', 'skill');

COMMENT ON TYPE session_index.event_type IS 'Type of event in the session timeline';

CREATE TYPE session_index.action_type AS ENUM ('command', 'file_change', 'file_read', 'search', 'glob', 'web', 'agent', 'skill');

COMMENT ON TYPE session_index.action_type IS 'Subcategory for tool_use events — maps tool name to semantic action';

-- ========================================

-- STEP 3: CREATE ALL TABLES

-- ========================================

-- SCHEMA: lessons

-- Definition for table lessons.metadata
-- Key-value store for system state — last manage-lessons run, config, thresholds
CREATE TABLE IF NOT EXISTS lessons.metadata (
    "key" VARCHAR(64) PRIMARY KEY,
    "value" TEXT NOT NULL,
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

COMMENT ON TABLE lessons.metadata IS 'Key-value store for system state — last manage-lessons run, config, thresholds';

COMMENT ON COLUMN lessons.metadata."key" IS 'Setting key (e.g. ''last_manage_run'', ''nudge_threshold_days'')';

COMMENT ON COLUMN lessons.metadata."value" IS 'Setting value (ISO date, number, etc. — app interprets)';

COMMENT ON COLUMN lessons.metadata."updated_at" IS 'When this key was last written';

-- Definition for table lessons.projects
-- Project dimension — same pattern as session-index.db
CREATE TABLE IF NOT EXISTS lessons.projects (
    "id" BIGSERIAL PRIMARY KEY,
    "name" VARCHAR(128) NOT NULL,
    CONSTRAINT uq_projects_name UNIQUE ("name")
);

COMMENT ON TABLE lessons.projects IS 'Project dimension — same pattern as session-index.db';

COMMENT ON COLUMN lessons.projects."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN lessons.projects."name" IS 'Project name (git root basename, e.g. ''claude-toolkit'')';

-- Definition for table lessons.tags
-- Tag registry — canonical tags with quality tracking. Prevents tag sprawl, enables synonym resolution and hook keyword mapping.
CREATE TABLE IF NOT EXISTS lessons.tags (
    "id" BIGSERIAL PRIMARY KEY,
    "name" VARCHAR(64) NOT NULL,
    "status" lessons.tag_status DEFAULT 'active' NOT NULL,
    "merged_into_id" BIGINT,
    "keywords" TEXT,
    "description" TEXT,
    "lesson_count" INTEGER DEFAULT 0 NOT NULL,
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_tags_merged_into_id_tags_id FOREIGN KEY ("merged_into_id")
        REFERENCES lessons.tags("id") ON DELETE SET NULL,
    CONSTRAINT uq_tags_name UNIQUE ("name")
);

COMMENT ON TABLE lessons.tags IS 'Tag registry — canonical tags with quality tracking. Prevents tag sprawl, enables synonym resolution and hook keyword mapping.';

COMMENT ON COLUMN lessons.tags."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN lessons.tags."name" IS 'Canonical tag name (e.g. ''git'', ''commit'', ''skills'')';

COMMENT ON COLUMN lessons.tags."status" IS 'Tag lifecycle status';

COMMENT ON COLUMN lessons.tags."merged_into_id" IS 'If status=merged, points to the tag this was consolidated into';

COMMENT ON COLUMN lessons.tags."keywords" IS 'Comma-separated hook keywords that map to this tag (e.g. ''git,push,pull,merge,rebase,branch'' for tag ''git'')';

COMMENT ON COLUMN lessons.tags."description" IS 'What this tag covers — helps manage-lessons decide tagging';

COMMENT ON COLUMN lessons.tags."lesson_count" IS 'Number of active lessons with this tag (maintained by triggers or app logic)';

CREATE INDEX IF NOT EXISTS idx_tags_status ON lessons.tags ("status");

-- Definition for table lessons.lessons
-- One row per captured lesson
CREATE TABLE IF NOT EXISTS lessons.lessons (
    "id" VARCHAR(64) PRIMARY KEY,
    "project_id" BIGINT NOT NULL,
    "date" VARCHAR(10) NOT NULL,
    "tier" lessons.lesson_tier DEFAULT 'recent' NOT NULL,
    "active" BOOLEAN DEFAULT TRUE NOT NULL,
    "text" TEXT NOT NULL,
    "branch" VARCHAR(256),
    "crystallized_from" TEXT,
    "absorbed_into" VARCHAR(256),
    "promoted" VARCHAR(10),
    "archived" VARCHAR(10),
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_lessons_project_id_projects_id FOREIGN KEY ("project_id")
        REFERENCES lessons.projects("id") ON DELETE RESTRICT
);

COMMENT ON TABLE lessons.lessons IS 'One row per captured lesson';

COMMENT ON COLUMN lessons.lessons."id" IS 'Unique ID: {project}_{YYYYMMDD}T{HHMM}_{NNN}';

COMMENT ON COLUMN lessons.lessons."project_id" IS 'FK to projects dimension';

COMMENT ON COLUMN lessons.lessons."date" IS 'Capture date (YYYY-MM-DD)';

COMMENT ON COLUMN lessons.lessons."tier" IS 'Lifecycle stage — promotion/archival track';

COMMENT ON COLUMN lessons.lessons."active" IS 'Whether this lesson is eligible for contextual surfacing. Active = loaded when tags match. Inactive = searchable only.';

COMMENT ON COLUMN lessons.lessons."text" IS 'One-line actionable rule — the lesson itself';

COMMENT ON COLUMN lessons.lessons."branch" IS 'Git branch at capture time';

COMMENT ON COLUMN lessons.lessons."crystallized_from" IS 'Comma-separated lesson IDs this was crystallized from — null for original lessons';

COMMENT ON COLUMN lessons.lessons."absorbed_into" IS 'Resource that absorbed this lesson (e.g. ''hook:git-safety'', ''skill:learn'', ''memory:essential-conventions-code_style'', ''claude.md''). Set when lesson graduates out of the system.';

COMMENT ON COLUMN lessons.lessons."promoted" IS 'Date when promoted to key tier (YYYY-MM-DD)';

COMMENT ON COLUMN lessons.lessons."archived" IS 'Date when archived to historical tier (YYYY-MM-DD)';

COMMENT ON COLUMN lessons.lessons."created_at" IS 'When the lesson was inserted';

CREATE INDEX IF NOT EXISTS idx_lessons_project ON lessons.lessons ("project_id");

CREATE INDEX IF NOT EXISTS idx_lessons_active_tier ON lessons.lessons ("active", "tier");

CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons.lessons ("date");

-- Definition for table lessons.lesson_tags
-- Junction table — which tags apply to which lessons
CREATE TABLE IF NOT EXISTS lessons.lesson_tags (
    "id" BIGSERIAL PRIMARY KEY,
    "lesson_id" VARCHAR(64) NOT NULL,
    "tag_id" BIGINT NOT NULL,
    CONSTRAINT fk_lesson_tags_lesson_id_lessons_id FOREIGN KEY ("lesson_id")
        REFERENCES lessons.lessons("id") ON DELETE CASCADE,
    CONSTRAINT fk_lesson_tags_tag_id_tags_id FOREIGN KEY ("tag_id")
        REFERENCES lessons.tags("id") ON DELETE RESTRICT
);

COMMENT ON TABLE lessons.lesson_tags IS 'Junction table — which tags apply to which lessons';

COMMENT ON COLUMN lessons.lesson_tags."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN lessons.lesson_tags."lesson_id" IS 'FK to lessons';

COMMENT ON COLUMN lessons.lesson_tags."tag_id" IS 'FK to tags registry';

CREATE UNIQUE INDEX IF NOT EXISTS idx_lesson_tags_unique ON lessons.lesson_tags ("lesson_id", "tag_id");

CREATE INDEX IF NOT EXISTS idx_lesson_tags_tag ON lessons.lesson_tags ("tag_id");

-- SCHEMA: session_index

-- Definition for table session_index.projects
-- Dimension table for project identity
CREATE TABLE IF NOT EXISTS session_index.projects (
    "id" BIGSERIAL PRIMARY KEY,
    "name" VARCHAR(128) NOT NULL,
    "dir_name" TEXT NOT NULL,
    "project_path" TEXT,
    "session_count" INTEGER DEFAULT 0,
    "first_seen" TIMESTAMP WITH TIME ZONE,
    "last_seen" TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_projects_name UNIQUE ("name")
);

COMMENT ON TABLE session_index.projects IS 'Dimension table for project identity';

COMMENT ON COLUMN session_index.projects."id" IS 'Auto-incrementing primary key';

COMMENT ON COLUMN session_index.projects."name" IS 'Human-readable project name (extracted from encoded dir)';

COMMENT ON COLUMN session_index.projects."dir_name" IS 'Encoded directory name (e.g. -home-hata-projects-personal-claude-toolkit)';

COMMENT ON COLUMN session_index.projects."project_path" IS 'Absolute filesystem path to the project directory (from JSONL cwd field)';

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
