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

import argparse
import json
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
    "memories": ["memory", "memories", "essential-", "MEMORIES.md"],
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

    print(f"{c['green']}Migrated {migrated} lessons{c['reset']}")
    print(f"Tags: {', '.join(sorted(tags_created))}")


# ---------------------------------------------------------------------------
# CLI subcommands
# ---------------------------------------------------------------------------


def cmd_add(args: argparse.Namespace) -> None:
    """Add a new lesson."""
    import subprocess

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
    )
    conn.close()

    c = _c()
    print(f"{c['green']}Added:{c['reset']} {lesson_id}")
    if tag_names:
        print(f"  Tags: {', '.join(tag_names)}")


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
        print(f"  {c['dim']}{date}{c['reset']} [{tier}] {status} {c['yellow']}{project}{c['reset']}")
        print(f"    {snippet[:100]}")
        print()


def cmd_list(args: argparse.Namespace) -> None:
    """List lessons with filters."""
    conn = init_lessons_db(args.db_path)
    c = _c()

    sql = """
        SELECT l.id, l.date, l.tier, l.active, l.text, p.name,
               GROUP_CONCAT(t.name, ', ') AS tags
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

    sql += " GROUP BY l.id ORDER BY l.date DESC LIMIT ?"
    params.append(args.limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    print(f"\n{c['bold']}{len(rows)} lesson(s){c['reset']}\n")
    for lid, date, tier, active, text, project, tags in rows:
        active_mark = "" if active else f" {c['dim']}(inactive){c['reset']}"
        tag_str = f" {c['dim']}[{tags}]{c['reset']}" if tags else ""
        print(f"  {c['dim']}{date}{c['reset']} [{tier}]{active_mark}{tag_str}")
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

    # search
    srch = sub.add_parser("search", help="Full-text search")
    srch.add_argument("query", help="Search query")
    srch.add_argument("--limit", type=int, default=20, help="Max results")

    # list
    lst = sub.add_parser("list", help="List lessons with filters")
    lst.add_argument("--tier", help="Filter by tier (recent/key/historical)")
    lst.add_argument("--active", action="store_true", help="Active lessons only")
    lst.add_argument("--tags", help="Comma-separated tags to filter by")
    lst.add_argument("--project", help="Filter by project name")
    lst.add_argument("--limit", type=int, default=50, help="Max results")

    # summary
    sub.add_parser("summary", help="Show summary counts")

    # set-meta
    sm = sub.add_parser("set-meta", help="Set metadata key-value")
    sm.add_argument("key", help="Metadata key")
    sm.add_argument("value", help="Metadata value")

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
        "list": cmd_list,
        "summary": cmd_summary,
        "set-meta": cmd_set_meta,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
