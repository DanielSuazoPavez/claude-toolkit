# Hooks Index

Automation hooks configured in `settings.json`.

## Included Hooks

| Hook | Status | Trigger | Description |
|------|--------|---------|-------------|
| `session-start.sh` | stable | SessionStart | Loads essential memories and git context |
| `enforce-feature-branch.sh` | stable | PreToolUse (EnterPlanMode) | Blocks plan mode on main/master |
| `block-dangerous-commands.sh` | alpha | PreToolUse (Bash) | Blocks destructive commands (rm -rf /, fork bombs, etc.) |
| `secrets-guard.sh` | alpha | PreToolUse (Read\|Bash) | Blocks reading .env files and exposing secrets |
| `suggest-json-reader.sh` | alpha | PreToolUse (Read) | Suggests /read-json skill for JSON files |
| `enforce-uv-run.sh` | alpha | PreToolUse (Bash) | Ensures Python uses `uv run` |
| `enforce-make-commands.sh` | alpha | PreToolUse (Bash) | Encourages Make targets |
| `copy-plan-to-project.sh` | stable | PostToolUse (Write) | Copies plans to `.planning/` |

**Note**: Alpha hooks work but have matcher scope limitations (too broad). Hook UX noise is a known issue.

---

### session-start.sh

**Trigger**: SessionStart

Loads essential memories and git context at the start of each session.

- Outputs all `essential-*.md` memories
- Lists other available memories
- Shows current git branch

### enforce-feature-branch.sh

**Trigger**: PreToolUse (EnterPlanMode)

Blocks entering plan mode while on main/master branch.

- Blocks: `EnterPlanMode` when on `main` or `master`
- Message: Suggests creating feature branch with prefix options
- Bypass: Set `ALLOW_PLAN_ON_MAIN=1`

Why: Non-trivial work (worthy of plan mode) should happen on feature branches.

### block-dangerous-commands.sh

**Trigger**: PreToolUse (Bash)

Blocks destructive bash commands that could damage the system.

- Blocks: `rm -rf /`, `rm -rf ~`, fork bombs, `mkfs`, `dd` to disks, `chmod -R 777 /`
- Bypass: Set `ALLOW_DANGEROUS_COMMANDS=1`

### secrets-guard.sh

**Trigger**: PreToolUse (Read|Bash)

Prevents accidental exposure of secrets from .env files.

- Blocks Read: `.env`, `.env.*` (except `.env.example`, `.env.template`, `.env.sample`)
- Blocks Bash: `cat .env`, `source .env`, `export $(cat .env)`, `env`
- Bypass: Set `ALLOW_ENV_READ=1`

### suggest-json-reader.sh

**Trigger**: PreToolUse (Read)

Suggests using `/read-json` skill for JSON files.

- Blocks: Any `.json` file read
- Reason: JSON files can be large; `/read-json` uses jq for efficient querying
- Bypass: Set `ALLOW_JSON_READ=1`

### enforce-uv-run.sh

**Trigger**: PreToolUse (Bash)

Ensures Python commands use `uv run` instead of raw Python/pip.

- Blocks: `python`, `python3`, `pip`, `pip3`, `pytest`, `ruff`, `mypy`
- Suggests: Use `uv run <command>` or Make targets

**Note**: Python-specific. Remove for non-Python projects.

### enforce-make-commands.sh

**Trigger**: PreToolUse (Bash)

Encourages using Make targets over raw commands.

- Warns when common commands could use Make targets
- Suggests: Check `make help` for available targets

### copy-plan-to-project.sh

**Trigger**: PostToolUse (Write)

Copies plan files to `.planning/` directory.

- Watches for plan file writes
- Maintains planning documentation in project

## Configuration

Hooks are configured in `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "EnterPlanMode",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/enforce-feature-branch.sh"}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/block-dangerous-commands.sh"},
          {"type": "command", "command": ".claude/hooks/enforce-uv-run.sh"}
        ]
      },
      {
        "matcher": "Read|Bash",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/suggest-json-reader.sh"}
        ]
      }
    ]
  }
}
```

## Creating New Hooks

1. Create `.claude/hooks/your-hook.sh`
2. Make executable: `chmod +x .claude/hooks/your-hook.sh`
3. Add to `settings.json` under appropriate trigger
4. Hook receives tool input via environment variables

### Available Triggers

| Trigger | When | Use For |
|---------|------|---------|
| `SessionStart` | Session begins | Loading context, setup |
| `PreToolUse` | Before tool execution | Validation, blocking |
| `PostToolUse` | After tool execution | Cleanup, side effects |

### Hook Environment

Hooks receive context via environment variables:
- `TOOL_INPUT` - JSON of tool parameters
- `TOOL_NAME` - Name of the tool being used
