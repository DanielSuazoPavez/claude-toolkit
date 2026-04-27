---
name: setup-toolkit
metadata: { type: command }
description: Diagnose and fix Claude Toolkit configuration after sync or drift. Keywords: setup, configure, toolkit, settings, hooks, permissions, mcp.
compatibility: jq
allowed-tools: Bash(jq:*), Bash(grep:*), Bash(diff:*), Bash(make:*), Bash(bash:*), Bash(ls:*), Bash(rm:*), Read, Write, Edit, Glob, Grep
---

Diagnose and fix Claude Toolkit configuration in the current project. Run after `claude-toolkit sync` or when session-start reports version drift.

**See also:** `relevant-toolkit-hooks_config` (hook system context), `relevant-toolkit-permissions_config` (permission system context)

## Prerequisites

- Project must have been synced at least once (`claude-toolkit sync .`)
- Templates must exist at `.claude/templates/` (copied by sync)

**Toolkit repo guard:** If `dist/base/` exists in the current directory, this is the toolkit repo itself — warn the user and exit. This skill runs in target projects only.

## Phase 1: Diagnostic

Run the diagnostic script to perform all checks in a single pass:

```bash
bash .claude/scripts/setup-toolkit-diagnose.sh
```

This runs 8 checks and outputs structured results. Parse the output to build the summary table.

### Output format

Section delimiters:
- `===CHECK:N:name:STATUS===` ... `===CHECK:N:END===` per check
- `===SUMMARY===` ... `===SUMMARY:END===` for final counts

Line prefixes:
- `MISSING:` — entry needs to be added (fixable)
- `EXTRA:` — entry in project but not template (informational)
- `ORPHAN:` — resource on disk but not in MANIFEST (cleanup candidate)
- `STALE_REF:` — settings.json references a file that doesn't exist
- `CLEANUP:` — settings entry references missing file and isn't in template
- `SUGGESTION:` — optional improvement (not an error)

Status values: `PASS`, `ISSUES_FOUND`, `INFO`, `SKIPPED`

### Present Summary

After parsing the output, show:

```
| # | Check                  | Status | Issues |
|---|------------------------|--------|--------|
| 1 | settings.json hooks    | ...    | ...    |
| 2 | settings.json perms    | ...    | ...    |
| 3 | MCP config             | ...    | ...    |
| 4 | Makefile targets       | ...    | ...    |
| 5 | .gitignore patterns    | ...    | ...    |
| 6 | CLAUDE.md + principles | ...    | ...    |
| 7 | PR template            | ...    | ...    |
| 8 | Cleanup verification   | ...    | ...    |
```

- **EXTRA** items: flag as informational — "These are in your settings.json but not in the template. If project-specific, consider moving to settings.local.json."
- If all checks pass, report "All checks passed" and skip to Phase 3.

## Phase 1.5: Ecosystem Opt-Ins

Runs before drift fixes. Only fires when `.claude/settings.json` lacks the ecosystem env keys — i.e., a pre-opt-in project that hasn't chosen yet. Once either key exists, this phase is skipped on future runs.

### Detection

```bash
jq -e '.env.CLAUDE_TOOLKIT_LESSONS // .env.CLAUDE_TOOLKIT_TRACEABILITY' .claude/settings.json >/dev/null 2>&1
```

- Exit 0 (either key present) → skip this phase.
- Exit non-zero (both absent) → run the prompts below.

### Prompts

Ask each in turn. Present the tradeoff plainly — both ecosystems store data locally only.

**Lessons ecosystem:**

> Enable the lessons ecosystem? It stores learned corrections in `~/.claude/lessons.db`, surfaces relevant lessons at session start, and injects matches before Bash/Read/Write/Edit calls. Local SQLite only — nothing leaves the machine. Disabled by default. [y/N]

**Traceability ecosystem:**

> Enable traceability? Logs hook executions to `~/.claude/hooks.db` for debugging/observability. If you use the statusline capture wrapper, it also appends usage snapshots to `~/.claude/usage-snapshots/`. Local only. Disabled by default. [y/N]

### Apply

Write both keys regardless of answer — presence is what silences the session-start nudge. "y" → `"1"`, anything else → `"0"`.

