#!/usr/bin/env python3
"""Session analytics for Claude Code — usage patterns from the session index DB.

Builds on the session-index.db created by session_search.py.

Usage:
    uv run scripts/session_analytics.py sessions [--project <name>] [--days N] [--limit N]
    uv run scripts/session_analytics.py projects [--days N]
    uv run scripts/session_analytics.py time [--project <name>] [--days N]
    uv run scripts/session_analytics.py branches [--project <name>] [--days N] [--limit N]
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from session_search import DB_PATH, _c, _fmt_tokens, init_db

# ---------------------------------------------------------------------------
# Preprocessing: base queries that filter out hook/progress noise
# ---------------------------------------------------------------------------

# All analytics queries should use this CTE or WHERE clause
FILTERED_EVENTS_CTE = """
filtered_events AS (
    SELECT * FROM events WHERE event_type != 'progress'
)
"""


def _cte(extra: str = "") -> str:
    """Build a WITH clause with the filtered events CTE plus optional extras."""
    parts = [FILTERED_EVENTS_CTE]
    if extra:
        parts.append(extra)
    return "WITH " + ",\n".join(parts)


# ---------------------------------------------------------------------------
# Step 1: Session shape
# ---------------------------------------------------------------------------

SESSION_SHAPE_SQL = f"""
{_cte()}
SELECT
    s.session_id,
    p.name as project,
    s.first_ts,
    s.last_ts,
    s.git_branch,
    s.model,
    s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens as total_tokens,
    -- Duration in minutes
    CASE
        WHEN s.first_ts IS NOT NULL AND s.last_ts IS NOT NULL
        THEN (julianday(s.last_ts) - julianday(s.first_ts)) * 24 * 60
        ELSE 0
    END as duration_min,
    -- Event counts from filtered set
    (SELECT COUNT(*) FROM filtered_events fe WHERE fe.session_id = s.session_id) as event_count,
    -- Distinct tools used
    (SELECT COUNT(DISTINCT fe.tool) FROM filtered_events fe
     WHERE fe.session_id = s.session_id AND fe.tool IS NOT NULL) as tool_diversity,
    -- Dominant action type
    (SELECT fe.action_type FROM filtered_events fe
     WHERE fe.session_id = s.session_id AND fe.action_type IS NOT NULL
     GROUP BY fe.action_type ORDER BY COUNT(*) DESC LIMIT 1) as dominant_action
