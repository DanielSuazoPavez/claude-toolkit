---
name: create-hook
metadata: { type: command }
description: Create new hooks for Claude Code. Use when adding safety, automation, or notification hooks. Keywords: PreToolUse, PostToolUse, block commands, hook script, settings.json hooks.
allowed-tools: Read, Write, Bash(chmod:*), Glob
---

Use when adding a new hook to `.claude/hooks/`.

**See also:** `.claude/docs/relevant-toolkit-hooks.md` (match/check pattern + dispatcher contract), `/evaluate-hook` (quality gate), `/create-skill` (when a skill fits better), `/create-agent` (when an agent fits better)

Use `verb-noun.sh` format for hook names. See `relevant-conventions-naming`.

## When to Use

- Adding safety hooks (block dangerous commands, protect secrets)
- Adding automation hooks (auto-stage, auto-format)
- Adding notification hooks (alerts when Claude needs input)

## Process

### 1. Choose Hook Event

**Decision tree:**
- Want to **block/prevent** an action? → `PreToolUse` (block before execution)
- Want to **auto-approve** a permission prompt? → `PermissionRequest`
- Want to **react after** something happens? → `PostToolUse`
- Want **alerts when Claude waits**? → `Notification`

See `resources/HOOKS_API.md` for all events.

### 2. Write the Hook

All hooks source the shared library `.claude/hooks/lib/hook-utils.sh` for standardized initialization, outcome helpers, and execution timing.

**PreToolUse hooks use the match/check pattern.** The hook body defines three functions:

- `match_<name>` — cheap predicate (bash pattern match only — no forks, no `jq`, no `git`, no I/O). Returns 0 if the hook applies.
- `check_<name>` — the guard itself. Runs only when `match_` returned 0. Sets `_BLOCK_REASON` and returns 1 to block; returns 0 to pass.
- `main` — standalone entry point. Parses stdin, calls `match_` + `check_`, emits the decision.

A dual-mode trigger at the bottom runs `main` only when the script is executed directly, not when sourced. That lets the same file work as a standalone hook and as a library sourced by `grouped-bash-guard.sh`. See `.claude/docs/relevant-toolkit-hooks.md` for the full contract (cheapness rules, dispatcher internals, anti-patterns).

Use the script below as the LITERAL STARTING POINT for a Bash PreToolUse hook. Copy it, then modify the match predicate, check body, and block reason for your use case.

```bash
#!/bin/bash
# Hook: <name>
# Event: PreToolUse (Bash)
# Purpose: <one line>
#
# Dual-mode: standalone (main) or sourced by grouped-bash-guard (match_/check_).
# See .claude/docs/relevant-toolkit-hooks.md for the match/check pattern.
#
# Settings.json (standalone):
#   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": ".claude/hooks/<name>.sh"}]}]
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/"}}' | bash .claude/hooks/<name>.sh
#   # Expected: {"decision":"block","reason":"..."}
#
#   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash .claude/hooks/<name>.sh
#   # Expected: (empty - allowed)

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"

# Cheap predicate — bash pattern match only. No forks, no jq, no git, no I/O.
# False positives are fine (check_ will no-op); false negatives are safety bugs.
match_<name>() {
    [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+~/ ]]
}

# Guard body — runs only when match_ returned 0. Expensive work is fine here.
# Return 0 = pass, 1 = block (and set _BLOCK_REASON).
check_<name>() {
    if [[ "$COMMAND" =~ rm[[:space:]]+-rf[[:space:]]+~/ ]]; then
        _BLOCK_REASON="Blocks rm -rf ~/ — use a specific path instead."
        return 1
    fi
    return 0
}

main() {
    hook_init "<name>" "PreToolUse"
    hook_require_tool "Bash"

    COMMAND=$(hook_get_input '.tool_input.command')
    [ -z "$COMMAND" ] && exit 0

    _BLOCK_REASON=""
    if match_<name>; then
        if ! check_<name>; then
            hook_block "$_BLOCK_REASON"
        fi
    fi
    exit 0
}

# Dual-mode trigger — main runs only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

**Why `${BASH_SOURCE[0]}` instead of `$0` for the source path:** when the grouped dispatcher sources this file, `$0` points to the dispatcher, not your hook. `${BASH_SOURCE[0]}` always points to the current file.

**Other event types** (PostToolUse, Notification, PermissionRequest) don't currently participate in the dispatcher — use the simpler single-function shape shown in the examples below. Match/check is specifically for Bash PreToolUse hooks that could be grouped.

**Shared library functions:**
- `hook_init "name" "Event"` — reads stdin, sets up timing, registers EXIT trap for logging
- `hook_require_tool "Tool1" "Tool2"` — parses tool_name, exits 0 if no match
- `hook_get_input '.jq.path'` — extracts field from stdin JSON
- `hook_block "reason"` — emits block JSON, exits 0
- `hook_approve "reason"` — emits permission-allow JSON, exits 0 (PermissionRequest only)
- `hook_inject "context"` — emits additionalContext JSON, exits 0

### 3. Test with Bash

```bash
# Should block
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/"}}' | bash .claude/hooks/<name>.sh
# Expected: {"decision":"block","reason":"..."}

