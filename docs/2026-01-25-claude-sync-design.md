# claude-sync Design

Sync script to distribute skills from claude-toolkit to other projects.

## Problem

- claude-toolkit is the source of truth for skills, agents, hooks, memories
- Other projects (dotfiles, python-template, future projects) need subsets of these
- Need a way to update projects when toolkit improves
- Some projects stay stable, others track latest
- Local customizations should be preserved

## Solution

A `claude-sync` command that:
1. Compares toolkit version with project's last synced version
2. Shows what changed (via CHANGELOG)
3. Handles conflicts when local files were modified
4. Maintains an ignore list for intentionally customized files

## File Structure

### claude-toolkit (source)

```
claude-toolkit/
├─ VERSION                    # "1.0.0"
├─ CHANGELOG.md               # what changed per version
├─ bin/claude-sync            # the sync script
├─ install.sh                 # existing (one-time initial copy)
└─ .claude/
    ├─ SKILLS.md, AGENTS.md, HOOKS.md, MEMORIES.md
    ├─ skills/
    ├─ agents/
    ├─ hooks/
    ├─ memories/
    └─ settings.local.json
```

### Target project (destination)

```
project/
├─ .claude-sync-version       # "1.0.0" (tracks last synced version)
├─ .claude-sync-ignore        # files to skip during sync
└─ .claude/
    └─ (synced content)
```

## Versioning

### Semver (MAJOR.MINOR.PATCH)

| Bump | When | Example |
|------|------|---------|
| **Major** (2.0.0) | Breaking change - skill renamed, removed, or behavior changed significantly | `write-memory` → `create-memory` |
| **Minor** (1.1.0) | New skill/agent/hook added, or meaningful improvement | Added `docker-deployment` skill |
| **Patch** (1.0.1) | Typo fix, clarification, minor tweak | Fixed example in `database-schema` |

### CHANGELOG.md Format

```markdown
# Changelog

## [1.2.0] - 2026-01-25
### Added
- `docker-deployment` skill

### Changed
- `code-reviewer`: now checks for security issues

## [1.1.0] - 2026-01-20
### Added
- `qa-planner` skill

### Fixed
- `database-schema`: typo in indexing example
```

## Sync Flow

```
claude-sync [path]           # default: current directory
│
├─ Read toolkit VERSION (e.g., "1.2.0")
├─ Read project .claude-sync-version (e.g., "1.1.0")
│
├─ Same version?
│   └─ "Already up to date" → exit
│
├─ Toolkit newer?
│   ├─ Show CHANGELOG entries since last sync
│   ├─ List files that would change
│   │
│   ├─ For each changed file:
│   │   ├─ In .claude-sync-ignore? → SKIP (silent)
│   │   ├─ Not in project? → NEW (auto-add)
│   │   ├─ Identical content? → UNCHANGED (silent)
│   │   └─ Different content? → CONFLICT
│   │       └─ Prompt user:
│   │           ├─ [o]verwrite - take toolkit version
│   │           ├─ [s]kip once - keep local this time
│   │           └─ [i]gnore always - add to .claude-sync-ignore
│   │
│   ├─ Confirm: "Apply N changes? [y/N]"
│   ├─ Apply changes
│   └─ Update .claude-sync-version to toolkit version
│
└─ Project newer than toolkit?
    └─ "Warning: project version (1.3.0) is newer than toolkit (1.2.0)"
```

## Commands

### claude-sync

```bash
claude-sync              # sync current directory
claude-sync /path/to     # sync specific project
```

### claude-sync --dry-run

Show what would change without applying:

```
$ claude-sync --dry-run

Toolkit version: 1.2.0
Project version: 1.1.0

Changes since 1.1.0:
  [1.2.0] Added docker-deployment skill
  [1.2.0] Changed code-reviewer: security checks

Files to update:
  + skills/docker-deployment/SKILL.md (new)
  ~ agents/code-reviewer.md (updated)

Conflicts:
  ! memories/essential-conventions-code_style.md (local changes)

Run without --dry-run to apply.
```

### claude-sync --force

Skip conflict prompts, overwrite all (still respects .claude-sync-ignore):

```bash
claude-sync --force      # overwrite conflicts, respect ignore list
```

## .claude-sync-ignore Format

```
# Files I've customized for this project
skills/database-schema/
memories/essential-conventions-code_style.md

# Hooks not relevant to this project
hooks/enforce-uv-run.sh
```

- One path per line (relative to .claude/)
- Directories end with `/`
- Comments start with `#`
- Blank lines ignored

## Installation

Add to `~/.bashrc`:

```bash
alias claude-sync="$HOME/projects/personal/claude-toolkit/bin/claude-sync"
```

Or add `claude-toolkit/bin` to PATH:

```bash
export PATH="$HOME/projects/personal/claude-toolkit/bin:$PATH"
```

## Relationship to install.sh

| Script | Purpose | When to use |
|--------|---------|-------------|
| `install.sh` | One-time copy, no version tracking | New project setup |
| `claude-sync` | Version-aware updates with conflict handling | Ongoing updates |

After initial `install.sh`, use `claude-sync` for all updates.

Optionally, `install.sh` could be updated to:
1. Run the copy
2. Create `.claude-sync-version` with current toolkit version

## Future: Public Distribution (Phase D)

When ready to publish:

1. Push claude-toolkit to GitHub
2. Users clone or download
3. Run `install.sh /path/to/project` for initial setup
4. Add alias, use `claude-sync` for updates

Could also explore:
- GitHub releases with version tags
- `curl | bash` one-liner for install
- Homebrew formula (if demand exists)

## Implementation Tasks

1. Create `VERSION` file with `1.0.0`
2. Create `CHANGELOG.md` with initial entry
3. Write `bin/claude-sync` script
4. Update `install.sh` to set `.claude-sync-version`
5. Add alias to personal `.bashrc`
6. Test sync flow with dotfiles and python-template