```bash
jq '.env = (.env // {}) | .env.CLAUDE_TOOLKIT_LESSONS = "<lessons_val>" | .env.CLAUDE_TOOLKIT_TRACEABILITY = "<trace_val>"' \
  .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

Confirm the write: re-run the detection jq expression; should now exit 0.

Note: env vars take effect on the next Claude Code session, not mid-session. Let the user know if they want to verify immediately they'll need to restart.

## Phase 1.6: Analytics Paths

Runs after ecosystem opt-in. Captures per-user paths for the global analytics surfaces and writes them into `.claude/settings.local.json` `env`.

There are four paths, split across two storage models:

- **`CLAUDE_ANALYTICS_LESSONS_DB`** — SQLite DB of learned corrections. Read+write by toolkit hooks/scripts.
- **`CLAUDE_ANALYTICS_SESSIONS_DB`** — SQLite DB of session history. Read by `session-start.sh` for context. Owned and populated by the claude-sessions indexer, not the toolkit.
- **`CLAUDE_ANALYTICS_HOOKS_DIR`** — directory of JSONL hook-execution logs (`invocations.jsonl`, `surface-lessons-context.jsonl`, `session-start-context.jsonl`). Write-only from the toolkit's perspective; the claude-sessions indexer projects these rows into `hooks.db`.
- **`CLAUDE_ANALYTICS_HOOKS_DB`** — read-only path to `hooks.db`, used by `surface-lessons.sh` for intra-session dedup. Owned and populated by the claude-sessions indexer, not the toolkit.

**Why here and not `.claude/settings.json`:** Claude Code passes JSON `env` values through literally — `"$HOME/..."` is not expanded. So the paths must be fully resolved. `settings.local.json` is per-user and gitignored, which is the right place for fully-resolved user-specific paths (avoids leaking `/home/alice/...` into shared repos).

**Scripts have a fallback.** If these env vars are unset, hooks/scripts default to `$HOME/.claude/lessons.db`, `$HOME/.claude/sessions.db`, `$HOME/claude-analytics/hook-logs`, and `$HOME/.claude/hooks.db` at runtime. This phase is about centralizing the override surface, not plugging a missing default.

For the full env-var registry (every var the toolkit reads, including non-analytics ones), see `.claude/docs/relevant-toolkit-env_vars.md`.

### Detection

```bash
jq -e '.env.CLAUDE_ANALYTICS_LESSONS_DB // .env.CLAUDE_ANALYTICS_SESSIONS_DB // .env.CLAUDE_ANALYTICS_HOOKS_DIR // .env.CLAUDE_ANALYTICS_HOOKS_DB' .claude/settings.local.json >/dev/null 2>&1
```

- Exit 0 (any key present) → skip (user already configured).
- Exit non-zero (all absent or file absent) → run prompts below.

### Prompts

Resolve `$HOME` to a real path first (`echo "$HOME"`). Offer it as the default in each prompt.

**Lessons DB path:**

> Where should the lessons DB live? Stores learned corrections across all your projects (global, not per-project). [$HOME/.claude/lessons.db]

**Sessions DB path (read-only):**

> Where does the sessions DB live? Read-only — `session-start.sh` queries it for context. Owned and populated by the claude-sessions indexer, not the toolkit. Leave the default if you don't run claude-sessions. [$HOME/.claude/sessions.db]

**Hook-logs JSONL directory:**

> Where should hook-execution logs (JSONL) live? The toolkit appends one line per hook invocation here; the claude-sessions indexer reads them downstream. Global, not per-project. [$HOME/claude-analytics/hook-logs]

**Hooks DB path (read-only):**

> Where does `hooks.db` live? Read-only — `surface-lessons.sh` queries it for intra-session dedup. Owned and populated by the claude-sessions indexer, not the toolkit. Leave the default if you don't run claude-sessions. [$HOME/.claude/hooks.db]

Empty input → accept default. Any non-empty input → use verbatim (don't re-expand — the user is giving a resolved path).

### Confirm before writing

`settings.local.json` is user-private config — never mutate silently. After the prompts, show the exact JSON that will be merged into `.claude/settings.local.json` `env` and ask one final yes/no:

```
The following will be added to .claude/settings.local.json (env block):
  "CLAUDE_ANALYTICS_LESSONS_DB": "<resolved_lessons_path>"
  "CLAUDE_ANALYTICS_SESSIONS_DB": "<resolved_sessions_path>"
  "CLAUDE_ANALYTICS_HOOKS_DIR": "<resolved_hooks_dir>"
  "CLAUDE_ANALYTICS_HOOKS_DB": "<resolved_hooks_db_path>"

