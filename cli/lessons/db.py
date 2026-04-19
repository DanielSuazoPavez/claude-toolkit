#!/usr/bin/env python3
"""Lessons database — SQLite storage for cross-project actionable rules.

Provides database initialization, CRUD helpers, and CLI for managing
lessons captured across Claude Code sessions.

Schema design: canonical yaml lives in claude-sessions/schemas/lessons.yaml
(ownership moved in claude-sessions v0.19.0 / claude-toolkit v2.59.3; toolkit
retains INIT_SQL for runtime bootstrap — it must stay byte-compatible with
the yaml).

Usage:
    claude-toolkit lessons migrate [--json-path PATH]
    claude-toolkit lessons add --text TEXT --tags t1,t2 [--project NAME] [--branch B] [--scope global|project]
    claude-toolkit lessons search <query> [--limit N]
    claude-toolkit lessons list [--tier T] [--active] [--tags t1,t2] [--project P]
    claude-toolkit lessons summary
    claude-toolkit lessons set-meta KEY VALUE
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from cli.lessons.formatting import _c

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
    scope               TEXT NOT NULL DEFAULT 'global'
                            CHECK(scope IN ('global', 'project')),
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
CREATE INDEX IF NOT EXISTS idx_lessons_scope ON lessons(scope);

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
    scope: str = "global",
) -> str:
    """Insert a lesson with project and tags. Returns the lesson id."""
    project_id = get_or_create_project(conn, project_name)
    conn.execute(
        """INSERT INTO lessons
           (id, project_id, date, tier, active, scope, text, branch,
            crystallized_from, promoted, archived)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            lesson_id,
            project_id,
            date,
            tier,
            1 if active else 0,
            scope,
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
        "absorbed_into", "promoted", "archived", "scope",
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


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

# Seed tags: old category -> (tag_name, keywords, description)
CATEGORY_TAG_MAP = {
    "correction": ("correction", "correction,mistake,wrong,error,fix", "Claude did something wrong, user corrected it"),
    "pattern": ("pattern", "pattern,approach,idiom,workflow", "Recurring approach or idiom"),
    "convention": ("convention", "convention,naming,style,structure,format", "Project-specific rule"),
    "gotcha": ("gotcha", "gotcha,trap,edge-case,surprising,unexpected", "Non-obvious behavior or surprising edge case"),
}

# Domain keywords to auto-infer tags from lesson text
DOMAIN_TAG_KEYWORDS = {
    "git": ["git", "commit", "merge", "rebase", "branch", "push", "pull", "checkout"],
    "hooks": ["hook", "PreToolUse", "PostToolUse", "session-start"],
    "skills": ["skill", "/learn", "/manage", "SKILL.md", "auto-trigger"],
    "docs": ["doc", "docs", "CLAUDE.md", "essential-", "relevant-"],
    "permissions": ["permission", "allowed-tools", "Bash("],
    "resources": ["MANIFEST", "resource", "sync"],
    "testing": ["test", "pytest", "make check"],
}


def _infer_domain_tags(text: str) -> list[str]:
    """Infer domain tags from lesson text via keyword matching."""
    text_lower = text.lower()
    return [
        tag
        for tag, keywords in DOMAIN_TAG_KEYWORDS.items()
        if any(kw.lower() in text_lower for kw in keywords)
    ]


