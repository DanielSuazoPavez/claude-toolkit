#!/usr/bin/env python3
"""Shared utilities for the session tools (index, search, analytics).

Provides database initialization, formatting helpers, and transcript
file discovery used across session_index, session_search, and session_analytics.
"""

from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path
from typing import Iterator

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DB_PATH = Path.home() / ".claude" / "session-index.db"

DEFAULT_TRANSCRIPTS_DIR = Path.home() / ".claude" / "projects"
BACKUP_TRANSCRIPTS_DIR = Path.home() / "backups" / "claude-transcripts"

# Regex to strip encoded path prefix and worktree suffix
# e.g. "-home-hata-projects-personal-claude-toolkit--worktrees-feat" -> "claude-toolkit"
PROJECT_PREFIX_RE = re.compile(r"^-home-[^-]+-projects-(?:personal|raiz)-")
WORKTREE_SUFFIX_RE = re.compile(r"--worktrees-.*$")

# ---------------------------------------------------------------------------
# Schema initialization
# ---------------------------------------------------------------------------

INIT_SQL = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    dir_name    TEXT NOT NULL,
    project_path TEXT,
    first_seen  TEXT,
    last_seen   TEXT,
    session_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
    session_id        TEXT PRIMARY KEY,
    project_id        INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    source_dir        TEXT NOT NULL,
    first_ts          TEXT,
    last_ts           TEXT,
    git_branch        TEXT,
    model             TEXT,
    event_count       INTEGER DEFAULT 0,
    input_tokens      INTEGER DEFAULT 0,
    output_tokens     INTEGER DEFAULT 0,
    cache_create_tokens INTEGER DEFAULT 0,
    cache_read_tokens INTEGER DEFAULT 0,
    file_mtime        REAL NOT NULL,
    file_size         INTEGER NOT NULL,
    indexed_at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_sessions_last_ts ON sessions(last_ts);

CREATE TABLE IF NOT EXISTS events (
    id            INTEGER PRIMARY KEY,
    session_id    TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    project_id    INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    seq           INTEGER NOT NULL,
    timestamp     TEXT,
    date          TEXT,
    event_type    TEXT NOT NULL,
    tool          TEXT,
    action_type   TEXT,
    detail        TEXT NOT NULL,
    output_tokens INTEGER DEFAULT 0,
    input_total   INTEGER DEFAULT 0,
    output_total  INTEGER DEFAULT 0,
    subagent_id   TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_project_date ON events(project_id, date);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_action_type ON events(action_type)
    WHERE action_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_session_seq ON events(session_id, seq);
CREATE INDEX IF NOT EXISTS idx_events_boundary ON events(session_id, seq, event_type, action_type)
    WHERE event_type = 'user' AND action_type = 'human';

CREATE TABLE IF NOT EXISTS resource_usage (
    id              INTEGER PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    project_id      INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    resource_type   TEXT NOT NULL,
    resource_name   TEXT NOT NULL,
    timestamp       TEXT,
    input_delta     INTEGER NOT NULL,
    output_delta    INTEGER NOT NULL,
    turn_count      INTEGER NOT NULL,
    end_reason      TEXT,
    files_written   TEXT
);
CREATE INDEX IF NOT EXISTS idx_resource_usage_name
    ON resource_usage(resource_type, resource_name);
CREATE INDEX IF NOT EXISTS idx_resource_usage_session
    ON resource_usage(session_id);

CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
    detail,
    content=events,
    content_rowid=id,
    tokenize="unicode61 tokenchars '-_./~'"
);

-- Triggers to keep FTS in sync with events table
CREATE TRIGGER IF NOT EXISTS events_fts_ai AFTER INSERT ON events BEGIN
    INSERT INTO events_fts(rowid, detail) VALUES (new.id, new.detail);
END;
CREATE TRIGGER IF NOT EXISTS events_fts_ad AFTER DELETE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, detail)
    VALUES('delete', old.id, old.detail);
END;
CREATE TRIGGER IF NOT EXISTS events_fts_au AFTER UPDATE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, detail)
    VALUES('delete', old.id, old.detail);
    INSERT INTO events_fts(rowid, detail) VALUES (new.id, new.detail);
END;
"""


def init_db(db_path: Path = DB_PATH) -> sqlite3.Connection:
    """Create or open the database and ensure schema exists."""
    conn = sqlite3.connect(str(db_path))
    conn.executescript(INIT_SQL)
    return conn


# ---------------------------------------------------------------------------
# Transcript file discovery
# ---------------------------------------------------------------------------


def extract_project_name(dir_name: str) -> str:
    """Extract human-readable project name from encoded directory name."""
    name = PROJECT_PREFIX_RE.sub("", dir_name)
    name = WORKTREE_SUFFIX_RE.sub("", name)
    # If prefix didn't match (e.g. "-home-hata-projects"), use the full dir after last known segment
    if name == dir_name:
        # Fallback: just strip leading dashes
        name = dir_name.lstrip("-")
    return name


def find_session_files(
    project_filter: str | None = None,
    transcripts_dir: Path = DEFAULT_TRANSCRIPTS_DIR,
) -> Iterator[Path]:
    """Yield all .jsonl session files, optionally filtered by project substring."""
    if not transcripts_dir.is_dir():
        return
    for project_dir in sorted(transcripts_dir.iterdir()):
        if not project_dir.is_dir():
            continue
        if project_filter:
            proj_name = extract_project_name(project_dir.name)
            if project_filter.lower() not in proj_name.lower():
                continue
        for jsonl_file in sorted(project_dir.glob("*.jsonl")):
            yield jsonl_file


# ---------------------------------------------------------------------------
# Output formatting (re-exported from shared)
# ---------------------------------------------------------------------------

sys.path.insert(0, str(Path(__file__).parent.parent / "shared"))
from formatting import _c, _fmt_tokens  # noqa: E402, F401
