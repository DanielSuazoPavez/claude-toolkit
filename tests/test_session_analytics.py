"""Tests for scripts/sessions/analytics.py — session usage pattern analytics."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from scripts.sessions.db import init_db
from scripts.sessions.index import index_sessions
from scripts.sessions.analytics import (
    FILTERED_EVENTS_CTE,
    _cte,
    _classify_claude_md,
    _extract_memory_filename,
    compute_active_time,
    query_agent_usage,
    query_branch_patterns,
    query_claude_md_reads,
    query_daily_activity,
    query_essential_estimates,
    query_hook_usage,
    query_hourly_activity,
    query_memory_diversity,
    query_memory_reads,
    query_project_patterns,
    query_session_gaps,
    query_session_shapes,
    query_skill_usage,
    query_tool_usage,
    query_weekly_volume,
)


# ---------------------------------------------------------------------------
# Record builders (duplicated from test_session_index for isolation)
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


@pytest.fixture(scope="session")
def indexed_db(tmp_path_factory: pytest.TempPathFactory) -> sqlite3.Connection:
    """Create and index a test DB with two projects and multiple sessions."""
    tmp_path = tmp_path_factory.mktemp("analytics")
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

    import scripts.sessions.index as si
    original = si.SOURCE_DIRS
    si.SOURCE_DIRS = [tmp_path / "transcripts"]
    try:
        index_sessions(conn)
    finally:
        si.SOURCE_DIRS = original

    # Insert resource_usage rows for skill/agent test coverage
    proj_a_id = conn.execute(
        "SELECT id FROM projects WHERE name LIKE '%alpha%'"
    ).fetchone()[0]
    conn.executemany(
        """INSERT INTO resource_usage
           (session_id, project_id, resource_type, resource_name,
            timestamp, input_delta, output_delta, turn_count)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        [
            ("sess-a1", proj_a_id, "skill", "learn", "2026-01-10T09:06:00Z", 500, 200, 3),
            ("sess-a2", proj_a_id, "skill", "learn", "2026-01-12T14:31:00Z", 400, 150, 2),
            ("sess-a1", proj_a_id, "skill", "commit", "2026-01-10T09:08:00Z", 300, 100, 1),
            ("sess-a1", proj_a_id, "agent", "Explore", "2026-01-10T09:07:00Z", 1000, 500, 8),
            ("sess-a2", proj_a_id, "agent", "Explore", "2026-01-12T14:32:00Z", 800, 400, 6),
            ("sess-a1", proj_a_id, "agent", "Plan", "2026-01-10T09:09:00Z", 600, 300, 4),
        ],
    )
    conn.commit()

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
# Active time
# ---------------------------------------------------------------------------