def cmd_migrate(args: argparse.Namespace) -> None:
    """Migrate lessons from learned.json to lessons.db."""
    json_path = Path(args.json_path)
    if not json_path.exists():
        print(f"Error: {json_path} not found", file=sys.stderr)
        sys.exit(1)

    data = json.loads(json_path.read_text())
    lessons = data.get("lessons", [])
    if not lessons:
        print("No lessons to migrate.")
        return

    conn = init_lessons_db(args.db_path)
    c = _c()

    migrated = 0
    skipped = 0
    tags_created: set[str] = set()

    # Seed category tags
    for cat, (name, keywords, desc) in CATEGORY_TAG_MAP.items():
        get_or_create_tag(conn, name, keywords=keywords, description=desc)
        tags_created.add(name)

    # Seed domain tags
    for tag, keywords in DOMAIN_TAG_KEYWORDS.items():
        get_or_create_tag(
            conn, tag,
            keywords=",".join(keywords),
            description=f"Domain: {tag}",
        )
        tags_created.add(tag)

    for lesson in lessons:
        # Build tag list: category + recurring flag + inferred domain tags
        tag_names: list[str] = []

        # Category -> tag
        cat = lesson.get("category", "")
        if cat in CATEGORY_TAG_MAP:
            tag_names.append(CATEGORY_TAG_MAP[cat][0])

        # Recurring flag -> tag
        flags = lesson.get("flags", [])
        if "recurring" in flags:
            get_or_create_tag(
                conn, "recurring",
                keywords="recurring,repeat,again",
                description="Lesson that keeps coming up",
            )
            tag_names.append("recurring")
            tags_created.add("recurring")

        # Domain tags from text
        tag_names.extend(_infer_domain_tags(lesson["text"]))

        # Deduplicate
        tag_names = list(dict.fromkeys(tag_names))

        active = lesson["tier"] in ("recent", "key")

        # Skip if this lesson ID already exists (idempotent per-lesson)
        if conn.execute("SELECT 1 FROM lessons WHERE id = ?", (lesson["id"],)).fetchone():
            skipped += 1
            continue

        insert_lesson(
            conn,
            lesson_id=lesson["id"],
            project_name=lesson["project"],
            date=lesson["date"],
            text=lesson["text"],
            tag_names=tag_names,
            tier=lesson["tier"],
            active=active,
            branch=lesson.get("branch"),
            promoted=lesson.get("promoted"),
            archived=lesson.get("archived"),
        )
        migrated += 1

    set_metadata(conn, "last_manage_run", _now_iso())
    conn.close()

    print(f"{c['green']}Migrated {migrated} lessons{c['reset']}", end="")
    if skipped:
        print(f" ({skipped} skipped — already in DB)")
    else:
        print()
    print(f"Tags: {', '.join(sorted(tags_created))}")


# ---------------------------------------------------------------------------
# CLI subcommands
# ---------------------------------------------------------------------------


def cmd_add(args: argparse.Namespace) -> None:
    """Add a new lesson."""
    conn = init_lessons_db(args.db_path)

    # Generate ID if not provided
    lesson_id = args.id
    if not lesson_id:
        project = args.project or _detect_project()
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M")
        prefix = f"{project}_{timestamp}"
        existing = conn.execute(
            "SELECT COUNT(*) FROM lessons WHERE id LIKE ?",
            (f"{prefix}%",),
        ).fetchone()[0]
        lesson_id = f"{prefix}_{existing + 1:03d}"

    project = args.project or _detect_project()
    date = args.date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    branch = args.branch or _detect_branch()
    tag_names = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []

    # Auto-infer domain tags
    inferred = _infer_domain_tags(args.text)
    tag_names = list(dict.fromkeys(tag_names + inferred))

    insert_lesson(
        conn,
        lesson_id=lesson_id,
        project_name=project,
        date=date,
        text=args.text,
        tag_names=tag_names,
        branch=branch,
        scope=args.scope,
    )
    conn.close()

    c = _c()
    print(f"{c['green']}Added:{c['reset']} {lesson_id}")
    if tag_names:
        print(f"  Tags: {', '.join(tag_names)}")
    if args.scope == "project":
        print(f"  Scope: project ({project})")


