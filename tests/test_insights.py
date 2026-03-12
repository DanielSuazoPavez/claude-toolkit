"""Tests for scripts/insights.py — Claude Code transcript analytics."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts.insights import (
    Session,
    TokenUsage,
    _fmt_duration,
    _fmt_tokens,
    _parse_subagent,
    _parse_ts,
    _process_record,
    cmd_hooks,
    cmd_overview,
    cmd_sessions,
    cmd_skills,
    cmd_tools,
    extract_project_name,
    load_sessions,
    parse_session,
)


# ---------------------------------------------------------------------------
# Record builders
# ---------------------------------------------------------------------------


def _assistant_record(
    ts: str,
    model: str,
    usage: dict,
    content: list,
    **extra: str,
) -> dict:
    """Build an assistant JSONL record."""
    rec = {
        "type": "assistant",
        "timestamp": ts,
        "message": {
            "model": model,
            "usage": usage,
            "content": content,
        },
    }
    rec.update(extra)
    return rec


def _user_record(ts: str, content: str) -> dict:
    """Build a user JSONL record."""
    return {
        "type": "user",
        "timestamp": ts,
        "message": {"content": content},
    }


def _progress_record(ts: str, hook_event: str, hook_name: str) -> dict:
    """Build a hook progress JSONL record."""
    return {
        "type": "progress",
        "timestamp": ts,
        "data": {
            "type": "hook_progress",
            "hookEvent": hook_event,
            "hookName": hook_name,
        },
    }


def _tool_use_block(name: str, input_dict: dict | None = None) -> dict:
    """Build a tool_use content block."""
    block = {"type": "tool_use", "name": name}
    if input_dict is not None:
        block["input"] = input_dict
    return block


def _write_jsonl(path: Path, records: list[dict], *, inject_bad_line: bool = False) -> None:
    """Write records as JSONL, optionally injecting a malformed line after record 0."""
    lines = []
    for i, rec in enumerate(records):
        lines.append(json.dumps(rec))
        if inject_bad_line and i == 0:
            lines.append("{not json")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Module-scoped fixture: transcripts_dir
# ---------------------------------------------------------------------------

# Session-1 records (project: my-project)
_SESSION1_RECORDS = [
    _assistant_record(
        ts="2026-03-10T10:00:00Z",
        model="claude-opus-4-6",
        usage={"input_tokens": 1000, "output_tokens": 200, "cache_creation_input_tokens": 500, "cache_read_input_tokens": 3000},
        content=[
            _tool_use_block("Read"),
            _tool_use_block("Edit"),
            _tool_use_block("Skill", {"skill": "wrap-up"}),
            _tool_use_block("Task", {"subagent_type": "Explore", "description": "test"}),
        ],
        gitBranch="feat/test",
        version="1.0.0",
    ),
    _progress_record("2026-03-10T10:01:00Z", "PreToolUse", "PreToolUse:Read"),
    _progress_record("2026-03-10T10:01:01Z", "PostToolUse", "PostToolUse:Read"),
    _user_record("2026-03-10T10:02:00Z", "please run <command-name>/wrap-up</command-name>"),
    _user_record("2026-03-10T10:03:00Z", "looks good"),
    _assistant_record(
        ts="2026-03-10T10:04:00Z",
        model="claude-opus-4-6",
        usage={"input_tokens": 800, "output_tokens": 300, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 2000},
        content=[
            _tool_use_block("Bash"),
            _tool_use_block("Grep"),
        ],
    ),
]

# Subagent records
_SUBAGENT_RECORDS = [
    _assistant_record(
        ts="2026-03-10T10:05:00Z",
        model="claude-haiku-4-5-20251001",
        usage={"input_tokens": 400, "output_tokens": 100, "cache_creation_input_tokens": 200, "cache_read_input_tokens": 1000},
        content=[
            _tool_use_block("Read"),
            _tool_use_block("Skill", {"skill": "snap-back"}),
        ],
    ),
    _progress_record("2026-03-10T10:05:30Z", "PreToolUse", "PreToolUse:Read"),
    _user_record("2026-03-10T10:06:00Z", '[{"type":"tool_result"}]'),
]

# Session-2 records (project: other-project)
_SESSION2_RECORDS = [
    _assistant_record(
        ts="2026-03-10T10:10:00Z",
        model="claude-opus-4-6",
        usage={"input_tokens": 500, "output_tokens": 150, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 1500},
        content=[_tool_use_block("Bash")],
    ),
    _user_record("2026-03-10T10:11:00Z", "thanks"),
]


@pytest.fixture(scope="module")
def transcripts_dir(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Create a synthetic transcripts directory mimicking ~/.claude/projects/."""
    root = tmp_path_factory.mktemp("transcripts")

    # Project 1: my-project
    proj1 = root / "-home-user-projects-personal-my-project"
    proj1.mkdir()
    _write_jsonl(proj1 / "session-1.jsonl", _SESSION1_RECORDS, inject_bad_line=True)

    # Subagent dir for session-1
    sa_dir = proj1 / "session-1" / "subagents"
    sa_dir.mkdir(parents=True)
    _write_jsonl(sa_dir / "agent-abc123.jsonl", _SUBAGENT_RECORDS)
    (sa_dir / "agent-abc123.meta.json").write_text(
        json.dumps({"agentType": "Explore"}), encoding="utf-8"
    )

    # Empty session
    (proj1 / "session-empty.jsonl").write_text("", encoding="utf-8")

    # Project 2: other-project
    proj2 = root / "-home-user-projects-personal-other-project"
    proj2.mkdir()
    _write_jsonl(proj2 / "session-2.jsonl", _SESSION2_RECORDS)

    return root


