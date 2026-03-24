#!/usr/bin/env python3
"""SQLite+FTS5 session history search for Claude Code transcripts.

Indexes all session transcripts into a SQLite database with full-text search
across tool calls, user messages, and assistant responses.

Usage:
    uv run scripts/session-search.py index [--full] [--project <name>]
    uv run scripts/session-search.py search <query> [--project <name>] [--since YYYY-MM-DD] [--type <type>] [--limit N]
    uv run scripts/session-search.py timeline [--days N] [--project <name>]
    uv run scripts/session-search.py files [<pattern>] [--days N] [--project <name>]
    uv run scripts/session-search.py stats
    uv run scripts/session-search.py resource-cost [--type skill|agent] [--project <name>] [--sort tokens|uses|avg] [--subagents]

Schema design: scripts/session-search/schema-smith/schemas/session_index.yaml
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterator

# Import shared utilities from insights.py
sys.path.insert(0, str(Path(__file__).parent))
from insights import (
    BACKUP_TRANSCRIPTS_DIR,
    DEFAULT_TRANSCRIPTS_DIR,
    extract_project_name,
    find_session_files,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DB_PATH = Path.home() / ".claude" / "session-index.db"

# Backup dir first = canonical (preserves deleted sessions)
SOURCE_DIRS = [BACKUP_TRANSCRIPTS_DIR, DEFAULT_TRANSCRIPTS_DIR]

# XML tags to strip from user messages
_XML_TAG_RE = re.compile(r"<[^>]+>")
# System boilerplate that should be skipped entirely
_SKIP_PREFIXES = (
    "<local-command-caveat>",
    "<system-reminder>",
)

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
# Event extraction
# ---------------------------------------------------------------------------

_TOOL_ACTION_MAP: dict[str, tuple[str, ...]] = {
    # tool_name -> (action_type, detail_keys...)
    "Bash": ("command",),
    "Write": ("file_change",),
    "Edit": ("file_change",),
    "Read": ("file_read",),
    "Grep": ("search",),
    "Glob": ("glob",),
    "WebFetch": ("web",),
    "WebSearch": ("web",),
    "Task": ("agent",),
    "Agent": ("agent",),
    "Skill": ("skill",),
}


def _extract_tool_detail(tool_name: str, inp: dict) -> tuple[str, str] | None:
    """Map a tool_use block to (action_type, detail). Returns None if not indexable."""
    mapping = _TOOL_ACTION_MAP.get(tool_name)
    if not mapping:
        # Unknown tool — index with generic detail
        detail = str(inp)[:200]
        return ("other", detail) if detail else None

    action_type = mapping[0]

    if tool_name == "Bash":
        detail = inp.get("command", "")[:1000]
    elif tool_name in ("Write", "Edit", "Read"):
        detail = inp.get("file_path", "")
    elif tool_name == "Grep":
        pattern = inp.get("pattern", "")
        path = inp.get("path", "")
        detail = f"{pattern} in {path}" if path else pattern
    elif tool_name == "Glob":
        pattern = inp.get("pattern", "")
        path = inp.get("path", "")
        detail = f"{pattern} in {path}" if path else pattern
    elif tool_name in ("WebFetch", "WebSearch"):
        detail = inp.get("url", "") or inp.get("query", "")
    elif tool_name in ("Task", "Agent"):
        agent_type = inp.get("subagent_type", "") or "general-purpose"
        desc = inp.get("description", "") or inp.get("prompt", "")[:300]
        detail = f"{agent_type}: {desc}" if desc else agent_type
    elif tool_name == "Skill":
        detail = inp.get("skill", "")
    else:
        detail = str(inp)[:200]

    return (action_type, detail) if detail else None


def _extract_user_text(content: str | list) -> str | None:
    """Extract searchable text from user message content.

    Skips system boilerplate, strips XML tags, returns plain text.
    """
    if isinstance(content, list):
        # Multipart content — extract text blocks
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
            elif isinstance(block, str):
                parts.append(block)
        text = "\n".join(parts)
    elif isinstance(content, str):
        text = content
    else:
        return None

    if not text:
        return None

    # Skip pure system boilerplate
    for prefix in _SKIP_PREFIXES:
        if text.lstrip().startswith(prefix):
            return None

    # Extract skill command args if present
    cmd_match = re.search(
        r"<command-name>/([a-z][a-z0-9-]*)</command-name>", text
    )
    if cmd_match:
        # Extract the command message if present
        msg_match = re.search(
            r"<command-message>(.*?)</command-message>", text, re.DOTALL
        )
        if msg_match:
            return f"/{cmd_match.group(1)} {msg_match.group(1)}".strip()[:2000]
        return f"/{cmd_match.group(1)}"

    # Strip XML tags for regular messages
    clean = _XML_TAG_RE.sub("", text).strip()
    return clean[:2000] if clean else None


def _extract_assistant_text(content: list) -> str | None:
    """Extract text content from assistant message blocks."""
    if not isinstance(content, list):
        return None
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            text = block.get("text", "").strip()
            if text:
                parts.append(text)
    combined = "\n".join(parts)
    return combined[:2000] if combined else None


def extract_session_events(
    file_path: Path,
) -> tuple[dict, list[dict]]:
    """Parse a JSONL session file into session metadata + ordered event list.

    Returns (session_meta, events) where:
    - session_meta has: session_id, first_ts, last_ts, git_branch, model,
      input_tokens, output_tokens, cache_create_tokens, cache_read_tokens
    - events is a list of dicts ready for INSERT into events table
    """
    session_id = file_path.stem
    project = extract_project_name(file_path.parent.name)

    meta: dict = {
        "session_id": session_id,
        "project_name": project,
        "dir_name": file_path.parent.name,
        "project_path": None,
        "first_ts": None,
        "last_ts": None,
        "git_branch": None,
        "model": None,
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_create_tokens": 0,
        "cache_read_tokens": 0,
    }
    events: list[dict] = []
    seq = 0
    # Running sums for cumulative token tracking
    running_input_total = 0
    running_output_total = 0

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            ts = record.get("timestamp", "")
            record_type = record.get("type", "")

            # Track timestamps
            if ts:
                if not meta["first_ts"] or ts < meta["first_ts"]:
                    meta["first_ts"] = ts
                if not meta["last_ts"] or ts > meta["last_ts"]:
                    meta["last_ts"] = ts

            date = ts[:10] if ts else None

            # Track metadata
            # First-wins: cwd from earliest record. May be a subdir in rare
            # cases (worktrees, nested sessions), but stable for typical usage.
            if record.get("cwd") and not meta["project_path"]:
                meta["project_path"] = record["cwd"]
            if record.get("gitBranch") and not meta["git_branch"]:
                meta["git_branch"] = record["gitBranch"]

            # Progress events (hooks)
            if record_type == "progress":
                data = record.get("data", {})
                if data.get("type") == "hook_progress":
                    seq += 1
                    events.append({
                        "seq": seq,
                        "timestamp": ts,
                        "date": date,
                        "event_type": "progress",
                        "tool": None,
                        "action_type": None,
                        "detail": f"{data.get('hookEvent', '')}:{data.get('hookName', '')}",
                        "output_tokens": 0,
                        "input_total": 0,
                        "output_total": 0,
                        "subagent_id": None,
                    })
                continue

            # User messages
            if record_type == "user":
                msg = record.get("message", {})
                content = msg.get("content", "")
                text = _extract_user_text(content)
                if text:
                    # Classify user event action_type
                    if text.startswith("Base directory for this skill:"):
                        user_action = "skill_content"
                    else:
                        user_action = "human"
                    seq += 1
                    events.append({
                        "seq": seq,
                        "timestamp": ts,
                        "date": date,
                        "event_type": "user",
                        "tool": None,
                        "action_type": user_action,
                        "detail": text,
                        "output_tokens": 0,
                        "input_total": 0,
                        "output_total": 0,
                        "subagent_id": None,
                    })
                continue

            # Assistant messages
            if record_type == "assistant":
                msg = record.get("message", {})
                model = msg.get("model", "")
                if model:
                    meta["model"] = model

                # Token accounting
                usage = msg.get("usage", {})
                if usage:
                    meta["input_tokens"] += usage.get("input_tokens", 0)
                    meta["output_tokens"] += usage.get("output_tokens", 0)
                    meta["cache_create_tokens"] += usage.get(
                        "cache_creation_input_tokens", 0
                    )
                    meta["cache_read_tokens"] += usage.get(
                        "cache_read_input_tokens", 0
                    )

                turn_output = usage.get("output_tokens", 0)
                # Cumulative input = cache_creation + cache_read + input_tokens
                turn_input_total = (
                    usage.get("cache_creation_input_tokens", 0)
                    + usage.get("cache_read_input_tokens", 0)
                    + usage.get("input_tokens", 0)
                )
                running_input_total = turn_input_total
                running_output_total += turn_output
                content = msg.get("content", [])

                # Extract assistant text
                assistant_text = _extract_assistant_text(content)
                if assistant_text:
                    seq += 1
                    events.append({
                        "seq": seq,
                        "timestamp": ts,
                        "date": date,
                        "event_type": "assistant",
                        "tool": None,
                        "action_type": None,
                        "detail": assistant_text,
                        "output_tokens": turn_output,
                        "input_total": running_input_total,
                        "output_total": running_output_total,
                        "subagent_id": None,
                    })

                # Extract tool_use blocks
                if isinstance(content, list):
                    tool_uses = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            tool_uses.append(block)

                    per_tool_tokens = (
                        turn_output // len(tool_uses) if tool_uses else 0
                    )
                    for block in tool_uses:
                        tool_name = block.get("name", "unknown")
                        inp = block.get("input", {})
                        result = _extract_tool_detail(tool_name, inp)
                        if result:
                            action_type, detail = result
                            seq += 1
                            events.append({
                                "seq": seq,
                                "timestamp": ts,
                                "date": date,
                                "event_type": "tool_use",
                                "tool": tool_name,
                                "action_type": action_type,
                                "detail": detail,
                                "output_tokens": per_tool_tokens,
                                "input_total": running_input_total,
                                "output_total": running_output_total,
                                "subagent_id": None,
                            })

    # Parse subagent transcripts
    subagents_dir = file_path.parent / session_id / "subagents"
    if subagents_dir.is_dir():
        for sa_file in sorted(subagents_dir.glob("agent-*.jsonl")):
            agent_id = sa_file.stem.removeprefix("agent-")
            sa_events = _extract_subagent_events(sa_file, agent_id)
            for evt in sa_events:
                seq += 1
                evt["seq"] = seq
            events.extend(sa_events)

    return meta, events


# Interactive skills that use file-write as end boundary
_INTERACTIVE_SKILLS = {"brainstorm-idea", "shape-proposal"}


def extract_resource_usage(events: list[dict]) -> list[dict]:
    """Extract resource usage spans from an ordered event list.

    Walks events linearly to find skill/agent invocations and their
    end boundaries, computing token deltas for each span.
    """
    usages: list[dict] = []

    i = 0
    while i < len(events):
        evt = events[i]

        # Skill invocation
        if evt["event_type"] == "tool_use" and evt["tool"] == "Skill":
            skill_name = evt["detail"]
            start_input = evt["input_total"]
            start_output = evt["output_total"]
            ts = evt["timestamp"]
            is_interactive = skill_name in _INTERACTIVE_SKILLS

            # Scan forward for end boundary
            turn_count = 0
            files_written: list[str] = []
            end_input = start_input
            end_output = start_output
            end_reason = "eof"

            for j in range(i + 1, len(events)):
                fwd = events[j]

                # Track assistant turns and token totals
                if fwd["event_type"] == "assistant" and fwd["subagent_id"] is None:
                    turn_count += 1
                    if fwd["input_total"] > 0:
                        end_input = fwd["input_total"]
                        end_output = fwd["output_total"]

                # Track file writes
                if fwd["action_type"] == "file_change":
                    fp = fwd["detail"]
                    files_written.append(fp)
                    if is_interactive:
                        end_reason = "file_write"
                        break

                # End at next human message (skip skill_content)
                if (fwd["event_type"] == "user"
                        and fwd["action_type"] == "human"):
                    end_reason = "user_msg"
                    break

            usages.append({
                "resource_type": "skill",
                "resource_name": skill_name,
                "timestamp": ts,
                "input_delta": end_input - start_input,
                "output_delta": end_output - start_output,
                "turn_count": turn_count,
                "end_reason": end_reason,
                "files_written": json.dumps(files_written) if files_written else None,
            })

        # Agent invocation
        elif (evt["event_type"] == "tool_use"
              and evt["tool"] in ("Agent", "Task")):
            detail = evt["detail"]
            # Parse "type: description" format
            if ": " in detail:
                agent_type = detail.split(": ", 1)[0]
            else:
                agent_type = detail
            start_input = evt["input_total"]
            start_output = evt["output_total"]
            ts = evt["timestamp"]

            turn_count = 0
            end_input = start_input
            end_output = start_output
            end_reason = "eof"

            for j in range(i + 1, len(events)):
                fwd = events[j]

                if fwd["event_type"] == "assistant" and fwd["subagent_id"] is None:
                    turn_count += 1
                    if fwd["input_total"] > 0:
                        end_input = fwd["input_total"]
                        end_output = fwd["output_total"]

                if (fwd["event_type"] == "user"
                        and fwd["action_type"] == "human"):
                    end_reason = "user_msg"
                    break

            usages.append({
                "resource_type": "agent",
                "resource_name": agent_type,
                "timestamp": ts,
                "input_delta": end_input - start_input,
                "output_delta": end_output - start_output,
                "turn_count": turn_count,
                "end_reason": end_reason,
                "files_written": None,
            })

        i += 1

    # Memory baseline: first assistant event's input_total
    for evt in events:
        if evt["event_type"] == "assistant" and evt["subagent_id"] is None:
            if evt["input_total"] > 0:
                usages.append({
                    "resource_type": "memory_baseline",
                    "resource_name": "session_baseline",
                    "timestamp": evt["timestamp"],
                    "input_delta": evt["input_total"],
                    "output_delta": 0,
                    "turn_count": 0,
                    "end_reason": None,
                    "files_written": None,
                })
            break

    return usages


def _extract_subagent_events(
    jsonl_path: Path, agent_id: str
) -> list[dict]:
    """Extract events from a subagent JSONL file."""
    events: list[dict] = []
    running_input_total = 0
    running_output_total = 0

    with open(jsonl_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            ts = record.get("timestamp", "")
            date = ts[:10] if ts else None
            record_type = record.get("type", "")

            if record_type == "assistant":
                msg = record.get("message", {})
                usage = msg.get("usage", {})
                turn_output = usage.get("output_tokens", 0)
                turn_input_total = (
                    usage.get("cache_creation_input_tokens", 0)
                    + usage.get("cache_read_input_tokens", 0)
                    + usage.get("input_tokens", 0)
                )
                running_input_total = turn_input_total
                running_output_total += turn_output
                content = msg.get("content", [])

                # Assistant text
                text = _extract_assistant_text(content)
                if text:
                    events.append({
                        "seq": 0,  # will be set by caller
                        "timestamp": ts,
                        "date": date,
                        "event_type": "assistant",
                        "tool": None,
                        "action_type": None,
                        "detail": text,
                        "output_tokens": turn_output,
                        "input_total": running_input_total,
                        "output_total": running_output_total,
                        "subagent_id": agent_id,
                    })

                # Tool uses
                if isinstance(content, list):
                    tool_uses = [
                        b for b in content
                        if isinstance(b, dict) and b.get("type") == "tool_use"
                    ]
                    per_tool = turn_output // len(tool_uses) if tool_uses else 0
                    for block in tool_uses:
                        tool_name = block.get("name", "unknown")
                        inp = block.get("input", {})
                        result = _extract_tool_detail(tool_name, inp)
                        if result:
                            action_type, detail = result
                            events.append({
                                "seq": 0,
                                "timestamp": ts,
                                "date": date,
                                "event_type": "tool_use",
                                "tool": tool_name,
                                "action_type": action_type,
                                "detail": detail,
                                "output_tokens": per_tool,
                                "input_total": running_input_total,
                                "output_total": running_output_total,
                                "subagent_id": agent_id,
                            })

    return events


# ---------------------------------------------------------------------------
# Indexing engine
# ---------------------------------------------------------------------------


def _find_all_session_files(
    project_filter: str | None = None,
) -> Iterator[tuple[Path, str]]:
    """Yield (file_path, source_dir) across all source dirs, deduplicating by session_id."""
    seen: set[str] = set()
    for source_dir in SOURCE_DIRS:
        if not source_dir.is_dir():
            continue
        for file_path in find_session_files(project_filter, source_dir):
            session_id = file_path.stem
            if session_id in seen:
                continue
            seen.add(session_id)
            yield file_path, str(source_dir)


def _get_or_create_project(
    conn: sqlite3.Connection,
    name: str,
    dir_name: str,
    project_path: str | None = None,
) -> int:
    """Upsert project and return its id."""
    row = conn.execute(
        "SELECT id, project_path FROM projects WHERE name = ?", (name,)
    ).fetchone()
    if row:
        # Backfill project_path if missing
        if project_path and not row[1]:
            conn.execute(
                "UPDATE projects SET project_path = ? WHERE id = ?",
                (project_path, row[0]),
            )
        return row[0]
    cursor = conn.execute(
        "INSERT INTO projects (name, dir_name, project_path) VALUES (?, ?, ?)",
        (name, dir_name, project_path),
    )
    return cursor.lastrowid  # type: ignore[return-value]


def index_sessions(
    conn: sqlite3.Connection,
    full: bool = False,
    project_filter: str | None = None,
) -> dict[str, int]:
    """Index sessions into the database. Returns stats."""
    stats = {"new": 0, "updated": 0, "skipped": 0, "errors": 0, "events": 0}

    # Always snapshot existing sessions (needed for accurate new vs updated stats)
    indexed: dict[str, tuple[float, int]] = {}
    for row in conn.execute(
        "SELECT session_id, file_mtime, file_size FROM sessions"
    ):
        indexed[row[0]] = (row[1], row[2])

    for file_path, source_dir in _find_all_session_files(project_filter):
        session_id = file_path.stem

        try:
            file_stat = file_path.stat()
        except OSError:
            stats["errors"] += 1
            continue

        mtime = file_stat.st_mtime
        size = file_stat.st_size

        # Incremental: skip unchanged
        if session_id in indexed and not full:
            old_mtime, old_size = indexed[session_id]
            if mtime == old_mtime and size == old_size:
                stats["skipped"] += 1
                continue

        try:
            meta, events = extract_session_events(file_path)
        except Exception as e:
            print(f"Error indexing {file_path}: {e}", file=sys.stderr)
            stats["errors"] += 1
            continue

        if not events:
            stats["skipped"] += 1
            continue

        # Delete old data if re-indexing
        if session_id in indexed or full:
            conn.execute(
                "DELETE FROM sessions WHERE session_id = ?", (session_id,)
            )
            if session_id in indexed:
                stats["updated"] += 1
            else:
                stats["new"] += 1
        else:
            stats["new"] += 1

        # Get or create project
        project_id = _get_or_create_project(
            conn, meta["project_name"], meta["dir_name"], meta["project_path"]
        )

        # Insert session
        conn.execute(
            """INSERT INTO sessions
            (session_id, project_id, source_dir, first_ts, last_ts,
             git_branch, model, event_count,
             input_tokens, output_tokens, cache_create_tokens, cache_read_tokens,
             file_mtime, file_size, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                session_id,
                project_id,
                source_dir,
                meta["first_ts"],
                meta["last_ts"],
                meta["git_branch"],
                meta["model"],
                len(events),
                meta["input_tokens"],
                meta["output_tokens"],
                meta["cache_create_tokens"],
                meta["cache_read_tokens"],
                mtime,
                size,
                datetime.now().isoformat(),
            ),
        )

        # Insert events
        conn.executemany(
            """INSERT INTO events
            (session_id, project_id, seq, timestamp, date,
             event_type, tool, action_type, detail, output_tokens,
             input_total, output_total, subagent_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            [
                (
                    session_id,
                    project_id,
                    e["seq"],
                    e["timestamp"],
                    e["date"],
                    e["event_type"],
                    e["tool"],
                    e["action_type"],
                    e["detail"],
                    e["output_tokens"],
                    e["input_total"],
                    e["output_total"],
                    e["subagent_id"],
                )
                for e in events
            ],
        )

        # Extract and insert resource usage
        resource_usages = extract_resource_usage(events)
        if resource_usages:
            conn.executemany(
                """INSERT INTO resource_usage
                (session_id, project_id, resource_type, resource_name,
                 timestamp, input_delta, output_delta, turn_count,
                 end_reason, files_written)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                [
                    (
                        session_id,
                        project_id,
                        u["resource_type"],
                        u["resource_name"],
                        u["timestamp"],
                        u["input_delta"],
                        u["output_delta"],
                        u["turn_count"],
                        u["end_reason"],
                        u["files_written"],
                    )
                    for u in resource_usages
                ],
            )

        stats["events"] += len(events)
        conn.commit()

    # Update project aggregates
    conn.execute("""
        UPDATE projects SET
            session_count = (SELECT COUNT(*) FROM sessions WHERE project_id = projects.id),
            first_seen = (SELECT MIN(first_ts) FROM sessions WHERE project_id = projects.id),
            last_seen = (SELECT MAX(last_ts) FROM sessions WHERE project_id = projects.id)
    """)
    conn.commit()

    return stats


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

