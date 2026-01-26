---
name: setup-worktree
description: Reference for git worktrees - setup, usage, and common pitfalls. Use when working on multiple branches simultaneously or setting up parallel agent workflows.
---

Reference for git worktrees - setup, usage, and common pitfalls.

## Layout Decision Tree

```
Where should I put worktrees?
├─ Want everything self-contained? → Option A: Inside project (.worktrees/)
├─ Working with multiple projects? → Option C: Central ~/worktrees/
└─ Simple one-off worktree? → Option B: Sibling directory
```

| Layout | Best For | Setup Effort |
|--------|----------|--------------|
| Inside project | Most cases, easy cleanup | Add to .gitignore once |
| Sibling dirs | Quick experiments | None |
| Central dir | Multi-project workflows | One-time setup |

## What Are Worktrees?

Multiple working directories sharing the same git repo. Each worktree has its own branch checked out. Changes in one don't affect others until merged.

## Where to Put Worktrees

### Option A: Inside Project (Recommended)

```
myproject/
├── .worktrees/          # gitignored
│   ├── feature-auth/
│   └── bugfix-123/
├── src/
└── .gitignore           # add: .worktrees/
```

**Pros:** Self-contained, easy to find, cleanup is `rm -rf .worktrees/`
**Setup:** Add `.worktrees/` to `.gitignore` before creating worktrees

### Option B: Adjacent (Sibling Directories)

```
~/projects/
├── myproject/           # main
├── myproject-feature/   # worktree
└── myproject-bugfix/    # worktree
```

**Pros:** No gitignore needed, clear separation
**Cons:** Clutters parent directory, harder to see relationships

### Option C: Central Worktrees Directory

```
~/worktrees/
├── myproject-feature/
└── otherproject-fix/
```

**Pros:** All worktrees in one place
**Cons:** Divorced from projects, easy to forget about

## Basic Commands

```bash
# Create worktree with new branch
git worktree add .worktrees/feature-x -b feature-x

# Create worktree from existing branch
git worktree add .worktrees/bugfix-123 bugfix-123

# List worktrees
git worktree list

# Remove worktree (after merging/done)
git worktree remove .worktrees/feature-x

# Prune stale worktree references
git worktree prune
```

## Handling Untracked Files (Data, Configs, etc.)

Worktrees don't share untracked files. Options:

### Symlinks (Recommended for Large Data)

```bash
# After creating worktree
cd .worktrees/feature-x
ln -s ../../data ./data
ln -s ../../.env ./.env
```

**Pros:** No duplication, changes reflect everywhere
**Cons:** Must remember to create symlinks

### Setup Script

Create `scripts/setup-worktree.sh`:
```bash
#!/bin/bash
WORKTREE_PATH=$1
ln -s "$(pwd)/data" "$WORKTREE_PATH/data"
ln -s "$(pwd)/.env" "$WORKTREE_PATH/.env"
# Add more as needed
```

Usage: `./scripts/setup-worktree.sh .worktrees/feature-x`

### Shared External Directory

Keep data outside all worktrees:
```
~/project-data/myproject/    # shared data
~/projects/myproject/        # main worktree
~/projects/myproject/.worktrees/feature-x/
```

Reference via environment variable or config file.

## Common Pitfalls

### 1. Forgetting to Gitignore

```bash
# BEFORE creating worktrees
echo ".worktrees/" >> .gitignore
git add .gitignore && git commit -m "Ignore worktrees directory"
```

### 2. Worktree Gets Stale

Worktrees don't auto-update. Periodically:
```bash
cd .worktrees/feature-x
git fetch origin
git rebase origin/main  # or merge
```

### 3. Orphaned Worktrees

After deleting a worktree directory manually:
```bash
git worktree prune
```

### 4. Dependencies Not Installed

Each worktree needs its own `node_modules`, `.venv`, etc:
```bash
cd .worktrees/feature-x
npm install        # or
uv sync            # or
cargo build
```

### 5. Can't Delete Branch

If branch is checked out in a worktree, you can't delete it:
```bash
git worktree remove .worktrees/feature-x
git branch -d feature-x  # now works
```

## Multi-Agent Workflow

When using multiple Claude agents in parallel:

1. Create worktree per agent task
2. Each agent works in isolation
3. Merge results back to main when done
4. Clean up worktrees after merge

```bash
# Setup for parallel work
git worktree add .worktrees/agent-1-auth -b feature/auth
git worktree add .worktrees/agent-2-api -b feature/api

# After agents complete
git worktree remove .worktrees/agent-1-auth
git worktree remove .worktrees/agent-2-api
```

## Quick Reference

| Task | Command |
|------|---------|
| Create | `git worktree add <path> -b <branch>` |
| List | `git worktree list` |
| Remove | `git worktree remove <path>` |
| Prune | `git worktree prune` |
| Where am I? | `git worktree list` (current marked) |