@pytest.fixture(scope="module")
def all_sessions(transcripts_dir: Path) -> list[Session]:
    """Load all sessions from the fixture transcripts dir."""
    return load_sessions(project_filter=None, since=None, transcripts_dir=transcripts_dir)


def test_import_succeeds():
    """Smoke test: module imports without error."""
    assert hasattr(parse_session, "__call__")


def test_fixture_creates_expected_files(transcripts_dir: Path):
    """Fixture builds expected directory structure."""
    proj1 = transcripts_dir / "-home-user-projects-personal-my-project"
    proj2 = transcripts_dir / "-home-user-projects-personal-other-project"
    assert (proj1 / "session-1.jsonl").exists()
    assert (proj1 / "session-empty.jsonl").exists()
    assert (proj1 / "session-1" / "subagents" / "agent-abc123.jsonl").exists()
    assert (proj1 / "session-1" / "subagents" / "agent-abc123.meta.json").exists()
    assert (proj2 / "session-2.jsonl").exists()


# ---------------------------------------------------------------------------
# Unit tests: pure functions, no I/O
# ---------------------------------------------------------------------------


class TestTimestampParsing:
    def test_iso_timestamp_parsed(self):
        dt = _parse_ts("2026-03-10T10:00:00+00:00")
        assert dt.hour == 10
        assert dt.minute == 0

    def test_z_suffix_converted_to_utc_offset(self):
        dt = _parse_ts("2026-03-10T10:00:00Z")
        assert dt.tzinfo is not None
        assert str(dt.tzinfo) == "UTC"

    def test_invalid_timestamp_raises(self):
        with pytest.raises(ValueError):
            _parse_ts("not-a-timestamp")


class TestProjectNameExtraction:
    @pytest.mark.parametrize(
        "dir_name, expected",
        [
            ("-home-hata-projects-personal-claude-toolkit", "claude-toolkit"),
            ("-home-hata-projects-personal-claude-toolkit--worktrees-feat", "claude-toolkit"),
            ("-home-hata-projects-raiz-blumar-bm-sop", "blumar-bm-sop"),
            ("-some-other-prefix", "some-other-prefix"),
        ],
    )
    def test_extraction(self, dir_name: str, expected: str):
        assert extract_project_name(dir_name) == expected


class TestTokenFormatting:
    @pytest.mark.parametrize(
        "n, expected",
        [
            (0, "0"),
            (500, "500"),
            (1500, "1.5K"),
            (1_000_000, "1.0M"),
            (2_500_000, "2.5M"),
        ],
    )
    def test_format(self, n: int, expected: str):
        assert _fmt_tokens(n) == expected


class TestDurationFormatting:
    @pytest.mark.parametrize(
        "minutes, expected",
        [
            (0.5, "<1m"),
            (45, "45m"),
            (90, "1.5h"),
            (1500, "1.0d"),
        ],
    )
    def test_format(self, minutes: float, expected: str):
        assert _fmt_duration(minutes) == expected