class TestActiveTime:
    def test_active_time_computed(self, indexed_db: sqlite3.Connection) -> None:
        active = compute_active_time(indexed_db, ["sess-a1", "sess-a2", "sess-b1"])
        assert "sess-a1" in active
        assert "sess-a2" in active
        assert "sess-b1" in active

    def test_active_time_within_duration(self, indexed_db: sqlite3.Connection) -> None:
        """Active time should not exceed wall clock duration + 1 bucket."""
        active = compute_active_time(indexed_db, ["sess-a1"])
        # sess-a1 is 10m wall clock, active time at most duration + bucket size
        assert active["sess-a1"] <= 15.0

    def test_active_time_sparse_session(self, indexed_db: sqlite3.Connection) -> None:
        """Sparse events across wide time range produce few active buckets."""
        # sess-b1: events at 08:00, 08:10, 08:20, 08:30
        # Each falls in a different 5m bucket = 4 buckets = 20m
        # Wall clock is 30m, so active < duration
        active = compute_active_time(indexed_db, ["sess-b1"])
        assert active["sess-b1"] < 30.0

    def test_custom_bucket_size(self, indexed_db: sqlite3.Connection) -> None:
        """Smaller buckets should produce less or equal active time."""
        small = compute_active_time(indexed_db, ["sess-b1"], bucket_min=1)
        large = compute_active_time(indexed_db, ["sess-b1"], bucket_min=10)
        assert large["sess-b1"] >= small["sess-b1"]

    def test_empty_session_ids(self, indexed_db: sqlite3.Connection) -> None:
        result = compute_active_time(indexed_db, [])
        assert result == {}

    def test_session_shape_includes_active_min(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_session_shapes(indexed_db)
        assert all("active_min" in r for r in rows)


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


# ---------------------------------------------------------------------------
# Time patterns
# ---------------------------------------------------------------------------


class TestTimePatterns:
    def test_hourly_returns_active_hours(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_hourly_activity(indexed_db, utc_offset=0)
        hours = {r["hour"]: r["sessions"] for r in rows}
        # sess-a1 starts at 09:00, sess-a2 at 14:00, sess-b1 at 08:00
        assert 9 in hours
        assert 14 in hours
        assert 8 in hours

    def test_hourly_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_hourly_activity(indexed_db, project="beta", utc_offset=0)
        hours = {r["hour"]: r["sessions"] for r in rows}
        # Only sess-b1 at 08:00
        assert len(hours) == 1
        assert hours[8] == 1

    def test_hourly_with_offset(self, indexed_db: sqlite3.Connection) -> None:
        """UTC offset shifts hours correctly."""
        utc = query_hourly_activity(indexed_db, utc_offset=0)
        shifted = query_hourly_activity(indexed_db, utc_offset=-3)
        utc_hours = {r["hour"] for r in utc}
        shifted_hours = {r["hour"] for r in shifted}
        # Hours should be shifted by -3
        expected = {(h - 3) % 24 for h in utc_hours}
        assert shifted_hours == expected

    def test_daily_returns_active_days(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_daily_activity(indexed_db, utc_offset=0)
        # Jan 10 2026 = Saturday (dow=6), Jan 12 = Monday (dow=1), Jan 15 = Thursday (dow=4)
        dows = {r["dow"] for r in rows}
        assert 6 in dows  # Saturday
        assert 1 in dows  # Monday
        assert 4 in dows  # Thursday

    def test_daily_session_counts(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_daily_activity(indexed_db, utc_offset=0)
        dow_map = {r["dow"]: r["sessions"] for r in rows}
        # Saturday has 1 session (sess-a1)
        assert dow_map[6] == 1

    def test_weekly_returns_active_weeks(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_weekly_volume(indexed_db)
        assert len(rows) >= 1
        for row in rows:
            assert row["sessions"] > 0
            assert row["week"] is not None

    def test_weekly_token_totals(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_weekly_volume(indexed_db)
        total_tokens = sum(r["tokens"] or 0 for r in rows)
        assert total_tokens > 0

    def test_gaps_returns_stats(self, indexed_db: sqlite3.Connection) -> None:
        gaps = query_session_gaps(indexed_db)
        assert gaps  # Should have gap data with 3 sessions
        assert "count" in gaps
        assert "median_h" in gaps
        assert "avg_h" in gaps
        assert gaps["count"] == 2  # 3 sessions = 2 gaps

    def test_gaps_min_less_than_max(self, indexed_db: sqlite3.Connection) -> None:
        gaps = query_session_gaps(indexed_db)
        assert gaps["min_h"] <= gaps["max_h"]

    def test_gaps_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        gaps = query_session_gaps(indexed_db, project="alpha")
        # alpha has 2 sessions = 1 gap
        assert gaps["count"] == 1


# ---------------------------------------------------------------------------
# Branch patterns
# ---------------------------------------------------------------------------


class TestBranchPatterns:
    def test_returns_branches(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_branch_patterns(indexed_db)
        assert len(rows) == 2  # feat/widgets + main

    def test_branch_has_expected_fields(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_branch_patterns(indexed_db)
        row = rows[0]
        expected_keys = {
            "git_branch", "project", "sessions", "first_session",
            "last_session", "total_tokens", "avg_duration_min",
            "total_events", "dominant_action",
        }
        assert expected_keys.issubset(row.keys())

    def test_branch_session_counts(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_branch_patterns(indexed_db)
        by_branch = {r["git_branch"]: r for r in rows}
        # feat/widgets: sess-a1 + sess-a2 = 2 sessions
        assert by_branch["feat/widgets"]["sessions"] == 2
        # main: sess-b1 = 1 session
        assert by_branch["main"]["sessions"] == 1

    def test_branch_events_exclude_progress(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_branch_patterns(indexed_db)
        by_branch = {r["git_branch"]: r for r in rows}
        # feat/widgets: sess-a1(4) + sess-a2(3) = 7 filtered events
        assert by_branch["feat/widgets"]["total_events"] == 7

    def test_branch_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_branch_patterns(indexed_db, project="beta")
        assert len(rows) == 1
        assert rows[0]["git_branch"] == "main"


# ---------------------------------------------------------------------------
# Memory patterns
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def memory_db(tmp_path_factory: pytest.TempPathFactory) -> sqlite3.Connection:
    """DB with memory reads, CLAUDE.md reads, and SessionStart events."""
    tmp_path = tmp_path_factory.mktemp("memory")
    db_path = tmp_path / "test.db"

    # Project A: /home/user/projects/alpha — 2 sessions with memory + CLAUDE.md reads
    proj_a = tmp_path / "transcripts" / "-home-user-projects-alpha"

    _write_jsonl(
        proj_a / "sess-m1.jsonl",
        [
            _progress_record("2026-02-01T09:00:00Z", "SessionStart", "SessionStart:clear"),
            {"type": "user", "timestamp": "2026-02-01T09:00:01Z",
             "cwd": "/home/user/projects/alpha",
             "gitBranch": "main",
             "message": {"content": "start"}},
            # Memory reads
            _assistant_record(
                "2026-02-01T09:01:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/.claude/memories/essential-foo.md"})],
            ),
            _assistant_record(
                "2026-02-01T09:02:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/.claude/memories/relevant-shared.md"})],
            ),
            # Root CLAUDE.md
            _assistant_record(
                "2026-02-01T09:03:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/CLAUDE.md"})],
            ),
            # Subfolder CLAUDE.md
            _assistant_record(
                "2026-02-01T09:04:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/tests/CLAUDE.md"})],
            ),
        ],
    )

    _write_jsonl(
        proj_a / "sess-m2.jsonl",
        [
            _progress_record("2026-02-03T10:00:00Z", "SessionStart", "SessionStart:startup"),
            {"type": "user", "timestamp": "2026-02-03T10:00:01Z",
             "cwd": "/home/user/projects/alpha",
             "gitBranch": "feat/thing",
             "message": {"content": "continue"}},
            # Same memory again (tests session count vs read count)
            _assistant_record(
                "2026-02-03T10:01:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/.claude/memories/essential-foo.md"})],
            ),
            # Single-use memory (only in this session)
            _assistant_record(
                "2026-02-03T10:02:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/.claude/memories/relevant-once.md"})],
            ),
            # MEMORY.md (should be excluded)
            _assistant_record(
                "2026-02-03T10:03:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/alpha/.claude/memories/MEMORY.md"})],
            ),
        ],
    )

    # Project B: /home/user/projects/beta — 1 session with shared memory name
    proj_b = tmp_path / "transcripts" / "-home-user-projects-beta"

    _write_jsonl(
        proj_b / "sess-m3.jsonl",
        [
            _progress_record("2026-02-05T11:00:00Z", "SessionStart", "SessionStart:clear"),
            {"type": "user", "timestamp": "2026-02-05T11:00:01Z",
             "cwd": "/home/user/projects/beta",
             "gitBranch": "main",
             "message": {"content": "review"}},
            # Same filename as alpha's — shared memory
            _assistant_record(
                "2026-02-05T11:01:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/beta/.claude/memories/relevant-shared.md"})],
            ),
            # Root CLAUDE.md
            _assistant_record(
                "2026-02-05T11:02:00Z",
                [_tool_use_block("Read", {"file_path": "/home/user/projects/beta/CLAUDE.md"})],
            ),
        ],
    )

    conn = init_db(db_path)

    import scripts.sessions.index as si
    original = si.SOURCE_DIRS
    si.SOURCE_DIRS = [tmp_path / "transcripts"]
    try:
        index_sessions(conn)
    finally:
        si.SOURCE_DIRS = original

    return conn