FROM sessions s
JOIN projects p ON s.project_id = p.id
"""


def query_session_shapes(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[sqlite3.Row]:
    """Get per-session shape metrics."""
    sql = SESSION_SHAPE_SQL
    params: list = []
    wheres: list[str] = []

    if project:
        wheres.append("p.name LIKE ?")
        params.append(f"%{project}%")
    if days:
        wheres.append("s.last_ts >= date('now', ?)")
        params.append(f"-{days} days")

    if wheres:
        sql += " WHERE " + " AND ".join(wheres)

    sql += " ORDER BY s.last_ts DESC"

    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def cmd_sessions(args: argparse.Namespace) -> None:
    """Show per-session shape metrics."""
    conn = init_db(args.db_path)
    c = _c()

    rows = query_session_shapes(conn, project=args.project, days=args.days)
    conn.close()

    if not rows:
        print("No sessions found.")
        return

    limit = args.limit
    showing = rows[:limit]

    print(f"\n{c['bold']}{c['cyan']}Session Shapes{c['reset']} ({len(rows)} total)\n")
    print(
        f"  {'Date':12} {'Project':30} {'Dur':>6} {'Events':>7} "
        f"{'Tools':>5} {'Tokens':>9} {'Dominant':>12}"
    )
    print(f"  {'─' * 12} {'─' * 30} {'─' * 6} {'─' * 7} {'─' * 5} {'─' * 9} {'─' * 12}")

    for row in showing:
        date = (row["last_ts"] or "")[:10]
        proj = (row["project"] or "")[:30]
        dur = f"{row['duration_min']:.0f}m" if row["duration_min"] else "—"
        events = row["event_count"]
        tools = row["tool_diversity"]
        tokens = _fmt_tokens(row["total_tokens"] or 0)
        dominant = row["dominant_action"] or "—"
        print(f"  {date:12} {proj:30} {dur:>6} {events:>7} {tools:>5} {tokens:>9} {dominant:>12}")

    if len(rows) > limit:
        print(f"\n  ... and {len(rows) - limit} more (use --limit to show more)")

    # Summary stats
    durations = [r["duration_min"] for r in rows if r["duration_min"] and r["duration_min"] > 0]
    event_counts = [r["event_count"] for r in rows]
    token_counts = [r["total_tokens"] for r in rows if r["total_tokens"]]

    print(f"\n  {c['bold']}Summary{c['reset']}")
    if durations:
        avg_dur = sum(durations) / len(durations)
        med_dur = sorted(durations)[len(durations) // 2]
        print(f"    Duration:  avg {avg_dur:.0f}m, median {med_dur:.0f}m")
    if event_counts:
        avg_ev = sum(event_counts) / len(event_counts)
        print(f"    Events:    avg {avg_ev:.0f}/session")
    if token_counts:
        avg_tok = sum(token_counts) / len(token_counts)
        print(f"    Tokens:    avg {_fmt_tokens(int(avg_tok))}/session")


# ---------------------------------------------------------------------------
# Step 2: Project patterns
# ---------------------------------------------------------------------------

PROJECT_PATTERNS_SQL = f"""
{_cte()}
SELECT
    p.name as project,
    p.session_count as total_sessions,
    p.first_seen,
    p.last_seen,
    -- Filtered event count
    (SELECT COUNT(*) FROM filtered_events fe WHERE fe.project_id = p.id) as event_count,
    -- Total tokens
    (SELECT SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens)
     FROM sessions s WHERE s.project_id = p.id) as total_tokens,
    -- Avg session duration in minutes
    (SELECT AVG(
        CASE WHEN s.first_ts IS NOT NULL AND s.last_ts IS NOT NULL
        THEN (julianday(s.last_ts) - julianday(s.first_ts)) * 24 * 60
        END)
     FROM sessions s WHERE s.project_id = p.id) as avg_duration_min,
    -- Avg events per session (filtered)
    CAST((SELECT COUNT(*) FROM filtered_events fe WHERE fe.project_id = p.id) AS REAL)
        / MAX(p.session_count, 1) as avg_events_per_session,
    -- Peak week (most sessions)
    (SELECT strftime('%Y-W%W', s.last_ts)
     FROM sessions s WHERE s.project_id = p.id
     GROUP BY strftime('%Y-W%W', s.last_ts)
     ORDER BY COUNT(*) DESC LIMIT 1) as peak_week,
    -- Peak week session count
    (SELECT COUNT(*)
     FROM sessions s WHERE s.project_id = p.id
     GROUP BY strftime('%Y-W%W', s.last_ts)
     ORDER BY COUNT(*) DESC LIMIT 1) as peak_week_sessions,
    -- Dominant action type across all sessions
    (SELECT fe.action_type FROM filtered_events fe
     WHERE fe.project_id = p.id AND fe.action_type IS NOT NULL
     GROUP BY fe.action_type ORDER BY COUNT(*) DESC LIMIT 1) as dominant_action,
    -- Days active (distinct dates with sessions)
    (SELECT COUNT(DISTINCT date(s.last_ts))
     FROM sessions s WHERE s.project_id = p.id) as days_active
FROM projects p
"""


def query_project_patterns(
    conn: sqlite3.Connection,
    days: int | None = None,
) -> list[sqlite3.Row]:
    """Get project-level usage patterns."""
    sql = PROJECT_PATTERNS_SQL
    params: list = []

    if days:
        sql += " WHERE p.last_seen >= date('now', ?)"
        params.append(f"-{days} days")

    sql += " ORDER BY total_sessions DESC"

    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def cmd_projects(args: argparse.Namespace) -> None:
    """Show project usage patterns."""
    conn = init_db(args.db_path)
    c = _c()

    rows = query_project_patterns(conn, days=args.days)
    conn.close()

    if not rows:
        print("No projects found.")
        return

    print(f"\n{c['bold']}{c['cyan']}Project Patterns{c['reset']}\n")

    for row in rows:
        proj = row["project"]
        sessions = row["total_sessions"]
        events = row["event_count"]
        tokens = _fmt_tokens(row["total_tokens"] or 0)
        avg_dur = row["avg_duration_min"]
        avg_ev = row["avg_events_per_session"]
        peak = row["peak_week"] or "—"
        peak_n = row["peak_week_sessions"] or 0
        dominant = row["dominant_action"] or "—"
        days_active = row["days_active"]
        first = (row["first_seen"] or "")[:10]
        last = (row["last_seen"] or "")[:10]

        # Lifecycle span in days
        span = ""
        if row["first_seen"] and row["last_seen"]:
            from datetime import datetime
            try:
                d1 = datetime.fromisoformat(row["first_seen"][:10])
                d2 = datetime.fromisoformat(row["last_seen"][:10])
                span_days = (d2 - d1).days
                span = f"{span_days}d span"
            except ValueError:
                span = ""

        print(f"  {c['bold']}{proj}{c['reset']}")
        print(f"    {sessions} sessions, {events} events, {tokens} tokens")
        print(f"    Active: {first} → {last} ({span}, {days_active}d active)")
        if avg_dur:
            print(f"    Avg session: {avg_dur:.0f}m duration, {avg_ev:.0f} events")
        print(f"    Peak: {peak} ({peak_n} sessions)")
        print(f"    Dominant action: {dominant}")
        print()


# ---------------------------------------------------------------------------
# Step 3: Time patterns
# ---------------------------------------------------------------------------

HOURLY_ACTIVITY_SQL = """
SELECT
    CAST(strftime('%H', s.first_ts) AS INTEGER) as hour,
    COUNT(*) as sessions,
    SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens) as tokens
