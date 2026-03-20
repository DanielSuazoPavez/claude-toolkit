---
name: setup-worktree
type: command
description: Set up a git worktree with full Claude configuration. Use when working on multiple branches simultaneously or setting up parallel agent workflows. Keywords: worktree, parallel, branch isolation.
argument-hint: Path to plan file (e.g. .claude/output/plans/2026-02-04_my-plan.md)
allowed-tools: Bash(git:*), Bash(ln:*), Bash(ls:*), Bash(mkdir:*), Read
---

Set up a worktree with full Claude configuration. Worktrees live in `.worktrees/` (gitignored, inside project).

**See also:** `/teardown-worktree` (close out worktree after completion), `/review-plan` (review the plan before handing to a worktree agent), `relevant-workflow-branch_development` memory (branch workflow conventions)

## Plan File

`$ARGUMENTS` must contain a path to the plan file to symlink into the worktree. If not provided, ask the user which plan file to use — every worktree needs a plan.

## Setup Procedure

### 1. Ensure .worktrees/ Is Gitignored

```bash
# Check first — only add if missing
grep -q '^\.worktrees/' .gitignore 2>/dev/null || echo ".worktrees/" >> .gitignore
```

### 2. Create the Worktree

```bash
# New branch
git worktree add .worktrees/<name> -b <branch-name>

# Existing branch (omit -b)
git worktree add .worktrees/<name> <branch-name>
```

### 3. Symlink Claude Resources

`.claude/` is typically gitignored (synced via claude-toolkit). Worktrees get **no** `.claude/` content by default. Without this step, Claude instances in the worktree have no agents, hooks, memories, skills, or settings.

`CLAUDE.md` at the project root IS tracked and inherited automatically — no action needed for it.

```bash
WORKTREE=.worktrees/<name>
MAIN=$(pwd)

mkdir -p "$WORKTREE/.claude/output/plans"

# Directories
ln -s "$MAIN/.claude/agents"   "$WORKTREE/.claude/agents"
ln -s "$MAIN/.claude/hooks"    "$WORKTREE/.claude/hooks"
ln -s "$MAIN/.claude/memories" "$WORKTREE/.claude/memories"
ln -s "$MAIN/.claude/skills"   "$WORKTREE/.claude/skills"

# Settings
ln -s "$MAIN/.claude/settings.json" "$WORKTREE/.claude/settings.json"

# Plan file — verify path exists first
PLAN="$ARGUMENTS"
[ -f "$MAIN/$PLAN" ] && ln -s "$MAIN/$PLAN" "$WORKTREE/.claude/output/plans/$(basename "$PLAN")"
```

**On retry** (partial setup): `ln -s` fails if the symlink already exists. Use `ln -sf` to overwrite, or remove the `.claude/` directory in the worktree and start fresh.

### 4. Verify Setup

```bash
# Symlinks resolve correctly
ls -la "$WORKTREE/.claude/agents" "$WORKTREE/.claude/skills" "$WORKTREE/.claude/settings.json"

# Plan is linked
ls -la "$WORKTREE/.claude/output/plans/"
```

## Common Pitfalls

### Missing Claude Resources

Most damaging pitfall. A Claude instance in the worktree operates with zero configuration — no custom agents, no behavioral hooks, no memories, wrong permissions. Always symlink immediately after creating the worktree (step 3).

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

## After Setup: Launching an Agent

The worktree is ready but nothing is running in it yet. To start implementation:

1. **Launch a Claude instance** in the worktree using the Agent tool with `isolation: "worktree"`, or by running `claude` manually from the worktree directory
2. **The plan is the entry point** — the agent's first action should be reading the symlinked plan in `.claude/output/plans/`
3. **When the agent reports done**, use `/teardown-worktree` to verify and close out

## Multi-Agent Workflow

When using multiple Claude agents in parallel:

1. Create worktree per agent task (each with its own plan)
2. Launch a Claude instance in each worktree
3. Each agent works in isolation with full Claude config
4. Use `/teardown-worktree` on each when done
5. Merge results back to main

**Note:** Worktree instances won't see uncommitted changes from other worktrees — check `git log` (not just `git status`) to see commits made by other instances.
