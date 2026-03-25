#!/usr/bin/env python3
"""Session indexing for Claude Code transcripts.

Extracts events from JSONL session files and indexes them into a SQLite
database with full-text search support.

Usage:
    uv run scripts/sessions/index.py index [--full] [--project <name>]

Schema design: scripts/sessions/schemas/session_index.yaml
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from typing import Iterator

from scripts.sessions.db import (
    BACKUP_TRANSCRIPTS_DIR,
    DB_PATH,
    DEFAULT_TRANSCRIPTS_DIR,
    _c,
    extract_project_name,
    find_session_files,
    init_db,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

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
# CLI
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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Index Claude Code session transcripts into SQLite",
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

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "index": cmd_index,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
