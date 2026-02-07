#!/usr/bin/env python3
"""Analytics for Claude Code transcripts (~/.claude/projects/).

Usage:
    uv run scripts/insights.py overview
    uv run scripts/insights.py projects
    uv run scripts/insights.py tools
    uv run scripts/insights.py skills
    uv run scripts/insights.py agents
    uv run scripts/insights.py hooks
    uv run scripts/insights.py sessions

Global flags:
    --project <name>    Filter to one project (substring match)
    --since YYYY-MM-DD  Only include sessions after date
    --json              JSON output instead of formatted tables
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterator

CLAUDE_PROJECTS_DIR = Path.home() / ".claude" / "projects"

# Regex to strip encoded path prefix and worktree suffix
# e.g. "-home-hata-projects-personal-claude-toolkit--worktrees-feat" -> "claude-toolkit"
PROJECT_PREFIX_RE = re.compile(r"^-home-[^-]+-projects-(?:personal|raiz)-")
WORKTREE_SUFFIX_RE = re.compile(r"--worktrees-.*$")
# Multi-segment project names (e.g. raiz clients: "blumar-bm-sop-backup-20250924-bm-sop")
# are kept as-is after prefix strip — no further collapsing needed.


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------


@dataclass
class TokenUsage:
    input_tokens: int = 0
    output_tokens: int = 0
    cache_creation_input_tokens: int = 0
    cache_read_input_tokens: int = 0


@dataclass
class ToolCall:
    name: str
    timestamp: str
    output_tokens: int = 0  # tokens for the turn containing this tool call


@dataclass
class SkillCall:
    name: str
    timestamp: str
    invoked_by: str  # "user" or "agent"


@dataclass
class AgentCall:
    agent_type: str
    description: str
    timestamp: str


@dataclass
class HookEvent:
    hook_event: str  # SessionStart, PreToolUse, PostToolUse, etc.
    hook_name: str
    timestamp: str


@dataclass
class Session:
    session_id: str
    project: str
    file_path: str
    first_timestamp: str = ""
    last_timestamp: str = ""
    git_branch: str = ""
    model: str = ""
    version: str = ""
    tokens: TokenUsage = field(default_factory=TokenUsage)
    tool_calls: list[ToolCall] = field(default_factory=list)
    skill_calls: list[SkillCall] = field(default_factory=list)
    agent_calls: list[AgentCall] = field(default_factory=list)
    hook_events: list[HookEvent] = field(default_factory=list)
    assistant_turns: int = 0
    user_turns: int = 0

    @property
    def duration_minutes(self) -> float:
        if not self.first_timestamp or not self.last_timestamp:
            return 0.0
        try:
            t0 = _parse_ts(self.first_timestamp)
            t1 = _parse_ts(self.last_timestamp)
            return max(0.0, (t1 - t0).total_seconds() / 60)
        except (ValueError, TypeError):
            return 0.0

    @property
    def total_tokens(self) -> int:
        return (
            self.tokens.input_tokens
            + self.tokens.output_tokens
            + self.tokens.cache_creation_input_tokens
            + self.tokens.cache_read_input_tokens
        )


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------


def _parse_ts(ts: str) -> datetime:
    """Parse ISO timestamp, handling Z suffix and optional microseconds."""
    ts = ts.replace("Z", "+00:00")
    return datetime.fromisoformat(ts)


def extract_project_name(dir_name: str) -> str:
    """Extract human-readable project name from encoded directory name."""
    name = PROJECT_PREFIX_RE.sub("", dir_name)
    name = WORKTREE_SUFFIX_RE.sub("", name)
    # If prefix didn't match (e.g. "-home-hata-projects"), use the full dir after last known segment
    if name == dir_name:
        # Fallback: just strip leading dashes
        name = dir_name.lstrip("-")
    return name


def find_session_files(project_filter: str | None = None) -> Iterator[Path]:
    """Yield all .jsonl session files, optionally filtered by project substring."""
    if not CLAUDE_PROJECTS_DIR.is_dir():
        return
    for project_dir in sorted(CLAUDE_PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        if project_filter:
            proj_name = extract_project_name(project_dir.name)
            if project_filter.lower() not in proj_name.lower():
                continue
        for jsonl_file in sorted(project_dir.glob("*.jsonl")):
            yield jsonl_file


def parse_session(file_path: Path) -> Session:
    """Parse a single JSONL session file into a Session object. Streams line by line."""
    project = extract_project_name(file_path.parent.name)
    session = Session(
        session_id=file_path.stem,
        project=project,
        file_path=str(file_path),
    )

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            _process_record(session, record)

    return session


def _process_record(session: Session, record: dict) -> None:
    """Process a single JSONL record and update session state."""
    ts = record.get("timestamp", "")
    record_type = record.get("type", "")

    # Track timestamps
    if ts:
        if not session.first_timestamp or ts < session.first_timestamp:
            session.first_timestamp = ts
        if not session.last_timestamp or ts > session.last_timestamp:
            session.last_timestamp = ts

    # Track metadata from first record
    if record.get("gitBranch") and not session.git_branch:
        session.git_branch = record["gitBranch"]
    if record.get("version") and not session.version:
        session.version = record["version"]

    # Hook events
    if record_type == "progress":
        data = record.get("data", {})
        if data.get("type") == "hook_progress":
            session.hook_events.append(
                HookEvent(
                    hook_event=data.get("hookEvent", ""),
                    hook_name=data.get("hookName", ""),
                    timestamp=ts,
                )
            )
        return

    # Assistant messages
    if record_type == "assistant":
        session.assistant_turns += 1
        msg = record.get("message", {})

        # Model
        model = msg.get("model", "")
        if model:
            session.model = model  # keep updating to latest

        # Token usage
        usage = msg.get("usage", {})
        if usage:
            session.tokens.input_tokens += usage.get("input_tokens", 0)
            session.tokens.output_tokens += usage.get("output_tokens", 0)
            session.tokens.cache_creation_input_tokens += usage.get(
                "cache_creation_input_tokens", 0
            )
            session.tokens.cache_read_input_tokens += usage.get(
                "cache_read_input_tokens", 0
            )

        # Tool calls in content
        turn_output_tokens = usage.get("output_tokens", 0)
        content = msg.get("content", [])
        if isinstance(content, list):
            tool_uses_in_turn = []
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    tool_name = block.get("name", "unknown")
                    tool_uses_in_turn.append(tool_name)

                    # Detect skills (Skill tool)
                    if tool_name == "Skill":
                        inp = block.get("input", {})
                        session.skill_calls.append(
                            SkillCall(
                                name=inp.get("skill", "unknown"),
                                timestamp=ts,
                                invoked_by="agent",
                            )
                        )

                    # Detect agents (Task tool)
                    if tool_name == "Task":
                        inp = block.get("input", {})
                        session.agent_calls.append(
                            AgentCall(
                                agent_type=inp.get("subagent_type", "unknown"),
                                description=inp.get("description", ""),
                                timestamp=ts,
                            )
                        )

            # Attribute output tokens proportionally across tool calls in this turn
            per_tool_tokens = (
                turn_output_tokens // len(tool_uses_in_turn)
                if tool_uses_in_turn
                else 0
            )
            for tool_name in tool_uses_in_turn:
                session.tool_calls.append(
                    ToolCall(
                        name=tool_name,
                        timestamp=ts,
                        output_tokens=per_tool_tokens,
                    )
                )

        return

    # User messages — check for user-invoked skills
    if record_type == "user":
        session.user_turns += 1
        msg = record.get("message", {})
        content = msg.get("content", "")
        if isinstance(content, str):
            match = re.search(r"<command-name>/([a-z][a-z0-9-]*)</command-name>", content)
            if match:
                session.skill_calls.append(
                    SkillCall(
                        name=match.group(1),
                        timestamp=ts,
                        invoked_by="user",
                    )
                )


# ---------------------------------------------------------------------------
# Aggregation & formatting
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


def _c(colors: dict[str, str]) -> dict[str, str]:
    """Return color dict, respecting NO_COLOR env."""
    import os

    if os.environ.get("NO_COLOR") or not sys.stdout.isatty():
        return NO_COLORS
    return colors


def _fmt_tokens(n: int) -> str:
    """Format token count with K/M suffix."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def _fmt_duration(minutes: float) -> str:
    """Format duration in human-readable form."""
    if minutes < 1:
        return "<1m"
    if minutes < 60:
        return f"{minutes:.0f}m"
    hours = minutes / 60
    if hours < 24:
        return f"{hours:.1f}h"
    days = hours / 24
    return f"{days:.1f}d"


