# Architecture

## Entry Points

- `install.sh` - Copies `.claude/` directory to target project for initial setup
- `bin/claude-sync` - Syncs toolkit updates to projects, handles version tracking and conflicts
- `.claude/settings.json` - Hook configuration that Claude Code reads at runtime

## Layer Structure

```
claude-toolkit/
├── bin/                    # CLI tools for toolkit management
│   └── claude-sync         # Sync command (pull updates, send resources)
├── scripts/                # Maintenance scripts
│   ├── analyze-usage.sh    # Usage analytics
│   └── validate-resources-indexed.sh  # Index validation
├── docs/                   # Documentation
│   └── naming-conventions.md
├── .claude/                # Core toolkit configuration
│   ├── settings.json       # Hook definitions and env vars
│   ├── settings.local.json # Local overrides
│   ├── skills/             # User-invocable workflows
│   ├── agents/             # Specialized task subprocesses
│   ├── hooks/              # Event-driven automation scripts
│   ├── memories/           # Persistent context templates
│   ├── plans/              # Saved planning documents
│   ├── templates/          # Template files (BACKLOG.md)
│   └── scripts/            # Internal scripts (backlog-query.sh)
└── suggestions-box/        # Incoming resources from other projects
```

## Data Flow

### Installation Flow
```
[User runs install.sh] → copies .claude/ → [Target project has toolkit]
```

### Sync Flow
```
[User runs claude-sync] → reads VERSION → compares with .claude-sync-version
                       → shows CHANGELOG diff → prompts for conflicts
                       → copies files → updates .claude-sync-version
```

### Session Flow
```
[Session starts] → SessionStart hook → session-start.sh
                → loads essential-*.md memories
                → shows git context
                → shows memory guidance
```

### Tool Use Flow
```
[Claude invokes tool] → PreToolUse hooks run (by matcher)
                     → Tool executes
                     → PostToolUse hooks run (by matcher)
```

## Key Patterns

### Hook Event System

Hooks are bash scripts triggered by Claude Code events. Configured in `settings.json`:

| Event | When Triggered | Use Case |
|-------|----------------|----------|
| `SessionStart` | Session begins | Load context, show guidance |
| `UserPromptSubmit` | User sends message | Track skill usage |
| `PreToolUse` | Before tool execution | Block dangerous actions, suggest alternatives |
| `PostToolUse` | After tool execution | Track usage, copy files |

Hooks receive context via stdin as JSON with `tool_name` and `tool_input` fields.

### Matcher Pattern

PreToolUse and PostToolUse hooks use matchers to filter which tools trigger them:
- Single tool: `"matcher": "Bash"`
- Multiple tools: `"matcher": "Read|Bash"`
- Multiple events: `"matcher": "EnterPlanMode|Bash"`

### Resource Indexing

Each resource type has:
- A directory containing the resources (`skills/`, `agents/`, `hooks/`, `memories/`)
- An index file documenting them (`SKILLS.md`, `AGENTS.md`, `HOOKS.md`, `MEMORIES.md`)
- A validation script (`scripts/validate-resources-indexed.sh`) that ensures sync

### Skill Structure

Skills follow progressive disclosure pattern:
```
skills/skill-name/
├── SKILL.md              # Main skill definition (<500 lines)
└── resources/            # Optional supporting files
    └── TOPIC.md          # Detailed reference (<500 lines each)
```

Skills have YAML frontmatter with `name` and `description` fields.

### Agent Structure

Agents are single markdown files with YAML frontmatter:
```yaml
---
name: agent-name
description: One-line description
tools: Read, Grep, Glob, Bash
color: cyan  # optional
---
```

### Memory Categories

Memories are categorized by lifespan:
- `essential-*` - Permanent, auto-loaded at session start
- `relevant-*` - Long-term, loaded when needed
- `branch-*` - Temporary, deleted after branch merge
- `idea-*` - Temporary, for future implementation ideas

### Version-Based Sync

`bin/claude-sync` uses semantic versioning to track toolkit updates:
- `VERSION` file in toolkit root
- `.claude-sync-version` file in target projects
- `.claude-sync-ignore` for project-specific exclusions
- `CHANGELOG.md` shows what changed between versions

## Component Relationships

```
settings.json
    ├── defines → hooks/
    │                 ├── session-start.sh → reads → memories/essential-*.md
    │                 ├── track-skill-usage.sh → writes → usage.log
    │                 ├── enforce-*.sh → blocks/warns → tool execution
    │                 └── copy-plan-to-project.sh → copies → .planning/
    │
install.sh ─┬─ copies → .claude/ (entire directory)
            └─ copies → VERSION → .claude-sync-version

bin/claude-sync ─┬─ reads → VERSION, .claude-sync-version
                 ├─ reads → .claude-sync-ignore
                 ├─ reads → CHANGELOG.md
                 └─ copies → .claude/* (selective)

scripts/validate-resources-indexed.sh
    ├── reads → skills/, SKILLS.md
    ├── reads → agents/, AGENTS.md
    ├── reads → hooks/, HOOKS.md
    └── reads → memories/, MEMORIES.md
```

## Environment Variables

Hooks support configuration via environment variables (documented in `settings.json._env_config`):

| Variable | Purpose |
|----------|---------|
| `CLAUDE_MEMORIES_DIR` | Directory for memories (default: `.claude/memories`) |
| `CLAUDE_PLANS_DIR` | Directory for plan copies (default: `.claude/plans`) |
| `CLAUDE_USAGE_LOG` | Usage log file path (default: `.claude/usage.log`) |
| `ALLOW_DANGEROUS_COMMANDS` | Bypass dangerous command blocking |
| `ALLOW_ENV_READ` | Allow reading .env files |
| `ALLOW_JSON_READ` | Bypass JSON read suggestions |
| `ALLOW_DIRECT_PYTHON` | Bypass `uv run` enforcement |
| `ALLOW_DIRECT_COMMANDS` | Bypass Make target suggestions |
| `ALLOW_COMMIT_ON_MAIN` | Allow git commit on protected branches |
