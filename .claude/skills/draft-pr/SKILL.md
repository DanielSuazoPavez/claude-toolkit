---
name: draft-pr
type: command
description: Use when requests mention "PR description", "pull request", "open PR", "create PR", or "draft PR". Analyzes branch commits and generates PR title and description.
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Read, Glob, Write
---

# Draft PR

Generate a pull request description for the current branch.

## When NOT to Use

- **Single-commit trivial fix** — the commit message is the description. Just open the PR.
- **WIP/draft branches** — use `/write-handoff` instead to capture context for later.
- **No commits yet** — nothing to describe. Commit first.

## Instructions

### 1. Analyze the branch

- Review commits since branching from main: `git log main..HEAD --oneline`
- Check changed files: `git diff main --stat`
- Read CHANGELOG.md for the latest entry (created by `/wrap-up`)

### 2. Check for PR template

Look for a pull request template in the project:
- `.github/pull_request_template.md`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/PULL_REQUEST_TEMPLATE/` (directory with multiple templates)

If a template exists, use it as the output format in step 5 instead of the default format. Fill in the template sections with the branch analysis.

### 3. Check PR size

| Lines Changed | Action |
|---------------|--------|
| <200 | Ship it |
| 200-400 | Review scope — can it split? |
| 400-600 | Should split unless tightly coupled |
| >600 | Must split — find the seam |

**Sizing exceptions:**

| Case | Guidance |
|------|----------|
| **Generated/lock files** | Exclude from line count (auto-generated, not reviewable) |
| **Monorepo cross-package** | Count per-package; each package's changes should independently pass sizing |
| **Infrastructure (CI, Docker, Terraform)** | Larger PRs acceptable when configs are declarative and self-documenting |
| **Security fixes** | Ship immediately regardless of size; note urgency in summary |
| **Large-scale rename/refactor** | Acceptable if purely mechanical — document the transformation clearly |

### 4. Split if needed

```
Is the PR >400 lines (excluding generated files)?
├─ No → Ship it
└─ Yes → Are all changes tightly coupled?
    ├─ Yes → Document why in PR, ship it
    └─ No → Find the seam:
        ├─ Different files/areas? → Split by area
        ├─ Refactor + feature? → Refactor PR first
        └─ Multiple features? → One feature per PR
```

**Stacked PRs** — when changes must land in order:

1. Create PR1 with the base change, target `main`
2. Create PR2 targeting PR1's branch (not `main`)
3. In each PR description, note the dependency: `Depends on #<PR1>`
4. Merge bottom-up: PR1 first, rebase PR2 onto `main`, then merge PR2
5. Keep each slice independently reviewable — the reviewer should not need PR1 context to evaluate PR2's diff

### 5. Generate PR description

Tell the story of WHY, not the chronology of HOW. Synthesize commits into a coherent narrative.

If a PR template was found in step 2, use it as the structure. Otherwise, use this default format:

```markdown
## Summary
[2-3 sentences: what changed and why — a reviewer should understand the WHY in 30 seconds]

## Changes
- [Key change 1]
- [Key change 2]

## Testing
[How you verified it works — specific tests, manual verification steps]
```

- Reference issue numbers: `Fixes #123`
- Explain non-obvious decisions in the summary
- If PR exceeds sizing guidelines, explain why it cannot be split

### 6. Output

Write the PR description to `.claude/output/pr-descriptions/{timestamp}_{branch-name}.md` (e.g., `20260320_feat-add-auth.md`). Include the PR title as an H1 heading at the top of the file.

Tell the user the file path so they can review and use it.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Mega-PR** | 1500 lines, "it's all connected" | It's not. Find the seam. |
| **The Empty PR** | "Fixed bug" | Add context: what bug, why it happened |
| **The Novel** | 5 paragraphs explaining the diff | Summary should add context, not repeat code |
| **The Commit Dump** | Copy-pasted commit messages | Synthesize into coherent narrative |
| **Premature PR** | No changelog, no version bump | Run `/wrap-up` first |

## The Quality Test

> Can a reviewer understand the WHY in 30 seconds and review the diff in one sitting?

If no — split or improve the description.

## See Also

- `/wrap-up` — Run first to update changelog and version before drafting the PR
- `/review-changes` — Verify code quality before drafting. Use review-changes to catch issues, then draft-pr to describe the result.
- `goal-verifier` agent — Verify feature completeness against the original goal before shipping