def _table(headers: list[str], rows: list[list[str]], colors: dict[str, str]) -> str:
    """Format aligned table with headers."""
    if not rows:
        return "  (no data)\n"

    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            col_widths[i] = max(col_widths[i], len(cell))

    c = colors
    lines = []

    # Header
    header_parts = []
    for i, h in enumerate(headers):
        if i == 0:
            header_parts.append(f"{c['bold']}{h:<{col_widths[i]}}{c['reset']}")
        else:
            header_parts.append(f"{c['bold']}{h:>{col_widths[i]}}{c['reset']}")
    lines.append("  " + "  ".join(header_parts))

    # Separator
    sep_parts = ["-" * w for w in col_widths]
    lines.append(f"  {c['dim']}{'  '.join(sep_parts)}{c['reset']}")

    # Rows
    for row in rows:
        parts = []
        for i, cell in enumerate(row):
            if i == 0:
                parts.append(f"{cell:<{col_widths[i]}}")
            else:
                parts.append(f"{cell:>{col_widths[i]}}")
        lines.append("  " + "  ".join(parts))

    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def load_sessions(
    project_filter: str | None, since: str | None
) -> list[Session]:
    """Load and parse all matching sessions."""
    sessions = []
    for f in find_session_files(project_filter):
        session = parse_session(f)
        # Filter by date
        if since and session.first_timestamp:
            try:
                session_date = session.first_timestamp[:10]
                if session_date < since:
                    continue
            except (ValueError, IndexError):
                pass
        # Skip empty sessions (no actual messages)
        if session.assistant_turns == 0 and session.user_turns == 0:
            continue
        sessions.append(session)
    return sessions


