---
name: setup-toolkit
type: command
description: Diagnose and fix Claude Toolkit configuration after sync or drift. Keywords: setup, configure, toolkit, settings, hooks, permissions, mcp.
allowed-tools: Bash(jq:*), Bash(grep:*), Bash(diff:*), Bash(make:*), Bash(bash:*), Bash(ls:*), Read, Write, Edit, Glob, Grep
---

Diagnose and fix Claude Toolkit configuration in the current project. Run after `claude-toolkit sync` or when session-start reports version drift.

**See also:** `relevant-toolkit-hooks_config` (hook system context), `relevant-toolkit-permissions_config` (permission system context)

## Prerequisites

- Project must have been synced at least once (`claude-toolkit sync .`)
- Templates must exist at `.claude/templates/` (copied by sync)

**Toolkit repo guard:** If `dist/base/` exists in the current directory, this is the toolkit repo itself — warn the user and exit. This skill runs in target projects only.

## Phase 1: Diagnostic

Run all checks below. Collect results, then present a summary table before proceeding to fixes.

### Check 1: settings.json hooks

Compare hook commands in `.claude/settings.json` against `.claude/templates/settings.template.json`:

```bash
# Extract hook commands from both files
jq -r '.. | objects | select(.command?) | .command' .claude/settings.json 2>/dev/null | sort > /tmp/ct-hooks-current.txt
jq -r '.. | objects | select(.command?) | .command' .claude/templates/settings.template.json 2>/dev/null | sort > /tmp/ct-hooks-template.txt

# Missing from settings.json (need to add)
comm -23 /tmp/ct-hooks-template.txt /tmp/ct-hooks-current.txt

# Extra in settings.json (informational only)
comm -13 /tmp/ct-hooks-template.txt /tmp/ct-hooks-current.txt
```

- **Missing:** these are issues to fix
- **Extra:** flag as informational — "These hooks are in your settings.json but not in the template. If project-specific, consider moving to settings.local.json."

### Check 2: settings.json permissions

```bash
# Extract permission arrays
jq -r '.permissions.allow // [] | .[]' .claude/settings.json 2>/dev/null | sort > /tmp/ct-perms-current.txt
jq -r '.permissions.allow // [] | .[]' .claude/templates/settings.template.json 2>/dev/null | sort > /tmp/ct-perms-template.txt

# Missing from settings.json
comm -23 /tmp/ct-perms-template.txt /tmp/ct-perms-current.txt

# Extra in settings.json
comm -13 /tmp/ct-perms-template.txt /tmp/ct-perms-current.txt
```

Same reporting as Check 1 — missing are issues, extras are informational.

### Check 3: MCP config

First, check if `mcp.json` exists at the project root (wrong location). If found, move it to `.claude/mcp.json` before proceeding:

```bash
if [ -f mcp.json ] && [ ! -f .claude/mcp.json ]; then
    mv mcp.json .claude/mcp.json
elif [ -f mcp.json ] && [ -f .claude/mcp.json ]; then
    echo "WARNING: mcp.json exists at both root and .claude/ — merge manually"
fi
```

Compare `.claude/mcp.json` against `.claude/templates/mcp.template.json`:

```bash
# Extract server names from both
jq -r '.mcpServers | keys[]' .claude/mcp.json 2>/dev/null | sort > /tmp/ct-mcp-current.txt
jq -r '.mcpServers | keys[]' .claude/templates/mcp.template.json 2>/dev/null | sort > /tmp/ct-mcp-template.txt

# Missing servers
comm -23 /tmp/ct-mcp-template.txt /tmp/ct-mcp-current.txt
```

If `.claude/mcp.json` doesn't exist, the entire file is missing — flag as an issue.

### Check 4: Makefile targets

```bash
grep -q 'claude-toolkit-validate' Makefile 2>/dev/null
```

If no match (or no Makefile), flag as an issue. The template targets are in `.claude/templates/Makefile.claude-toolkit`.

### Check 5: .gitignore patterns

For each non-comment, non-blank line in `.claude/templates/gitignore.claude-toolkit`, check if it exists in `.gitignore`:

```bash
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    grep -qxF "$line" .gitignore 2>/dev/null || echo "Missing: $line"
done < .claude/templates/gitignore.claude-toolkit
```

If `.gitignore` doesn't exist, all lines are missing.

### Check 6: CLAUDE.md exists and has key principles

Check if `CLAUDE.md` exists in the project root. If missing, flag it. Template available at `.claude/templates/CLAUDE.md.template`.

If `CLAUDE.md` exists, also check for key principles from the template that may be missing:

```bash
# Extract bullet points from "Key Principles" section of template
# (lines starting with "- **" between "## Key Principles" and the next "##")
sed -n '/^## Key Principles/,/^## /{/^- \*\*/p}' .claude/templates/CLAUDE.md.template > /tmp/ct-principles-template.txt

# Check which ones are missing from CLAUDE.md (match on the bold text)
while IFS= read -r line; do
    keyword=$(echo "$line" | grep -oP '\*\*[^*]+\*\*' | head -1)
    grep -qF "$keyword" CLAUDE.md 2>/dev/null || echo "Missing: $line"
done < /tmp/ct-principles-template.txt
```

Report missing principles as suggestions (not errors) — the user may have intentionally omitted or reworded them.

### Check 7: PR template

```bash
# Check if .github/PULL_REQUEST_TEMPLATE.md exists
if [ ! -f .github/PULL_REQUEST_TEMPLATE.md ] && [ -f .claude/templates/PULL_REQUEST_TEMPLATE.md ]; then
    echo "Missing: .github/PULL_REQUEST_TEMPLATE.md (template available)"
fi
```

If the template source exists but `.github/PULL_REQUEST_TEMPLATE.md` doesn't, flag as an issue.

### Present Summary

After all checks, show:

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
```

If all checks pass, report "All checks passed" and skip to Phase 3.

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

## Phase 3: Validation

After all fixes are applied (or skipped), run the validation suite:

```bash
bash .claude/scripts/validate-all.sh
```

Report the result:
- **All passed:** "Setup complete. All validations passed."
- **Failures:** List what failed and suggest manual resolution.

### PR template (Check 7)

If `.github/PULL_REQUEST_TEMPLATE.md` doesn't exist and `.claude/templates/PULL_REQUEST_TEMPLATE.md` does:

```
"Copy PR template to .github/PULL_REQUEST_TEMPLATE.md? [y/n]"
```

If approved, create `.github/` directory if needed and copy the template.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No `.claude/templates/` directory | "Templates not found. Run `claude-toolkit sync .` first." Exit. |
| settings.json doesn't exist at all | Offer to copy entire file from template |
| mcp.json doesn't exist | Offer to copy from template |
| Makefile doesn't exist | Ask user: create or skip |
| .gitignore doesn't exist | Offer to create with toolkit patterns |
| User declines all fixes | Clean exit with summary of skipped items |
| Running in toolkit repo (`dist/base/` exists) | Warn and exit — this skill is for target projects |
| settings.json has custom hooks not in template | Informational only — don't remove, suggest settings.local.json |

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| Auto-fix without asking | User loses control | Always present and ask before each fix |
| Remove existing entries | Breaks project config | Additive only — never delete |
| Edit settings.local.json | That's user-private config | Never touch it |
| Skip final validation | Fixes might be incomplete | Always run validate-all.sh at the end |
| Overwrite files entirely | Loses project customizations | Merge, don't replace |
