"""Tests for scripts/session-search.py — SQLite+FTS5 session history search."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from scripts.session_search import (
    _extract_assistant_text,
    _extract_tool_detail,
    _extract_user_text,
    extract_session_events,
    init_db,
    index_sessions,
    _get_or_create_project,
)


# ---------------------------------------------------------------------------
# Record builders
# ---------------------------------------------------------------------------


def _assistant_record(
    ts: str,
    content: list,
    model: str = "claude-opus-4-6",
    usage: dict | None = None,
) -> dict:
    return {
        "type": "assistant",
        "timestamp": ts,
        "message": {
            "model": model,
            "usage": usage or {"input_tokens": 100, "output_tokens": 50},
            "content": content,
        },
    }


def _user_record(ts: str, content: str) -> dict:
    return {
        "type": "user",
        "timestamp": ts,
        "message": {"content": content},
    }


def _tool_use_block(tool: str, inp: dict) -> dict:
    return {"type": "tool_use", "name": tool, "input": inp}


def _text_block(text: str) -> dict:
    return {"type": "text", "text": text}


def _progress_record(ts: str, hook_event: str, hook_name: str) -> dict:
    return {
        "type": "progress",
        "timestamp": ts,
        "data": {
            "type": "hook_progress",
            "hookEvent": hook_event,
            "hookName": hook_name,
        },
    }


def _write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for rec in records:
            f.write(json.dumps(rec) + "\n")


# ---------------------------------------------------------------------------
# Tool detail extraction
# ---------------------------------------------------------------------------


class TestExtractToolDetail:
    def test_bash_command(self) -> None:
        result = _extract_tool_detail("Bash", {"command": "ls -la"})
        assert result == ("command", "ls -la")

    def test_write_file(self) -> None:
        result = _extract_tool_detail("Write", {"file_path": "/tmp/foo.py"})
        assert result == ("file_change", "/tmp/foo.py")

    def test_edit_file(self) -> None:
        result = _extract_tool_detail("Edit", {"file_path": "/tmp/bar.py"})
        assert result == ("file_change", "/tmp/bar.py")

    def test_read_file(self) -> None:
        result = _extract_tool_detail("Read", {"file_path": "/tmp/baz.py"})
        assert result == ("file_read", "/tmp/baz.py")

    def test_grep_with_path(self) -> None:
        result = _extract_tool_detail("Grep", {"pattern": "foo", "path": "/src"})
        assert result == ("search", "foo in /src")

    def test_grep_without_path(self) -> None:
        result = _extract_tool_detail("Grep", {"pattern": "foo"})
        assert result == ("search", "foo")

    def test_glob(self) -> None:
        result = _extract_tool_detail("Glob", {"pattern": "*.py", "path": "/src"})
        assert result == ("glob", "*.py in /src")

    def test_webfetch(self) -> None:
        result = _extract_tool_detail("WebFetch", {"url": "https://example.com"})
        assert result == ("web", "https://example.com")

    def test_task_agent(self) -> None:
        result = _extract_tool_detail("Task", {"description": "explore code"})
        assert result == ("agent", "explore code")

    def test_skill(self) -> None:
        result = _extract_tool_detail("Skill", {"skill": "wrap-up"})
        assert result == ("skill", "wrap-up")

    def test_unknown_tool(self) -> None:
        result = _extract_tool_detail("CustomTool", {"key": "value"})
        assert result is not None
        assert result[0] == "other"

    def test_empty_input(self) -> None:
        result = _extract_tool_detail("Write", {})
        assert result is None


# ---------------------------------------------------------------------------
# User text extraction
# ---------------------------------------------------------------------------


class TestExtractUserText:
    def test_plain_text(self) -> None:
        assert _extract_user_text("hello world") == "hello world"

    def test_system_reminder_skip(self) -> None:
        assert _extract_user_text("<system-reminder>some stuff</system-reminder>") is None

    def test_local_command_skip(self) -> None:
        assert _extract_user_text("<local-command-caveat>stuff</local-command-caveat>") is None

    def test_skill_invocation(self) -> None:
        content = '<command-name>/wrap-up</command-name><command-message>finish</command-message>'
        result = _extract_user_text(content)
        assert result == "/wrap-up finish"

    def test_xml_stripping(self) -> None:
        content = "hello <some-tag>world</some-tag> test"
        result = _extract_user_text(content)
        assert result == "hello world test"

    def test_truncation(self) -> None:
        long_text = "a" * 3000
        result = _extract_user_text(long_text)
        assert result is not None
        assert len(result) == 2000

    def test_list_content(self) -> None:
        content = [{"type": "text", "text": "hello"}, {"type": "text", "text": "world"}]
        result = _extract_user_text(content)
        assert result == "hello\nworld"


# ---------------------------------------------------------------------------
# Assistant text extraction
# ---------------------------------------------------------------------------


class TestExtractAssistantText:
    def test_text_blocks(self) -> None:
        content = [_text_block("hello"), _text_block("world")]
        assert _extract_assistant_text(content) == "hello\nworld"

    def test_mixed_blocks(self) -> None:
        content = [_text_block("hello"), _tool_use_block("Bash", {"command": "ls"})]
        assert _extract_assistant_text(content) == "hello"

    def test_no_text(self) -> None:
        content = [_tool_use_block("Bash", {"command": "ls"})]
        assert _extract_assistant_text(content) is None

    def test_empty_text(self) -> None:
        content = [_text_block("")]
        assert _extract_assistant_text(content) is None


# ---------------------------------------------------------------------------
# Session event extraction (round-trip)
# ---------------------------------------------------------------------------


class TestExtractSessionEvents:
    def test_full_extraction(self, tmp_path: Path) -> None:
        records = [
            {"type": "user", "timestamp": "2026-01-01T10:00:00Z",
             "gitBranch": "main",
             "message": {"content": "hello world"}},
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_text_block("I'll help"), _tool_use_block("Read", {"file_path": "/tmp/f.py"})],
            ),
            _progress_record("2026-01-01T10:01:01Z", "PreToolUse", "Read"),
        ]

        session_dir = tmp_path / "test-project"
        session_file = session_dir / "abc-123.jsonl"
        _write_jsonl(session_file, records)

        meta, events = extract_session_events(session_file)

        assert meta["session_id"] == "abc-123"
        assert meta["git_branch"] == "main"
        assert meta["model"] == "claude-opus-4-6"
        assert meta["input_tokens"] == 100
        assert meta["output_tokens"] == 50

        # user + assistant text + tool_use + progress = 4 events
        assert len(events) == 4
        types = [e["event_type"] for e in events]
        assert types == ["user", "assistant", "tool_use", "progress"]

        # Check ordering
        seqs = [e["seq"] for e in events]
        assert seqs == [1, 2, 3, 4]

    def test_empty_session(self, tmp_path: Path) -> None:
        session_dir = tmp_path / "test-project"
        session_file = session_dir / "empty.jsonl"
        _write_jsonl(session_file, [])

        meta, events = extract_session_events(session_file)
        assert len(events) == 0


# ---------------------------------------------------------------------------
# Database round-trip
# ---------------------------------------------------------------------------


class TestDatabaseRoundTrip:
    def test_init_db(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.db"
        conn = init_db(db_path)

        # Verify tables exist
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "projects" in tables
        assert "sessions" in tables
        assert "events" in tables
        assert "events_fts" in tables
        conn.close()

    def test_project_upsert(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.db"
        conn = init_db(db_path)

        id1 = _get_or_create_project(conn, "my-project", "-home-user-my-project")
        id2 = _get_or_create_project(conn, "my-project", "-home-user-my-project")
        assert id1 == id2

        id3 = _get_or_create_project(conn, "other", "-home-user-other")
        assert id3 != id1
        conn.close()

    def test_index_and_search(self, tmp_path: Path) -> None:
        """Full round-trip: create JSONL, index, search, verify."""
        db_path = tmp_path / "test.db"

        # Create a fake transcript directory structure
        project_dir = tmp_path / "transcripts" / "-home-user-projects-personal-myproj"
        records = [
            _user_record("2026-01-01T10:00:00Z", "implement the frobulator"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [
                    _text_block("I'll implement the frobulator now"),
                    _tool_use_block("Write", {"file_path": "/src/frobulator.py"}),
                ],
            ),
        ]
        _write_jsonl(project_dir / "sess-001.jsonl", records)

        conn = init_db(db_path)

        # Monkeypatch SOURCE_DIRS for test
        import scripts.session_search as ss
        original = ss.SOURCE_DIRS
        ss.SOURCE_DIRS = [tmp_path / "transcripts"]
        try:
            stats = index_sessions(conn)
        finally:
            ss.SOURCE_DIRS = original

        assert stats["new"] == 1
        assert stats["events"] > 0

        # Search for frobulator
        rows = conn.execute("""
            SELECT e.detail FROM events_fts
            JOIN events e ON e.id = events_fts.rowid
            WHERE events_fts MATCH '"frobulator"'
        """).fetchall()
        assert len(rows) >= 2  # user message + assistant text

        # Search for file path (detail stores full path as single token)
        rows = conn.execute("""
            SELECT e.detail FROM events e
            WHERE e.action_type = 'file_change'
              AND e.detail LIKE '%frobulator.py'
        """).fetchall()
        assert len(rows) == 1

        conn.close()

    def test_dedup(self, tmp_path: Path) -> None:
        """Same session_id in two source dirs — only one indexed."""
        db_path = tmp_path / "test.db"

        records = [_user_record("2026-01-01T10:00:00Z", "hello")]

        # Same session_id in two dirs
        dir1 = tmp_path / "backup" / "-home-user-proj"
        dir2 = tmp_path / "live" / "-home-user-proj"
        _write_jsonl(dir1 / "sess-dup.jsonl", records)
        _write_jsonl(dir2 / "sess-dup.jsonl", records)

        conn = init_db(db_path)

        import scripts.session_search as ss
        original = ss.SOURCE_DIRS
        ss.SOURCE_DIRS = [tmp_path / "backup", tmp_path / "live"]
        try:
            stats = index_sessions(conn)
        finally:
            ss.SOURCE_DIRS = original

        assert stats["new"] == 1

        count = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
        assert count == 1

        # Verify it came from backup (first source)
        source = conn.execute(
            "SELECT source_dir FROM sessions"
        ).fetchone()[0]
        assert "backup" in source

        conn.close()

    def test_incremental(self, tmp_path: Path) -> None:
        """Re-indexing unchanged files should skip."""
        db_path = tmp_path / "test.db"

        project_dir = tmp_path / "transcripts" / "-home-user-proj"
        records = [_user_record("2026-01-01T10:00:00Z", "hello")]
        _write_jsonl(project_dir / "sess-inc.jsonl", records)

        conn = init_db(db_path)

        import scripts.session_search as ss
        original = ss.SOURCE_DIRS
        ss.SOURCE_DIRS = [tmp_path / "transcripts"]
        try:
            stats1 = index_sessions(conn)
            assert stats1["new"] == 1

            stats2 = index_sessions(conn)
            assert stats2["skipped"] == 1
            assert stats2["new"] == 0
        finally:
            ss.SOURCE_DIRS = original

        conn.close()