FROM sessions s
JOIN projects p ON s.project_id = p.id
WHERE s.first_ts IS NOT NULL
"""

DAILY_ACTIVITY_SQL = """
SELECT
    CAST(strftime('%w', s.first_ts) AS INTEGER) as dow,
    COUNT(*) as sessions,
    SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens) as tokens
FROM sessions s
JOIN projects p ON s.project_id = p.id
WHERE s.first_ts IS NOT NULL
"""

WEEKLY_VOLUME_SQL = """
SELECT
    strftime('%Y-W%W', s.last_ts) as week,
    COUNT(*) as sessions,
    SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens) as tokens
FROM sessions s
JOIN projects p ON s.project_id = p.id
WHERE s.last_ts IS NOT NULL
"""

GAP_ANALYSIS_SQL = """
SELECT
    s.session_id,
    s.last_ts,
    LAG(s.last_ts) OVER (ORDER BY s.last_ts) as prev_last_ts
FROM sessions s
JOIN projects p ON s.project_id = p.id
WHERE s.last_ts IS NOT NULL
"""

_DOW_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


def _add_filters(sql: str, project: str | None, days: int | None) -> tuple[str, list]:
    """Append WHERE clauses for project/days filters."""
    params: list = []
    clauses: list[str] = []
    if project:
        clauses.append("p.name LIKE ?")
        params.append(f"%{project}%")
    if days:
        clauses.append("s.last_ts >= date('now', ?)")
        params.append(f"-{days} days")
    if clauses:
        # Check if SQL already has WHERE
        if "WHERE" in sql:
            sql += " AND " + " AND ".join(clauses)
        else:
            sql += " WHERE " + " AND ".join(clauses)
    return sql, params


def query_hourly_activity(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[sqlite3.Row]:
    sql, params = _add_filters(HOURLY_ACTIVITY_SQL, project, days)
    sql += " GROUP BY hour ORDER BY hour"
    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def query_daily_activity(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[sqlite3.Row]:
    sql, params = _add_filters(DAILY_ACTIVITY_SQL, project, days)
    sql += " GROUP BY dow ORDER BY dow"
    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def query_weekly_volume(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[sqlite3.Row]:
    sql, params = _add_filters(WEEKLY_VOLUME_SQL, project, days)
    sql += " GROUP BY week ORDER BY week"
    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def query_session_gaps(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[dict]:
    """Compute gaps between consecutive sessions, return gap stats."""
    sql, params = _add_filters(GAP_ANALYSIS_SQL, project, days)
    sql += " ORDER BY s.last_ts"
    conn.row_factory = sqlite3.Row
    rows = conn.execute(sql, params).fetchall()

    gaps_hours: list[float] = []
    for row in rows:
        if row["prev_last_ts"]:
            from datetime import datetime
            try:
                curr = datetime.fromisoformat(row["last_ts"])
                prev = datetime.fromisoformat(row["prev_last_ts"])
                gap_h = (curr - prev).total_seconds() / 3600
                if gap_h > 0:
                    gaps_hours.append(gap_h)
            except ValueError:
                continue

    if not gaps_hours:
        return []

    gaps_sorted = sorted(gaps_hours)
    return {
        "count": len(gaps_sorted),
        "min_h": gaps_sorted[0],
        "max_h": gaps_sorted[-1],
        "median_h": gaps_sorted[len(gaps_sorted) // 2],
        "avg_h": sum(gaps_sorted) / len(gaps_sorted),
        "pct_under_1h": sum(1 for g in gaps_sorted if g < 1) / len(gaps_sorted) * 100,
        "pct_under_4h": sum(1 for g in gaps_sorted if g < 4) / len(gaps_sorted) * 100,
    }


def _bar(value: int, max_value: int, width: int = 30) -> str:
    """Simple horizontal bar."""
    if max_value == 0:
        return ""
    filled = round(value / max_value * width)
    return "█" * filled


def cmd_time(args: argparse.Namespace) -> None:
    """Show time-based usage patterns."""
    conn = init_db(args.db_path)
    c = _c()

    hourly = query_hourly_activity(conn, project=args.project, days=args.days)
    daily = query_daily_activity(conn, project=args.project, days=args.days)
    weekly = query_weekly_volume(conn, project=args.project, days=args.days)
    gaps = query_session_gaps(conn, project=args.project, days=args.days)
    conn.close()

    # Hourly distribution
    print(f"\n{c['bold']}{c['cyan']}Time Patterns{c['reset']}\n")

    if hourly:
        print(f"  {c['bold']}By Hour{c['reset']}")
        max_sess = max(r["sessions"] for r in hourly)
        # Fill in missing hours
        hour_map = {r["hour"]: r for r in hourly}
        for h in range(24):
            r = hour_map.get(h)
            sess = r["sessions"] if r else 0
            bar = _bar(sess, max_sess)
            print(f"    {h:02d}:00  {sess:>4}  {bar}")
        print()

    # Day of week
    if daily:
        print(f"  {c['bold']}By Day of Week{c['reset']}")
        max_sess = max(r["sessions"] for r in daily)
        dow_map = {r["dow"]: r for r in daily}
        for d in range(7):
            r = dow_map.get(d)
            sess = r["sessions"] if r else 0
            tok = _fmt_tokens(r["tokens"] or 0) if r else "0"
            bar = _bar(sess, max_sess)
            print(f"    {_DOW_NAMES[d]}  {sess:>4}  {tok:>8}  {bar}")
        print()

    # Weekly volume
    if weekly:
        print(f"  {c['bold']}Weekly Volume{c['reset']}")
        max_sess = max(r["sessions"] for r in weekly)
        for row in weekly:
            bar = _bar(row["sessions"], max_sess, width=20)
            print(f"    {row['week']}  {row['sessions']:>4} sessions  {_fmt_tokens(row['tokens'] or 0):>8}  {bar}")
        print()

    # Gap analysis
    if gaps:
        print(f"  {c['bold']}Session Gaps{c['reset']}")
        print(f"    Between consecutive sessions:")
        print(f"    Min: {gaps['min_h']:.1f}h  Median: {gaps['median_h']:.1f}h  Avg: {gaps['avg_h']:.1f}h  Max: {gaps['max_h']:.1f}h")
        print(f"    {gaps['pct_under_1h']:.0f}% under 1h  {gaps['pct_under_4h']:.0f}% under 4h")


# ---------------------------------------------------------------------------
# Step 4: Git branch patterns
# ---------------------------------------------------------------------------

BRANCH_PATTERNS_SQL = f"""
{_cte()}
SELECT
    s.git_branch,
    p.name as project,
    COUNT(*) as sessions,
    MIN(s.first_ts) as first_session,
    MAX(s.last_ts) as last_session,
    SUM(s.input_tokens + s.output_tokens + s.cache_create_tokens + s.cache_read_tokens) as total_tokens,
    AVG(
        CASE WHEN s.first_ts IS NOT NULL AND s.last_ts IS NOT NULL
        THEN (julianday(s.last_ts) - julianday(s.first_ts)) * 24 * 60
        END
    ) as avg_duration_min,
    SUM(
        (SELECT COUNT(*) FROM filtered_events fe WHERE fe.session_id = s.session_id)
    ) as total_events,
    -- Dominant action across all sessions on this branch
    (SELECT fe2.action_type FROM filtered_events fe2
     JOIN sessions s2 ON fe2.session_id = s2.session_id
     WHERE s2.git_branch = s.git_branch AND s2.project_id = p.id
       AND fe2.action_type IS NOT NULL
     GROUP BY fe2.action_type ORDER BY COUNT(*) DESC LIMIT 1) as dominant_action