class TestMemoryPatterns:
    def _proj(self, rows: list, substr: str) -> dict:
        """Find a row by project name substring."""
        for r in rows:
            if substr in r["project"]:
                return dict(r)
        raise KeyError(f"No project matching '{substr}'")

    def test_essential_estimate_counts(self, memory_db: sqlite3.Connection) -> None:
        """SessionStart events counted per project as distinct sessions."""
        rows = query_essential_estimates(memory_db)
        assert self._proj(rows, "alpha")["sessions"] == 2  # clear + startup in 2 sessions
        assert self._proj(rows, "beta")["sessions"] == 1   # clear in 1 session

    def test_memory_reads_ranked_by_sessions(self, memory_db: sqlite3.Connection) -> None:
        """Memory reads ordered by session count descending."""
        rows = query_memory_reads(memory_db)
        sessions = [r["sessions"] for r in rows]
        assert sessions == sorted(sessions, reverse=True)
        # essential-foo.md read in 2 sessions
        foo = [r for r in rows if "essential-foo" in r["detail"]]
        assert foo[0]["sessions"] == 2
        assert foo[0]["reads"] == 2

    def test_memory_excludes_memory_md(self, memory_db: sqlite3.Connection) -> None:
        """MEMORY.md index file is not counted as a memory read."""
        rows = query_memory_reads(memory_db)
        details = [r["detail"] for r in rows]
        assert not any("MEMORY.md" in d for d in details)

    def test_shared_memories_global(self, memory_db: sqlite3.Connection) -> None:
        """Same filename across projects detected in global view."""
        rows = query_memory_reads(memory_db)
        # relevant-shared.md appears for both alpha and beta
        shared = [r for r in rows if "relevant-shared" in r["detail"]]
        projects = {r["project"] for r in shared}
        assert len(projects) == 2
        assert any("alpha" in p for p in projects)
        assert any("beta" in p for p in projects)

    def test_claude_md_root_vs_subfolder(self, memory_db: sqlite3.Connection) -> None:
        """Root vs subfolder CLAUDE.md correctly classified."""
        rows = query_claude_md_reads(memory_db)
        for row in rows:
            kind = _classify_claude_md(row["detail"], row["project_path"])
            if row["detail"].endswith("alpha/CLAUDE.md"):
                assert kind == "root"
            elif row["detail"].endswith("tests/CLAUDE.md"):
                assert kind == "tests/"
            elif row["detail"].endswith("beta/CLAUDE.md"):
                assert kind == "root"

    def test_diversity_metrics(self, memory_db: sqlite3.Connection) -> None:
        """Distinct count and per-project metrics."""
        rows = query_memory_diversity(memory_db)
        alpha = self._proj(rows, "alpha")
        beta = self._proj(rows, "beta")
        # alpha: essential-foo, relevant-shared, relevant-once = 3 distinct
        assert alpha["distinct_memories"] == 3
        # beta: relevant-shared = 1 distinct
        assert beta["distinct_memories"] == 1

    def test_filter_by_project(self, memory_db: sqlite3.Connection) -> None:
        """--project narrows all queries."""
        reads = query_memory_reads(memory_db, project="beta")
        assert all("beta" in r["project"] for r in reads)
        assert len(reads) == 1  # only relevant-shared

        essentials = query_essential_estimates(memory_db, project="beta")
        assert len(essentials) == 1
        assert essentials[0]["hook_fires"] == 1

    def test_filter_by_days(self, memory_db: sqlite3.Connection) -> None:
        """--days narrows results (all test data is old, so 0 results with days=1)."""
        reads = query_memory_reads(memory_db, days=1)
        assert len(reads) == 0

    def test_extract_memory_filename(self) -> None:
        assert _extract_memory_filename("/a/b/.claude/memories/essential-foo.md") == "essential-foo.md"
        assert _extract_memory_filename("/x/y/MEMORY.md") == "MEMORY.md"

    def test_classify_claude_md_with_project_path(self) -> None:
        assert _classify_claude_md("/proj/CLAUDE.md", "/proj") == "root"
        assert _classify_claude_md("/proj/src/CLAUDE.md", "/proj") == "src/"
        assert _classify_claude_md("/proj/src/cli/CLAUDE.md", "/proj") == "src/cli/"

    def test_classify_claude_md_without_project_path(self) -> None:
        """Falls back to parent directory name when project_path is None."""
        result = _classify_claude_md("/proj/src/CLAUDE.md", None)
        assert result == "src/"


