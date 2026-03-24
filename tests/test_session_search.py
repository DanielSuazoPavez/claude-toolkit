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
    extract_resource_usage,
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
        result = _extract_tool_detail("Task", {"description": "explore code", "subagent_type": "Explore"})
        assert result == ("agent", "Explore: explore code")

    def test_agent_default_type(self) -> None:
        result = _extract_tool_detail("Agent", {"description": "do stuff"})
        assert result == ("agent", "general-purpose: do stuff")

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


# ---------------------------------------------------------------------------
# Cumulative tokens and user classification
# ---------------------------------------------------------------------------


class TestCumulativeTokens:
    def test_input_total_on_assistant_events(self, tmp_path: Path) -> None:
        """Assistant and tool_use events should have input_total from usage."""
        records = [
            _user_record("2026-01-01T10:00:00Z", "hello"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_text_block("hi"), _tool_use_block("Read", {"file_path": "/f.py"})],
                usage={
                    "input_tokens": 10,
                    "output_tokens": 50,
                    "cache_creation_input_tokens": 100,
                    "cache_read_input_tokens": 200,
                },
            ),
            _assistant_record(
                "2026-01-01T10:02:00Z",
                [_text_block("done")],
                usage={
                    "input_tokens": 15,
                    "output_tokens": 30,
                    "cache_creation_input_tokens": 150,
                    "cache_read_input_tokens": 250,
                },
            ),
        ]

        session_dir = tmp_path / "test-project"
        session_file = session_dir / "tok-001.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)

        # user event has input_total=0
        user_evt = [e for e in events if e["event_type"] == "user"][0]
        assert user_evt["input_total"] == 0

        # First assistant turn: 10 + 100 + 200 = 310
        asst_evts = [e for e in events if e["event_type"] == "assistant"]
        assert asst_evts[0]["input_total"] == 310
        assert asst_evts[0]["output_total"] == 50

        # tool_use from same turn shares the same totals
        tool_evts = [e for e in events if e["event_type"] == "tool_use"]
        assert tool_evts[0]["input_total"] == 310
        assert tool_evts[0]["output_total"] == 50

        # Second assistant turn: 15 + 150 + 250 = 415, output_total = 50 + 30 = 80
        assert asst_evts[1]["input_total"] == 415
        assert asst_evts[1]["output_total"] == 80

    def test_progress_events_zero_tokens(self, tmp_path: Path) -> None:
        records = [
            _progress_record("2026-01-01T10:00:00Z", "PreToolUse", "Bash"),
        ]
        session_dir = tmp_path / "test-project"
        session_file = session_dir / "tok-002.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        assert events[0]["input_total"] == 0
        assert events[0]["output_total"] == 0


class TestUserClassification:
    def test_human_message(self, tmp_path: Path) -> None:
        records = [
            _user_record("2026-01-01T10:00:00Z", "please fix the bug"),
        ]
        session_dir = tmp_path / "test-project"
        session_file = session_dir / "usr-001.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        assert events[0]["action_type"] == "human"

    def test_skill_content_message(self, tmp_path: Path) -> None:
        records = [
            _user_record(
                "2026-01-01T10:00:00Z",
                "Base directory for this skill: /home/user/.claude/skills/wrap-up\n\nDo the wrap-up.",
            ),
        ]
        session_dir = tmp_path / "test-project"
        session_file = session_dir / "usr-002.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        assert events[0]["action_type"] == "skill_content"

    def test_slash_command_is_human(self, tmp_path: Path) -> None:
        records = [
            _user_record(
                "2026-01-01T10:00:00Z",
                '<command-name>/wrap-up</command-name><command-message>wrap-up</command-message>',
            ),
        ]
        session_dir = tmp_path / "test-project"
        session_file = session_dir / "usr-003.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        assert events[0]["action_type"] == "human"


# ---------------------------------------------------------------------------
# Resource cost query
# ---------------------------------------------------------------------------