Apply? [y/n]
```

Only proceed on explicit "y". On "n" (or anything else), skip this phase — scripts fall back to the defaults above, which is correct for most users.

### Apply

If `.claude/settings.local.json` doesn't exist, create it as `{}`. Then merge:

```bash
jq --arg lessons "<resolved_lessons_path>" \
   --arg sessions "<resolved_sessions_path>" \
   --arg hooks_dir "<resolved_hooks_dir>" \
   --arg hooks_db "<resolved_hooks_db_path>" \
   '.env = (.env // {})
    | .env.CLAUDE_ANALYTICS_LESSONS_DB = $lessons
    | .env.CLAUDE_ANALYTICS_SESSIONS_DB = $sessions
    | .env.CLAUDE_ANALYTICS_HOOKS_DIR = $hooks_dir
    | .env.CLAUDE_ANALYTICS_HOOKS_DB = $hooks_db' \
   .claude/settings.local.json > .claude/settings.local.json.tmp && mv .claude/settings.local.json.tmp .claude/settings.local.json
```

Confirm: re-run the detection jq expression; should now exit 0.

Note: same Claude-Code-restart caveat as Phase 1.5.

## Phase 2: Fix

Process each issue one at a time. Present the proposed change and ask for approval before applying.

### Fix flow

For each issue:

1. Show what will change (exact entries being added, lines being appended)
2. Ask: "Apply this fix? [y/n]"
3. If approved, apply the change
4. If declined, skip and move on

### settings.json hooks/permissions (Checks 1-2)

**Additive only.** Read the current settings.json, add missing entries, write back. Use jq for merging.

For hooks — each hook in the template has an event type (SessionStart, PreToolUse, etc.) and a matcher. Add missing hook entries to the correct event array:

```bash
# Example: add a missing hook command to PreToolUse
jq '.hooks.PreToolUse[0].hooks += [{"type": "command", "command": ".claude/hooks/new-hook.sh"}]' .claude/settings.json
```

For permissions — append missing entries to the allow array:

```bash
# Example: add missing permissions
jq '.permissions.allow += ["Bash(new:*)"]' .claude/settings.json
```

**Show the user the exact jq transformation before applying.** Write the result back to `.claude/settings.json`.

### MCP config (Check 3)

If `mcp.json` is at the project root instead of `.claude/mcp.json`, offer to move it first.

If `.claude/mcp.json` doesn't exist, offer to copy from template:

```
".claude/mcp.json doesn't exist. Create from template? [y/n]"
```

If it exists but is missing servers, add them from the template (additive merge):

```bash
# Merge missing servers from template into current config
jq -s '.[1].mcpServers * .[0].mcpServers | {mcpServers: .}' .claude/mcp.json .claude/templates/mcp.template.json
```

Note: this preserves existing server config and adds missing ones.

### Makefile targets (Check 4)

If Makefile exists but lacks targets, show the content from `.claude/templates/Makefile.claude-toolkit` and offer to append:

```
"Append toolkit Make targets to Makefile? [y/n]"
```

If no Makefile exists, ask:

```
"No Makefile found. Create one with toolkit targets, or skip? [create/skip]"
```

### .gitignore patterns (Check 5)

Show missing lines and offer to append:

```
"Add these lines to .gitignore?
  output/claude-toolkit/
  .claude/settings.local.json
[y/n]"
```

If `.gitignore` doesn't exist, offer to create it with the toolkit patterns.

### CLAUDE.md (Check 6)

If missing, offer to copy from template:

```
"CLAUDE.md not found. Create from template? The template has placeholder sections you'll want to fill in. [y/n]"
```

If CLAUDE.md exists but is missing key principles from the template, show the missing ones and offer to add them:

```
"These key principles from the template are missing from your CLAUDE.md:
  - **Plan before building**: Use plan mode for non-trivial tasks...
  - **Zero warnings**: Treat lint/type warnings as errors...
