# v3 Audit — `output/claude-toolkit/`

Structure-only audit of `output/claude-toolkit/`. Individual files are session-generated artifacts (plans, handoffs, review reports, exploration notes, etc.) and are **gitignored** (`.gitignore` line 23) — per-file findings would be noise. This audit evaluates the directory **layout** only.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this layout assume orchestration, or is it workshop-shaped?

---

## Summary

`output/claude-toolkit/` is the scratch drawer: sessions, plans, reviews, drafts, exploration, analysis, research, proposals, notes. All gitignored. Referenced by multiple resources:

- Settings grants write access: `Write(/output/claude-toolkit/**)`, `Edit(/output/claude-toolkit/**)` (per `relevant-toolkit-permissions_config.md:30`).
- Skills use specific subdirs by convention (`plans/` for plan files, `drafts/` for ideas — `relevant-toolkit-context.md:57`).
- Identity doc calls out `output/claude-toolkit/exploration/` as the lane for "interesting but not actionable now" (`relevant-project-identity.md:68`).
- BACKLOG entries point at `output/claude-toolkit/plans/plan-file.md` (`relevant-workflow-backlog.md:57`).

**Workshop-shaped by definition.** The directory is the workshop's local work surface — nothing published, nothing synced, nothing that reaches into downstream projects. It's where the workshop thinks before committing.

---

## Current layout

```
output/claude-toolkit/
├── analysis/        # Investigation reports (research agent outputs, feasibility analyses)
├── design/          # Design docs, brainstorm outputs (e.g. v3 design lives here)
├── drafts/          # Ideation drafts — pre-resource scratch space
├── exploration/     # Curated references; "interesting but not actionable now"
├── notes/           # Short-form observations, session notes
├── plans/           # Plan-mode outputs referenced by BACKLOG items
├── proposals/       # Shaped proposals (shape-proposal skill output)
├── research/        # Background research before a decision
├── reviews/         # Agent-generated review reports (code-reviewer, goal-verifier, etc.)
└── sessions/        # Write-handoff outputs across session boundaries
```

10 subdirectories. Naming is noun-plural, consistent.

---

## Structural finding

- **Tag:** `Keep`
- **Finding:** Layout is workshop-shaped and largely canonical:
  - **Writable-by-claude zone.** Settings explicitly permit writes here and **only** here outside `.claude/` — one place for generated artifacts, away from source resources. Clean.
  - **Gitignored.** Scratch work doesn't leak into git history unless explicitly promoted. The `planning/v3-audit/` files (current audit work) live *outside* `output/` because they're tracked work, not scratch. That distinction is correct.
  - **Subdir semantics are real.** Skills reference specific subdirs (`plans/`, `drafts/`, `exploration/`), so the split isn't ornamental. Handoffs to `sessions/`, reviews to `reviews/`, etc. Each subdir has a purpose.
  - **No orchestration smells.** Nothing here coordinates downstream projects; these are artifacts *of* workshop work.

  Three small queueable notes (none blocking):

  1. **No documented catalog.** The 10 subdir purposes aren't listed in any one doc — they're inferred by walking skills and observed conventions. A brief `output/claude-toolkit/README.md` (gitignored like its contents, or tracked as meta) mapping each subdir to its intended use would make the layout self-documenting. Small benefit; opt-in.
  2. **Possible overlap: `drafts/` vs `exploration/` vs `notes/`.** All three are "short prose before it becomes something." Identity doc §5 singles out `exploration/` as the "interesting but not actionable now" lane. `drafts/` is called out in context conventions as ideation space. `notes/` isn't documented anywhere I see. If `notes/` is a de-facto synonym for one of the others, either formalize it or deprecate it at the decision point.
  3. **Subdir growth over time.** The workshop hasn't had a pruning pass on `output/` subdirs since creation. If a subdir has been empty for months or holds only stale drafts, consolidating would reduce cognitive load. Not visible without per-subdir age stats; flag as future hygiene, not v3-blocking.

- **Action:** at decision point: (1) consider a `README.md` cataloging subdirs and their intended skill owners, (2) reconcile `drafts/` / `exploration/` / `notes/` overlap, (3) optional hygiene pass on stale subdirs.
- **Scope:** (1) 20-line doc, (2) 1-line reconciliation call, (3) out-of-scope for v3 likely.

---

## Cross-cutting notes

- **This directory is the clearest expression of "human-in-the-loop, not leave-Claude-running."** Scratch artifacts accumulate because workshop sessions produce a lot of ephemeral thinking; the gitignore keeps it from polluting the repo. Matches the identity doc's "collaborative sessions, not 'leave Claude running for hours.'"
- **Decision queue is short** — layout is working. Notes are polish, not structural rewrites.

---

## Decision-point queue (carry forward)

From this directory, the following items need explicit in-or-out calls for v3:

1. `output/claude-toolkit/` **subdir catalog doc** — 20-line README mapping each subdir to its intended use and owning skill/agent.
2. `output/claude-toolkit/` **drafts / exploration / notes overlap** — pick one purpose per subdir or consolidate.
