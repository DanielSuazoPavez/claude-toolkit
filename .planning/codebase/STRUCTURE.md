# Project Structure

## Root Directory

| Path | Type | Purpose |
|------|------|---------|
| `install.sh` | Script | Initial installation to target projects |
| `VERSION` | File | Semantic version for sync tracking |
| `CHANGELOG.md` | File | Version history for sync diffs |
| `README.md` | File | Project documentation |
| `CLAUDE.md` | File | Claude Code instructions |
| `BACKLOG.md` | File | Project backlog items |
| `.gitignore` | File | Git ignore patterns |

## bin/

CLI tools for toolkit management.

| File | Purpose |
|------|---------|
| `claude-toolkit` | Main CLI for toolkit management |

**Commands:**
- `claude-toolkit sync [path]` - Sync updates to a project
- `claude-toolkit sync --only <categories>` - Sync specific categories (comma-separated)
- `claude-toolkit send <path> --type <type> --project <name>` - Send resource to suggestions-box
- `claude-toolkit --help` - Show main help
- `claude-toolkit <command> --help` - Show command-specific help

## scripts/

Maintenance and validation scripts.

| File | Purpose |
|------|---------|
| `analyze-usage.sh` | Analyze usage.log for patterns |
| `validate-resources-indexed.sh` | Ensure all resources are in index files |

## docs/

Project documentation.

| File | Purpose |
|------|---------|
| `naming-conventions.md` | Naming guidelines for all resource types |

## .claude/

Core toolkit configuration directory. This entire directory is copied to target projects.

### Index Files

| File | Indexes |
|------|---------|
| `SKILLS.md` | All skills in `skills/` |
| `AGENTS.md` | All agents in `agents/` |
| `HOOKS.md` | All hooks in `hooks/` |
| `MEMORIES.md` | All memories in `memories/` |

### Configuration Files

| File | Purpose |
|------|---------|
| `settings.json` | Hook definitions, matchers, env var documentation |
| `settings.local.json` | Local overrides (bash permissions, etc.) |
| `usage.log` | Usage tracking log (gitignored) |

### skills/

User-invocable workflows activated with `/skill-name`.

**Structure:** Each skill is a directory with `SKILL.md` and optional `resources/` subdirectory.

| Skill | Description |
|-------|-------------|
| `analyze-idea/` | Research and exploration tasks |
| `analyze-naming/` | Variable/function naming analysis |
| `brainstorm-idea/` | Structured design dialogue |
| `design-db/` | Database schema design |
| `design-diagram/` | Architecture diagrams |
| `draft-pr/` | Pull request descriptions |
| `evaluate-agent/` | Agent prompt quality evaluation |
| `evaluate-hook/` | Hook quality evaluation |
| `evaluate-memory/` | Memory file quality evaluation |
| `evaluate-skill/` | Skill design evaluation |
| `list-memories/` | List memories with Quick Reference |
| `read-json/` | JSON file analysis with jq |
| `review-plan/` | Plan quality review |
| `setup-worktree/` | Git worktree reference |
| `snap-back/` | Reset sycophantic tone |
| `wrap-up/` | Session wrap-up |
| `write-agent/` | Create new agents |
| `write-handoff/` | Session handoff context |
| `write-hook/` | Create new hooks |
| `write-memory/` | Create new memories |
| `write-skill/` | Create new skills |

### agents/

Specialized agents for complex tasks. Single markdown files with YAML frontmatter.

| Agent | Description | Tools |
|-------|-------------|-------|
| `codebase-mapper.md` | Explore and document codebase | Read, Bash, Grep, Glob, Write |
| `code-debugger.md` | Bug investigation | Read, Write, Edit, Bash, Grep, Glob |
| `code-reviewer.md` | Pragmatic code review | Read, Grep, Glob, Bash |
| `goal-verifier.md` | Verify work completion | Read, Bash, Grep, Glob |
| `implementation-checker.md` | Compare implementation to plan | Read, Grep, Glob, Write |
| `pattern-finder.md` | Find implementation patterns | Read, Bash, Grep, Glob |

