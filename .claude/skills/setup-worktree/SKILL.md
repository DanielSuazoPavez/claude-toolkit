---
name: setup-worktree
metadata: { type: command }
description: Set up a git worktree with full Claude configuration. Use when working on multiple branches simultaneously or isolating work for parallel Claude instances. Keywords: worktree, parallel, branch isolation.
argument-hint: "[optional] Path to context file to symlink into worktree"
allowed-tools: Bash(git:*), Bash(ln:*), Bash(ls:*), Bash(mkdir:*), Read
---

Set up a worktree for branch isolation. Worktrees live in `.worktrees/` (gitignored, inside project).

**See also:** `/teardown-worktree` (close out worktree after completion)

## Context File (Optional)

If `$ARGUMENTS` contains a file path, symlink it into the worktree's `output/claude-toolkit/` directory. This is optional — worktrees work fine without one.

## Setup Procedure

### 1. Ensure .worktrees/ Is Gitignored

```bash
# Check first — only add if missing
grep -q '^\.worktrees/' .gitignore 2>/dev/null || echo ".worktrees/" >> .gitignore
```

### 2. Create the Worktree

Ask the user for the branch name if not obvious from context.

```bash
# New branch
git worktree add .worktrees/<name> -b <branch-name>

# Existing branch (omit -b)
git worktree add .worktrees/<name> <branch-name>
```

### 3. Symlink Claude Resources (If Needed)

Check if `.claude/` already exists in the worktree (it will if the project tracks `.claude/` in git). If it does, **skip this step** — the worktree already has everything.

If `.claude/` is missing (gitignored, synced via claude-toolkit), symlink from the main project:

```bash
WORKTREE=.worktrees/<name>
MAIN=$(pwd)

if [ ! -d "$WORKTREE/.claude/skills" ]; then
  # .claude/ not tracked — symlink from main
  mkdir -p "$WORKTREE/.claude"
  ln -s "$MAIN/.claude/agents"   "$WORKTREE/.claude/agents"
  ln -s "$MAIN/.claude/hooks"    "$WORKTREE/.claude/hooks"
  ln -s "$MAIN/.claude/memories" "$WORKTREE/.claude/memories"
  ln -s "$MAIN/.claude/skills"   "$WORKTREE/.claude/skills"
  ln -s "$MAIN/.claude/scripts"  "$WORKTREE/.claude/scripts"
  ln -s "$MAIN/.claude/settings.json" "$WORKTREE/.claude/settings.json"
fi
```

**On retry** (partial setup): `ln -s` fails if the symlink already exists. Use `ln -sf` to overwrite, or remove the `.claude/` directory in the worktree and start fresh.

### 4. Link Context File (If Provided)

```bash
if [ -n "$ARGUMENTS" ] && [ -f "$MAIN/$ARGUMENTS" ]; then
  mkdir -p "$WORKTREE/output/claude-toolkit"
  ln -s "$MAIN/$ARGUMENTS" "$WORKTREE/output/claude-toolkit/$(basename "$ARGUMENTS")"
fi
```

### 5. Verify Setup

```bash
ls -la "$WORKTREE/.claude/"
```

## Common Pitfalls

### Missing Claude Resources

If `.claude/` is gitignored and you skip step 3, the Claude instance in the worktree has zero configuration — no agents, hooks, memories, or permissions. Always check whether `.claude/` exists in the worktree after creation.

### Worktree Gets Stale

Your worktree diverges from main. Periodically:
```bash
cd .worktrees/feature-x
git fetch origin
git rebase origin/main
```

### Orphaned Worktrees

Git maintains internal references. If you `rm -rf` without `git worktree remove`, git still thinks it exists.

```bash
# Proper removal
git worktree remove .worktrees/feature-x

# Clean up after manual deletion
git worktree prune
```

### Can't Delete Branch

Git refuses to delete a branch checked out in any worktree:
```bash
git worktree remove .worktrees/feature-x
git branch -d feature-x  # now works
```

## After Setup

Start a Claude instance in the worktree directory. When done, use `/teardown-worktree` to close out.