FROM sessions s
JOIN projects p ON s.project_id = p.id
WHERE s.git_branch IS NOT NULL
"""


def query_branch_patterns(
    conn: sqlite3.Connection,
    project: str | None = None,
    days: int | None = None,
) -> list[sqlite3.Row]:
    sql = BRANCH_PATTERNS_SQL
    params: list = []

    if project:
        sql += " AND p.name LIKE ?"
        params.append(f"%{project}%")
    if days:
        sql += " AND s.last_ts >= date('now', ?)"
        params.append(f"-{days} days")

    sql += " GROUP BY s.git_branch, p.id ORDER BY sessions DESC"

    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def cmd_branches(args: argparse.Namespace) -> None:
    """Show git branch usage patterns."""
    conn = init_db(args.db_path)
    c = _c()

    rows = query_branch_patterns(conn, project=args.project, days=args.days)
    conn.close()

    if not rows:
        print("No branch data found.")
        return

    limit = args.limit
    showing = rows[:limit]

    print(f"\n{c['bold']}{c['cyan']}Branch Patterns{c['reset']} ({len(rows)} branches)\n")
    print(
        f"  {'Branch':35} {'Project':25} {'Sess':>5} {'Events':>7} "
        f"{'Tokens':>9} {'Avg Dur':>7} {'Dominant':>12}"
    )
    print(
        f"  {'─' * 35} {'─' * 25} {'─' * 5} {'─' * 7} "
        f"{'─' * 9} {'─' * 7} {'─' * 12}"
    )

    for row in showing:
        branch = (row["git_branch"] or "—")[:35]
        proj = (row["project"] or "")[:25]
        sessions = row["sessions"]
        events = row["total_events"]
        tokens = _fmt_tokens(row["total_tokens"] or 0)
        avg_dur = f"{row['avg_duration_min']:.0f}m" if row["avg_duration_min"] else "—"
        dominant = row["dominant_action"] or "—"

        print(
            f"  {branch:35} {proj:25} {sessions:>5} {events:>7} "
            f"{tokens:>9} {avg_dur:>7} {dominant:>12}"
        )

    if len(rows) > limit:
        print(f"\n  ... and {len(rows) - limit} more (use --limit to show more)")

    # Branch lifetime summary
    lifetimes: list[float] = []
    for row in rows:
        if row["first_session"] and row["last_session"]:
            from datetime import datetime
            try:
                d1 = datetime.fromisoformat(row["first_session"][:10])
                d2 = datetime.fromisoformat(row["last_session"][:10])
                lifetimes.append((d2 - d1).days)
            except ValueError:
                continue

    if lifetimes:
        avg_life = sum(lifetimes) / len(lifetimes)
        med_life = sorted(lifetimes)[len(lifetimes) // 2]
        print(f"\n  {c['bold']}Branch Lifetimes{c['reset']}")
        print(f"    Avg: {avg_life:.0f}d  Median: {med_life:.0f}d")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Session analytics for Claude Code usage patterns",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DB_PATH,
        dest="db_path",
        help=f"Database path (default: {DB_PATH})",
    )
    sub = parser.add_subparsers(dest="command", help="Subcommand")

    # sessions
    sess = sub.add_parser("sessions", help="Per-session shape metrics")
    sess.add_argument("--project", help="Filter by project name")
    sess.add_argument("--days", type=int, help="Limit to last N days")
    sess.add_argument("--limit", type=int, default=30, help="Max rows to display")

    # projects
    proj = sub.add_parser("projects", help="Project usage patterns")
    proj.add_argument("--days", type=int, help="Only projects active in last N days")

    # time
    tm = sub.add_parser("time", help="Time-based usage patterns")
    tm.add_argument("--project", help="Filter by project name")
    tm.add_argument("--days", type=int, help="Limit to last N days")

    # branches
    br = sub.add_parser("branches", help="Git branch usage patterns")
    br.add_argument("--project", help="Filter by project name")
    br.add_argument("--days", type=int, help="Limit to last N days")
    br.add_argument("--limit", type=int, default=30, help="Max rows to display")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "sessions": cmd_sessions,
        "projects": cmd_projects,
        "time": cmd_time,
        "branches": cmd_branches,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
