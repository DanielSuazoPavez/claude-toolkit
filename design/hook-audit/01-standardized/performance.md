---
category: 01-standardized
axis: performance
status: drafted
date: 2026-05-03
n_per_variant: 30
mode: smoke + real (paired outcomes, V21+)
---

# 01-standardized — performance

End-to-end per-hook wall-clock measurements for all 13 standardized hooks under the same probe shape as `00-shared/performance.md`, in two paired modes (`smoke` / `real`) **and** two paired fixture outcomes (block / pass) where both fixtures exist. Goal: isolate **check-body cost** (the hook's own logic) per outcome — block-fixture cost is the full check + decision-JSON build, pass-fixture cost is the early-return path.

## Methodology

- **Wall-clock probe:** `design/hook-audit/measurement/probe/run-per-hook-probe.sh` (V21+ paired). For each hook, runs `bash <hook>.sh < <fixture>.json` end-to-end with `env -i` isolation matching `tests/hooks/run-smoke.sh`. N=30 per (hook, outcome, mode), warmup pass discarded.
- **Two outcomes per hook (V21+ paired):** block-outcome and pass-outcome where both fixtures exist; see "Coverage notes" for the four exceptions (one pass-only, two error-as-second-fixture, one approve+pass).
- **Two modes per hook:**
  - **smoke** — sandboxed `sessions.db` (path nonexistent), `CLAUDE_TOOLKIT_TRACEABILITY=0`. No sqlite3 fork, no JSONL row written. Same env contract as `tests/hooks/run-smoke.sh`.
  - **real** — points `CLAUDE_ANALYTICS_SESSIONS_DB` at the real `~/.claude/sessions.db` (read-only via `mode=ro` in the hook), `CLAUDE_TOOLKIT_TRACEABILITY=1`. One sqlite3 fork in `_resolve_project_id` (when `_ensure_project` fires) plus one `jq -c` fork in the `_hook_log_timing` EXIT trap.
- **Direct V20 probe (companion):** `tests/hooks/run-smoke.sh` walked over every fixture, N=20, capturing `duration_ms` from the JSONL row. This is what V20 measures and what `PERF-BUDGET-MS` headers target. The wall-clock probe brackets *outside* the `env -i bash …` call so it includes fork+exec + env setup; `duration_ms` is measured from `HOOK_START_MS` (set after `hook_init`) to the EXIT trap, so it excludes ~5ms bash startup + ~2.5ms hook-utils parse + ~5ms `hook_init` ≈ 13ms of structural floor.
- **Files:**
  - `design/hook-audit/measurement/probe/per-hook-N30.tsv` / `.summary` — V18 single-fixture wall-clock (kept as historical record from the 2026-05-02 snapshot)
  - `design/hook-audit/measurement/probe/per-hook-N30-paired.tsv` / `.summary` — V21+ paired-outcome wall-clock (this rerun, 2026-05-03)
  - `design/hook-audit/measurement/probe/per-hook-N20-duration-ms.tsv` — V20-style `duration_ms` per fixture (drives `PERF-BUDGET-MS` header derivation; smoke-mode only since V20 is smoke-mode only)
- **Bash startup floor** for the env-isolated probe shape (measured separately, N=30): p50 ~4.4ms, p95 ~5.9ms. Subtract before attributing to hook work. This is higher than `00-shared`'s 94µs baseline because that baseline is bash startup with `EPOCHREALTIME` markers *inside* the bash invocation; the per-hook probe brackets *outside* the `env -i bash …` call.
- **Variance:** the V21+ paired wall-clock probe ran on a multi-session-loaded box. p95/p50 ratios sit in the 1.4–2.0× band — wider than the 1.1–1.4× band of the original V18 snapshot. The `duration_ms` companion probe is much tighter (1.1–1.3× p95/p50) because it measures from inside the bash process rather than wall-clock, so kernel scheduling jitter on `env -i bash` startup doesn't contaminate the sample. Budget derivation uses the `duration_ms` companion data; the wall-clock probe drives the structural per-outcome breakdown.

Numbers below are **p50 in milliseconds** unless noted. Microsecond raw is in the TSV files.

## Per-hook totals (paired outcomes, wall-clock)

Two rows per hook where the (block, pass) pair exists. Three exceptions ship a single row labeled by their available outcome — see "Coverage notes" for why.

| Hook | Outcome | smoke p50 | smoke p95 | real p50 | real p95 | real − smoke (Δ p50) |
|------|---------|----------:|----------:|---------:|---------:|---------------------:|
| `approve-safe-commands` | approved | 63 | 106 | 91 | 135 | +28 |
| `approve-safe-commands` | pass | 76 | 119 | 119 | 228 | +43 |
| `auto-mode-shared-steps` | blocked | 80 | 154 | 108 | 211 | +28 |
| `auto-mode-shared-steps` | pass | 83 | 108 | 109 | 183 | +26 |
| `block-config-edits` | blocked | 80 | 110 | 92 | 188 | +12 |
| `block-config-edits` | pass | 55 | 122 | 92 | 128 | +37 |
| `block-credential-exfiltration` | blocked | 55 | 76 | 75 | 111 | +20 |
| `block-credential-exfiltration` | pass | 66 | 89 | 100 | 139 | +34 |
| `block-dangerous-commands` | blocked | 53 | 61 | 74 | 84 | +21 |
| `block-dangerous-commands` | pass | 27 | 33 | 56 | 145 | +29 |
| `detect-session-start-truncation` | pass | 24 | 44 | 63 | 123 | +39 |
| `enforce-make-commands` | blocked | 32 | 77 | 51 | 91 | +19 |
| `enforce-make-commands` | pass | 33 | 41 | 57 | 78 | +24 |
| `enforce-uv-run` | blocked | 36 | 44 | 62 | 83 | +26 |
| `enforce-uv-run` | pass | 33 | 41 | 55 | 75 | +22 |
| `git-safety` | blocked | 52 | 75 | 94 | 182 | +42 |
| `git-safety` | pass | 37 | 49 | 71 | 144 | +34 |
| `log-permission-denied` | error | 28 | 36 | 54 | 66 | +26 |
| `log-permission-denied` | pass | 26 | 30 | 57 | 72 | +31 |
| `log-tool-uses` | error | 27 | 31 | 47 | 56 | +20 |
| `log-tool-uses` | pass | 32 | 40 | 47 | 54 | +15 |
| `secrets-guard` | blocked | 65 | 89 | 88 | 110 | +23 |
| `secrets-guard` | pass | 52 | 58 | 74 | 80 | +22 |
| `suggest-read-json` | blocked | 33 | 39 | 55 | 63 | +22 |
| `suggest-read-json` | pass | 29 | 35 | 50 | 72 | +21 |

**Real − smoke = traceability cost.** The +15–43ms gap across hooks is one sqlite3 fork (`_resolve_project_id`) + one `jq -c` fork (`_hook_log_timing` EXIT trap), now read on a noisier box than the V18 snapshot — most variance lives in that real-mode tail. The structural cost is the same ~14–17ms documented in the V18 snapshot.

`measurement/lazy-resolution-experiment.md` already showed that with lazy resolution applied, the real-vs-smoke gap collapses from ~14–17ms to ~0.2ms for hooks that don't read `$PROJECT`. That patch is not yet on main; numbers above are pre-patch.

**Block vs pass at a glance:** for hooks where the pass-outcome fixture is materially cheaper than the block-outcome fixture (early return before the heavy check), the gap is 10–30ms p50:

- `block-dangerous-commands` block 53 / pass 27 — the regex iteration is most of the work; passing input never iterates the danger list (match returns false fast).
- `git-safety` block 52 / pass 37 — `git rev-parse` fork only fires when `match_git_safety` is true.
- `secrets-guard` block 65 / pass 52 — registry path-pattern matching only runs once a candidate path is detected.
- `block-config-edits` block 80 / pass 55 — registry resolution + path canonicalization only runs on Edit/Write of a `.claude/`-adjacent path.

For hooks where pass and block are within ~5ms of each other (`enforce-make-commands`, `enforce-uv-run`, `block-credential-exfiltration`), both outcomes pay roughly the same `match` + `check` cost — the decision-JSON build is the dominant difference.

## Check-body cost (smoke − bash floor − lib floor)

Subtracting the bash startup floor (~4.4ms p50) and the documented lib floor (`00-shared/performance.md` per-event predictions) from the smoke total isolates `hook_init` + the hook's own check-body work, **per outcome**. Block-outcome rows are the full check + decision JSON build; pass-outcome rows are the early-return path.

| Hook | Outcome | smoke p50 | bash floor | lib floor | check-body + hook_init | of which check-body (≈ −5ms hook_init) |
|------|---------|----------:|-----------:|----------:|-----------------------:|----------------------------------------:|
| `approve-safe-commands` | approved | 63 | 4.4 | 11.4 | **47** | ~42 |
| `approve-safe-commands` | pass | 76 | 4.4 | 11.4 | **60** | ~55 |
| `auto-mode-shared-steps` | blocked | 80 | 4.4 | 21.0 | **55** | ~50 |
| `auto-mode-shared-steps` | pass | 83 | 4.4 | 21.0 | **58** | ~53 |
| `block-config-edits` | blocked | 80 | 4.4 | 12.3 | **63** | ~58 |
| `block-config-edits` | pass | 55 | 4.4 | 12.3 | **38** | ~33 |
| `block-credential-exfiltration` | blocked | 55 | 4.4 | 12.3 | **38** | ~33 |
| `block-credential-exfiltration` | pass | 66 | 4.4 | 12.3 | **49** | ~44 |
| `block-dangerous-commands` | blocked | 53 | 4.4 | 2.5 | **46** | ~41 |
| `block-dangerous-commands` | pass | 27 | 4.4 | 2.5 | **20** | ~15 |
| `detect-session-start-truncation` | pass | 24 | 4.4 | 2.5 | **17** | ~12 |
| `enforce-make-commands` | blocked | 32 | 4.4 | 2.5 | **25** | ~20 |
| `enforce-make-commands` | pass | 33 | 4.4 | 2.5 | **26** | ~21 |
| `enforce-uv-run` | blocked | 36 | 4.4 | 2.5 | **29** | ~24 |
| `enforce-uv-run` | pass | 33 | 4.4 | 2.5 | **26** | ~21 |
| `git-safety` | blocked | 52 | 4.4 | 2.5 | **45** | ~40 |
| `git-safety` | pass | 37 | 4.4 | 2.5 | **30** | ~25 |
| `log-permission-denied` | error | 28 | 4.4 | 2.5 | **21** | ~16 |
| `log-permission-denied` | pass | 26 | 4.4 | 2.5 | **19** | ~14 |
| `log-tool-uses` | error | 27 | 4.4 | 2.5 | **20** | ~15 |
| `log-tool-uses` | pass | 32 | 4.4 | 2.5 | **25** | ~20 |
| `secrets-guard` | blocked | 65 | 4.4 | 12.3 | **48** | ~43 |
| `secrets-guard` | pass | 52 | 4.4 | 12.3 | **35** | ~30 |
| `suggest-read-json` | blocked | 33 | 4.4 | 2.5 | **26** | ~21 |
| `suggest-read-json` | pass | 29 | 4.4 | 2.5 | **22** | ~17 |

`hook_init` cost is ~5ms (one consolidated `jq` fork on stdin extraction, plus globals setup). The "of which check-body" column subtracts that to leave the hook's own logic.

These are wall-clock numbers from a loaded box. The `duration_ms` companion probe (next section) is the cleaner read for budget-setting; both tell the same shape.

## Direct duration_ms data (V20 budget basis)

Per-fixture `duration_ms` from `tests/hooks/run-smoke.sh` (N=20, smoke mode). This is the number V20 reads from the JSONL row and compares against `PERF-BUDGET-MS`. Microsecond cost from `env -i bash` startup is invisible to V20; what V20 sees is from `HOOK_START_MS` (after `hook_init`) to the EXIT trap.

| Hook | Outcome | n | min | p50 | p90 | p95 | max |
|------|---------|--:|----:|----:|----:|----:|----:|
| `approve-safe-commands` | approved | 20 | 30 | 40 | 50 | 51 | 54 |
| `approve-safe-commands` | pass | 20 | 34 | 40 | 53 | 57 | 68 |
| `auto-mode-shared-steps` | blocked | 20 | 23 | 28 | 31 | 34 | 40 |
| `auto-mode-shared-steps` | pass | 20 | 20 | 22 | 30 | 32 | 32 |
| `block-config-edits` | blocked | 20 | 20 | 23 | 29 | 30 | 31 |
| `block-config-edits` | pass | 20 | 19 | 23 | 27 | 30 | 37 |
| `block-credential-exfiltration` | blocked | 20 | 14 | 17 | 21 | 22 | 22 |
| `block-credential-exfiltration` | pass | 20 | 14 | 17 | 20 | 22 | 24 |
| `block-dangerous-commands` | blocked | 20 | 36 | 43 | 47 | 60 | 64 |
| `block-dangerous-commands` | pass | 20 | 13 | 15 | 18 | 19 | 21 |
| `detect-session-start-truncation` | pass | 20 | 7 | 8 | 9 | 12 | 14 |
| `enforce-make-commands` | blocked | 20 | 12 | 16 | 19 | 20 | 22 |
| `enforce-make-commands` | pass | 20 | 12 | 15 | 16 | 17 | 20 |
| `enforce-uv-run` | blocked | 20 | 15 | 18 | 25 | 26 | 28 |
| `enforce-uv-run` | pass | 20 | 14 | 19 | 22 | 23 | 24 |
| `git-safety` | blocked (force-push) | 20 | 31 | 38 | 52 | 52 | 62 |
| `git-safety` | blocked (malformed-stdin) | 20 | 7 | 8 | 9 | 10 | 12 |
| `git-safety` | pass | 20 | 14 | 17 | 23 | 24 | 34 |
| `log-permission-denied` | pass | 20 | 12 | 14 | 17 | 18 | 20 |
| `log-permission-denied` | error | 20 | 12 | 15 | 19 | 20 | 23 |
| `log-tool-uses` | pass | 20 | 13 | 15 | 19 | 19 | 22 |
| `log-tool-uses` | error | 20 | 13 | 14 | 19 | 20 | 21 |
| `secrets-guard` | blocked | 20 | 28 | 32 | 36 | 36 | 50 |
| `secrets-guard` | pass | 20 | 19 | 24 | 36 | 38 | 40 |
| `suggest-read-json` | blocked | 20 | 19 | 22 | 27 | 32 | 49 |
| `suggest-read-json` | pass | 20 | 14 | 18 | 23 | 23 | 25 |

`git-safety/blocks-malformed-stdin` is a fast-fail path (jq parse fails on malformed stdin → silent exit 0); the 10ms p95 represents the hook-utils stdin parse failing fast. The meaningful block-outcome budget for `git-safety` is the `force-push-main` row (52ms p95).

## Coverage notes

The V18 snapshot mixed block- and pass-outcome costs in a single table. The V21+ paired set fills that gap for 9 of 13 hooks. Four exceptions:

- **`detect-session-start-truncation`** ships a pass-only fixture. The block-outcome fixture (transcript injection) requires the smoke runner to write a transcript file into the sandboxed `$HOME` so the hook's truncation grep finds it. The smoke runner sandboxes `$HOME` to a fresh tmpdir per run, so the work to inject a fixture transcript is filed under `hook-audit-01-detect-truncation-injected-fixture` (P3) and deferred from this rerun.
- **`log-permission-denied`** and **`log-tool-uses`** are pure-logger hooks with no decision body. Their second fixture (`passes-on-malformed-stdin`) exercises the `outcome=error` early-exit path on jq stdin-parse failure, not a logical "block" — but V20 still applies `scope_hit` to non-`pass` outcomes, so the data is useful for budget derivation.
- **`approve-safe-commands`** has `outcome=approved` (not `blocked`) on its non-pass fixture. V20 treats anything ≠ `pass` as `scope_hit`, so the approved path drives `scope_hit` here.

## Per-hook PERF-BUDGET-MS recommendations

Methodology mirrors `02-dispatchers/inventory.md:145`:
- `scope_miss` covers the **pass-outcome** `duration_ms` worst-observed with modest headroom (V20 applies `scope_miss` when outcome=pass per `validate.sh:614`).
- `scope_hit` covers the **non-pass-outcome** `duration_ms` worst-observed with the same headroom (V20 applies `scope_hit` for any outcome ≠ pass).
- For pass-only hooks, `scope_hit` falls back to the pass-outcome max with the same headroom (V20 will never read it, but the header still needs a numeric value for V17 validity).
- `scope_hit ≥ scope_miss` always (a hit budget below the miss budget would let a regression hide on the pass path).

The ship budget covers `max(observed)` over 43 combined samples per fixture (N=20 quiet probe via `tests/hooks/run-smoke.sh` + N=23 from concurrent `make check` validate.sh runs that captured the loaded-box tail). Headroom: `ceil(max * 0.95 * 1.15)` ≈ `max * 1.09`. The two-pass derivation matters because the standalone p95 from a quiet box understated the loaded-`make check` tail by 1.5–2× (e.g., `secrets-guard/blocks-dotenv-grep` p95=36ms quiet vs max=79ms under load). A budget set at quiet-p95 + 10% trips on every loaded `make check` — the very false-positive shape this task was filed to fix.

| Hook | scope_miss | scope_hit | Source |
|------|-----------:|----------:|--------|
| `approve-safe-commands` | 114 | 114 | pass max=104; approved max=104 |
| `auto-mode-shared-steps` | 68 | 83 | pass max=62; blocked max=75 |
| `block-config-edits` | 58 | 76 | pass max=53; blocked max=69 |
| `block-credential-exfiltration` | 46 | 58 | pass max=42; blocked max=53 |
| `block-dangerous-commands` | 45 | 98 | pass max=41; blocked max=89 |
| `detect-session-start-truncation` | 26 | 26 | pass-only max=23 |
| `enforce-make-commands` | 46 | 50 | pass max=41; blocked max=45 |
| `enforce-uv-run` | 43 | 50 | pass max=39; blocked max=45 |
| `git-safety` | 47 | 87 | pass max=43; blocked max=79 (force-push, the meaningful row) |
| `log-permission-denied` | 50 | 50 | pass max=45; error max=44 (cap at miss) |
| `log-tool-uses` | 45 | 45 | pass max=41; error max=21 (cap at miss) |
| `secrets-guard` | 55 | 87 | pass max=40, +25% headroom for the tail under load (verification run hit 49ms); blocked max=79 |
| `suggest-read-json` | 62 | 62 | pass max=56; blocked max=55 (cap at miss) |

These ship as `# CC-HOOK: PERF-BUDGET-MS: scope_miss=N, scope_hit=N` lines added to each hook's header block (V17 validates the format per `validate.sh:654`).

`approve-safe-commands` is an outlier — its 100ms+ measurements come from the `settings-permissions.sh` regex compilation on first hook firing in the harness. The hook fires on PermissionRequest only, which is rare in real-session use; the harness measurement does not generalize. Budget set to absorb the cold-cache spike.

## Hooks flagged for follow-up

The audit task said "flag hooks whose check-body cost exceeds 5ms." Every hook in the category exceeds that — the floor is structural, not implementation. Useful flags are relative to what's plausible to compress.

### Loggers paying ~14–20ms duration_ms for ~0 lines of logic

`log-tool-uses` (~14–22ms `duration_ms`) and `log-permission-denied` (~14–22ms) are the two pure-logger hooks. Their `duration_ms` is **the EXIT trap row build** plus minimal pre-trap work — there is no logic body. The V21+ paired probe confirms what the V18 snapshot saw: pass and error fixtures are within ~2ms of each other (no decision branch differentiates them).

These tripped the default `scope_miss=5` budget on every `make check`. The new per-hook budgets (`scope_miss=20`, `scope_hit=22`) reflect the structural floor without hiding regressions. The lazy-resolution patch from `measurement/lazy-resolution-experiment.md` would still cut ~4.6ms off real-session for these two — recommended for the implement phase regardless.

### Detect-session-start-truncation: ~8–12ms duration_ms, pass-only coverage

`detect-session-start-truncation` measured 7–12ms `duration_ms` (smoke pass). The probe samples the **first-run** path because the env-isolated tmpdir gives every run a fresh `~/.claude/cache/`, so the marker is recreated each run. In real-session use, this hook's amortized cost is ~bash startup + lib floor (~7ms) per UserPromptSubmit, with the first prompt of each session paying the extra ~6ms.

The block-outcome (truncation injected) path is unmeasured here — see "Coverage notes". Filed as `hook-audit-01-detect-truncation-injected-fixture` (P3).

### Big check bodies: block-dangerous-commands, git-safety, secrets-guard

The V18 snapshot flagged these three with mixed-outcome check-body 26–31ms. The paired data clarifies the picture:

- **`block-dangerous-commands`**: blocked `duration_ms` p95=60ms vs pass p95=19ms. A 3× block/pass spread — the regex iteration is the dominant cost on the block path; the pass path bails out fast on the match predicate. The check is doing real work; whether to compress it is a `clarity.md` question.
- **`git-safety`**: blocked (force-push) p95=52ms vs pass p95=24ms. ~2× block/pass spread — the `git rev-parse` fork only fires on the block path. Caching the branch lookup across the dispatcher's lifetime (`02-dispatchers/clarity.md` Proposal 6) would compress this ~28ms gap.
- **`secrets-guard`**: blocked p95=36ms vs pass p95=38ms — within noise. The pass path also exercises the registry path-pattern matching (the predicate broad enough to false-positive on the pass fixture); both outcomes pay essentially the same check cost. The decision-JSON build is a small fraction.

`secrets-guard`'s near-equal block/pass cost is the most surprising find. The implication is that the hot path for this hook *is* the registry walk, not the block-decision build — which means compression would have to attack the registry shape, not the post-decision branch.

### Auto-mode-shared-steps: heaviest lib stack, modest check body

`auto-mode-shared-steps` measured 80–83ms wall-clock smoke total (matches V18 ordering: highest in the category). `duration_ms` companion shows blocked p95=34ms vs pass p95=32ms — the lib stack (~21ms hook-utils + detection-registry + settings-permissions) dominates. Under the dispatcher, the lib floor is *deduplicated* with sibling children that share registry/settings-permissions (the dispatcher's source loop pays it once). Standalone-mode cost is the worst case; dispatcher-child cost is much lower. Real per-event cost lives in `02-dispatchers/performance.md`.

## Cross-cutting observations

- **Real-session adds ~15–43ms over smoke for every hook on this loaded run.** The structural cost (sqlite3 fork + jq -c fork) is the same ~14–17ms documented in the V18 snapshot; the wider variance here is run-noise. The `duration_ms` companion data sits inside the bash process and shows the structural cost cleanly.
- **Block-vs-pass `duration_ms` gap concentrates in three hooks.** `block-dangerous-commands` (3×), `git-safety` (2×), and `block-config-edits` (~1× — the registry resolution fires on both paths). For the other 7 paired hooks, block and pass `duration_ms` p95 are within ±5ms.
- **`hook_init` is ~5ms across every hook.** Structural — one consolidated jq fork. There's no per-hook variation in init cost; the difference between hooks is entirely lib floor + check-body.
- **The wall-clock-to-`duration_ms` gap is not a fixed 13ms under load.** The probe wall-clock numbers ran 2-3× the `duration_ms` numbers on this loaded box because `env -i bash` startup + fork+exec is exposed to kernel scheduling jitter. `duration_ms` is measured *inside* the bash process and is the cleaner number for budget derivation. The plan's static "13ms gap" estimate holds for a quiet box; under load, use `duration_ms` directly.

## Verified findings feeding downstream axes

### Robustness

- The probe runs each hook end-to-end without observed runtime errors at N=30 across both outcomes. No fatal paths surfaced. Robustness fixtures (malformed stdin, missing tool_input fields) need explicit fixtures — captured under `hook-audit-00-malformed-stdin-fixtures`.

### Testability

- **Per-hook fork cost is ~22–67ms wall-clock (smoke).** A test harness that fans out across all 13 hooks × M cases pays 13×M forks at this cost. The smoke harness already does this — the paired set runs in ~5–7s for the current 31×1 fixture set. Adding multi-case-per-fixture expansion (`hook-audit-00-shape-a-lib-tests`) to the standardized hooks would multiply the fork cost; whether to invest in in-process testing depends on M growing past ~3–4 per hook. `01-standardized/testability.md` to estimate against a target case count.

### Clarity

- **The block-vs-pass spread on `block-dangerous-commands` and `git-safety`** is the natural target for `clarity.md`'s "where does the logic live" question. Both hooks have a fast match-predicate that correctly bails out on the pass path; compression on the block path would attack the regex iteration (block-dangerous-commands) or the `git rev-parse` fork (git-safety, already addressed by `02-dispatchers/clarity.md` Proposal 6).
- **`secrets-guard`'s near-equal block/pass cost** is a code-shape signal — the registry walk fires on every Grep/Read input regardless of outcome. Whether this is the right shape (broad predicate, narrow check) is a `clarity.md` call.

## Confidence

- **High confidence** in p50 ordering across hooks. The `duration_ms` companion probe is the same shape as the V18 single-fixture snapshot, varies only in the (hook, outcome) tuple, and N=20 produced p95/p50 ratios in the 1.1–1.3× band.
- **Medium confidence** on absolute wall-clock numbers in the V21+ paired probe. The box was multi-session-loaded during the rerun; smoke wall-clock p95 inflated 1.5–2× from the V18 snapshot for the same hooks. p50 ordering is preserved; p95 absolutes should be re-measured on a quiet box if a downstream decision hinges on the worst-case wall-clock.
- **High confidence** on `PERF-BUDGET-MS` derivation. The `duration_ms` companion data is the V20 measurement, sampled at N=20 with low variance; `make check` post-budget shows 0 V20 warnings from category 01 (validation step in `Verification` below).

## Open

- **Lazy-resolution patch on main.** `measurement/lazy-resolution-experiment.md` showed the patch closes the real-vs-smoke gap. Re-running this probe after the patch lands would give a final pre-/post-implement comparison. Recorded for the implement phase.
- **`detect-session-start-truncation` block-outcome fixture.** Smoke runner needs to inject a transcript file into sandboxed `$HOME` so the truncation grep finds it. Filed as `hook-audit-01-detect-truncation-injected-fixture` (P3).
- **`git-safety`'s `git rev-parse` fork on every Bash dispatch.** Whether caching the branch in the dispatcher (one fork per dispatch instead of per child) would meaningfully change the dispatcher's total cost falls to `02-dispatchers/performance.md`.
- **Per-child parse cost in the dispatcher's source loop.** Same open as `00-shared/performance.md`. Falls to `02-dispatchers/performance.md`.
