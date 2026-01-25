# Claude Code Hooks API Reference

Source: karanb192/claude-code-hooks (may become outdated)

## Hook Events

| Event | When | Can Block? |
|-------|------|------------|
| SessionStart | Session begins | No |
| SessionEnd | Session ends | No |
| UserPromptSubmit | User sends message | No |
| **PreToolUse** | Before tool runs | **Yes** |
| PostToolUse | After tool succeeds | No |
| PostToolUseFailure | After tool fails | No |
| PermissionRequest | User prompt for permission | No |
| SubagentStart | Subagent spawns | No |
| SubagentStop | Subagent completes | No |
| Stop | Session stops | No |
| PreCompact | Before context compaction | No |
| Setup | Initial setup | No |
| Notification | Needs user attention | No |

## Input Payload (stdin JSON)

```json
{
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /"
  },
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "permission_mode": "default"
}
```

### Tool-Specific Inputs

| Tool | tool_input fields |
|------|-------------------|
| Bash | `command` |
| Read | `file_path` |
| Edit | `file_path`, `old_string`, `new_string` |
| Write | `file_path`, `content` |

## Output Format

### To Block (PreToolUse only)

```json
{
  "decision": "block",
  "reason": "Human-readable explanation"
}
```

### To Allow

Empty output or `{}`.

## settings.json Configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/hook.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/post-hook.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/notify.sh"
          }
        ]
      }
    ]
  }
}
```

### Matcher Syntax

- Single tool: `"Bash"`
- Multiple tools: `"Read|Edit|Write|Bash"`
- Notification types: `"permission_prompt|idle_prompt"`

## Safety Level Pattern

```bash
SAFETY_LEVEL="high"  # critical | high | strict

# critical - Only catastrophic (rm -rf ~, fork bombs)
# high     - + risky (force push main, secrets exposure)
# strict   - + cautionary (any force push, sudo rm)
```

## Common Protected Patterns

### Dangerous Commands (PreToolUse/Bash)

| Pattern | Level | Reason |
|---------|-------|--------|
| `rm -rf ~/` | critical | Deletes home directory |
| `rm -rf /` | critical | Deletes root filesystem |
| `dd of=/dev/sda` | critical | Overwrites disk |
| `:(){:\|:&};:` | critical | Fork bomb |
| `curl \| sh` | high | Remote code execution |
| `git push --force main` | high | Destroys shared history |
| `git reset --hard` | high | Loses uncommitted work |
| `cat .env` | high | Exposes secrets |

### Sensitive Files (PreToolUse/Read|Edit|Write)

| Pattern | Level | Reason |
|---------|-------|--------|
| `.env` | critical | Contains secrets |
| `~/.ssh/id_*` | critical | SSH private keys |
| `~/.aws/credentials` | critical | AWS credentials |
| `*.pem`, `*.key` | critical | Private keys |
| `credentials.json` | high | Credentials file |
| `secrets.yaml` | high | Secrets config |

### Allowlist Examples

Safe to access (don't block):
- `.env.example`, `.env.template`, `.env.sample`
- `~/.ssh/config` (not a key)
- `package.json`, `README.md`

## Debugging Hooks

Log all events to inspect payload structure:

```bash
#!/bin/bash
# event-logger.sh
INPUT=$(cat)
LOG_DIR="$HOME/.claude/hooks-logs"
mkdir -p "$LOG_DIR"
echo "$(date -Iseconds) $INPUT" >> "$LOG_DIR/$(date +%Y-%m-%d).jsonl"
```