# ---------------------------------------------------------------------------
# Tool usage
# ---------------------------------------------------------------------------


class TestToolUsage:
    def test_returns_all_tools(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_tool_usage(indexed_db)
        tools = {r["tool"] for r in rows}
        assert "Write" in tools
        assert "Read" in tools
        assert "Bash" in tools
        assert "Grep" in tools

    def test_counts_correct(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_tool_usage(indexed_db)
        by_tool = {r["tool"]: r for r in rows}
        # Read: sess-a1(1) + sess-b1(2) = 3
        assert by_tool["Read"]["total"] == 3
        # Write: sess-a1(1) = 1
        assert by_tool["Write"]["total"] == 1

    def test_all_main_no_subagents(self, indexed_db: sqlite3.Connection) -> None:
        """All test data is from main context, so subagent=0."""
        rows = query_tool_usage(indexed_db)
        for r in rows:
            assert r["subagent"] == 0
            assert r["main"] == r["total"]

    def test_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_tool_usage(indexed_db, project="beta")
        tools = {r["tool"] for r in rows}
        # beta only has Read and Grep
        assert tools == {"Read", "Grep"}

    def test_sorted_by_total_desc(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_tool_usage(indexed_db)
        totals = [r["total"] for r in rows]
        assert totals == sorted(totals, reverse=True)


# ---------------------------------------------------------------------------
# Skill usage
# ---------------------------------------------------------------------------


class TestSkillUsage:
    def test_returns_skills(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_skill_usage(indexed_db)
        names = {r["resource_name"] for r in rows}
        assert "learn" in names
        assert "commit" in names

    def test_counts_correct(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_skill_usage(indexed_db)
        by_name = {r["resource_name"]: r for r in rows}
        # learn: 2 uses (sess-a1 + sess-a2)
        assert by_name["learn"]["total"] == 2
        # commit: 1 use
        assert by_name["commit"]["total"] == 1

    def test_tokens_summed(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_skill_usage(indexed_db)
        by_name = {r["resource_name"]: r for r in rows}
        # learn: (500+200) + (400+150) = 1250
        assert by_name["learn"]["tokens"] == 1250

    def test_sorted_by_total_desc(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_skill_usage(indexed_db)
        totals = [r["total"] for r in rows]
        assert totals == sorted(totals, reverse=True)


# ---------------------------------------------------------------------------
# Agent usage
# ---------------------------------------------------------------------------


class TestAgentUsage:
    def test_returns_agents(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_agent_usage(indexed_db)
        names = {r["resource_name"] for r in rows}
        assert "Explore" in names
        assert "Plan" in names

    def test_counts_correct(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_agent_usage(indexed_db)
        by_name = {r["resource_name"]: r for r in rows}
        # Explore: 2 uses
        assert by_name["Explore"]["count"] == 2
        # Plan: 1 use
        assert by_name["Plan"]["count"] == 1

    def test_tokens_summed(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_agent_usage(indexed_db)
        by_name = {r["resource_name"]: r for r in rows}
        # Explore: (1000+500) + (800+400) = 2700
        assert by_name["Explore"]["tokens"] == 2700

    def test_tool_calls_summed(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_agent_usage(indexed_db)
        by_name = {r["resource_name"]: r for r in rows}
        # Explore: 8 + 6 = 14
        assert by_name["Explore"]["tool_calls"] == 14
        # Plan: 4
        assert by_name["Plan"]["tool_calls"] == 4

    def test_sorted_by_count_desc(self, indexed_db: sqlite3.Connection) -> None:
        rows = query_agent_usage(indexed_db)
        counts = [r["count"] for r in rows]
        assert counts == sorted(counts, reverse=True)


# ---------------------------------------------------------------------------
# Hook usage
# ---------------------------------------------------------------------------


class TestHookUsage:
    def test_returns_by_event_and_by_hook(self, indexed_db: sqlite3.Connection) -> None:
        by_event, by_hook = query_hook_usage(indexed_db)
        assert len(by_event) > 0
        assert len(by_hook) > 0

    def test_event_types(self, indexed_db: sqlite3.Connection) -> None:
        by_event, _ = query_hook_usage(indexed_db)
        events = {r["hook_event"] for r in by_event}
        assert "PreToolUse" in events
        assert "PostToolUse" in events

    def test_hook_names(self, indexed_db: sqlite3.Connection) -> None:
        _, by_hook = query_hook_usage(indexed_db)
        hooks = {r["hook_name"] for r in by_hook}
        assert "Write" in hooks
        assert "Bash" in hooks

    def test_counts_correct(self, indexed_db: sqlite3.Connection) -> None:
        by_event, _ = query_hook_usage(indexed_db)
        by_name = {r["hook_event"]: r for r in by_event}
        # PreToolUse: sess-a1(1 for Write) + sess-a2(1 for Bash) = 2
        assert by_name["PreToolUse"]["total"] == 2
        # PostToolUse: sess-a1(1 for Write) = 1
        assert by_name["PostToolUse"]["total"] == 1

    def test_filter_by_project(self, indexed_db: sqlite3.Connection) -> None:
        by_event, by_hook = query_hook_usage(indexed_db, project="beta")
        # beta has no progress events
        assert len(by_event) == 0
        assert len(by_hook) == 0
