"""Tests for scripts/session_analytics.py — session usage pattern analytics."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from scripts.session_search import (
    init_db,
    index_sessions,
)
from scripts.session_analytics import (
    FILTERED_EVENTS_CTE,
    _cte,
    query_session_shapes,
    query_project_patterns,
)


# ---------------------------------------------------------------------------
# Record builders (duplicated from test_session_search for isolation)
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
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def indexed_db(tmp_path: Path) -> sqlite3.Connection:
    """Create and index a test DB with two projects and multiple sessions."""
    db_path = tmp_path / "test.db"

    # Project A: 2 sessions, mix of tools and progress events
    proj_a = tmp_path / "transcripts" / "-home-user-projects-alpha"

    _write_jsonl(
        proj_a / "sess-a1.jsonl",
        [
            {"type": "user", "timestamp": "2026-01-10T09:00:00Z",
             "gitBranch": "feat/widgets",
             "message": {"content": "add widgets"}},
            _assistant_record(
                "2026-01-10T09:05:00Z",
                [_text_block("On it"), _tool_use_block("Write", {"file_path": "/src/widget.py"})],
                usage={"input_tokens": 200, "output_tokens": 100},
            ),
            _progress_record("2026-01-10T09:05:01Z", "PreToolUse", "Write"),
            _progress_record("2026-01-10T09:05:02Z", "PostToolUse", "Write"),
            _assistant_record(
                "2026-01-10T09:10:00Z",
                [_tool_use_block("Read", {"file_path": "/src/widget.py"})],
                usage={"input_tokens": 150, "output_tokens": 80},
            ),
        ],
    )

    _write_jsonl(
        proj_a / "sess-a2.jsonl",
        [
            {"type": "user", "timestamp": "2026-01-12T14:00:00Z",
             "gitBranch": "feat/widgets",
             "message": {"content": "fix widget bug"}},
            _assistant_record(
                "2026-01-12T14:30:00Z",
                [_text_block("Found the issue"), _tool_use_block("Bash", {"command": "pytest"})],
                usage={"input_tokens": 300, "output_tokens": 200},
            ),
            _progress_record("2026-01-12T14:30:01Z", "PreToolUse", "Bash"),
        ],
    )

    # Project B: 1 session, heavier on reads
    proj_b = tmp_path / "transcripts" / "-home-user-projects-beta"

    _write_jsonl(
        proj_b / "sess-b1.jsonl",
        [
            {"type": "user", "timestamp": "2026-01-15T08:00:00Z",
             "gitBranch": "main",
             "message": {"content": "review codebase"}},
            _assistant_record(
                "2026-01-15T08:10:00Z",
                [_tool_use_block("Read", {"file_path": "/src/a.py"})],
                usage={"input_tokens": 500, "output_tokens": 300},
            ),
            _assistant_record(
                "2026-01-15T08:20:00Z",
                [_tool_use_block("Read", {"file_path": "/src/b.py"})],
                usage={"input_tokens": 400, "output_tokens": 250},
            ),
            _assistant_record(
                "2026-01-15T08:30:00Z",
                [_tool_use_block("Grep", {"pattern": "TODO", "path": "/src"})],
                usage={"input_tokens": 200, "output_tokens": 100},
            ),
        ],
    )

    conn = init_db(db_path)

    import scripts.session_search as ss
    original = ss.SOURCE_DIRS
    ss.SOURCE_DIRS = [tmp_path / "transcripts"]
    try:
        index_sessions(conn)
    finally:
        ss.SOURCE_DIRS = original

    return conn


# ---------------------------------------------------------------------------
# Preprocessing filter
# ---------------------------------------------------------------------------


class TestPreprocessingFilter:
    def test_cte_excludes_progress(self, indexed_db: sqlite3.Connection) -> None:
        """Filtered CTE should exclude all progress events."""
        total = indexed_db.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        progress = indexed_db.execute(
            "SELECT COUNT(*) FROM events WHERE event_type = 'progress'"
        ).fetchone()[0]

        filtered = indexed_db.execute(
            f"WITH {FILTERED_EVENTS_CTE} SELECT COUNT(*) FROM filtered_events"
        ).fetchone()[0]

        assert progress > 0, "Test data should include progress events"
        assert filtered == total - progress

    def test_cte_helper(self) -> None:
        """_cte() builds correct WITH clauses."""
        base = _cte()
        assert base.startswith("WITH ")
        assert "filtered_events" in base

        extended = _cte("extra AS (SELECT 1)")
        assert "filtered_events" in extended
        assert "extra AS" in extended


# ---------------------------------------------------------------------------
# Session shapes
# ---------------------------------------------------------------------------


class TestSessionShapes:
    def test_returns_all_sessions(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db)
        assert len(rows) == 3

    def test_session_has_expected_fields(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db)
        row = rows[0]
        expected_keys = {
            "session_id", "project", "first_ts", "last_ts", "git_branch",
            "model", "total_tokens", "duration_min", "event_count",
            "tool_diversity", "dominant_action",
        }
        assert expected_keys.issubset(row.keys())

    def test_duration_computed(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db)
        durations = {r["session_id"]: r["duration_min"] for r in rows}
        # sess-a1: 09:00 -> 09:10 = 10 min
        assert abs(durations["sess-a1"] - 10.0) < 0.1
        # sess-a2: 14:00 -> 14:30 = 30 min
        assert abs(durations["sess-a2"] - 30.0) < 0.1

    def test_event_count_excludes_progress(self, indexed_db: sqlite3.Connection) -> None:
        """Event count should not include progress/hook events."""
        rows = query_session_shapes(indexed_db)
        counts = {r["session_id"]: r["event_count"] for r in rows}
        # sess-a1: user + assistant(text+tool) + assistant(tool) = 4 events (no progress)
        assert counts["sess-a1"] == 4
        # sess-a2: user + assistant(text+tool) = 3 events (no progress)
        assert counts["sess-a2"] == 3

    def test_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db, project="beta")
        assert len(rows) == 1
        assert "beta" in rows[0]["project"]

    def test_tool_diversity(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db)
        diversity = {r["session_id"]: r["tool_diversity"] for r in rows}
        # sess-a1: Write + Read = 2 distinct tools
        assert diversity["sess-a1"] == 2
        # sess-b1: Read + Grep = 2 distinct tools
        assert diversity["sess-b1"] == 2


# ---------------------------------------------------------------------------
# Project patterns
# ---------------------------------------------------------------------------


class TestProjectPatterns:
    def test_returns_all_projects(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_project_patterns(indexed_db)
        assert len(rows) == 2

    def test_project_has_expected_fields(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_project_patterns(indexed_db)
        row = rows[0]
        expected_keys = {
            "project", "total_sessions", "first_seen", "last_seen",
            "event_count", "total_tokens", "avg_duration_min",
            "avg_events_per_session", "peak_week", "dominant_action",
            "days_active",
        }
        assert expected_keys.issubset(row.keys())

    def _by_name(self, indexed_db: sqlite3.Connection) -> dict:
        """Helper to get project patterns keyed by partial name match."""
        rows = query_project_patterns(indexed_db)
        result = {}
        for r in rows:
            if "alpha" in r["project"]:
                result["alpha"] = r
            elif "beta" in r["project"]:
                result["beta"] = r
        return result

    def test_session_counts(self, indexed_db: sqlite3.Connection) -> None:
        by_name = self._by_name(indexed_db)
        assert by_name["alpha"]["total_sessions"] == 2
        assert by_name["beta"]["total_sessions"] == 1

    def test_event_counts_exclude_progress(self, indexed_db: sqlite3.Connection) -> None:
        by_name = self._by_name(indexed_db)
        # alpha: sess-a1(4) + sess-a2(3) = 7 filtered events
        assert by_name["alpha"]["event_count"] == 7

    def test_days_active(self, indexed_db: sqlite3.Connection) -> None:
        by_name = self._by_name(indexed_db)
        # alpha: sessions on Jan 10 and Jan 12 = 2 active days
        assert by_name["alpha"]["days_active"] == 2
        assert by_name["beta"]["days_active"] == 1

    def test_dominant_action(self, indexed_db: sqlite3.Connection) -> None:
        by_name = self._by_name(indexed_db)
        # beta: 2 reads + 1 search = file_read dominant
        assert by_name["beta"]["dominant_action"] == "file_read"
