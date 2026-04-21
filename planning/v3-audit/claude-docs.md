# v3 Audit — `.claude/docs/`

Exhaustive file-level audit of the `.claude/docs/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`.claude/docs/` holds 13 prescriptive docs (rules, conventions, reference material) split between `essential-*` (always-on, session-start) and `relevant-*` (on-demand). Every doc follows the Quick Reference pattern from `relevant-toolkit-context.md` §4. Contents are workshop-shaped: they describe how the workshop's own resources are built, evaluated, and configured — not how downstream projects should be coordinated.

Three docs sync only to the workshop itself (via `dist/base/EXCLUDE`), ten sync to consumers. Per-file findings are mostly `Keep` with a handful of `Rewrite`/`Investigate` flags for drift that's accumulated since the v3 identity rewrite.

Biggest cross-cutting observation: **`relevant-toolkit-lessons.md` hasn't been reconciled with the v3 canon** (§3 of the identity doc says schema ownership is claude-sessions'). That's a doc-level version of the same tension flagged in `cli/lessons/db.py`. Logging it, not acting.

---

## Files

### `essential-conventions-code_style.md`

- **Tag:** `Investigate`
- **Finding:** Loaded at session start (auto). Prescriptive rules for implementation — functions over classes, leverage existing systems, env vars for config, minimal interfaces. Python tooling section (uv, ruff, ty) is workshop-specific but generalizable. Verification section (§4) carefully separates `make check` (read-only) from formatting (pre-commit). No orchestration smell. Synced to consumers (not in EXCLUDE). **User flagged** this doc as wanting a polish/pruning pass — likely candidates are duplication between §1 Quick Reference and §2 Design Principles, and section headings that could condense. Flagged as out-of-scope for v3 but on the list.
- **Action:** separate concern, deferred. Log a BACKLOG item for a focused polish pass post-v3.
- **Scope:** deferred.

### `essential-preferences-communication_style.md`

- **Tag:** `Investigate`
- **Finding:** Loaded at session start (auto). Code-first, pragmatic-directness rules with a good anti-pattern table. The "Would a competent colleague say this?" test is load-bearing — referenced by `/snap-back`. **User flagged** this doc as personal (consumed by local projects, not raiz — the raiz-equivalent is the `/build-communication-style` skill) and wanting tightening on the "be concise" side. §3 Anti-Patterns and §5 Key Principle have some overlap that could be compacted. Flagged as out-of-scope for v3 but on the list.
- **Action:** separate concern, deferred. Log a BACKLOG item for a tightening pass post-v3.
- **Scope:** deferred.
- **Note:** document does not currently declare its personal-vs-consumer-facing scope. Worth adding a one-line note that this is a personal preference doc and the raiz-equivalent is `/build-communication-style`, so future edits don't accidentally generalize it.

### `relevant-conventions-naming.md`

- **Tag:** `Rewrite`
- **Finding:** Covers naming for skills (`verb-noun`), agents (`context-role`), memories (`descriptive_name`), hooks (`functionality-context-detail`). Two issues:
  1. **Hook pattern is underspecified** (§6, line 124): *"Detailed conventions to be defined."* That TODO has been there long enough that the current hook set (`block-dangerous-commands`, `git-safety`, `secrets-guard`, `approve-safe-commands`, `enforce-make-commands`, `enforce-uv-run`, `block-config-edits`, `grouped-bash-guard`, `grouped-read-guard`, `suggest-read-json`, `session-start`, `surface-lessons`, `track-skill-usage`) can be used to backfill the spec — most follow `verb-noun` or `noun-role`, not the documented `functionality-context-detail`. Either update the doc to match observed practice, or pick one pattern and rename outliers.
  2. **"Memories" section (§5)** describes memories as "organic context" — consistent with `relevant-toolkit-context.md`. But this doc is in the base EXCLUDE (toolkit-internal), meaning consumers never see this naming convention. That's the right call (consumers don't name toolkit resources), but there's no satellite-equivalent naming doc for consumers who *do* create their own memories. Small gap — not a v3 blocker.
- **Action:** at decision point: (a) backfill §6 with observed hook naming patterns, (b) decide whether consumers need a slimmer naming doc in the synced set.
- **Scope:** (a) small; (b) design call.

### `relevant-conventions-testing.md`

- **Tag:** `Rewrite`
- **Finding:** Describes the workshop's own test infrastructure — bash tests in `tests/`, pytest for Python, Makefile targets, validation scripts. Content is accurate for the workshop. **User call:** this is toolkit-internal testing (test-hooks.sh, test-cli.sh, test-skill-triggers.sh, validation scripts — all specific to this repo's tests). Consumers don't run `test-skill-triggers.sh`. Belongs scoped to the workshop, not synced.
- **Action:** add `docs/relevant-conventions-testing.md` to `dist/base/EXCLUDE`. Stays in the workshop's `.claude/docs/`, stops getting synced to consumers. Queue this for the decision-point actions (not executed in stage 2).
- **Scope:** trivial — 1-line EXCLUDE addition.

### `relevant-philosophy-reducing_entropy.md`

- **Tag:** `Keep`
- **Finding:** "Measure changes by final code amount, not effort. Bias toward deletion." Three questions (smallest viable, net reduction, what can be deleted). Aligns tightly with the identity doc's "curated, not exhaustive" principle. The red flags table is reference material — short, direct, no filler. Synced to consumers.
- **Action:** none.

### `relevant-project-identity.md`

- **Tag:** `Keep`
- **Finding:** The v3 canon itself — reframes the toolkit as a resource workshop, lays out consumer-vs-satellite downstream model, catalogs resource roles (skill/hook/agent/doc), provides the "does this belong?" scope gate. Correctly listed in `dist/base/EXCLUDE` (toolkit-internal; consumers get a different identity). This is the doc every other audit finding is measured against.
- **Action:** none.

### `relevant-toolkit-context.md`

- **Tag:** `Keep`
- **Finding:** Defines the docs/memories boundary, category conventions (`essential-`/`relevant-`), Quick Reference section requirement, auto-memory symlink pattern. The "decision guide" (line 26: *"If it tells Claude how to behave → doc. If it tells Claude who you are → memory."*) is the single sentence that keeps this architecture coherent. Synced to consumers.
- **Action:** none.
- *Minor:* the auto-memory symlink instructions (§6) are workshop-specific setup — consumers likely won't configure it. Not a rewrite reason, but a candidate for splitting into a setup-only appendix if the doc ever gets too long.

### `relevant-toolkit-hooks.md`

- **Tag:** `Rewrite`
- **Finding:** Match/check authoring pattern for hooks — cheap predicate, expensive guard, dual-mode trigger. The "Cheapness Contract" (§4) and "Anti-Patterns" (§10) tables are load-bearing for anyone writing hooks. Dispatcher internals (§8) include a specific warning about the `_HOOK_UTILS_SOURCED` guard that's easy to break.

  §9 "Current Hook Set" table lists 6 Bash-touching hooks (block-dangerous-commands, git-safety, secrets-guard, block-config-edits, enforce-make-commands, enforce-uv-run). **User call:** newer hooks missing from this table (`grouped-bash-guard`, `grouped-read-guard`, `surface-lessons`, `suggest-read-json`, `approve-safe-commands`, `session-start`, `track-skill-usage`) is **not intentional** — this is table drift, not scope. Needs backfilling. The match/check pattern doc is the single source of truth for *how* hooks are written; if hooks exist that aren't listed here, the doc silently implies they may not follow the pattern (and several of them *do* follow it).

- **Action:** at decision point: update §9 table to reflect the full current hook set, grouped by pattern/role if needed (Bash guards vs grouped dispatchers vs session hooks vs context-injection hooks).
- **Scope:** moderate — requires walking each missing hook to confirm whether it follows match/check or is a legitimately different pattern (session-start is a singleton, track-skill-usage is PostToolUse-style, etc.). The table should reflect the taxonomy, not just add rows.

### `relevant-toolkit-hooks_config.md`

- **Tag:** `Rewrite`
- **Finding:** Hook triggers + env vars reference. Two issues:
  1. **Missing hooks from the Active Hooks tables (§2).** The tables list 8 hooks (session-start, block-dangerous-commands, enforce-uv-run, enforce-make-commands, block-config-edits, secrets-guard, suggest-read-json, git-safety). Missing: `surface-lessons.sh`, `approve-safe-commands.sh`, `track-skill-usage.sh`, `grouped-bash-guard.sh`, `grouped-read-guard.sh`. The first three are real hooks with distinct events (PreToolUse, PermissionRequest, PostToolUse or similar); the dispatcher hooks probably don't belong in a per-trigger table but the others do. Check actual `.claude/hooks/` contents and backfill.
  2. **Nudge logic description (§3, para after the env-block table)** describes `/setup-toolkit` Phase 1.5 writing both opt-in keys. Worth verifying this still matches `/setup-toolkit`'s current phases — it's a live skill and may have drifted.
- **Action:** at decision point: (1) reconcile §2 tables against actual hook set, (2) verify setup-toolkit cross-ref is current.
- **Scope:** small — doc-table update + one lookup.

### `relevant-toolkit-lessons.md`

- **Tag:** `Investigate`
- **Finding:** Comprehensive lessons ecosystem reference — schema, tiers, tags, skills, hooks, CLI, lifecycle. Three tensions with v3 canon:

  1. **Schema ownership is not stated.** Lines 32–62 describe the schema as if the workshop owns it, but per v3 canon (`relevant-project-identity.md` §3, *"their schema and analytics logic are owned by the satellite whose niche they fit"*), claude-sessions owns the lessons/sessions schemas. The doc should acknowledge that INIT_SQL in `cli/lessons/db.py` is a runtime-bootstrap mirror of the canonical yaml in claude-sessions — not the source of truth.

  2. **CLI surface breadth.** Lists 13 subcommands (§8) including analytics operations (clusters, crystallize, absorb, tag-hygiene, health). If the v3 decision is to move analytics to claude-sessions (flagged in the cli/ audit decision queue), this doc would need trimming.

  3. **Backup script lives in the toolkit (§9).** `.claude/scripts/cron/backup-lessons-db.sh` backs up a db whose schema is owned by claude-sessions. Either the backup script belongs in claude-sessions (schema ownership), or this is a pragmatic split (toolkit owns user-facing scheduled maintenance, satellite owns schema/data).

  **User framing:** this is not a doc-local problem — it's *the same* lessons-ecosystem ownership question as `cli/lessons/db.py`. The doc and the code will need to be reconciled together, not separately. Decision belongs at the ecosystem level (with claude-sessions), not here.

- **Action:** defer all three sub-items to the ecosystem-level decision about lessons ownership. Once that call is made (in coordination with claude-sessions), sweep this doc + `cli/lessons/db.py` + CLI surface together in one pass.
- **Scope:** deferred pending ecosystem decision.

### `relevant-toolkit-permissions_config.md`

- **Tag:** `Keep`
- **Finding:** Two-tier permissions architecture (`settings.json` globally safe + `settings.local.json` project-specific). Decision guide (§6) is a clean flowchart. Evaluation order (§4) and scope precedence documented — useful because Claude Code's permission merging is easy to get wrong. `validate-safe-commands-sync.sh` reference (§3) is accurate. Synced to consumers.
- **Action:** none.

### `relevant-toolkit-resource_frontmatter.md`

- **Tag:** `Investigate`
- **Finding:** Reference for supported YAML frontmatter fields in skills and agents. Last verified 2026-03-20 — about a month old. Two things:
  1. **Verification freshness.** The Agent Skills spec and Claude Code extension fields change; a one-month-old verification is probably fine but worth re-checking before v3 closes. Consumer-facing frontmatter accuracy matters for `/create-skill` and `/create-agent`.
  2. **§6 Notes mentions `skill-frontmatter-type-rename` backlog item.** Quick check — is that still in the backlog, or resolved? If resolved, update this doc's note. If still open, keep as-is.
- **Action:** at decision point: (1) re-verify frontmatter against current Claude Code docs, (2) check `skill-frontmatter-type-rename` backlog status.
- **Scope:** both small.

### `relevant-workflow-backlog.md`

- **Tag:** `Keep`
- **Finding:** Schema doc for `BACKLOG.md` — section hierarchy, entry format (minimal + standard), metadata fields, status values, priority guidelines. Tooling section (§7) references `cli/backlog/query.sh` and `validate.sh` — consistent with the cli/ audit. Reference-quality doc; used by `/wrap-up`. Synced to consumers.
- **Action:** none.

---

## Cross-cutting notes

- **Docs are prescriptive and workshop-internal.** Nothing here tells consumer projects what to do; everything tells Claude *how to shape the workshop's own resources*. When these docs get copied to consumers via sync, they shape how the consumer's Claude instance treats toolkit-provided resources — still workshop-shaped, just at a different distance.

- **EXCLUDE boundary is coherent.** The three excluded docs (`relevant-conventions-naming`, `relevant-project-identity`, `relevant-toolkit-resource_frontmatter`) are the three most toolkit-internal — naming rules for workshop resources, the workshop's own identity, and frontmatter rules consumers don't need if they're not creating skills/agents. Consistent with the "workshop keeps meta-tools for itself" principle.

- **One systematic drift source: table drift.** Two of the three `Rewrite`/`Investigate` findings (naming §6, hooks_config §2) are tables that describe the hook or resource set and have fallen out of sync. Worth a lightweight mechanism — maybe a validate script that diffs the tables against the filesystem — but that's a decision-point call, not a v3 blocker.

- **Lessons-ecosystem doc is the largest v3 ownership question in this directory.** The schema-ownership framing in `relevant-toolkit-lessons.md` predates the v3 canon and needs reconciling with claude-sessions' ownership of the schema.

---

## Decision-point queue (carry forward)

From this directory. Several items were resolved during the review (calls noted inline):

**Resolved during review (pending execution at decision point):**

1. `relevant-conventions-testing.md` — **add to `dist/base/EXCLUDE`**. Toolkit-internal testing docs, should not sync to consumers.
2. `relevant-toolkit-hooks.md` §9 table — **backfill missing hooks** (grouped-*, surface-lessons, suggest-read-json, approve-safe-commands, session-start, track-skill-usage). Drift, not intentional scope. Group by pattern/role.
3. `relevant-toolkit-hooks_config.md` §2 — **reconcile tables against actual hook set**. Same drift pattern as #2. Agreed.
4. `relevant-toolkit-lessons.md` — **part of the broader lessons ecosystem ownership decision**. Defer and sweep together with `cli/lessons/db.py` once claude-sessions owner-call is made.

**Deferred post-v3 (separate concerns):**

5. `essential-conventions-code_style.md` — polish/pruning pass (duplication between §1 and §2). Log a BACKLOG item.
6. `essential-preferences-communication_style.md` — tightening pass on the "be concise" side. Log a BACKLOG item. Also add a one-line note that this doc is personal (local-only, not raiz; raiz-equivalent is the `/build-communication-style` skill) so future edits don't generalize it.

**Still open for decision:**

7. `relevant-conventions-naming.md` §6 Hooks — backfill conventions from observed hook set.
8. `relevant-conventions-naming.md` — consumer-facing naming doc in synced set? (currently EXCLUDE'd).
9. `relevant-toolkit-hooks_config.md` §3 — verify setup-toolkit Phase 1.5 cross-reference is current.
10. `relevant-toolkit-resource_frontmatter.md` — re-verify frontmatter against current Claude Code docs (last verified 2026-03-20).
11. `relevant-toolkit-resource_frontmatter.md` §6 — check `skill-frontmatter-type-rename` backlog status.
12. **Cross-cutting** — consider a validate script that keeps doc tables in sync with filesystem state (hooks table especially).