class TestResourceUsageExtraction:
    def test_skill_span(self, tmp_path: Path) -> None:
        """Skill invocation followed by work, ended by human message."""
        records = [
            _user_record("2026-01-01T10:00:00Z", "do the wrap-up"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_tool_use_block("Skill", {"skill": "wrap-up"})],
                usage={
                    "input_tokens": 10,
                    "output_tokens": 20,
                    "cache_creation_input_tokens": 500,
                    "cache_read_input_tokens": 500,
                },
            ),
            _user_record(
                "2026-01-01T10:01:01Z",
                "Base directory for this skill: /home/user/.claude/skills/wrap-up\n\nSteps...",
            ),
            _assistant_record(
                "2026-01-01T10:02:00Z",
                [_tool_use_block("Edit", {"file_path": "/CHANGELOG.md"})],
                usage={
                    "input_tokens": 15,
                    "output_tokens": 100,
                    "cache_creation_input_tokens": 800,
                    "cache_read_input_tokens": 700,
                },
            ),
            _assistant_record(
                "2026-01-01T10:03:00Z",
                [_text_block("Done with wrap-up")],
                usage={
                    "input_tokens": 20,
                    "output_tokens": 50,
                    "cache_creation_input_tokens": 1000,
                    "cache_read_input_tokens": 900,
                },
            ),
            _user_record("2026-01-01T10:04:00Z", "thanks"),
        ]

        session_dir = tmp_path / "test-project"
        session_file = session_dir / "rc-001.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        usages = extract_resource_usage(events)

        skills = [u for u in usages if u["resource_type"] == "skill"]
        assert len(skills) == 1
        assert skills[0]["resource_name"] == "wrap-up"
        assert skills[0]["end_reason"] == "user_msg"
        assert skills[0]["turn_count"] == 1  # Only the text turn has event_type='assistant'
        # Start: 10+500+500=1010, End: 20+1000+900=1920
        assert skills[0]["input_delta"] == 910
        # Start output: 20, End output: 20+100+50=170
        assert skills[0]["output_delta"] == 150

    def test_agent_span(self, tmp_path: Path) -> None:
        records = [
            _user_record("2026-01-01T10:00:00Z", "review code"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_tool_use_block("Agent", {"subagent_type": "code-reviewer", "description": "review"})],
                usage={
                    "input_tokens": 5,
                    "output_tokens": 30,
                    "cache_creation_input_tokens": 200,
                    "cache_read_input_tokens": 300,
                },
            ),
            _assistant_record(
                "2026-01-01T10:02:00Z",
                [_text_block("Review complete")],
                usage={
                    "input_tokens": 10,
                    "output_tokens": 80,
                    "cache_creation_input_tokens": 400,
                    "cache_read_input_tokens": 500,
                },
            ),
            _user_record("2026-01-01T10:03:00Z", "ok"),
        ]

        session_dir = tmp_path / "test-project"
        session_file = session_dir / "rc-002.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        usages = extract_resource_usage(events)

        agents = [u for u in usages if u["resource_type"] == "agent"]
        assert len(agents) == 1
        assert agents[0]["resource_name"] == "code-reviewer"
        assert agents[0]["end_reason"] == "user_msg"

    def test_memory_baseline(self, tmp_path: Path) -> None:
        records = [
            _user_record("2026-01-01T10:00:00Z", "hi"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_text_block("hello")],
                usage={
                    "input_tokens": 50,
                    "output_tokens": 10,
                    "cache_creation_input_tokens": 5000,
                    "cache_read_input_tokens": 3000,
                },
            ),
        ]

        session_dir = tmp_path / "test-project"
        session_file = session_dir / "rc-003.jsonl"
        _write_jsonl(session_file, records)

        _, events = extract_session_events(session_file)
        usages = extract_resource_usage(events)

        baselines = [u for u in usages if u["resource_type"] == "memory_baseline"]
        assert len(baselines) == 1
        assert baselines[0]["input_delta"] == 8050  # 50+5000+3000

    def test_db_round_trip(self, tmp_path: Path) -> None:
        """Resource usage survives index -> query cycle."""
        records = [
            _user_record("2026-01-01T10:00:00Z", "wrap it up"),
            _assistant_record(
                "2026-01-01T10:01:00Z",
                [_tool_use_block("Skill", {"skill": "wrap-up"})],
                usage={
                    "input_tokens": 10,
                    "output_tokens": 20,
                    "cache_creation_input_tokens": 500,
                    "cache_read_input_tokens": 500,
                },
            ),
            _user_record(
                "2026-01-01T10:01:01Z",
                "Base directory for this skill: /skills/wrap-up\n\nDo stuff",
            ),
            _assistant_record(
                "2026-01-01T10:02:00Z",
                [_text_block("Done")],
                usage={
                    "input_tokens": 20,
                    "output_tokens": 50,
                    "cache_creation_input_tokens": 1000,
                    "cache_read_input_tokens": 900,
                },
            ),
            _user_record("2026-01-01T10:03:00Z", "thanks"),
        ]

        project_dir = tmp_path / "transcripts" / "-home-user-projects-personal-myproj"
        _write_jsonl(project_dir / "rc-004.jsonl", records)

        db_path = tmp_path / "test.db"
        conn = init_db(db_path)

        import scripts.session_search as ss
        original = ss.SOURCE_DIRS
        ss.SOURCE_DIRS = [tmp_path / "transcripts"]
        try:
            index_sessions(conn)
        finally:
            ss.SOURCE_DIRS = original

        rows = conn.execute("""
            SELECT resource_type, resource_name, input_delta, output_delta,
                   turn_count, end_reason
            FROM resource_usage
            ORDER BY resource_type
        """).fetchall()

        # Should have memory_baseline + skill
        types = {r[0] for r in rows}
        assert "skill" in types
        assert "memory_baseline" in types

        skill_row = [r for r in rows if r[0] == "skill"][0]
        assert skill_row[1] == "wrap-up"
        assert skill_row[4] == 1  # 1 assistant turn in span
        assert skill_row[5] == "user_msg"
        conn.close()


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