def cmd_search(args: argparse.Namespace) -> None:
    """Full-text search over lesson text."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    tokens = args.query.split()
    safe_query = " ".join(
        '"' + t.replace('"', '""') + '"' for t in tokens if t
    )

    sql = """
        SELECT l.id, l.date, l.tier, l.active, p.name,
               highlight(lessons_fts, 0, '>>>', '<<<') AS snippet
        FROM lessons_fts
        JOIN lessons l ON l.rowid = lessons_fts.rowid
        JOIN projects p ON p.id = l.project_id
        WHERE lessons_fts MATCH ?
        ORDER BY l.date DESC
        LIMIT ?
    """
    rows = conn.execute(sql, (safe_query, args.limit)).fetchall()
    conn.close()

    print(f"\n{c['bold']}{c['cyan']}Search: '{args.query}' ({len(rows)} results){c['reset']}\n")
    for lid, date, tier, active, project, snippet in rows:
        status = f"{c['green']}active{c['reset']}" if active else f"{c['dim']}inactive{c['reset']}"
        print(f"  {c['dim']}{lid}{c['reset']}")
        print(f"    {c['dim']}{date}{c['reset']} [{tier}] {status} {c['yellow']}{project}{c['reset']}")
        print(f"    {snippet[:100]}")
        print()


def cmd_get(args: argparse.Namespace) -> None:
    """Get a single lesson by ID with full detail."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    sql = """
        SELECT l.id, l.date, l.tier, l.active, l.scope, l.text, l.branch,
               l.crystallized_from, l.absorbed_into, l.promoted, l.archived,
               l.created_at, p.name AS project,
               GROUP_CONCAT(t.name, ', ') AS tags
        FROM lessons l
        JOIN projects p ON p.id = l.project_id
        LEFT JOIN lesson_tags lt ON lt.lesson_id = l.id
        LEFT JOIN tags t ON t.id = lt.tag_id
        WHERE l.id = ?
        GROUP BY l.id
    """
    row = conn.execute(sql, (args.id,)).fetchone()
    conn.close()

    if not row:
        print(f"Lesson not found: {args.id}", file=sys.stderr)
        sys.exit(1)

    lid, date, tier, active, scope, text, branch, crystal_from, absorbed, promoted, archived, created, project, tags = row
    status = f"{c['green']}active{c['reset']}" if active else f"{c['dim']}inactive{c['reset']}"

    print(f"\n{c['bold']}{c['cyan']}Lesson: {lid}{c['reset']}\n")
    print(f"  Date:      {date}")
    print(f"  Tier:      {tier}")
    print(f"  Status:    {status}")
    print(f"  Scope:     {scope}")
    print(f"  Project:   {c['yellow']}{project}{c['reset']}")
    if branch:
        print(f"  Branch:    {branch}")
    if tags:
        print(f"  Tags:      {tags}")
    if promoted:
        print(f"  Promoted:  {promoted}")
    if archived:
        print(f"  Archived:  {archived}")
    if crystal_from:
        print(f"  Crystallized from: {crystal_from}")
    if absorbed:
        print(f"  Absorbed into:     {absorbed}")
    print(f"  Created:   {c['dim']}{created}{c['reset']}")
    print(f"\n  {text}\n")


def cmd_list(args: argparse.Namespace) -> None:
    """List lessons with filters."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    sql = """
        SELECT l.id, l.date, l.tier, l.active, l.text, p.name,
               GROUP_CONCAT(t.name, ', ') AS tags, l.scope
        FROM lessons l
        JOIN projects p ON p.id = l.project_id
        LEFT JOIN lesson_tags lt ON lt.lesson_id = l.id
        LEFT JOIN tags t ON t.id = lt.tag_id
        WHERE 1=1
    """
    params: list = []

    if args.tier:
        sql += " AND l.tier = ?"
        params.append(args.tier)
    if args.active:
        sql += " AND l.active = 1"
    if args.project:
        sql += " AND p.name LIKE ?"
        params.append(f"%{args.project}%")
    if args.tags:
        filter_tags = [t.strip() for t in args.tags.split(",")]
        placeholders = ",".join("?" for _ in filter_tags)
        sql += f"""
            AND l.id IN (
                SELECT lt2.lesson_id FROM lesson_tags lt2
                JOIN tags t2 ON t2.id = lt2.tag_id
                WHERE t2.name IN ({placeholders})
            )
        """
        params.extend(filter_tags)
    if args.scope:
        sql += " AND l.scope = ?"
        params.append(args.scope)

    sql += " GROUP BY l.id ORDER BY l.date DESC LIMIT ?"
    params.append(args.limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    print(f"\n{c['bold']}{len(rows)} lesson(s){c['reset']}\n")
    for lid, date, tier, active, text, project, tags, scope in rows:
        active_mark = "" if active else f" {c['dim']}(inactive){c['reset']}"
        scope_mark = "[P]" if scope == "project" else ""
        tag_str = f" {c['dim']}[{tags}]{c['reset']}" if tags else ""
        print(f"  {c['dim']}{lid}{c['reset']}")
        print(f"    {c['dim']}{date}{c['reset']} [{tier}]{scope_mark}{active_mark}{tag_str}")
        print(f"    {text[:120]}")
        print()


def cmd_summary(args: argparse.Namespace) -> None:
    """Show summary counts."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    total = conn.execute("SELECT COUNT(*) FROM lessons").fetchone()[0]
    active = conn.execute("SELECT COUNT(*) FROM lessons WHERE active = 1").fetchone()[0]

    print(f"\n{c['bold']}Lessons Summary{c['reset']}\n")
    print(f"  Total: {total}  Active: {active}  Inactive: {total - active}")

    # By tier
    print(f"\n  {c['bold']}By tier:{c['reset']}")
    for row in conn.execute(
        "SELECT tier, COUNT(*), SUM(active) FROM lessons GROUP BY tier ORDER BY tier"
    ).fetchall():
        print(f"    {row[0]:12} {row[1]:3} total, {row[2]:3} active")

    # By tag (active lessons only)
    print(f"\n  {c['bold']}By tag (active lessons):{c['reset']}")
    for row in conn.execute(
        """SELECT t.name, t.lesson_count
           FROM tags t WHERE t.status = 'active' AND t.lesson_count > 0
           ORDER BY t.lesson_count DESC"""
    ).fetchall():
        print(f"    {row[0]:20} {row[1]:3}")

    # Metadata
    last_manage = get_metadata(conn, "last_manage_run")
    if last_manage:
        print(f"\n  Last manage-lessons run: {last_manage}")

    conn.close()
    print()