def cmd_overview(sessions: list[Session], as_json: bool) -> None:
    """High-level summary."""
    total_input = sum(s.tokens.input_tokens for s in sessions)
    total_output = sum(s.tokens.output_tokens for s in sessions)
    total_cache_create = sum(s.tokens.cache_creation_input_tokens for s in sessions)
    total_cache_read = sum(s.tokens.cache_read_input_tokens for s in sessions)
    total_all = total_input + total_output + total_cache_create + total_cache_read
    total_duration = sum(s.duration_minutes for s in sessions)
    total_tools = sum(len(s.tool_calls) for s in sessions)
    total_assistant = sum(s.assistant_turns for s in sessions)
    total_user = sum(s.user_turns for s in sessions)

    # Top projects by total tokens
    project_tokens: dict[str, int] = {}
    for s in sessions:
        project_tokens[s.project] = project_tokens.get(s.project, 0) + s.total_tokens
    top_projects = sorted(project_tokens.items(), key=lambda x: -x[1])[:5]

    # Models used
    model_counts: dict[str, int] = {}
    for s in sessions:
        if s.model:
            model_counts[s.model] = model_counts.get(s.model, 0) + 1

    if as_json:
        print(
            json.dumps(
                {
                    "sessions": len(sessions),
                    "total_duration_minutes": round(total_duration, 1),
                    "tokens": {
                        "input": total_input,
                        "output": total_output,
                        "cache_creation": total_cache_create,
                        "cache_read": total_cache_read,
                        "total": total_all,
                    },
                    "assistant_turns": total_assistant,
                    "user_turns": total_user,
                    "tool_calls": total_tools,
                    "top_projects": [
                        {"project": p, "tokens": t} for p, t in top_projects
                    ],
                    "models": model_counts,
                },
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Claude Code Usage Overview{c['reset']}\n")
    print(f"  Sessions:        {c['bold']}{len(sessions)}{c['reset']}")
    print(f"  Duration:        {_fmt_duration(total_duration)}")
    print(f"  Assistant turns: {total_assistant}")
    print(f"  User turns:      {total_user}")
    print(f"  Tool calls:      {total_tools}")
    print()
    print(f"  {c['bold']}Tokens{c['reset']}")
    print(f"    Input:          {_fmt_tokens(total_input):>8}")
    print(f"    Output:         {_fmt_tokens(total_output):>8}")
    print(f"    Cache create:   {_fmt_tokens(total_cache_create):>8}")
    print(f"    Cache read:     {_fmt_tokens(total_cache_read):>8}")
    print(f"    {c['bold']}Total:          {_fmt_tokens(total_all):>8}{c['reset']}")
    print()

    if top_projects:
        print(f"  {c['bold']}Top Projects (by tokens){c['reset']}")
        rows = [[p, _fmt_tokens(t)] for p, t in top_projects]
        print(_table(["Project", "Tokens"], rows, c))

    if model_counts:
        print(f"  {c['bold']}Models{c['reset']}")
        rows = [
            [m, str(n)]
            for m, n in sorted(model_counts.items(), key=lambda x: -x[1])
        ]
        print(_table(["Model", "Sessions"], rows, c))


def cmd_projects(sessions: list[Session], as_json: bool) -> None:
    """Per-project breakdown."""
    projects: dict[str, dict] = {}
    for s in sessions:
        p = projects.setdefault(
            s.project,
            {
                "sessions": 0,
                "input": 0,
                "output": 0,
                "cache_create": 0,
                "cache_read": 0,
                "duration": 0.0,
                "tools": 0,
            },
        )
        p["sessions"] += 1
        p["input"] += s.tokens.input_tokens
        p["output"] += s.tokens.output_tokens
        p["cache_create"] += s.tokens.cache_creation_input_tokens
        p["cache_read"] += s.tokens.cache_read_input_tokens
        p["duration"] += s.duration_minutes
        p["tools"] += len(s.tool_calls)

    sorted_projects = sorted(
        projects.items(),
        key=lambda x: -(x[1]["input"] + x[1]["output"] + x[1]["cache_create"] + x[1]["cache_read"]),
    )

    if as_json:
        print(
            json.dumps(
                [
                    {"project": name, **data}
                    for name, data in sorted_projects
                ],
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Projects{c['reset']}\n")
    headers = ["Project", "Sessions", "Input", "Output", "Cache Cr", "Cache Rd", "Duration", "Tools"]
    rows = []
    for name, d in sorted_projects:
        rows.append([
            name,
            str(d["sessions"]),
            _fmt_tokens(d["input"]),
            _fmt_tokens(d["output"]),
            _fmt_tokens(d["cache_create"]),
            _fmt_tokens(d["cache_read"]),
            _fmt_duration(d["duration"]),
            str(d["tools"]),
        ])
    print(_table(headers, rows, c))


def cmd_tools(sessions: list[Session], as_json: bool) -> None:
    """Tool usage distribution."""
    tools: dict[str, dict] = {}
    for s in sessions:
        for tc in s.tool_calls:
            t = tools.setdefault(tc.name, {"count": 0, "output_tokens": 0})
            t["count"] += 1
            t["output_tokens"] += tc.output_tokens

    sorted_tools = sorted(tools.items(), key=lambda x: -x[1]["count"])

    if as_json:
        print(
            json.dumps(
                [
                    {"tool": name, **data}
                    for name, data in sorted_tools
                ],
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Tool Usage{c['reset']}\n")
    headers = ["Tool", "Calls", "Output Tokens"]
    rows = [
        [name, str(d["count"]), _fmt_tokens(d["output_tokens"])]
        for name, d in sorted_tools
    ]
    print(_table(headers, rows, c))


def cmd_skills(sessions: list[Session], as_json: bool) -> None:
    """Skill invocation frequency."""
    skills: dict[str, dict] = {}
    for s in sessions:
        for sc in s.skill_calls:
            sk = skills.setdefault(sc.name, {"user": 0, "agent": 0, "total": 0})
            sk[sc.invoked_by] += 1
            sk["total"] += 1

    sorted_skills = sorted(skills.items(), key=lambda x: -x[1]["total"])

    if as_json:
        print(
            json.dumps(
                [{"skill": name, **data} for name, data in sorted_skills],
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Skill Usage{c['reset']}\n")
    headers = ["Skill", "Total", "User", "Agent"]
    rows = [
        [name, str(d["total"]), str(d["user"]), str(d["agent"])]
        for name, d in sorted_skills
    ]
    print(_table(headers, rows, c))


def cmd_agents(sessions: list[Session], as_json: bool) -> None:
    """Sub-agent usage patterns."""
    agents: dict[str, int] = {}
    descriptions: dict[str, list[str]] = {}
    for s in sessions:
        for ac in s.agent_calls:
            agents[ac.agent_type] = agents.get(ac.agent_type, 0) + 1
            descs = descriptions.setdefault(ac.agent_type, [])
            if ac.description and len(descs) < 3:
                descs.append(ac.description)

    sorted_agents = sorted(agents.items(), key=lambda x: -x[1])

    if as_json:
        print(
            json.dumps(
                [
                    {
                        "agent_type": name,
                        "count": count,
                        "example_descriptions": descriptions.get(name, []),
                    }
                    for name, count in sorted_agents
                ],
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Agent Usage{c['reset']}\n")
    headers = ["Agent Type", "Count", "Examples"]
    rows = [
        [name, str(count), "; ".join(descriptions.get(name, [])[:2])]
        for name, count in sorted_agents
    ]
    print(_table(headers, rows, c))


def cmd_hooks(sessions: list[Session], as_json: bool) -> None:
    """Hook event counts."""
    hooks: dict[str, dict[str, int]] = {}  # hookName -> {hookEvent: count}
    event_totals: dict[str, int] = {}
    for s in sessions:
        for he in s.hook_events:
            h = hooks.setdefault(he.hook_name, {})
            h[he.hook_event] = h.get(he.hook_event, 0) + 1
            event_totals[he.hook_event] = event_totals.get(he.hook_event, 0) + 1

    if as_json:
        print(
            json.dumps(
                {
                    "by_hook": hooks,
                    "by_event": event_totals,
                },
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Hook Events{c['reset']}\n")

    # By event type
    print(f"  {c['bold']}By Event Type{c['reset']}")
    sorted_events = sorted(event_totals.items(), key=lambda x: -x[1])
    rows = [[name, str(count)] for name, count in sorted_events]
    print(_table(["Event", "Count"], rows, c))

    # By hook name
    print(f"  {c['bold']}By Hook Name{c['reset']}")
    hook_totals = [(name, sum(evts.values())) for name, evts in hooks.items()]
    hook_totals.sort(key=lambda x: -x[1])
    rows = [[name, str(count)] for name, count in hook_totals]
    print(_table(["Hook", "Count"], rows, c))


def cmd_sessions(sessions: list[Session], as_json: bool) -> None:
    """Session list with details."""
    # Sort by timestamp descending
    sorted_sessions = sorted(sessions, key=lambda s: s.first_timestamp, reverse=True)

    if as_json:
        print(
            json.dumps(
                [
                    {
                        "session_id": s.session_id,
                        "project": s.project,
                        "date": s.first_timestamp[:10] if s.first_timestamp else "",
                        "duration_minutes": round(s.duration_minutes, 1),
                        "model": s.model,
                        "git_branch": s.git_branch,
                        "tokens": {
                            "input": s.tokens.input_tokens,
                            "output": s.tokens.output_tokens,
                            "cache_creation": s.tokens.cache_creation_input_tokens,
                            "cache_read": s.tokens.cache_read_input_tokens,
                            "total": s.total_tokens,
                        },
                        "assistant_turns": s.assistant_turns,
                        "tool_calls": len(s.tool_calls),
                    }
                    for s in sorted_sessions
                ],
                indent=2,
            )
        )
        return

    c = _c(COLORS)
    print(f"\n{c['bold']}{c['cyan']}Sessions{c['reset']}\n")
    headers = ["Date", "Project", "Branch", "Duration", "Tokens", "Tools", "Model"]
    rows = []
    for s in sorted_sessions:
        date = s.first_timestamp[:10] if s.first_timestamp else "?"
        # Shorten model name for display
        model_short = s.model.replace("claude-", "").replace("-20251001", "").replace("-20250929", "")
        rows.append([
            date,
            s.project[:30],
            s.git_branch[:20] if s.git_branch else "-",
            _fmt_duration(s.duration_minutes),
            _fmt_tokens(s.total_tokens),
            str(len(s.tool_calls)),
            model_short,
        ])
    print(_table(headers, rows, c))
    print(f"  {c['dim']}Showing {len(sorted_sessions)} sessions{c['reset']}\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analytics for Claude Code transcripts",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "command",
        choices=["overview", "projects", "tools", "skills", "agents", "hooks", "sessions", "full"],
        help="Subcommand to run",
    )
    parser.add_argument(
        "--project",
        help="Filter to one project (substring match)",
    )
    parser.add_argument(
        "--since",
        help="Only include sessions after date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="JSON output instead of formatted tables",
    )
    parser.add_argument(
        "--output",
        metavar="PATH",
        help="Write output to file instead of console",
    )
    args = parser.parse_args()

    # Validate --since format
    if args.since:
        try:
            datetime.strptime(args.since, "%Y-%m-%d")
        except ValueError:
            print(f"Error: --since must be YYYY-MM-DD format, got '{args.since}'", file=sys.stderr)
            sys.exit(1)

    # Redirect stdout to file if --output given
    output_file = None
    if args.output:
        output_file = open(args.output, "w", encoding="utf-8")
        sys.stdout = output_file

    # Load sessions with progress indicator
    if not args.as_json and sys.stderr.isatty():
        print("Loading sessions...", end="", flush=True, file=sys.stderr)

    sessions = load_sessions(args.project, args.since)

    if not args.as_json and sys.stderr.isatty():
        print(f" {len(sessions)} sessions loaded.", file=sys.stderr)

    if not sessions:
        print("No sessions found.", file=sys.stderr)
        if output_file:
            output_file.close()
        sys.exit(0)

    commands = {
        "overview": cmd_overview,
        "projects": cmd_projects,
        "tools": cmd_tools,
        "skills": cmd_skills,
        "agents": cmd_agents,
        "hooks": cmd_hooks,
        "sessions": cmd_sessions,
    }

    if args.command == "full":
        for name, cmd_fn in commands.items():
            cmd_fn(sessions, args.as_json)
    else:
        commands[args.command](sessions, args.as_json)

    if output_file:
        output_file.close()
        # Print confirmation to real stderr
        print(f"Output written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