# Should allow
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash .claude/hooks/<name>.sh
# Expected: (empty)
```

### 4. Register the Hook

A Bash PreToolUse hook is registered in **one** of two modes — never both. Dual registration would run the hook twice.

**Standalone** — the harness runs the script directly. Use this for non-Bash branches, or if the hook is the only Bash hook in the project:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": ".claude/hooks/<name>.sh"}]
    }]
  }
}
```

**Grouped** — register the hook inside `grouped-bash-guard.sh`'s `CHECK_SPECS` array (toolkit default for Bash). The dispatcher sources your file and calls `match_<name>` / `check_<name>`. This amortizes bash startup + `jq` parsing across all Bash PreToolUse hooks:

```bash
# In .claude/hooks/grouped-bash-guard.sh
CHECK_SPECS=(
    "dangerous:block-dangerous-commands.sh"
    ...
    "<name>:<name>.sh"   # ← add your hook here
)
```

Order matters — earlier checks run first. Put cheap-to-gate hooks before expensive ones. If your hook has a non-Bash branch (e.g., matches `EnterPlanMode` too), keep a standalone registration for the non-Bash matcher; the Bash branch still goes through the dispatcher only.

### 5. Quality Gate

Run `/evaluate-hook` on the result:
- **Target: 85%**
- If below target, iterate on the weakest dimensions

### PostToolUse Example

PostToolUse hooks use the same `hook_init` + `hook_require_tool` pattern. Since PostToolUse can't block actions, they don't call `hook_block` — they just perform side effects (logging, notifications):

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
hook_init "log-writes" "PostToolUse"
hook_require_tool "Write"

FILE_PATH=$(hook_get_input '.tool_input.file_path')
echo "[$(date)] Wrote: $FILE_PATH" >> ~/.claude/hooks-logs/writes.log
exit 0
```

Configuration:
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write",
      "hooks": [{"type": "command", "command": "bash .claude/hooks/log-writes.sh"}]
    }]
  }
}
```

### Notification Example

Notification hooks don't have tool_name — simpler pattern using `hook_init` only (no `hook_require_tool`):

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
hook_init "desktop-alert" "Notification"

MESSAGE=$(hook_get_input '.message')
[ -z "$MESSAGE" ] && MESSAGE="Claude needs your attention"
notify-send "Claude Code" "$MESSAGE" 2>/dev/null || true
exit 0
```

Configuration:
```json
{
  "hooks": {
    "Notification": [{
      "hooks": [{"type": "command", "command": "bash .claude/hooks/desktop-alert.sh"}]
    }]
  }
}
```

### PermissionRequest Example

A hook that auto-approves specific Bash commands from the permission prompt:

```bash
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
hook_init "auto-approve-safe" "PermissionRequest"
hook_require_tool "Bash"

COMMAND=$(hook_get_input '.tool_input.command')