def cmd_set_meta(args: argparse.Namespace) -> None:
    """Set a metadata key-value pair."""
    conn = init_lessons_db(args.db_path)
    set_metadata(conn, args.key, args.value)
    conn.close()
    print(f"Set {args.key} = {args.value}")


# ---------------------------------------------------------------------------
# Phase 2b: Manage-lessons subcommands
# ---------------------------------------------------------------------------


def cmd_tags(args: argparse.Namespace) -> None:
    """Show tag registry with counts and status."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    rows = conn.execute(
        """SELECT t.name, t.status, t.lesson_count, t.keywords, t.description,
                  m.name AS merged_into
           FROM tags t
           LEFT JOIN tags m ON t.merged_into_id = m.id
           ORDER BY t.lesson_count DESC, t.name"""
    ).fetchall()
    conn.close()

    print(f"\n{c['bold']}Tag Registry ({len(rows)} tags){c['reset']}\n")
    for name, status, count, keywords, desc, merged_into in rows:
        status_fmt = (
            f"{c['green']}{status}{c['reset']}" if status == "active"
            else f"{c['dim']}{status}{c['reset']}"
        )
        merged_note = f" → {merged_into}" if merged_into else ""
        kw = f" kw:[{keywords}]" if keywords else ""
        print(f"  {name:20} {count:3} lessons  {status_fmt}{merged_note}{kw}")
        if desc:
            print(f"  {' ':20} {c['dim']}{desc}{c['reset']}")
    print()


def cmd_clusters(args: argparse.Namespace) -> None:
    """Find lessons sharing 2+ tags — crystallization candidates."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    # Find pairs of active lessons sharing tags
    rows = conn.execute(
        """SELECT l1.id, l1.text, l2.id, l2.text,
                  GROUP_CONCAT(DISTINCT t.name) AS shared_tags,
                  COUNT(DISTINCT t.id) AS shared_count
           FROM lesson_tags lt1
           JOIN lesson_tags lt2 ON lt1.tag_id = lt2.tag_id AND lt1.lesson_id < lt2.lesson_id
           JOIN lessons l1 ON l1.id = lt1.lesson_id
           JOIN lessons l2 ON l2.id = lt2.lesson_id
           JOIN tags t ON t.id = lt1.tag_id
           WHERE l1.active = 1 AND l2.active = 1
           GROUP BY l1.id, l2.id
           HAVING shared_count >= ?
           ORDER BY shared_count DESC""",
        (args.min_shared,),
    ).fetchall()
    conn.close()

    if not rows:
        print(f"\n{c['dim']}No clusters found (min shared tags: {args.min_shared}){c['reset']}\n")
        return

    print(f"\n{c['bold']}Crystallization Candidates ({len(rows)} pairs){c['reset']}\n")
    for id1, text1, id2, text2, shared_tags, shared_count in rows:
        print(f"  {c['yellow']}Shared tags ({shared_count}): {shared_tags}{c['reset']}")
        print(f"    {c['dim']}{id1}{c['reset']}: {text1[:100]}")
        print(f"    {c['dim']}{id2}{c['reset']}: {text2[:100]}")
        print()


