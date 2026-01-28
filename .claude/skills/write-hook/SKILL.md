---
name: write-hook
description: Create new hooks for Claude Code. Use when adding safety, automation, or notification hooks. Keywords: PreToolUse, PostToolUse, block commands, hook script, settings.json hooks.
---

Use when adding a new hook to `.claude/hooks/`.

Use `verb-noun.sh` format for hook names. See `docs/naming-conventions.md`.

## When to Use

- Adding safety hooks (block dangerous commands, protect secrets)
- Adding automation hooks (auto-stage, auto-format)
- Adding notification hooks (alerts when Claude needs input)

## Process

### 1. Choose Hook Event

**Decision tree:**
- Want to **block/prevent** an action? → `PreToolUse` (only one that can block)
- Want to **react after** something happens? → `PostToolUse`
- Want **alerts when Claude waits**? → `Notification`

See `HOOKS_API.md` for all 13 events.

### 2. Write the Hook

Bash script structure:

```bash
#!/bin/bash
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Early exit for non-matching tools
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Check patterns and block if needed
if [[ "$COMMAND" =~ rm\ -rf\ ~/ ]]; then
    echo '{"decision": "block", "reason": "Blocks rm -rf ~/"}'
    exit 0
fi

# Allow by default (empty output)
exit 0
```

### 3. Test with Bash

```bash
# Should block
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/"}}' | ./hook.sh
# Expected: {"decision":"block","reason":"..."}

# Should allow
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | ./hook.sh
# Expected: (empty)
```

### 4. Configure in settings.json

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": "/path/to/hook.sh"}]
    }]
  }
}
```

## Best Patterns

- **Safety levels** - Single constant (`critical`/`high`/`strict`) to adjust strictness
- **Allowlists** - Explicit exceptions (e.g., `.env.example` is safe)
- **Cross-tool protection** - Same logic across Read/Edit/Write/Bash

## Output Formats: When to Use Each

| Format | When to Use | Example |
|--------|-------------|---------|
| Empty output (exit 0) | Allow the action | Default case, no match |
| `{"decision": "block", "reason": "..."}` | Simple block with message | Blocking dangerous command |
| `hookSpecificOutput` | Modify tool behavior or add context | Injecting warnings, modifying arguments |

**Simple block** - Use when you just need to prevent an action:
```bash
echo '{"decision": "block", "reason": "Cannot delete home directory"}'
```

**hookSpecificOutput** - Use when you need to modify or augment:
```bash
echo '{"hookSpecificOutput": {"warning": "This file is in .gitignore"}}'
```

Most hooks only need simple block or empty output. Use `hookSpecificOutput` only when you need to pass data back to Claude.

## Edge Cases

### Multiple Hooks on Same Event

When multiple hooks match the same tool:
- Hooks run in order listed in settings.json
- First `block` decision wins (stops execution)
- All `allow` hooks must pass for action to proceed

**Ordering strategy:**
1. Put broadest safety hooks first (catch-all patterns)
2. Put specific allowlist hooks after (exceptions to rules)

### Hook Chaining Example

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [
        {"type": "command", "command": "block-dangerous.sh"},
        {"type": "command", "command": "allow-make-commands.sh"}
      ]
    }]
  }
}
```

Order matters: `block-dangerous.sh` runs first, then `allow-make-commands.sh` can add exceptions.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **No tests** | Hook breaks silently | Test block + allow cases |
| **Overly strict** | Blocks legitimate work | Use safety levels |
| **No allowlist** | Can't handle exceptions | Add allowlist for safe patterns |
| **Silent failures** | Hook errors go unnoticed | Log to `~/.claude/hooks-logs/` |
| **No early exit** | Processes irrelevant tools | Check `tool_name` first, exit 0 if no match |
| **Hardcoded paths** | Breaks on other machines | Use `$HOME`, relative paths, or env vars |
| **Wrong hook order** | Allowlist blocked by earlier hook | Order: blockers first, allowlists after |

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Hook not running | Not in settings.json | Check `hooks` config, restart Claude Code |
| `jq: command not found` | jq not installed | `apt install jq` or `brew install jq` |
| Hook errors silently | stderr not captured | Add `2>> ~/.claude/hooks-logs/errors.log` |
| Wrong tool blocked | Matcher too broad | Use specific matcher like `"Bash"` not `"*"` |
