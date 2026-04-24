# cli/

CLI subcommands for the `claude-toolkit` tool. Each subdirectory is a subcommand dispatched by `bin/claude-toolkit`.

## Structure

```
cli/
├── backlog/
│   ├── query.sh       # claude-toolkit backlog — query BACKLOG.md
│   └── validate.sh    # claude-toolkit backlog validate — format checks
├── docs/
│   └── query.sh       # claude-toolkit docs — emit workshop agent-facing contracts
├── eval/
│   └── query.sh       # claude-toolkit eval — query evaluation scores
└── lessons/
    ├── db.py          # claude-toolkit lessons — SQLite lessons CRUD
    └── formatting.py  # Shared terminal color/formatting helpers
```

## How Subcommands Are Wired

- **backlog, docs, eval**: Shell scripts, exec'd directly from `bin/claude-toolkit`
- **lessons**: Python package, installed as `ct-lessons` via `[project.scripts]` in `pyproject.toml`, invoked from `bin/claude-toolkit` through the venv

## Conventions

- Shell scripts are self-contained (no external dependencies beyond coreutils/bash)
- Python CLI uses `argparse`, no third-party CLI frameworks
- Colors respect `NO_COLOR` env and non-TTY detection (see `formatting.py`)
- Database path defaults to `~/.claude/lessons.db` (global, not per-project); overridable via `CLAUDE_ANALYTICS_LESSONS_DB`
