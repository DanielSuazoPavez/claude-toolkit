# v3 Audit — `cli/`

Exhaustive file-level audit of the `cli/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`cli/` hosts the subcommands dispatched by `bin/claude-toolkit`: `backlog`, `eval`, `lessons`. Two of three are self-contained workshop tools (backlog = author-facing, eval = curation). The third (`lessons`) is the one load-bearing tension: the toolkit ships a CLI that reads/writes a **global** database whose **schema is owned by a satellite** (claude-sessions). The audit captures that as the main structural question; the Python code itself is fine.

No file in `cli/` encodes "orchestrate downstream projects." Findings are small: one stale docstring line, one legacy-subcommand question, and the schema-ownership question for `lessons/db.py`.

---

## Files

### `cli/CLAUDE.md`

- **Tag:** `Keep`
- **Finding:** Accurately describes the three subcommands and how they're wired. No orchestration assumptions. Mentions that the lessons DB lives at `~/.claude/lessons.db` (global) — consistent with the new canon.
- **Action:** none.

### `cli/__init__.py`

- **Tag:** `Keep`
- **Finding:** Empty package marker. File is 0 bytes and exists only so `cli.lessons` imports work under `uv` workspace packaging. No workshop-vs-orchestrator signal either way.
- **Action:** none.

### `cli/backlog/query.sh`

- **Tag:** `Keep`
- **Finding:** Self-contained bash script for parsing/querying the workshop's own `BACKLOG.md`. Author-facing tool — this is *the workshop keeping its own house in order*, not coordinating downstream projects. Fits the workshop identity cleanly.
- **Action:** none.

### `cli/backlog/validate.sh`

- **Tag:** `Keep`
- **Finding:** Format-validator for `BACKLOG.md`. Same shape/role as `query.sh` — workshop-internal tooling. Enforces the backlog schema defined in `.claude/docs/relevant-workflow-backlog.md`. No orchestration, no runtime state.
- **Action:** none.

### `cli/eval/query.sh`

- **Tag:** `Keep`
- **Finding:** Queries `docs/indexes/evaluations.json` to report evaluation status (stale, unevaluated, above-threshold) for workshop resources (skills, hooks, docs, agents). This is core curation machinery — the *"does this belong"* loop from the identity doc §5 runs on top of this. Workshop-shaped by definition.
- **Action:** none.

### `cli/lessons/__init__.py`

- **Tag:** `Keep`
- **Finding:** Empty package marker. Required for `cli.lessons.formatting` imports. No finding.
- **Action:** none.

### `cli/lessons/db.py`

- **Tag:** `Investigate`
- **Finding:** This is the one file in `cli/` where the canon tension lands. Three things to resolve:

  1. **Schema ownership.** The module docstring (lines 7–10) already acknowledges the v3 reality: *"canonical yaml lives in claude-sessions/schemas/lessons.yaml ... toolkit retains INIT_SQL for runtime bootstrap — it must stay byte-compatible with the yaml."* But `INIT_SQL` is still a ~80-line hardcoded SQL blob (lines 43–122). Every schema change upstream requires a manual re-copy here. Options (decide at stage 2 decision point, do not act yet):
     - **Keep the dup as-is**, trust the docstring warning. Pro: no coupling. Con: silent drift risk — nothing enforces byte-compat.
     - **Read `INIT_SQL` from the synced yaml at runtime**, making claude-sessions the single source of truth. Pro: eliminates drift. Con: adds a sync dependency to CLI bootstrap; failure mode is harder to debug.
     - **Move `init_lessons_db` into claude-sessions**, have the toolkit CLI call into it. Pro: cleanest ownership. Con: creates a runtime dep from toolkit → satellite, which inverts the workshop→satellite arrow.
     - Probably the right v3 answer is **option 1 with a test**: keep the dup, but add a contract test (or a CI check) that diffs the in-file SQL against the synced yaml. No runtime coupling, drift becomes loud.

  2. **CRUD surface breadth.** `cli/lessons/db.py` ships 13 subcommands (migrate, add, search, get, list, summary, set-meta, tags, clusters, crystallize, absorb, tag-hygiene, health). Several — `clusters`, `crystallize`, `tag-hygiene`, `health` — are analytics/curation operations, not CRUD. Per canon §3 ("analytics logic ... owned by the satellite whose niche they fit"), those *probably* belong in claude-sessions, with the toolkit keeping only the thin CRUD surface (add/get/list/search/summary/set-meta). But that's a satellite-repo decision and moving them risks breaking `/manage-lessons` flows. Flagging for the decision point, not proposing an action.

  3. **`migrate` subcommand.** Migrates from `learned.json` → `lessons.db`. That migration path is historical (the JSON-era predates the db). If no project still has a `learned.json`, `cmd_migrate` is dead code. Worth a quick grep before v3 closes.

- **Action:** Defer decisions 1 and 2 to the post-audit decision point. For decision 3, grep for `learned.json` references across consumer projects at decision time; if none exist, remove `cmd_migrate` and its parser wiring.
- **Scope:** Decisions 1 and 2 are non-trivial (design calls with claude-sessions implications). Decision 3 is a ~30-line deletion.

### `cli/lessons/formatting.py`

- **Tag:** `Keep`
- **Finding:** Small shared helpers: ANSI color dict and a `_fmt_tokens` helper. Respects `NO_COLOR` and TTY detection. Reused by `cli/lessons/db.py`. No orchestration signal.
- **Action:** none. *(Minor: `_fmt_tokens` is defined but I don't see it imported in `db.py` — if it's unused across the repo, could trim. Not a v3 blocker. Investigate at decision point if convenient.)*

---

## Cross-cutting notes

- **No bin/claude-toolkit dispatcher review here.** The dispatcher itself lives at `bin/claude-toolkit` (top-level), not under `cli/`. That file gets audited when stage 2 reaches "Top-level files."
- **Tests:** `tests/cli/` exists and covers these modules — audit of those is part of `tests/` stage 2 slot, not `cli/`.
- **Stage 2 findings are logged, not applied.** Everything above queues for the post-audit decision point.

---

## Decision-point queue (carry forward)

From this directory, the following items need explicit in-or-out calls for v3:

1. `cli/lessons/db.py` **INIT_SQL ↔ yaml** drift — pick one of the four options above.
2. `cli/lessons/db.py` **analytics subcommands** (`clusters`, `crystallize`, `tag-hygiene`, `health`) — keep in toolkit CLI, or migrate to claude-sessions?
3. `cli/lessons/db.py` **`cmd_migrate`** — dead code check (grep `learned.json` across consumers); remove if unused.
4. `cli/lessons/formatting.py` **`_fmt_tokens`** — used anywhere? trim if not.