### hooks/

Automation scripts triggered by Claude Code events.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Load essential memories, show git context |
| `track-skill-usage.sh` | UserPromptSubmit | Log skill invocations |
| `track-agent-usage.sh` | PostToolUse (Task) | Log agent spawns |
| `enforce-feature-branch.sh` | PreToolUse (EnterPlanMode\|Bash) | Block plan mode and commits on main |
| `block-dangerous-commands.sh` | PreToolUse (Bash) | Block rm -rf /, fork bombs, etc. |
| `secrets-guard.sh` | PreToolUse (Read\|Bash) | Block .env file reads |
| `suggest-json-reader.sh` | PreToolUse (Read) | Suggest /read-json for JSON |
| `enforce-uv-run.sh` | PreToolUse (Bash) | Enforce `uv run` for Python |
| `enforce-make-commands.sh` | PreToolUse (Bash) | Encourage Make targets |
| `copy-plan-to-project.sh` | PostToolUse (Write) | Copy plans to .planning/ |

### memories/

Persistent context templates for projects.

**Categories:**
- `essential-*` - Auto-loaded at session start
- `relevant-*` - Loaded when needed
- `branch-*` - Temporary, per-branch
- `idea-*` - Future implementation ideas

| Memory | Category | Purpose |
|--------|----------|---------|
| `essential-conventions-code_style.md` | essential | Coding style guide |
| `essential-conventions-memory.md` | essential | Memory naming conventions |
| `essential-preferences-communication_style.md` | essential | Communication preferences |
| `essential-reference-commands.md` | essential | CLI/Make commands reference |
| `essential-workflow-branch_development.md` | essential | Branch-based workflow |
| `essential-workflow-task_completion.md` | essential | Task completion checklist |
| `philosophy-reducing_entropy.md` | philosophy | Code entropy philosophy |
| `relevant-conventions-backlog_schema.md` | relevant | BACKLOG.md schema |

### plans/

Saved planning documents from Claude Code sessions. Created by the `copy-plan-to-project.sh` hook.

Format: `YYYY-MM-DD_HHMM_plan-name.md`

### templates/

Template files for project scaffolding.

| File | Purpose |
|------|---------|
| `BACKLOG.md` | Project backlog template |
| `Makefile.claude-toolkit` | Suggested make targets |
| `gitignore.claude-toolkit` | Suggested .gitignore entries |
| `settings.template.json` | Reference settings.json |
| `claude-sync-ignore.template` | Default ignore patterns |
| `mcp.template.json` | MCP servers template (context7, sequential-thinking) |

### scripts/

Internal scripts used by hooks or toolkit.

| File | Purpose |
|------|---------|
| `backlog-query.sh` | Query BACKLOG.md for items |

## suggestions-box/

Incoming resources from other projects, organized by project name.

**Usage:** `claude-sync send <path> --type <type> --project <name>`

Creates files like: `suggestions-box/<project>/<name>-<TYPE>.md`

## File Patterns

### Skills

```
.claude/skills/<skill-name>/
├── SKILL.md              # Required: skill definition
└── resources/            # Optional: supporting files
    └── *.md              # Detailed reference docs
```

### Agents

```
.claude/agents/<agent-name>.md  # Single file with YAML frontmatter
```

### Hooks

```
.claude/hooks/<hook-name>.sh    # Executable bash script
```

### Memories

```
.claude/memories/<category>-<context>-<name>.md
```

## Validation

Run `scripts/validate-resources-indexed.sh` to verify:
- All skills in `skills/` are listed in `SKILLS.md`
- All agents in `agents/` are listed in `AGENTS.md`
- All hooks in `hooks/` are listed in `HOOKS.md`
- All memories in `memories/` are listed in `MEMORIES.md`
