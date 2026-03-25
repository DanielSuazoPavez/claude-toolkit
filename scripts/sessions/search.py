#!/usr/bin/env python3
"""Full-text search across indexed Claude Code session transcripts.

Usage:
    uv run scripts/sessions/search.py search <query> [--project <name>] [--since YYYY-MM-DD] [--type <type>] [--limit N]

Requires a populated session index — run `uv run scripts/sessions/index.py index` first.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from scripts.sessions.db import DB_PATH, _c, init_db

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


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
        JOIN sessions s ON s.session_id = e.session_id
        JOIN projects p ON p.id = s.project_id
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

    sql += " ORDER BY e.date DESC, e.id DESC LIMIT ?"
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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Full-text search across Claude Code session transcripts",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DB_PATH,
        dest="db_path",
        help=f"Database path (default: {DB_PATH})",
    )
    sub = parser.add_subparsers(dest="command", help="Subcommand")

    # search
    srch = sub.add_parser("search", help="Full-text search")
    srch.add_argument("query", help="Search query")
    srch.add_argument("--project", help="Filter by project")
    srch.add_argument("--since", help="Only results after date (YYYY-MM-DD)")
    srch.add_argument("--type", help="Filter by event type")
    srch.add_argument("--limit", type=int, default=30, help="Max results")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    commands = {
        "search": cmd_search,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