Add them to your Key Principles section? [y/n/pick]"
```

If the user picks "pick", present each one individually. These are suggestions — the user may have intentionally omitted or reworded them.

### PR template (Check 7)

If `.github/PULL_REQUEST_TEMPLATE.md` doesn't exist and `.claude/templates/PULL_REQUEST_TEMPLATE.md` does:

```
"Copy PR template to .github/PULL_REQUEST_TEMPLATE.md? [y/n]"
```

If approved, create `.github/` directory if needed and copy the template.

### Cleanup verification (Check 8)

**Orphaned resources (ORPHAN items):**

For each `ORPHAN:` item, present the resource and ask per-item:

```
"skills/old-skill/ exists on disk but not in MANIFEST — likely removed from toolkit.
 Remove? [y/n/re-sync]"
```

- **y**: Remove the resource directory/file:
  ```bash
  # For skill directories
  rm -rf .claude/skills/old-skill/
  # For individual files (agents, hooks, docs)
  rm .claude/agents/<agent-name>.md
  ```
- **n**: Skip this resource
- **re-sync**: Skip all remaining orphan fixes — suggest running `claude-toolkit sync .` to refresh MANIFEST instead

**Stale hook references (STALE_REF items):**

For each `STALE_REF:` item:

```
"settings.json references .claude/hooks/old-hook.sh but the file doesn't exist.
 Remove this hook entry from settings.json? [y/n]"
```

If approved, remove the hook entry using jq. The hook is nested inside an event array — find and filter it:

```bash
# Remove a hook command from its event array (e.g., PreToolUse)
jq '(.hooks.PreToolUse // [])[] |= (.hooks = [.hooks[] | select(.command != ".claude/hooks/old-hook.sh")])' .claude/settings.json
```

After filtering, if a matcher group's hooks array is empty, remove the entire matcher group:

```bash
# Clean up empty matcher groups
jq '(.hooks | to_entries[] | .value) |= [.[] | select(.hooks | length > 0)]' .claude/settings.json
```

**Removal candidates (CLEANUP items):**

For each `CLEANUP:` permission item:

```
"Permission 'Bash(.claude/hooks/old.sh:*)' references a hook that doesn't exist.
 Remove this permission? [y/n]"
```

If approved:
```bash
jq '.permissions.allow = [.permissions.allow[] | select(. != "Bash(.claude/hooks/old.sh:*)")]' .claude/settings.json
```

For `CLEANUP:` hook items (not in template, not on disk):
```
"Hook '.claude/hooks/old.sh' is not in the template and doesn't exist on disk.
 Remove from settings.json? [y/n]"
