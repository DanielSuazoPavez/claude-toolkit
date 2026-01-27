# claude-toolkit CLI Redesign

**Date:** 2026-01-27
**Status:** Draft

## Summary

Redesign `claude-sync` into `claude-toolkit` CLI with improved UX: help system, interactive category-based sync, and additive templates.

## Goals

1. Better discoverability via `--help`
2. Safer syncing with category-based preview
3. Non-invasive templates for project setup guidance
4. Cleaner separation of toolkit vs project settings

## Non-Goals

- Bidirectional sync (send subcommand is sufficient)
- Hook dependency validation (future)
- Automatic Makefile/gitignore merging (templates are suggestions only)

---

## Command Structure

```
claude-toolkit                    # Shows help
claude-toolkit sync [path] [opts] # Sync toolkit → project
claude-toolkit send <file> [opts] # Send resource → suggestions-box
claude-toolkit --help             # Same as bare command
claude-toolkit <cmd> --help       # Command-specific help
```

---

## Help Output

### Main Help

```
claude-toolkit - Manage Claude Code configurations across projects

Usage:
  claude-toolkit sync [path] [options]   Sync toolkit to a project
  claude-toolkit send <file> [options]   Send a resource to suggestions-box

Run 'claude-toolkit <command> --help' for command-specific help.
```

### Sync Help

```
Sync toolkit resources to a project

Usage: claude-toolkit sync [path] [options]

Arguments:
  path          Target project (default: current directory)

Options:
  --dry-run     Preview changes without applying
  --force       Skip confirmations, overwrite conflicts
  --only TYPE   Sync only specific types (comma-separated)
                Types: skills, agents, hooks, memories
  --help        Show this help

Files:
  .claude-sync-version   Tracks synced toolkit version
  .claude-sync-ignore    Patterns to skip (one per line)

Examples:
  claude-toolkit sync ~/myproject
  claude-toolkit sync . --only skills,agents
  claude-toolkit sync --dry-run
```

### Send Help

```
Send a resource from another project to the toolkit's suggestions-box

Usage: claude-toolkit send <path> --type TYPE --project NAME

Arguments:
  path              Path to the resource file

Options:
  --type TYPE       Resource type: skill, agent, hook, memory
  --project NAME    Source project name (creates suggestions-box/<project>/)
  --help            Show this help

Example:
  claude-toolkit send .claude/skills/draft-pr/SKILL.md --type skill --project myapp
  # Creates: suggestions-box/myapp/draft-pr-SKILL.md
```

---

## Sync Flow

### Interactive Category Preview

```
$ claude-toolkit sync ~/myproject

Toolkit: 0.15.0 → Project: 0.14.0

Changes since 0.14.0:
  ## [0.15.0] - 2026-01-28
  - Added new-skill
  ...

Files by category:
  skills     2 new, 1 updated
  agents     0 new, 0 updated
  hooks      1 new, 0 updated
  memories   0 new, 3 updated
  templates  1 updated

Sync categories? [a]ll / [s]elect / [n]one: s
  [y/n] skills (2 new, 1 updated)? y
  [y/n] hooks (1 new)? y
  [y/n] memories (3 updated)? n
  [y/n] templates (1 updated)? y

Applying 5 files...
  + skills/new-skill/SKILL.md
  + skills/other/SKILL.md
  ~ skills/existing/SKILL.md
  + hooks/new-hook.sh
  ~ templates/Makefile.claude-toolkit

Synced to 0.15.0

Templates updated - consider merging into your project:
  .claude/templates/Makefile.claude-toolkit → your Makefile
  .claude/templates/gitignore.claude-toolkit → your .gitignore
```

### Category Detection

Map file paths to categories:

| Path Pattern | Category |
|--------------|----------|
| `skills/**` | skills |
| `agents/**` | agents |
| `hooks/**` | hooks |
| `memories/**` | memories |
| `templates/**` | templates |
| `scripts/**` | scripts |
| `*` (root files) | other |

### --only Flag

```bash
claude-toolkit sync --only skills,agents
```

Skips interactive prompt, syncs only specified categories.

---

## Templates

### Location

`.claude/templates/` - synced to projects as reference files.

### Files

#### Makefile.claude-toolkit

```makefile
# Makefile.claude-toolkit
# Suggested make targets for Claude Code hooks
# Add these to your project's Makefile
# ---

.PHONY: lint lint-hooks validate-resources

lint: lint-hooks
	@echo "Linting complete"

lint-hooks:
	@shellcheck .claude/hooks/*.sh 2>/dev/null || true

validate-resources:
	@.claude/scripts/validate-resources-indexed.sh
```

#### gitignore.claude-toolkit

```gitignore
# gitignore.claude-toolkit
# Suggested .gitignore entries for Claude Code
# Add these to your project's .gitignore
# ---

# Claude Code local files
.claude/settings.local.json
.claude/usage.log
.claude/plans/

# Sync tracking (optional - some prefer to commit this)
# .claude-sync-version
```

#### settings.template.json

```json
{
  "_comment": "Reference settings - compare with your .claude/settings.json",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [".claude/hooks/user-prompt-submit.sh"]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [".claude/hooks/post-tool-use-lint.sh"]
      }
    ]
  }
}
```

---

## Default Ignores

Update built-in ignores in the script:

```bash
# Built-in ignores (always skip these)
IGNORE_PATTERNS+=("plans/")
IGNORE_PATTERNS+=("usage.log")
IGNORE_PATTERNS+=("settings.local.json")
IGNORE_PATTERNS+=("settings.json")  # NEW: never overwrite project settings
```

### .claude-sync-ignore Template

Provide as `.claude/templates/claude-sync-ignore.template`:

```
# .claude-sync-ignore
# Patterns to exclude from claude-toolkit sync
# One pattern per line, # for comments
# ---

# Project-specific memories (never overwrite)
memories/

# Local settings
settings.json
settings.local.json

# Plans and logs
plans/
usage.log
```

---

## Post-Sync Reminders

Show reminder when template files are synced:

```bash
if [[ ${#SYNCED_TEMPLATES[@]} -gt 0 ]]; then
    echo ""
    echo "Templates updated - consider merging into your project:"
    for t in "${SYNCED_TEMPLATES[@]}"; do
        case "$t" in
            *Makefile*) echo "  .claude/templates/$t → your Makefile" ;;
            *gitignore*) echo "  .claude/templates/$t → your .gitignore" ;;
            *settings*) echo "  .claude/templates/$t → compare with .claude/settings.json" ;;
        esac
    done
fi
```

---

## File Changes

| Action | File |
|--------|------|
| Rename | `bin/claude-sync` → `bin/claude-toolkit` |
| Create | `.claude/templates/Makefile.claude-toolkit` |
| Create | `.claude/templates/gitignore.claude-toolkit` |
| Create | `.claude/templates/settings.template.json` |
| Create | `.claude/templates/claude-sync-ignore.template` |
| Update | `README.md` - document new CLI |
| Update | `CHANGELOG.md` - document changes |

---

## Future Considerations

- **Hook dependency hints**: "hook X requires make target Y" (opt-in verbose mode)
- **Diff preview**: Show actual diffs for updated files before confirming
- **Undo**: `claude-toolkit sync --undo` to revert last sync