def cmd_crystallize(args: argparse.Namespace) -> None:
    """Crystallize multiple lessons into one, deactivating the sources."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    source_ids = [s.strip() for s in args.ids.split(",")]

    # Verify all source lessons exist and are active
    for sid in source_ids:
        row = conn.execute(
            "SELECT active FROM lessons WHERE id = ?", (sid,)
        ).fetchone()
        if not row:
            print(f"Error: lesson {sid} not found", file=sys.stderr)
            sys.exit(1)
        if not row[0]:
            print(f"Warning: lesson {sid} is already inactive", file=sys.stderr)

    # Get project from first source
    project_name = conn.execute(
        "SELECT p.name FROM lessons l JOIN projects p ON l.project_id = p.id WHERE l.id = ?",
        (source_ids[0],),
    ).fetchone()[0]

    # Determine scope: project only if ALL sources are project-scoped for the same project
    source_scopes = conn.execute(
        f"SELECT DISTINCT l.scope, p.name FROM lessons l "  # noqa: S608
        f"JOIN projects p ON l.project_id = p.id "
        f"WHERE l.id IN ({','.join('?' for _ in source_ids)})",
        source_ids,
    ).fetchall()
    if all(s == "project" for s, _ in source_scopes) and len({p for _, p in source_scopes}) == 1:
        crystallized_scope = "project"
    else:
        crystallized_scope = "global"

    tag_names = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []
    inferred = _infer_domain_tags(args.text)
    tag_names = list(dict.fromkeys(tag_names + inferred))

    # Generate ID
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M")
    prefix = f"{project_name}_{timestamp}"
    existing = conn.execute(
        "SELECT COUNT(*) FROM lessons WHERE id LIKE ?", (f"{prefix}%",)
    ).fetchone()[0]
    new_id = f"{prefix}_{existing + 1:03d}"

    # Insert crystallized lesson
    insert_lesson(
        conn,
        lesson_id=new_id,
        project_name=project_name,
        date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        text=args.text,
        tag_names=tag_names,
        tier="key",
        branch=_detect_branch(),
        crystallized_from=",".join(source_ids),
        promoted=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        scope=crystallized_scope,
    )

    # Deactivate sources
    for sid in source_ids:
        update_lesson(conn, sid, active=0)

    conn.close()

    print(f"{c['green']}Crystallized:{c['reset']} {new_id}")
    print(f"  From: {', '.join(source_ids)}")
    print(f"  Tags: {', '.join(tag_names)}")
    print(f"  Text: {args.text[:100]}")


def cmd_absorb(args: argparse.Namespace) -> None:
    """Mark a lesson as absorbed into a resource, deactivating it."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    row = conn.execute("SELECT text, active FROM lessons WHERE id = ?", (args.id,)).fetchone()
    if not row:
        print(f"Error: lesson {args.id} not found", file=sys.stderr)
        sys.exit(1)

    update_lesson(conn, args.id, absorbed_into=args.into, active=0)
    conn.close()

    print(f"{c['green']}Absorbed:{c['reset']} {args.id}")
    print(f"  Into: {args.into}")
    print(f"  Text: {row[0][:100]}")


