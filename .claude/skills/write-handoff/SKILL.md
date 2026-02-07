---
name: write-handoff
description: Use before /clear when you have uncommitted changes, partial work, or context needed for next session. Keywords: session handoff, save context, continuation file, preserve state, resume work.
---

Use before /clear to preserve context. Generates a continuation file for resuming work in a new session.

## What to Include vs Exclude

```
Is this information...
├─ Needed to resume work immediately?
│   ├─ Yes → Include in continuation file
│   └─ No → Skip it
├─ Already in CLAUDE.md or memories?
│   ├─ Yes → Reference, don't repeat
│   └─ No → Include if important
├─ Specific to this branch?
│   ├─ Yes → Include branch name and context
│   └─ No → Probably skip
└─ Actionable (has a "do this next")?
    ├─ Yes → Include in Next Steps
    └─ No → Consider if needed at all
```

**Always include:** Branch name, uncommitted changes summary, next 1-3 actions
**Usually skip:** Full file contents, obvious context, completed work details

## Output

`.claude/sessions/{YYYYMMDD}_{HHMM}__write-handoff__{context}.md` - self-contained file to restore context after `/clear`.

## Instructions

### 1. Gather Context

Run these in parallel:
```bash
# Current branch and recent commits
git branch --show-current
git log --oneline -5

# Recent changes (uncommitted)
git status --short

# Recently modified files (last hour)
find . -name "*.py" -o -name "*.md" | xargs ls -lt 2>/dev/null | head -15
```

### 2. Generate the Continuation File

Create `.claude/sessions/{YYYYMMDD}_{HHMM}__write-handoff__{context}.md` with this structure (use branch name or topic as context slug):

```markdown
# Continue Session: [Date] [Time]

## Branch
`[branch-name]` - [brief description of what's being worked on]

## Recent Work
- [What was just done in bullet points]
- [Key changes made]

## Key Files
- `path/to/file.py` - [why it's relevant]
- `path/to/other.py` - [why it's relevant]

## Memories to Load
- `essential-preferences-communication_style` - communication style
- [Other relevant memories based on the work]

## Reports/Docs
- `docs/reports/[relevant-report].md` - [what it contains]
- `backlog_[project].md` - active backlog

## Next Steps
1. [Immediate next action]
2. [Following action]
3. [Or: See `backlog_[project].md` section X]

## Context Notes
[Any important context that wouldn't be obvious from files alone]
```

### 3. Guidelines

- **Be concise**: This is a restoration file, not documentation
- **Prioritize actionable info**: What files to read, what to do next
- **Include backlog reference**: Point to specific backlog sections if applicable
- **Skip obvious context**: Don't repeat what's in CLAUDE.md
- **Use relative paths**: Keep it portable

### 4. Output

1. Create directory if needed: `mkdir -p .claude/sessions`
2. Write the file to `.claude/sessions/{YYYYMMDD}_{HHMM}__write-handoff__{context}.md`
3. Report with copy-paste ready path for new session:

```
Wrote continuation file.

To resume in a new session, paste:
read .claude/sessions/{YYYYMMDD}_{HHMM}__write-handoff__{context}.md
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Novel** | 500+ line continuation file | Focus on actionable context only |
| **Stale Files** | Old continuation files pile up | Delete after resuming |
| **Missing Branch** | Forgot to note current branch | Always include branch name |
| **No Next Steps** | Context but no direction | List 1-3 immediate actions |
| **The Dump** | Copy-pasted full files | Summarize, link to files |
| **Vague Actions** | "Continue working on feature" | Specific: "Add tests for X in file Y" |
| **Missing Dependencies** | Next step requires context not saved | Include blockers and prerequisites |
| **Over-documenting** | Every detail from session | Only what's needed to resume |

### Examples

**Bad continuation file:**
```markdown
## Next Steps
- Keep working on the feature
- Fix bugs
- Write tests
```

**Good continuation file:**
```markdown
## Next Steps
1. Add unit tests for `validate_input()` in `src/validator.py:45`
2. Fix edge case: empty array input returns None instead of []
3. Run `pytest tests/test_validator.py -v` to verify
```

## Edge Cases

### Merge Conflicts Pending

When there are unresolved merge conflicts:

```markdown
## Branch
`feature/x` - MERGE IN PROGRESS with conflicts

## Conflicts to Resolve
- `src/api.py` - conflicting imports (lines 5-12)
- `tests/test_api.py` - both branches added tests

## Resolution Notes
- Keep the import from main (uses new auth module)
- Merge test functions, don't replace
```

**Always note:** Which branch is being merged, specific conflict locations, resolution guidance.

### Multi-Branch Work

When working across multiple branches (e.g., with worktrees):

```markdown
## Active Branches
| Branch | Worktree | Status |
|--------|----------|--------|
| `feature/auth` | `.worktrees/auth` | Ready for review |
| `feature/api` | `.worktrees/api` | WIP - tests failing |
| `main` | `.` | Clean |

## Resume Priority
1. Fix failing tests in `feature/api`
2. Address review comments on `feature/auth`
```

### Interrupted Deployment

When a deployment was started but not completed:

```markdown
## Deployment Status
- **Environment:** staging
- **State:** INTERRUPTED after step 3 of 5
- **Completed:** migrations, asset build, config update
- **Remaining:** service restart, health check

## To Resume
1. Check current service state: `kubectl get pods -n staging`
2. If pods unhealthy, rollback: `kubectl rollout undo deployment/api`
3. If pods healthy, continue from step 4: restart services
```

## Validation Checklist

Before outputting "Wrote continuation file", verify:

- [ ] **Branch name included?** First thing next session needs
- [ ] **Uncommitted changes listed?** `git status` summary present
- [ ] **Next steps actionable?** Specific files and line numbers, not vague
- [ ] **Blockers noted?** Anything that prevents immediate resumption
- [ ] **File path correct?** `.claude/sessions/{YYYYMMDD}_{HHMM}__write-handoff__{context}.md`

If any check fails, fix the continuation file before announcing completion.
