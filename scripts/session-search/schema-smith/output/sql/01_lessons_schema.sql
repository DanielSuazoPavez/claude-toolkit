-- ========================================

-- SCHEMA: lessons

-- ========================================

-- Schema creation order: 1

CREATE SCHEMA IF NOT EXISTS lessons;

CREATE TYPE lessons.lesson_tier AS ENUM ('recent', 'key', 'historical');

COMMENT ON TYPE lessons.lesson_tier IS 'Lifecycle stage: recent (new, under review), key (validated, eligible for surfacing), historical (archived, searchable only)';

CREATE TYPE lessons.tag_status AS ENUM ('active', 'deprecated', 'merged');

COMMENT ON TYPE lessons.tag_status IS 'Tag lifecycle: active (in use), deprecated (being phased out), merged (consolidated into another tag)';

-- Table: lessons.metadata

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

-- Table: lessons.projects

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

-- Table: lessons.tags

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

-- Table: lessons.lessons

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

-- Table: lessons.lesson_tags

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
