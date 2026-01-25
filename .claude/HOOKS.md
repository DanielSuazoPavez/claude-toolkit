# Hooks Index

Automation hooks configured in `settings.local.json`.

## Included Hooks

### session-start.sh

**Trigger**: SessionStart

Loads essential memories and git context at the start of each session.

- Outputs all `essential-*.md` memories
- Lists other available memories
- Shows current git branch

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

Hooks are configured in `settings.local.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/session-start.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/enforce-uv-run.sh"},
          {"type": "command", "command": ".claude/hooks/enforce-make-commands.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/copy-plan-to-project.sh"}
        ]
      }
    ]
  }
}
```

## Creating New Hooks

1. Create `.claude/hooks/your-hook.sh`
2. Make executable: `chmod +x .claude/hooks/your-hook.sh`
3. Add to `settings.local.json` under appropriate trigger
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