# Allowlist: auto-approve safe commands
ALLOWED_PATTERNS=(
    "^make (test|check|lint|format)"
    "^npm (test|run lint)"
    "^uv run (pytest|ruff)"
)

for pattern in "${ALLOWED_PATTERNS[@]}"; do
    if [[ "$COMMAND" =~ $pattern ]]; then
        hook_approve "Auto-approved by allowlist"
    fi
done

# No match — fall through to normal permission prompt
exit 0
```

Configuration:
```json
{
  "hooks": {
    "PermissionRequest": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": "bash .claude/hooks/auto-approve-safe.sh"}]
    }]
  }
}
```

Test:
```bash
# Should auto-approve
echo '{"tool_name":"Bash","tool_input":{"command":"make test"}}' | bash .claude/hooks/auto-approve-safe.sh
# Expected: {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}

# Should fall through (no output)
echo '{"tool_name":"Bash","tool_input":{"command":"npm publish"}}' | bash .claude/hooks/auto-approve-safe.sh
# Expected: (empty)
```

**PermissionRequest vs `allowed-tools`:** Use `allowed-tools` in settings.json for static, all-or-nothing tool approval (e.g., allow all `Bash` commands). Use a `PermissionRequest` hook when you need conditional logic — approve `npm test` but not `npm publish`, or approve `rm` only in certain directories.

## Real-World Reference

See `relevant-toolkit-hooks_config` doc for 10 production hooks in this toolkit (all sourcing the shared library), covering safety (secrets-guard, enforce-uv-run), automation (session-start), and context injection (surface-lessons) patterns.

## Best Patterns

- **Shared library** — Always source `lib/hook-utils.sh` for standardized init, outcome helpers, and execution timing
- **Safety levels** - Single constant (`critical`/`high`/`strict`) to adjust strictness
- **Allowlists** - Explicit exceptions (e.g., `.env.example` is safe)
- **Cross-tool protection** - Same logic across Read/Edit/Write/Bash

## Output Formats: When to Use Each

| Format | When to Use | How |
|--------|-------------|-----|
| Empty output (exit 0) | Allow the action | Default — no match, just exit |
| Block | Prevent an action | `hook_block "reason"` |
| Approve | Auto-approve permission | `hook_approve "reason"` (PermissionRequest only) |
| Inject context | Add info for Claude | `hook_inject "context"` |

Most hooks only need block or empty output. Use `hook_inject` when you need to pass additional context back to Claude (e.g., surfacing relevant lessons).

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
        {"type": "command", "command": "bash .claude/hooks/block-dangerous.sh"},
        {"type": "command", "command": "bash .claude/hooks/allow-make-commands.sh"}
      ]
    }]
  }
}
```

Order matters: `block-dangerous.sh` runs first, then `allow-make-commands.sh` can add exceptions.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Raw JSON output** | Fragile, inconsistent formatting | Use `hook_block`/`hook_approve`/`hook_inject` from shared library |
| **No tests** | Hook breaks silently | Test block + allow cases |
| **Overly strict** | Blocks legitimate work | Use safety levels |
| **No allowlist** | Can't handle exceptions | Add allowlist for safe patterns |
| **Silent failures** | Hook errors go unnoticed | Log to `~/.claude/hooks-logs/` |
| **No early exit** | Processes irrelevant tools | Use `hook_require_tool` — exits 0 if no match |
| **Hardcoded paths** | Breaks on other machines | Use `$HOME`, relative paths, or env vars |
| **Wrong hook order** | Allowlist blocked by earlier hook | Order: blockers first, allowlists after |
| **Env var bypass** | Defeats the hook's purpose; user can just run the command directly if needed | Don't add `ALLOW_*` env var overrides |

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Hook not running | Not in settings.json | Check `hooks` config, restart Claude Code |
| `jq: command not found` | jq not installed | `apt install jq` or `brew install jq` |
| Hook errors silently | stderr not captured | Add `2>> ~/.claude/hooks-logs/errors.log` |
| Wrong tool blocked | Matcher too broad | Use specific matcher like `"Bash"` not `"*"` |