COLORS = {
    "bold": "\033[1m",
    "dim": "\033[2m",
    "cyan": "\033[36m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "red": "\033[31m",
    "reset": "\033[0m",
}
NO_COLORS = {k: "" for k in COLORS}


def _c() -> dict[str, str]:
    import os
    if os.environ.get("NO_COLOR") or not sys.stdout.isatty():
        return NO_COLORS
    return COLORS


def _fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_index(args: argparse.Namespace) -> None:
    """Build or update the session index."""
    conn = init_db(args.db_path)
    c = _c()

    if sys.stderr.isatty():
        print(
            f"{c['cyan']}Indexing sessions...{c['reset']}",
            file=sys.stderr,
            flush=True,
        )

    stats = index_sessions(conn, full=args.full, project_filter=args.project)
    conn.close()

    print(
        f"{c['green']}Done:{c['reset']} "
        f"{stats['new']} new, {stats['updated']} updated, "
        f"{stats['skipped']} skipped, {stats['events']} events"
    )
    if stats["errors"]:
        print(f"{c['red']}{stats['errors']} errors{c['reset']}")


def cmd_search(args: argparse.Namespace) -> None:
    """Full-text search across sessions."""
    conn = init_db(args.db_path)
    c = _c()

    # Quote each token individually for AND semantics
    # "git" "branch" matches docs with both words (any position)
    tokens = args.query.split()
    safe_query = " ".join(
        '"' + t.replace('"', '""') + '"' for t in tokens if t
    )

    sql = """
        SELECT e.date, p.name, e.event_type, e.tool, e.action_type,
               highlight(events_fts, 0, '>>>', '<<<') AS snippet
        FROM events_fts
        JOIN events e ON e.id = events_fts.rowid
        JOIN projects p ON p.id = e.project_id
        WHERE events_fts MATCH ?
    """
    params: list = [safe_query]

    if args.project:
        sql += " AND p.name LIKE ?"
        params.append(f"%{args.project}%")

    if args.since:
        sql += " AND e.date >= ?"
        params.append(args.since)

    if args.type:
        sql += " AND e.event_type = ?"
        params.append(args.type)

    sql += " ORDER BY rank LIMIT ?"
    params.append(args.limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    print(
        f"\n{c['bold']}{c['cyan']}Search: '{args.query}' "
        f"({len(rows)} results){c['reset']}\n"
    )

    for date, project, event_type, tool, action_type, snippet in rows:
        proj = project[:25] if len(project) > 25 else project
        label = tool or event_type
        if action_type:
            label = f"{tool}:{action_type}"
        snippet_short = snippet[:80].replace("\n", " ")
        print(
            f"  {c['dim']}{date}{c['reset']} "
            f"{proj:25} {c['yellow']}{label:15}{c['reset']} "
            f"{snippet_short}"
        )


def cmd_timeline(args: argparse.Namespace) -> None:
    """Show daily activity timeline."""
    conn = init_db(args.db_path)
    c = _c()

    since = (datetime.now() - timedelta(days=args.days)).strftime("%Y-%m-%d")

    sql = """
        SELECT e.date, p.name,
               COUNT(*) as events,
               COUNT(DISTINCT e.session_id) as sessions
        FROM events e
        JOIN projects p ON p.id = e.project_id
        WHERE e.date >= ?
    """
    params: list = [since]

    if args.project:
        sql += " AND p.name LIKE ?"
        params.append(f"%{args.project}%")

    sql += " GROUP BY e.date, p.name ORDER BY e.date DESC, events DESC"

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    print(f"\n{c['bold']}{c['cyan']}Timeline (last {args.days} days){c['reset']}\n")

    current_date = None
    for date, project, events, sessions in rows:
        if date != current_date:
            print(f"\n  {c['bold']}--- {date} ---{c['reset']}")
            current_date = date
        proj = project[:30] if len(project) > 30 else project
        print(
            f"    {proj:30} "
            f"{c['green']}{sessions:3} sessions{c['reset']}  "
            f"{events:5} events"
        )


def cmd_files(args: argparse.Namespace) -> None:
    """Show most-touched files."""
    conn = init_db(args.db_path)
    c = _c()

    since = (datetime.now() - timedelta(days=args.days)).strftime("%Y-%m-%d")

    sql = """
        SELECT e.detail, COUNT(*) as times,
               MAX(e.date) as last_date,
               e.action_type
        FROM events e
        JOIN projects p ON p.id = e.project_id
        WHERE e.action_type IN ('file_change', 'file_read')
          AND e.date >= ?
    """
    params: list = [since]

    if args.project:
        sql += " AND p.name LIKE ?"
        params.append(f"%{args.project}%")

    if args.pattern:
        sql += " AND e.detail LIKE ?"
        params.append(f"%{args.pattern}%")

    sql += " GROUP BY e.detail ORDER BY times DESC LIMIT ?"
    params.append(args.limit)

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    print(f"\n{c['bold']}{c['cyan']}Files (last {args.days} days){c['reset']}\n")

    for detail, times, last_date, action_type in rows:
        atype = "W" if action_type == "file_change" else "R"
        path_short = detail[-60:] if len(detail) > 60 else detail
        print(
            f"  {c['dim']}{last_date}{c['reset']} "
            f"{times:5}x {c['yellow']}{atype}{c['reset']} "
            f"{path_short}"
        )


def cmd_stats(args: argparse.Namespace) -> None:
    """Show database statistics."""
    conn = init_db(args.db_path)
    c = _c()

    session_count = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    event_count = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    project_count = conn.execute("SELECT COUNT(*) FROM projects").fetchone()[0]

    date_range = conn.execute(
        "SELECT MIN(date), MAX(date) FROM events"
    ).fetchone()

    total_tokens = conn.execute(
        "SELECT SUM(input_tokens + output_tokens + cache_create_tokens + cache_read_tokens) FROM sessions"
    ).fetchone()[0] or 0

    by_project = conn.execute("""
        SELECT p.name,
               p.session_count as sessions,
               (SELECT COUNT(*) FROM events e WHERE e.project_id = p.id) as events,
               (SELECT SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens)
                FROM sessions s WHERE s.project_id = p.id) as tokens
        FROM projects p
        ORDER BY sessions DESC
        LIMIT 15
    """).fetchall()

    by_type = conn.execute("""
        SELECT event_type, COUNT(*) FROM events
        GROUP BY event_type ORDER BY 2 DESC
    """).fetchall()

    by_action = conn.execute("""
        SELECT action_type, COUNT(*) FROM events
        WHERE action_type IS NOT NULL
        GROUP BY action_type ORDER BY 2 DESC
    """).fetchall()

    conn.close()

    # DB file size
    db_size = args.db_path.stat().st_size if args.db_path.exists() else 0
    db_size_mb = db_size / (1024 * 1024)

    print(f"\n{c['bold']}{c['cyan']}Session Index Stats{c['reset']}\n")
    print(f"  Sessions:  {c['bold']}{session_count}{c['reset']}")
    print(f"  Events:    {event_count}")
    print(f"  Projects:  {project_count}")
    print(f"  Tokens:    {_fmt_tokens(total_tokens)}")
    print(f"  DB size:   {db_size_mb:.1f} MB")
    if date_range[0]:
        print(f"  Date range: {date_range[0]} to {date_range[1]}")

    if by_project:
        print(f"\n  {c['bold']}By Project{c['reset']}")
        for name, sessions, events, tokens in by_project:
            tok = _fmt_tokens(tokens or 0)
            print(f"    {name:35} {sessions:4} sessions  {events:6} events  {tok:>8} tokens")

    if by_type:
        print(f"\n  {c['bold']}By Event Type{c['reset']}")
        for etype, count in by_type:
            print(f"    {etype:15} {count:8}")

    if by_action:
        print(f"\n  {c['bold']}By Action Type{c['reset']}")
        for atype, count in by_action:
            print(f"    {atype:15} {count:8}")


def cmd_resource_cost(args: argparse.Namespace) -> None:
    """Show token cost of toolkit resources (skills, agents)."""
    conn = init_db(args.db_path)
    c = _c()

    type_filter = args.type if hasattr(args, "type") and args.type else None

    def _print_table(
        title: str,
        rows: list[tuple],
        name_header: str = "Name",
    ) -> None:
        if not rows:
            return
        print(f"\n{c['bold']}{c['cyan']}{title}{c['reset']}\n")
        print(
            f"  {name_header:30} {'Uses':>5} {'Avg In':>8} "
            f"{'Avg Out':>8} {'Turns':>5} "
            f"{'Total In':>10} {'Total Out':>10}"
        )
        print(f"  {'-' * 88}")
        for name, invocations, avg_in, avg_out, avg_turns, total_in, total_out in rows:
            print(
                f"  {name:30} {invocations:5} "
                f"{_fmt_tokens(avg_in or 0):>8} {_fmt_tokens(avg_out or 0):>8} "
                f"{avg_turns or 0:5} "
                f"{_fmt_tokens(total_in or 0):>10} "
                f"{_fmt_tokens(total_out or 0):>10}"
            )

    sort_col = {
        "tokens": "total_input",
        "uses": "invocations",
        "avg": "avg_input_delta",
    }.get(args.sort, "total_input")

    for rtype, title, name_header in [
        ("skill", "Skills", "Name"),
        ("agent", "Agents", "Type"),
    ]:
        if type_filter and type_filter != rtype:
            continue

        sql = """
            SELECT
                resource_name,
                COUNT(*) AS invocations,
                CAST(AVG(input_delta) AS INTEGER) AS avg_input_delta,
                CAST(AVG(output_delta) AS INTEGER) AS avg_output_delta,
                CAST(AVG(turn_count) AS INTEGER) AS avg_turns,
                SUM(input_delta) AS total_input,
                SUM(output_delta) AS total_output
            FROM resource_usage
            WHERE resource_type = ?
        """
        params: list = [rtype]

        if args.project:
            sql += " AND project_id IN (SELECT id FROM projects WHERE name LIKE ?)"
            params.append(f"%{args.project}%")

        sql += f" GROUP BY resource_name ORDER BY {sort_col} DESC"
        rows = conn.execute(sql, params).fetchall()
        _print_table(title, rows, name_header)

    # Memory baseline
    if not type_filter:
        row = conn.execute("""
            SELECT COUNT(*) AS sessions,
                   CAST(AVG(input_delta) AS INTEGER) AS avg_baseline
            FROM resource_usage
            WHERE resource_type = 'memory_baseline'
        """).fetchone()
        if row and row[0]:
            print(f"\n{c['bold']}{c['cyan']}Memory Baseline{c['reset']}\n")
            print(
                f"  Avg first-turn input: {_fmt_tokens(row[1])} tokens "
                f"({row[0]} sessions)"
            )

    conn.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Session history search for Claude Code transcripts",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DB_PATH,
        dest="db_path",
        help=f"Database path (default: {DB_PATH})",
    )
    sub = parser.add_subparsers(dest="command", help="Subcommand")

    # index
    idx = sub.add_parser("index", help="Build/update session index")
    idx.add_argument("--full", action="store_true", help="Force full reindex")
    idx.add_argument("--project", help="Filter by project name")

    # search
    srch = sub.add_parser("search", help="Full-text search")
    srch.add_argument("query", help="Search query")
    srch.add_argument("--project", help="Filter by project")
    srch.add_argument("--since", help="Only results after date (YYYY-MM-DD)")
    srch.add_argument("--type", help="Filter by event type")
    srch.add_argument("--limit", type=int, default=30, help="Max results")

    # timeline
    tl = sub.add_parser("timeline", help="Daily activity timeline")
    tl.add_argument("--days", type=int, default=7, help="Days to show")
    tl.add_argument("--project", help="Filter by project")

    # files
    fl = sub.add_parser("files", help="Most-touched files")
    fl.add_argument("pattern", nargs="?", help="File path pattern")
    fl.add_argument("--days", type=int, default=7, help="Days to search")
    fl.add_argument("--project", help="Filter by project")
    fl.add_argument("--limit", type=int, default=30, help="Max results")

    # stats
    sub.add_parser("stats", help="Database statistics")

    # resource-cost
    rc = sub.add_parser("resource-cost", help="Token cost of toolkit resources")
    rc.add_argument("--type", choices=["skill", "agent"], help="Filter by resource type")
    rc.add_argument("--project", help="Filter by project")
    rc.add_argument(
        "--sort",
        choices=["tokens", "uses", "avg"],
        default="tokens",
        help="Sort order (default: tokens)",
    )

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "index": cmd_index,
        "search": cmd_search,
        "timeline": cmd_timeline,
        "files": cmd_files,
        "stats": cmd_stats,
        "resource-cost": cmd_resource_cost,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