def cmd_tag_hygiene(args: argparse.Namespace) -> None:
    """Report tag quality issues: orphaned, near-duplicates, keyword gaps."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    issues: list[str] = []

    # Orphaned tags (no active lessons)
    orphaned = conn.execute(
        "SELECT name FROM tags WHERE status = 'active' AND lesson_count = 0"
    ).fetchall()
    if orphaned:
        names = ", ".join(r[0] for r in orphaned)
        issues.append(f"Orphaned tags (0 active lessons): {names}")

    # Tags without keywords (can't be surfaced by hooks)
    no_kw = conn.execute(
        "SELECT name FROM tags WHERE status = 'active' AND (keywords IS NULL OR keywords = '')"
    ).fetchall()
    if no_kw:
        names = ", ".join(r[0] for r in no_kw)
        issues.append(f"Tags without keywords (won't surface in hooks): {names}")

    # Tags without descriptions
    no_desc = conn.execute(
        "SELECT name FROM tags WHERE status = 'active' AND (description IS NULL OR description = '')"
    ).fetchall()
    if no_desc:
        names = ", ".join(r[0] for r in no_desc)
        issues.append(f"Tags without descriptions: {names}")

    # Deprecated tags still in use
    deprecated_used = conn.execute(
        """SELECT t.name, COUNT(*) FROM tags t
           JOIN lesson_tags lt ON lt.tag_id = t.id
           JOIN lessons l ON l.id = lt.lesson_id
           WHERE t.status = 'deprecated' AND l.active = 1
           GROUP BY t.id"""
    ).fetchall()
    if deprecated_used:
        for name, count in deprecated_used:
            issues.append(f"Deprecated tag '{name}' still on {count} active lesson(s)")

    conn.close()

    print(f"\n{c['bold']}Tag Hygiene Report{c['reset']}\n")
    if issues:
        for issue in issues:
            print(f"  {c['yellow']}⚠{c['reset']} {issue}")
    else:
        print(f"  {c['green']}All tags healthy{c['reset']}")
    print()


def cmd_health(args: argparse.Namespace) -> None:
    """Overall health report for the lessons system."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    total = conn.execute("SELECT COUNT(*) FROM lessons").fetchone()[0]
    active = conn.execute("SELECT COUNT(*) FROM lessons WHERE active = 1").fetchone()[0]
    by_tier = conn.execute(
        "SELECT tier, COUNT(*), SUM(active) FROM lessons GROUP BY tier ORDER BY tier"
    ).fetchall()
    tag_count = conn.execute("SELECT COUNT(*) FROM tags WHERE status = 'active'").fetchone()[0]
    absorbed = conn.execute(
        "SELECT COUNT(*) FROM lessons WHERE absorbed_into IS NOT NULL"
    ).fetchone()[0]
    crystallized = conn.execute(
        "SELECT COUNT(*) FROM lessons WHERE crystallized_from IS NOT NULL"
    ).fetchone()[0]

    last_manage = get_metadata(conn, "last_manage_run")
    threshold = get_metadata(conn, "nudge_threshold_days") or "7"

    print(f"\n{c['bold']}Lessons Health Report{c['reset']}\n")
    print(f"  Total: {total}  Active: {active}  Inactive: {total - active}")
    print(f"  Absorbed: {absorbed}  Crystallized: {crystallized}")
    print(f"  Active tags: {tag_count}")

    print(f"\n  {c['bold']}By tier:{c['reset']}")
    for tier, count, active_count in by_tier:
        print(f"    {tier:12} {count:3} total, {int(active_count or 0):3} active")

    # Top tags
    top_tags = conn.execute(
        """SELECT t.name, t.lesson_count FROM tags t
           WHERE t.status = 'active' AND t.lesson_count > 0
           ORDER BY t.lesson_count DESC LIMIT 5"""
    ).fetchall()
    if top_tags:
        print(f"\n  {c['bold']}Top tags:{c['reset']}")
        for name, count in top_tags:
            print(f"    {name:20} {count:3}")

    print(f"\n  Last manage-lessons: {last_manage or 'never'}")
    print(f"  Nudge threshold: {threshold} days")

    # Health warnings
    warnings: list[str] = []
    if active > 15:
        warnings.append(f"Active lesson count ({active}) exceeds recommended max (15) — prune")
    if last_manage:
        from datetime import datetime as dt
        try:
            last_dt = dt.fromisoformat(last_manage)
            days_since = (datetime.now(timezone.utc) - last_dt.replace(tzinfo=timezone.utc)).days
            if days_since >= int(threshold):
                warnings.append(f"{days_since}d since last manage-lessons (threshold: {threshold}d)")
        except ValueError:
            pass

    orphaned = conn.execute(
        "SELECT COUNT(*) FROM tags WHERE status = 'active' AND lesson_count = 0"
    ).fetchone()[0]
    if orphaned:
        warnings.append(f"{orphaned} orphaned tag(s)")

    hist_active = conn.execute(
        "SELECT COUNT(*) FROM lessons WHERE tier = 'historical' AND active = 1"
    ).fetchone()[0]
    if hist_active:
        warnings.append(
            f"{hist_active} historical lesson(s) still active — deactivate or change tier"
        )

    conn.close()

    if warnings:
        print(f"\n  {c['bold']}Warnings:{c['reset']}")
        for w in warnings:
            print(f"    {c['yellow']}⚠{c['reset']} {w}")
    print()


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------


