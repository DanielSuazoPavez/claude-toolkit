#!/usr/bin/env python3
"""Lessons database — SQLite storage for cross-project actionable rules.

Provides database initialization, CRUD helpers, and CLI for managing
lessons captured across Claude Code sessions.

Schema design: scripts/session-search/schema-smith/schemas/lessons.yaml

Usage:
    uv run scripts/lesson_db.py migrate [--json-path PATH]
    uv run scripts/lesson_db.py add --text TEXT --tags t1,t2 [--project NAME] [--branch B]
    uv run scripts/lesson_db.py search <query> [--limit N]
    uv run scripts/lesson_db.py list [--tier T] [--active] [--tags t1,t2] [--project P]
    uv run scripts/lesson_db.py summary
    uv run scripts/lesson_db.py set-meta KEY VALUE
"""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from session_db import _c  # noqa: E402

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

LESSONS_DB_PATH = Path.home() / ".claude" / "lessons.db"
LEARNED_JSON_PATH = Path(".claude/learned.json")

# ---------------------------------------------------------------------------
# Schema initialization
# ---------------------------------------------------------------------------

INIT_SQL = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS tags (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK(status IN ('active', 'deprecated', 'merged')),
    merged_into_id  INTEGER REFERENCES tags(id) ON DELETE SET NULL,
    keywords        TEXT,
    description     TEXT,
    lesson_count    INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_tags_status ON tags(status);

CREATE TABLE IF NOT EXISTS lessons (
    id                  TEXT PRIMARY KEY,
    project_id          INTEGER NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    date                TEXT NOT NULL,
    tier                TEXT NOT NULL DEFAULT 'recent'
                            CHECK(tier IN ('recent', 'key', 'historical')),
    active              INTEGER NOT NULL DEFAULT 1,
    text                TEXT NOT NULL,
    branch              TEXT,
    crystallized_from   TEXT,
    absorbed_into       TEXT,
    promoted            TEXT,
    archived            TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_lessons_project ON lessons(project_id);
CREATE INDEX IF NOT EXISTS idx_lessons_active_tier ON lessons(active, tier);
CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons(date);

CREATE TABLE IF NOT EXISTS metadata (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS lesson_tags (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    lesson_id   TEXT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
    UNIQUE(lesson_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_lesson_tags_tag ON lesson_tags(tag_id);

-- FTS5 for full-text search over lesson text
CREATE VIRTUAL TABLE IF NOT EXISTS lessons_fts USING fts5(
    text,
    content=lessons,
    content_rowid=rowid,
    tokenize="unicode61 tokenchars '-_./~'"
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS lessons_fts_ai AFTER INSERT ON lessons BEGIN
    INSERT INTO lessons_fts(rowid, text) VALUES (new.rowid, new.text);
END;
CREATE TRIGGER IF NOT EXISTS lessons_fts_ad AFTER DELETE ON lessons BEGIN
    INSERT INTO lessons_fts(lessons_fts, rowid, text)
    VALUES('delete', old.rowid, old.text);
END;
CREATE TRIGGER IF NOT EXISTS lessons_fts_au AFTER UPDATE ON lessons BEGIN
    INSERT INTO lessons_fts(lessons_fts, rowid, text)
    VALUES('delete', old.rowid, old.text);
    INSERT INTO lessons_fts(rowid, text) VALUES (new.rowid, new.text);
END;
"""


def init_lessons_db(db_path: Path = LESSONS_DB_PATH) -> sqlite3.Connection:
    """Create or open the lessons database and ensure schema exists."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.executescript(INIT_SQL)
    return conn


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")


def get_or_create_project(conn: sqlite3.Connection, name: str) -> int:
    """Return project id, creating if needed."""
    row = conn.execute(
        "SELECT id FROM projects WHERE name = ?", (name,)
    ).fetchone()
    if row:
        return row[0]
    cur = conn.execute("INSERT INTO projects (name) VALUES (?)", (name,))
    conn.commit()
    return cur.lastrowid  # type: ignore[return-value]


def get_or_create_tag(
    conn: sqlite3.Connection,
    name: str,
    *,
    keywords: str | None = None,
    description: str | None = None,
) -> int:
    """Return tag id, creating if needed. Updates keywords/description if provided."""
    row = conn.execute(
        "SELECT id FROM tags WHERE name = ?", (name,)
    ).fetchone()
    if row:
        tag_id = row[0]
        updates = {}
        if keywords is not None:
            updates["keywords"] = keywords
        if description is not None:
            updates["description"] = description
        if updates:
            sets = ", ".join(f"{k} = ?" for k in updates)
            conn.execute(
                f"UPDATE tags SET {sets} WHERE id = ?",  # noqa: S608
                [*updates.values(), tag_id],
            )
            conn.commit()
        return tag_id
    cur = conn.execute(
        "INSERT INTO tags (name, keywords, description) VALUES (?, ?, ?)",
        (name, keywords, description),
    )
    conn.commit()
    return cur.lastrowid  # type: ignore[return-value]


def tag_lesson(
    conn: sqlite3.Connection, lesson_id: str, tag_ids: list[int]
) -> None:
    """Attach tags to a lesson and update tag counts."""
    for tag_id in tag_ids:
        conn.execute(
            "INSERT OR IGNORE INTO lesson_tags (lesson_id, tag_id) VALUES (?, ?)",
            (lesson_id, tag_id),
        )
    conn.commit()
    _refresh_tag_counts(conn, tag_ids)


def _refresh_tag_counts(
    conn: sqlite3.Connection, tag_ids: list[int] | None = None
) -> None:
    """Recompute lesson_count for given tags (or all if None)."""
    if tag_ids:
        placeholders = ",".join("?" for _ in tag_ids)
        conn.execute(
            f"""UPDATE tags SET lesson_count = (
                SELECT COUNT(*) FROM lesson_tags lt
                JOIN lessons l ON lt.lesson_id = l.id
                WHERE lt.tag_id = tags.id AND l.active = 1
            ) WHERE id IN ({placeholders})""",
            tag_ids,
        )
    else:
        conn.execute(
            """UPDATE tags SET lesson_count = (
                SELECT COUNT(*) FROM lesson_tags lt
                JOIN lessons l ON lt.lesson_id = l.id
                WHERE lt.tag_id = tags.id AND l.active = 1
            )"""
        )
    conn.commit()


def insert_lesson(
    conn: sqlite3.Connection,
    *,
    lesson_id: str,
    project_name: str,
    date: str,
    text: str,
    tag_names: list[str],
    tier: str = "recent",
    active: bool = True,
    branch: str | None = None,
    crystallized_from: str | None = None,
    promoted: str | None = None,
    archived: str | None = None,
) -> str:
    """Insert a lesson with project and tags. Returns the lesson id."""
    project_id = get_or_create_project(conn, project_name)
    conn.execute(
        """INSERT INTO lessons
           (id, project_id, date, tier, active, text, branch,
            crystallized_from, promoted, archived)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            lesson_id,
            project_id,
            date,
            tier,
            1 if active else 0,
            text,
            branch,
            crystallized_from,
            promoted,
            archived,
        ),
    )
    conn.commit()

    tag_ids = [get_or_create_tag(conn, name) for name in tag_names]
    tag_lesson(conn, lesson_id, tag_ids)

    return lesson_id


def update_lesson(
    conn: sqlite3.Connection, lesson_id: str, **fields: str | int | None
) -> None:
    """Update lesson fields by id."""
    allowed = {
        "tier", "active", "text", "branch", "crystallized_from",
        "absorbed_into", "promoted", "archived",
    }
    to_set = {k: v for k, v in fields.items() if k in allowed}
    if not to_set:
        return
    sets = ", ".join(f"{k} = ?" for k in to_set)
    conn.execute(
        f"UPDATE lessons SET {sets} WHERE id = ?",  # noqa: S608
        [*to_set.values(), lesson_id],
    )
    conn.commit()
    # Refresh tag counts if active status changed
    if "active" in to_set:
        _refresh_tag_counts(conn)


def set_metadata(conn: sqlite3.Connection, key: str, value: str) -> None:
    """Upsert a metadata key-value pair."""
    conn.execute(
        """INSERT INTO metadata (key, value, updated_at) VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value,
           updated_at = excluded.updated_at""",
        (key, value, _now_iso()),
    )
    conn.commit()


def get_metadata(conn: sqlite3.Connection, key: str) -> str | None:
    """Get a metadata value by key, or None if not set."""
    row = conn.execute(
        "SELECT value FROM metadata WHERE key = ?", (key,)
    ).fetchone()
    return row[0] if row else None