class TestSessionProperties:
    def test_duration_from_valid_timestamps(self):
        s = Session(session_id="x", project="p", file_path="/tmp/x")
        s.first_timestamp = "2026-03-10T10:00:00Z"
        s.last_timestamp = "2026-03-10T10:30:00Z"
        assert s.duration_minutes == 30.0

    def test_duration_zero_when_timestamps_missing(self):
        s = Session(session_id="x", project="p", file_path="/tmp/x")
        assert s.duration_minutes == 0.0

    def test_duration_zero_when_timestamps_invalid(self):
        s = Session(session_id="x", project="p", file_path="/tmp/x")
        s.first_timestamp = "garbage"
        s.last_timestamp = "garbage"
        assert s.duration_minutes == 0.0

    def test_total_tokens_sums_all_fields(self):
        s = Session(session_id="x", project="p", file_path="/tmp/x")
        s.tokens = TokenUsage(input_tokens=100, output_tokens=50, cache_creation_input_tokens=25, cache_read_input_tokens=75)
        assert s.total_tokens == 250


# ---------------------------------------------------------------------------
# Parsing tests
# ---------------------------------------------------------------------------


class TestRecordProcessing:
    def _make_session(self) -> Session:
        return Session(session_id="test", project="test", file_path="/tmp/test")

    def test_assistant_record_accumulates_tokens_and_model(self):
        s = self._make_session()
        rec = _assistant_record(
            "2026-03-10T10:00:00Z", "claude-opus-4-6",
            {"input_tokens": 100, "output_tokens": 50, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            [],
        )
        _process_record(s, rec)
        assert s.tokens.input_tokens == 100
        assert s.tokens.output_tokens == 50
        assert s.model == "claude-opus-4-6"
        assert s.assistant_turns == 1

    def test_tool_calls_get_proportional_output_tokens(self):
        s = self._make_session()
        rec = _assistant_record(
            "2026-03-10T10:00:00Z", "claude-opus-4-6",
            {"input_tokens": 0, "output_tokens": 300, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            [_tool_use_block("Bash"), _tool_use_block("Grep")],
        )
        _process_record(s, rec)
        assert len(s.tool_calls) == 2
        assert all(tc.output_tokens == 150 for tc in s.tool_calls)

    def test_skill_tool_detected_as_agent_invoked_skill(self):
        s = self._make_session()
        rec = _assistant_record(
            "2026-03-10T10:00:00Z", "claude-opus-4-6",
            {"input_tokens": 0, "output_tokens": 100, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            [_tool_use_block("Skill", {"skill": "wrap-up"})],
        )
        _process_record(s, rec)
        assert len(s.skill_calls) == 1
        assert s.skill_calls[0].name == "wrap-up"
        assert s.skill_calls[0].invoked_by == "agent"

    def test_task_tool_detected_as_agent_call(self):
        s = self._make_session()
        rec = _assistant_record(
            "2026-03-10T10:00:00Z", "claude-opus-4-6",
            {"input_tokens": 0, "output_tokens": 100, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            [_tool_use_block("Task", {"subagent_type": "Explore", "description": "test"})],
        )
        _process_record(s, rec)
        assert len(s.agent_calls) == 1
        assert s.agent_calls[0].agent_type == "Explore"

    def test_user_record_increments_turn_count(self):
        s = self._make_session()
        _process_record(s, _user_record("2026-03-10T10:00:00Z", "hello"))
        assert s.user_turns == 1

    def test_user_skill_command_detected(self):
        s = self._make_session()
        _process_record(s, _user_record("2026-03-10T10:00:00Z", "run <command-name>/wrap-up</command-name>"))
        assert len(s.skill_calls) == 1
        assert s.skill_calls[0].name == "wrap-up"
        assert s.skill_calls[0].invoked_by == "user"

    def test_progress_hook_creates_hook_event(self):
        s = self._make_session()
        _process_record(s, _progress_record("2026-03-10T10:00:00Z", "PreToolUse", "PreToolUse:Read"))
        assert len(s.hook_events) == 1
        assert s.hook_events[0].hook_event == "PreToolUse"
        assert s.hook_events[0].hook_name == "PreToolUse:Read"

    def test_unknown_record_type_ignored(self):
        s = self._make_session()
        _process_record(s, {"type": "unknown_thing", "timestamp": "2026-03-10T10:00:00Z"})
        assert s.assistant_turns == 0
        assert s.user_turns == 0


class TestSubagentParsing:
    @pytest.fixture(scope="class")
    def subagent_dir(self, tmp_path_factory: pytest.TempPathFactory) -> Path:
        d = tmp_path_factory.mktemp("subagent")
        _write_jsonl(d / "agent-abc123.jsonl", _SUBAGENT_RECORDS)
        (d / "agent-abc123.meta.json").write_text(json.dumps({"agentType": "Explore"}), encoding="utf-8")
        # Also create one without meta for missing-meta test
        _write_jsonl(d / "agent-nometa.jsonl", _SUBAGENT_RECORDS)
        return d

    def _parse(self, subagent_dir: Path, agent_file: str = "agent-abc123.jsonl", meta_file: str | None = "agent-abc123.meta.json"):
        jsonl = subagent_dir / agent_file
        meta = subagent_dir / meta_file if meta_file else None
        return _parse_subagent(jsonl, meta)

    def test_subagent_extracts_type_model_tokens_tools(self, subagent_dir: Path):
        info = self._parse(subagent_dir)
        assert info.agent_type == "Explore"
        assert info.model == "claude-haiku-4-5-20251001"
        assert info.tokens.input_tokens == 400
        assert info.tokens.output_tokens == 100
        assert len(info.tool_calls) == 2

    def test_subagent_hook_events_parsed(self, subagent_dir: Path):
        info = self._parse(subagent_dir)
        assert len(info.hook_events) == 1
        assert info.hook_events[0].hook_name == "PreToolUse:Read"

    def test_subagent_user_turns_counted(self, subagent_dir: Path):
        info = self._parse(subagent_dir)
        assert info.user_turns == 1

    def test_subagent_skill_calls_detected(self, subagent_dir: Path):
        info = self._parse(subagent_dir)
        assert len(info.skill_calls) == 1
        assert info.skill_calls[0].name == "snap-back"
        assert info.skill_calls[0].invoked_by == "agent"

    def test_subagent_output_tokens_attributed(self, subagent_dir: Path):
        info = self._parse(subagent_dir)
        # 100 output_tokens / 2 tools = 50 each
        assert all(tc.output_tokens == 50 for tc in info.tool_calls)

    def test_missing_meta_defaults_to_unknown_type(self, subagent_dir: Path):
        info = self._parse(subagent_dir, agent_file="agent-nometa.jsonl", meta_file=None)
        assert info.agent_type == "unknown"


class TestSessionParsing:
    def test_session_with_subagent_dir_populates_subagents(self, transcripts_dir: Path):
        f = transcripts_dir / "-home-user-projects-personal-my-project" / "session-1.jsonl"
        s = parse_session(f)
        assert len(s.subagents) == 1
        assert s.subagents[0].agent_type == "Explore"

    def test_session_without_subagent_dir_has_empty_list(self, transcripts_dir: Path):
        f = transcripts_dir / "-home-user-projects-personal-other-project" / "session-2.jsonl"
        s = parse_session(f)
        assert s.subagents == []

    def test_malformed_json_line_skipped(self, transcripts_dir: Path):
        """Session-1 has a bad line injected; parsing should still succeed."""
        f = transcripts_dir / "-home-user-projects-personal-my-project" / "session-1.jsonl"
        s = parse_session(f)
        # Should still get all valid records processed
        assert s.assistant_turns == 2
        assert s.user_turns == 2


# ---------------------------------------------------------------------------
# Integration tests: load_sessions + cmd_* output
# ---------------------------------------------------------------------------


class TestSessionLoading:
    def test_loads_expected_session_count(self, all_sessions: list[Session]):
        assert len(all_sessions) == 2

    def test_project_filter_narrows_results(self, transcripts_dir: Path):
        sessions = load_sessions(project_filter="my-project", since=None, transcripts_dir=transcripts_dir)
        assert len(sessions) == 1
        assert sessions[0].project == "my-project"

    def test_empty_sessions_excluded(self, transcripts_dir: Path):
        """session-empty.jsonl should not appear."""
        sessions = load_sessions(project_filter=None, since=None, transcripts_dir=transcripts_dir)
        ids = [s.session_id for s in sessions]
        assert "session-empty" not in ids


class TestToolsCommand:
    def test_subagent_columns_shown_when_subagents_present(self, all_sessions: list[Session], capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        cmd_tools(all_sessions, as_json=False)
        out = capsys.readouterr().out
        assert "Main" in out
        assert "Subagent" in out
        assert "Total" in out

    def test_simple_columns_when_no_subagents(self, transcripts_dir: Path, capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        sessions = load_sessions(project_filter="other-project", since=None, transcripts_dir=transcripts_dir)
        cmd_tools(sessions, as_json=False)
        out = capsys.readouterr().out
        assert "Calls" in out
        assert "Main" not in out

    def test_json_includes_source_breakdown(self, all_sessions: list[Session], capsys):
        cmd_tools(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        assert isinstance(data, list)
        assert all("main" in entry and "subagent" in entry and "total" in entry for entry in data)


class TestHooksCommand:
    def test_subagent_breakdown_in_both_tables(self, all_sessions: list[Session], capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        cmd_hooks(all_sessions, as_json=False)
        out = capsys.readouterr().out
        assert "Main" in out
        assert "Subagent" in out

    def test_simple_format_when_no_subagents(self, transcripts_dir: Path, capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        sessions = load_sessions(project_filter="other-project", since=None, transcripts_dir=transcripts_dir)
        cmd_hooks(sessions, as_json=False)
        out = capsys.readouterr().out
        # No hooks in other-project, so should show "no data"
        assert "no data" in out

    def test_json_has_by_event_and_by_hook_with_sources(self, all_sessions: list[Session], capsys):
        cmd_hooks(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        assert "by_event" in data
        assert "by_hook" in data
        for entry in data["by_event"].values():
            assert "main" in entry and "subagent" in entry and "total" in entry


class TestOverviewCommand:
    def test_subagent_detail_section_with_correct_counts(self, all_sessions: list[Session], capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        cmd_overview(all_sessions, as_json=False)
        out = capsys.readouterr().out
        assert "Subagent Detail" in out
        assert "Spawned:" in out

    def test_json_subagents_has_new_fields(self, all_sessions: list[Session], capsys):
        cmd_overview(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        sa = data["subagents"]
        assert "hook_events" in sa
        assert "skill_calls" in sa
        assert "user_turns" in sa

    def test_token_totals_match_fixture_data(self, all_sessions: list[Session], capsys):
        cmd_overview(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        tokens = data["tokens"]
        # Session 1: 1800 input, 500 output, 500 cache_create, 5000 cache_read
        # Session 2: 500 input, 150 output, 0 cache_create, 1500 cache_read
        assert tokens["input"] == 1800 + 500
        assert tokens["output"] == 500 + 150
        assert tokens["cache_creation"] == 500
        assert tokens["cache_read"] == 5000 + 1500
        assert tokens["total"] == 2300 + 650 + 500 + 6500


class TestSkillsCommand:
    def test_subagent_skill_calls_included(self, all_sessions: list[Session], capsys):
        cmd_skills(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        skill_names = [entry["skill"] for entry in data]
        assert "snap-back" in skill_names  # from subagent

    def test_user_vs_agent_attribution_correct(self, all_sessions: list[Session], capsys):
        cmd_skills(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        wrap_up = next(e for e in data if e["skill"] == "wrap-up")
        # 1 from Skill tool (agent) + 1 from command-name (user)
        assert wrap_up["agent"] == 1
        assert wrap_up["user"] == 1
        assert wrap_up["total"] == 2


class TestSessionsCommand:
    def test_json_subagent_entries_have_detail_fields(self, all_sessions: list[Session], capsys):
        cmd_sessions(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        # Find session with subagents
        with_sa = [s for s in data if s["subagents"]]
        assert len(with_sa) == 1
        sa = with_sa[0]["subagents"][0]
        assert "hook_events" in sa
        assert "skill_calls" in sa
        assert "user_turns" in sa

    def test_sessions_sorted_by_timestamp_descending(self, all_sessions: list[Session], capsys):
        cmd_sessions(all_sessions, as_json=True)
        data = json.loads(capsys.readouterr().out)
        dates = [s["date"] for s in data]
        assert dates == sorted(dates, reverse=True)


class TestFullCommand:
    def test_all_section_headers_present(self, all_sessions: list[Session], capsys, monkeypatch):
        monkeypatch.setenv("NO_COLOR", "1")
        # Run all commands like "full" does
        cmd_overview(all_sessions, as_json=False)
        cmd_tools(all_sessions, as_json=False)
        cmd_skills(all_sessions, as_json=False)
        cmd_hooks(all_sessions, as_json=False)
        cmd_sessions(all_sessions, as_json=False)
        out = capsys.readouterr().out
        for header in ["Overview", "Tool Usage", "Skill Usage", "Hook Events", "Sessions"]:
            assert header in out