def _detect_project() -> str:
    """Detect project name from git root or cwd."""
    import subprocess

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        return Path(result.stdout.strip()).name
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd().name


def _detect_branch() -> str | None:
    """Detect current git branch."""
    import subprocess

    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip() or None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


# ---------------------------------------------------------------------------
# CLI parser
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Lessons database — manage cross-project actionable rules",
    )
    parser.add_argument(
        "--db", type=Path, default=LESSONS_DB_PATH, dest="db_path",
        help=f"Database path (default: {LESSONS_DB_PATH})",
    )
    sub = parser.add_subparsers(dest="command", help="Subcommand")

    # migrate
    mig = sub.add_parser("migrate", help="Import from learned.json")
    mig.add_argument(
        "--json-path", default=str(LEARNED_JSON_PATH),
        help=f"Path to learned.json (default: {LEARNED_JSON_PATH})",
    )

    # add
    add = sub.add_parser("add", help="Add a new lesson")
    add.add_argument("--id", default=None, help="Lesson ID (auto-generated if omitted)")
    add.add_argument("--project", default=None, help="Project name (auto-detected)")
    add.add_argument("--date", default=None, help="Date YYYY-MM-DD (default: today)")
    add.add_argument("--text", required=True, help="Lesson text")
    add.add_argument("--tags", default="", help="Comma-separated tag names")
    add.add_argument("--branch", default=None, help="Git branch (auto-detected)")
    add.add_argument("--scope", choices=["global", "project"], default="global",
                     help="Scope: global (all projects) or project (this project only)")

    # search
    srch = sub.add_parser("search", help="Full-text search")
    srch.add_argument("query", help="Search query")
    srch.add_argument("--limit", type=int, default=20, help="Max results")

    # get
    gt = sub.add_parser("get", help="Get a lesson by ID (full detail)")
    gt.add_argument("id", help="Lesson ID")

    # list
    lst = sub.add_parser("list", help="List lessons with filters")
    lst.add_argument("--tier", help="Filter by tier (recent/key/historical)")
    lst.add_argument("--active", action="store_true", help="Active lessons only")
    lst.add_argument("--tags", help="Comma-separated tags to filter by")
    lst.add_argument("--project", help="Filter by project name")
    lst.add_argument("--scope", choices=["global", "project"], help="Filter by scope")
    lst.add_argument("--limit", type=int, default=50, help="Max results")

    # summary
    sub.add_parser("summary", help="Show summary counts")

    # set-meta
    sm = sub.add_parser("set-meta", help="Set metadata key-value")
    sm.add_argument("key", help="Metadata key")
    sm.add_argument("value", help="Metadata value")

    # tags
    sub.add_parser("tags", help="Show tag registry")

    # clusters
    cl = sub.add_parser("clusters", help="Find crystallization candidates")
    cl.add_argument("--min-shared", type=int, default=2, help="Min shared tags (default: 2)")

    # crystallize
    cr = sub.add_parser("crystallize", help="Merge lessons into one")
    cr.add_argument("--ids", required=True, help="Comma-separated source lesson IDs")
    cr.add_argument("--text", required=True, help="Crystallized lesson text")
    cr.add_argument("--tags", default="", help="Comma-separated tag names")

    # absorb
    ab = sub.add_parser("absorb", help="Mark lesson as absorbed into a resource")
    ab.add_argument("--id", required=True, help="Lesson ID")
    ab.add_argument("--into", required=True, help="Resource (e.g. hook:git-safety, skill:learn)")

    # tag-hygiene
    sub.add_parser("tag-hygiene", help="Report tag quality issues")

    # health
    sub.add_parser("health", help="Overall health report")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "migrate": cmd_migrate,
        "add": cmd_add,
        "search": cmd_search,
        "get": cmd_get,
        "list": cmd_list,
        "summary": cmd_summary,
        "set-meta": cmd_set_meta,
        "tags": cmd_tags,
        "clusters": cmd_clusters,
        "crystallize": cmd_crystallize,
        "absorb": cmd_absorb,
        "tag-hygiene": cmd_tag_hygiene,
        "health": cmd_health,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