```

Apply the same jq hook removal pattern as stale refs above.

## Phase 3: Validation

After all fixes are applied (or skipped), run the validation suite:

```bash
bash .claude/scripts/validate-all.sh
```

Report the result:
- **All passed:** "Setup complete. All validations passed."
- **Failures:** List what failed and suggest manual resolution.

### Statusline (powerline)

After validation, check if `statusLine` is configured in `.claude/settings.json`. If not, offer to set it up:

```
"Would you like to configure the Claude Code statusline (powerline)?
This adds a two-line status bar showing directory, git state, model, context usage, and more. [y/skip]"
```

If yes:

1. Add the `statusLine` entry to `.claude/settings.json`, pointing to the capture wrapper (not powerline directly):
   ```json
   "statusLine": {
     "type": "command",
     "command": ".claude/scripts/statusline-capture.sh"
   }
   ```

2. Create `.claude/scripts/statusline-capture.sh` (chmod +x) — this appends each statusline JSON payload to `~/.claude/usage-snapshots/snapshots.jsonl` before forwarding to powerline. It fails safe: any capture error still forwards stdin so the statusline never breaks.

   ```bash
   #!/usr/bin/env bash
   # Statusline capture wrapper — intercepts Claude Code statusline JSON payload,
   # appends the raw JSON to a single JSONL file, and forwards the original
   # payload to the downstream powerline command unchanged.

   set -euo pipefail

   SNAPSHOTS_DIR="${HOME}/.claude/usage-snapshots"
   SNAPSHOTS_FILE="${SNAPSHOTS_DIR}/snapshots.jsonl"
   POWERLINE_CMD="npx -y @owloops/claude-powerline@1.25.1 --config=.claude/claude-powerline.json"

   INPUT="$(cat)"

   {
       mkdir -p "${SNAPSHOTS_DIR}" 2>/dev/null || true
       CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
       STAMPED="$(printf '%s' "${INPUT}" | jq -c --arg ts "$CAPTURED_AT" '. + {captured_at: $ts}' 2>/dev/null)" || true
       if [[ -n "${STAMPED}" ]]; then
           printf '%s\n' "${STAMPED}" >> "${SNAPSHOTS_FILE}" 2>/dev/null || true
       fi
   } &

   printf '%s' "${INPUT}" | ${POWERLINE_CMD}
   ```

   Version is pinned to `@1.25.1` — bump deliberately after checking `npm view @owloops/claude-powerline version`.

3. Copy the powerline config from the toolkit repo template. If no template exists, use this default `.claude/claude-powerline.json`:
   ```json
   {
     "theme": "custom",
     "display": {
       "style": "minimal",
       "colorCompatibility": "auto",
       "lines": [
         {
           "segments": {
             "directory": { "enabled": true, "showBasename": true },
             "git": {
               "enabled": true,
               "showSha": false,
               "showWorkingTree": true,
               "showOperation": true,
               "showTag": true,
               "showTimeSinceCommit": false,
               "showUpstream": false,
               "showRepoName": false
             }
           }
         },
         {
           "segments": {
             "model": { "enabled": true },
             "version": { "enabled": true },
             "block": {
               "enabled": true,
               "type": "weighted",
               "burnType": "none"
             },
             "context": { "enabled": true, "showPercentageOnly": true }
           }
         }
       ]
     },
     "colors": {
       "custom": {
         "directory": { "bg": "#5E81AC", "fg": "#ECEFF4" },
         "model": { "bg": "#D08770", "fg": "#2E3440" },
         "version": { "bg": "#88C0D0", "fg": "#2E3440" },
         "block": { "bg": "#BF616A", "fg": "#ECEFF4" },
         "context": { "bg": "#6B8E5F", "fg": "#ECEFF4" },
         "git": { "bg": "#A3BE8C", "fg": "#2E3440" }
       }
     },
     "modelContextLimits": {
       "sonnet": 200000,
       "haiku": 200000
     }
   }
   ```

### Communication style doc

After validation, check if `.claude/docs/essential-preferences-communication_style.md` exists. If not, ask:

```
"Would you also like to build a communication style doc? This customizes how Claude
communicates with you — tone, verbosity, ceremony, and more. Run /build-communication-style
to get started. [y/skip]"
```

If yes, invoke `/build-communication-style`.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No `.claude/templates/` directory | Script exits: "Templates not found. Run `claude-toolkit sync .` first." |
| settings.json doesn't exist at all | Offer to copy entire file from template |
| mcp.json doesn't exist | Offer to copy from template |
| Makefile doesn't exist | Ask user: create or skip |
| .gitignore doesn't exist | Offer to create with toolkit patterns |
| User declines all fixes | Clean exit with summary of skipped items |
| Running in toolkit repo (`dist/base/` exists) | Script exits with warning — this skill is for target projects |
| settings.json has custom hooks not in template | Informational only — don't remove, suggest settings.local.json |
| No MANIFEST file | Check 8a skipped — "MANIFEST not found. Run `claude-toolkit sync` for cleanup detection." Checks 8b-8c still run. |
| Resource in `.claude-toolkit-ignore` | Not flagged as orphan — these are project-specific exclusions |
| User selects "re-sync" for orphans | Skip remaining orphan fixes, suggest `claude-toolkit sync .` |

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Auto-fix without asking | User loses control | Always present and ask before each fix |
| Remove existing entries (Checks 1-2) | Breaks project config | Additive only for hooks/permissions — never delete |
| Edit settings.local.json | That's user-private config | Never touch it — **except** Phase 1.6, which writes the analytics DB paths there (per-user resolved paths belong in the gitignored local file, not the shared one) |
| Skip final validation | Fixes might be incomplete | Always run validate-all.sh at the end |
| Overwrite files entirely | Loses project customizations | Merge, don't replace |
| Auto-delete orphans without asking | User may want to keep them | Always ask per-item, offer re-sync as alternative |
