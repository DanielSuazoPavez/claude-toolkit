---
category: 02-dispatchers
axis: clarity
status: drafted
date: 2026-05-02
---

# 02-dispatchers — clarity

Code shape, naming, where logic lives. Like `01-standardized/clarity.md`, this axis is opinion-shaped — the goal isn't to prescribe a "right" structure but to evaluate the proposals queued by the other axes (inventory, performance, robustness, testability) and recommend keep / move / reshape.

## Proposals from other axes

Eight concrete proposals were flagged by upstream axes. Each is evaluated below against the per-dispatcher data the earlier axes collected.

### Proposal 1 — Add per-dispatcher `PERF-BUDGET-MS` headers (from performance)

**Background.** Both dispatchers warn on every `make check` because they inherit the framework default `scope_miss=5, scope_hit=50` (`validate.sh:592–596`). The 5ms `scope_miss` is structurally wrong for a hook whose floor is "loader + N children" — `02-dispatchers/performance.md` measured smoke p50 of 130ms (bash) / 61ms (read), with p95 of 204ms / 74ms.

The fix: add a `# CC-HOOK: PERF-BUDGET-MS: scope_miss=<X>, scope_hit=<Y>` line to each dispatcher's header block, grounded in N=30 measurement.

Recommended numbers (from `02-dispatchers/performance.md` § "What this means for the implement phase"):

| Dispatcher | smoke p95 | real p95 | Recommended `scope_miss` | Recommended `scope_hit` |
|------------|----------:|---------:|-------------------------:|------------------------:|
| `grouped-bash-guard` | 204 | 254 | **150** | **220** |
| `grouped-read-guard` | 74 | 104 | **75** | **120** |

**Pros:**
- One header line per dispatcher. Cheapest possible fix.
- Stops V20 false-positives without hiding regressions: a +20% drift in either dispatcher would still warn at the new threshold.
- Numbers are backed by N=30 measurement, not eyeballed.
- The pattern matches how V20 handles other slow hooks (`session-start`, `surface-lessons` already declare per-hook budgets via the same header — see `01-standardized/performance.md`'s V20 column).

**Cons:**
- Encodes "this hook is structurally slower than the default" into the codebase. That's a true statement, not a smell, but operators reading the header for the first time may want a one-line explanation. Mitigated by adding a brief comment alongside the budget.

**Cross-axis impact:**
- Performance: directly removes the false-positive warnings on every `make check`. No runtime cost.
- Robustness, testability: zero impact.

**Recommendation: do.** Backed by data, single-line header change, removes recurring noise. Already captured as `hook-audit-02-perf-budget-headers` (P1) — clarity confirms the numbers without modification.

### Proposal 2 — Source children at session start instead of dispatch time (from inventory + performance)

**Background.** Today the dispatcher sources every child file inside the per-event bash process (see `lib/dispatcher-grouped-bash-guard.sh` lines 17–28: `for spec in "${CHECK_SPECS[@]}"; do source "$src"; done`). Per-child source cost from `02-dispatchers/performance.md`: **~52ms** for the 8-child bash dispatcher, **~22ms** for the 2-child read dispatcher. Per fork.

Move this loop to a once-per-session lib load — children get sourced when Claude starts, the dispatcher's per-event work shrinks to "iterate `CHECKS`, call `match_<name>` / `check_<name>`, log substeps, exit."

**Pros:**
- **Largest single perf win available to dispatchers.** ~52ms saved per Bash dispatch, ~22ms per Read dispatch. Sessions fire many Bash events; cumulative save is substantial.
- The children's `match_<name>` / `check_<name>` functions are pure-bash and stateless — sourcing them once per process is semantically equivalent to per-event re-sourcing.
- Aligns dispatchers with how the registry works today (`detection-registry.sh` is already loaded once per process via `_DETECTION_REGISTRY_SOURCED` guard).

**Cons (the load-bearing ones):**
- **Loses the file-level distribution tolerance.** Today's `[ -f "$src" ] || continue` branch in the dispatcher's per-event loop silently skips children that aren't shipped in the current distribution (raiz ships without `enforce-make-commands.sh` / `enforce-uv-run.sh`; the bash dispatcher just runs the 6 children that exist). Moving the source loop to session-start means the missing-file probe also moves to session-start — survivable, but it changes when the absence is detected from "every event" to "once per session start." Re-sync mid-session would need a session restart to pick up new children.
- **Breaks the per-fork freshness assumption.** Today, if a hook author edits `block-dangerous-commands.sh` and saves, the next Bash event picks up the new code automatically (because `source` re-parses on every fork). With session-start sourcing, the cached function definitions persist for the whole session — the author has to restart Claude (or the harness) to see changes. Not a production concern, but a developer-experience regression.
- **Forces a session-start hook dependency.** The session-start hook becomes responsible for loading the dispatcher children. If session-start fails or is misconfigured, dispatchers run with empty `CHECKS` arrays — silent fail-open, the worst possible failure mode for a safety dispatcher. Mitigation: make dispatcher fall back to per-event sourcing if `CHECKS` is empty. Adds complexity, partially negates the perf win on the recovery path.
- **Increases session-start cost.** Today `session-start` runs in ~50–80ms; adding ~52ms of bash-children parse + ~22ms of read-children parse pushes it past 150ms. The session-start hook is already on V20's warn list (per CLAUDE.md `make check` notes); piling more work on it makes that warning worse, not better.

**Cross-axis impact:**
- Performance: ~52ms / Bash dispatch saved + ~22ms / Read dispatch saved (on the hot path). ~74ms one-time cost shifted to session-start.
- Robustness: distribution tolerance shifts from per-event to per-session; mid-session edits don't pick up. Both are real regressions.
- Testability: tests today fork a fresh bash per case — they wouldn't benefit from session-start sourcing because the sourcing happens before the test even forks. The save accrues to *production*, not to *test wall*.

**Verdict: defer.** The save is real and large, but the costs touch three load-bearing properties (distribution tolerance, dev-loop freshness, session-start budget) and the most painful failure mode (empty `CHECKS` = silent fail-open) is the kind of thing that gets caught by an outage, not a test. A safer staging path: first land the substep-batching from Proposal 6 below (saves ~35ms on real-mode bash-dispatcher runs without touching the source loop), measure the resulting dispatcher cost, *then* revisit whether session-start sourcing is still worth the trade.

Recorded as a future design proposal — `hook-audit-02-session-start-source` (P3, idea) — gated on substep batching landing first. Not added to BACKLOG immediately because a P3-idea item with a "blocked on P2" dependency adds noise; will reopen after Proposal 6 lands and dispatcher cost is re-measured.

### Proposal 3 — Cache `git rev-parse` across dispatcher children (from performance)

**Background.** `git-safety.sh` is the only standardized hook that calls `git rev-parse` (one fork). When it's a child of `grouped-bash-guard`, `match_git_safety` runs cheaply (pure-bash regex on `$COMMAND`); `check_git_safety` runs only when `match_` returns true (the command starts with `git ...`). One `git rev-parse` fork per Bash dispatch on a `git ...` command.

Caching the branch in a dispatcher-level global would save ~5ms on git-shaped Bash dispatches.

**Pros:**
- Save is real (~5ms per git-shaped Bash dispatch).
- Implementation is small: a `_GIT_BRANCH_CACHED=""` global, set on first `check_git_safety` call.

**Cons:**
- **Save is small × frequency-of-git-Bash-commands.** Per `02-dispatchers/performance.md`, `git-safety`'s block-fixture cost is ~26ms — and the `git rev-parse` is ~5ms of that. The hook isn't the long pole; the dispatcher isn't held back by it.
- **Cache invalidation is non-trivial.** `git rev-parse`'s output depends on `cwd`. The model can `cd` between dispatch and check; the dispatcher process is short-lived (one bash process per Bash event), so cache lifetime is one event — but within that event, multiple children running `git rev-parse` from different `cwd`s would race against the cached branch. Today only `git_safety` calls `git rev-parse`; the cache is "safe" only because there's exactly one consumer.
- **Optimization for a hypothetical.** If/when a second hook needs branch info, the cache becomes meaningful. Today it's optimizing the only consumer of the only callsite.

**Cross-axis impact:**
- Performance: ~5ms × frequency-of-git-Bash-commands. Small.
- Robustness: cache-invalidation semantics need careful thought (cwd changes mid-process); easy to introduce a bug here.
- Testability: caching adds a new "cached vs cold" branch to test. Net negative.

**Verdict: defer.** Save is real but small; cost is non-trivial. Reopen if `git rev-parse` ever dominates dispatcher cost. Already captured as `hook-audit-02-git-rev-parse-caching` (P3); clarity confirms the defer call.

### Proposal 4 — Formalize the `_BLOCK_REASON` mutation contract (from robustness + testability)

**Background.** The dispatcher's contract: a child's `check_<name>` function returns rc=1 ⇒ that child has written `_BLOCK_REASON`. The dispatcher reads `_BLOCK_REASON` after the loop ends and emits `hook_block "$_BLOCK_REASON"`. Per `02-dispatchers/robustness.md`'s audit, all 10 current children comply. But the contract is **convention, not enforced** — T18 verified that a child returning rc=1 without setting `_BLOCK_REASON` produces `{"decision":"block","reason":""}` (a block with an empty reason).

`relevant-toolkit-hooks.md` §4 documents the `match_*` / `check_*` pair semantics; it does NOT explicitly state the `rc=1 ⇒ _BLOCK_REASON set` invariant.

Two-pronged hardening proposed in robustness:

a. **Dispatcher-side runtime fallback.** After `check_$name` returns 1, assert `[ -n "$_BLOCK_REASON" ] || _BLOCK_REASON="(child '$name' returned block but did not set _BLOCK_REASON — bug in $name)"`. ~3 LoC per dispatcher.
b. **Validator-side static check.** For every dual-mode hook with `DISPATCH-FN`, grep `check_<name>` body for `_BLOCK_REASON=` near every `return 1`. Fails CI if missing.

**Pros of formalizing in doc + enforcing both ways:**
- The contract is real and load-bearing — every dispatcher relies on it. Documenting it explicitly costs one paragraph.
- Two-layer enforcement covers both runtime (operator gets an actionable diagnostic instead of empty reason) and authoring time (CI catches the violation before it ships).
- Pairs naturally with the `match_*` / `check_*` superset invariant from `01-standardized/clarity.md` Proposal 1 — both are cases where a documented convention should become enforced.

**Cons:**
- The runtime fallback (option a) is dead code in the happy path — every check today writes `_BLOCK_REASON` correctly. Adds ~3 LoC per dispatcher that never fires in production.
- The validator-side check (option b) requires a new pattern in `validate-hook-headers.sh` (or a sibling validator). ~30–50 LoC.

**Cross-axis impact:**
- Robustness: directly closes T18. Future child writers can't ship the empty-reason defect.
- Testability: enables the runtime regression test from `02-dispatchers/testability.md` recommendation #3 — the test asserts the fallback message fires when `_BLOCK_REASON` is empty. Without option (a), there's nothing to test.
- Performance: zero impact (the fallback fires only on the rare-and-buggy block path; the validator runs at `make validate` time, not in production).

**Recommendation: do both, formalize in the doc.**

- Update `relevant-toolkit-hooks.md` §4 (or §8 "Dispatcher Internals") to state the invariant: *"a child's `check_<name>` returns rc=1 ⇒ that child has set `_BLOCK_REASON` to a non-empty string. The dispatcher emits the value via `hook_block`. Returning rc=1 with an empty `_BLOCK_REASON` is a bug."*
- Land both the runtime fallback (option a) and the static check (option b). The runtime fallback gives operator diagnostics if the static check ever misses; the static check prevents the ship.

This is the highest-leverage clarity recommendation in the category — it converts a documented-by-existing-behavior convention into a doc + enforced contract and closes a real defect class.

Already captured as `hook-audit-02-block-reason-contract` (P2). Clarity adds: also update `relevant-toolkit-hooks.md` to formalize the invariant. The doc update is small (~1 paragraph) and should ride along with the validator/dispatcher patches.

### Proposal 5 — Symmetric early-bail between dispatchers (from robustness)

**Background.** `grouped-bash-guard.sh` has an explicit `[ -z "$COMMAND" ] && exit 0` at line 68 (after `hook_get_input '.tool_input.command'`). `grouped-read-guard.sh` does NOT have a corresponding `[ -z "$FILE_PATH" ] && exit 0`. Both are correct end-to-end today (each Read child's `match_*` returns false on empty `$FILE_PATH`, so the dispatch loop emits `not_applicable` and exits clean), but the asymmetry means a future Read child added that doesn't handle empty `$FILE_PATH` would inherit a different contract than its Bash sibling.

**Options:**
1. Add `[ -z "$FILE_PATH" ] && exit 0` to `grouped-read-guard.sh` for symmetry.
2. Remove the `[ -z "$COMMAND" ] && exit 0` from `grouped-bash-guard.sh` — let bash children handle empty `$COMMAND` themselves.
3. Keep as-is, document the asymmetry.

**Pros of option 1:**
- Symmetric dispatchers. Easier to read both files side-by-side.
- Future-proofs against children that don't handle empty input.

**Cons of option 1:**
- The bash early-bail exists because `match_dangerous` (and several others) explicitly assume `$COMMAND` is non-empty for their regex matches. The Read children all explicitly handle empty `$FILE_PATH` (verified in robustness audit). Adding the early-bail to read is "fixing" something that isn't broken.
- One more line to maintain across the two dispatchers. Marginal but real.

**Pros of option 2:**
- Pushes empty-input handling into children where it belongs (each child knows what its match needs). One source of truth.

**Cons of option 2:**
- Risk: forgetting to handle empty in even one bash child = a child running on `$COMMAND=""` and producing undefined behavior. The early-bail is a backstop.

**Cross-axis impact:** all options are low-impact functionally. Pure clarity question.

**Recommendation: option 3 — keep as-is, add a one-line comment in `grouped-read-guard.sh`** explaining why no `[ -z "$FILE_PATH" ]` early-bail (because all current Read children handle empty `$FILE_PATH` in their `match_*` predicates, and the dispatch loop's `not_applicable` accumulation is the right shape).

Cost: ~2 lines of comment. Locks in the deliberate-asymmetry decision so a future "consistency pass" doesn't add the bail without thinking.

### Proposal 6 — Substep-logging fork count (from performance)

**Background.** `grouped-bash-guard` pays 8 `hook_log_substep` jq forks per dispatch when traceability is on. ~5ms each = ~40ms of the +67ms real−smoke gap. The output schema today: one `kind:"substep"` row per substep, written immediately at each `hook_log_substep` call.

**Constraint (firm): the per-substep row schema does not change.** Collapsing 8 substep rows into one dispatch row with a nested `substeps` array would break any downstream consumer that walks the JSONL expecting one row per substep. The output stays one row per substep.

**The compression that fits the constraint:** buffer substep tuples in bash arrays during the dispatcher loop; emit *all* substep rows via one `jq -c -n --argjson rows '[…]'` at the EXIT trap. Same N rows in the JSONL output; one jq fork instead of N.

Concrete shape:

```bash
# In dispatcher loop (replaces direct hook_log_substep call):
_SUBSTEP_NAMES+=("$check_fn")
_SUBSTEP_DURATIONS+=("$dur")
_SUBSTEP_OUTCOMES+=("pass")  # or "block" / "skipped" / "not_applicable"
_SUBSTEP_BYTES+=(0)

# In hook-logging.sh's EXIT trap path (or a new flush function called by it):
hook_feature_enabled traceability || return 0
local rows_json
rows_json=$(jq -c -n \
    --argjson names "$(printf '%s\n' "${_SUBSTEP_NAMES[@]}" | jq -R . | jq -s .)" \
    --argjson durations "$(printf '%s\n' "${_SUBSTEP_DURATIONS[@]}" | jq -s .)" \
    --argjson outcomes "$(printf '%s\n' "${_SUBSTEP_OUTCOMES[@]}" | jq -R . | jq -s .)" \
    --argjson bytes "$(printf '%s\n' "${_SUBSTEP_BYTES[@]}" | jq -s .)" \
    '[range(0; $names | length) | {kind:"substep", session_id:$session_id, …, section:$names[.], duration_ms:$durations[.], outcome:$outcomes[.], bytes_injected:$bytes[.], …}] | .[] | tostring' )
# Write all rows as a single append.
printf '%s\n' "$rows_json" >> "$invocations_file"
```

(The `printf '%s\n' | jq -s .` round-trips above are bash-level; they don't fork additional jq processes. The exact jq invocation can be tightened — the point is one jq invocation produces N JSONL lines, and one append writes them as a block.)

**Pros:**
- ~35ms saved on real-mode bash-dispatcher dispatches (8 forks → 1 fork).
- ~10ms saved on real-mode read-dispatcher dispatches (2 forks → 1 fork).
- **Schema unchanged.** Downstream consumers see the same N-rows-per-dispatch JSONL shape. No migration.
- Atomic block-write: today, an interrupted dispatcher could leave partial substep rows in the JSONL (rows for early substeps written, later substeps lost). The batched flush either writes all rows or none — cleaner failure mode for log consumers.

**Cons:**
- **Substep timestamps shift.** Today each row's `timestamp` field is `$_HOOK_TIMESTAMP` (set once at hook_init, same for all substeps in the same dispatch). Buffered, the field is still `$_HOOK_TIMESTAMP` — actually unchanged. Per-substep wall-clock ordering is preserved by `duration_ms` (a duration, not a timestamp), which is also unchanged. So this concern is *not* a real con; checked.
- **Buffer state lives in shell globals across the dispatcher loop.** Four arrays (`_SUBSTEP_*`) need to be initialized empty at hook_init time and cleared at the end of the EXIT-trap flush. Manageable, but new state.
- **EXIT-trap flush has to fire before `hook_block`'s exit path.** The EXIT trap already fires after `hook_block` (per `hook-utils.sh:_hook_log_timing`); appending substep flush there is the natural shape. Need to verify no path bypasses the EXIT trap.
- **Skipped-substep emission post-block needs to also buffer rather than direct-write.** The `if [ "$BLOCK_IDX" -ge 0 ]` block at the dispatcher bottom calls `hook_log_substep` directly for each skipped child — those calls also need to switch to buffer-append.

**Cross-axis impact:**
- Performance: ~35ms saved per real-mode bash dispatch + ~10ms per real-mode read dispatch. Same magnitude as the original "collapse to one row" option, achieved without the schema change.
- Robustness: cleaner partial-write failure mode (all-or-nothing flush). New state to manage; risk of forgetting to initialize/clear.
- Testability: tests that assert on substep rows (e.g. the proposed block-fall-out fixture from `testability.md`) work unchanged — same row count, same row shape. Net zero impact on test code.

**Verdict: do, with the buffer-then-flush shape.** The save is real and the constraint is met. Implementation requires care around the four bash array globals and the EXIT-trap ordering, but the user-facing JSONL shape is preserved.

Captured as `hook-audit-02-substep-batching` (P2 — already on backlog from performance axis). Clarity confirms the buffer-then-flush shape (NOT the schema-changing collapse-to-one-row variant) and adds the implementation notes above as the design constraint.

### Proposal 7 — File-absent vs functions-missing produce different traceability rows (from robustness + inventory)

**Background.** The generated dispatcher loop has two distribution-tolerance branches:

- File absent → `[ -f "$src" ] || continue` → silent skip, **no log signal**.
- File present, functions missing → `declare -F` guard fails → `hook_log_substep "check_${name}_missing_match_check" 0 "skipped" 0` → traceable.

The file-absent branch is silently undetectable from the JSONL row; only `make validate`'s drift detector can catch it.

**Options:**
1. Add symmetric "skipped (source_missing)" log emission to the file-absent branch.
2. Keep as-is.

**Pros of option 1:**
- Symmetric traceability. Any sync mishap (including file-deletion) is detectable from the JSONL row.
- Cheap implementation: 1 line in the generator (write a `hook_log_substep "check_${name}_source_missing" 0 "skipped" 0` before `continue`).

**Cons of option 1:**
- **Traceability noise on intentionally-thin distributions.** Raiz ships without `enforce-make` and `enforce-uv` — every Bash dispatch in raiz would write 2 extra `skipped` substep rows. Multiplied across many Bash events per session, that's nontrivial JSONL bloat.
- The `make validate` drift detector already catches sync mishaps at build time. The JSONL signal would be redundant for the production-bug case (already caught by validate) and just noisy for the intentional-distribution-trim case (raiz).

**Cross-axis impact:**
- Robustness: small win (covers the sync-mishap case the validator might somehow miss). Marginal.
- Performance: 2 extra `hook_log_substep` calls per dispatch in raiz = ~10ms (real mode) or ~0ms (smoke, gated). Real but small.
- Testability: would need a new test asserting the source-missing substep fires in raiz-sim. Already covered by the existing distribution-tolerance test's structure.

**Recommendation: keep as-is.** The asymmetry is intentional: file-absent is the *expected* state for some distributions; functions-missing is the *unexpected* state (file present but broken). Logging the unexpected state is right; logging the expected state is noise. The `make validate` drift detector is the right layer for catching unexpected file absence — runtime traceability would be redundant.

Add a one-line comment in the generator (`scripts/hook-framework/render-dispatcher.sh`) explaining why the file-absent branch doesn't log: *"file absence is expected for distribution-trimmed deployments (e.g. raiz); functions-missing is unexpected and gets a substep row."* Cost: ~2 lines.

### Proposal 8 — Extract dispatcher entrypoint seams as testable functions (from testability)

**Background.** `02-dispatchers/testability.md` recommends per-seam Shape A as a deferred follow-up: extract three pieces of the entrypoint (block-fall-out logic, `_BLOCK_REASON` fallback, distribution-tolerance loop) into named callable functions. Today the dispatcher entrypoint runs everything top-level — readable as a script, but each phase is undirectly testable except via end-to-end fork.

**Pros:**
- Enables Shape A testing of the three seams (~0ms per case vs ~130ms per fork).
- Makes the dispatcher's structure self-documenting: phase names become function names.

**Cons:**
- ~50 LoC of refactor across both dispatcher entrypoints.
- The top-level shape is currently very readable: `hook_init` → `hook_get_input` → `source ...lib/dispatcher-...` → driver loop → fall-out emit. Splitting into named functions is more navigable for testing but slightly less linear to read.
- Survives `make hooks-render`: the generated `lib/dispatcher-grouped-*.sh` would need to be aware of (or unaware of) the entrypoint refactor. Likely unaware (the lib only generates `CHECK_SPECS` and the source loop), but the boundary needs care.
- The proposed Shape B fixtures from testability §1–§5 (block-fall-out, precedence, `_BLOCK_REASON`-empty, `_missing_match_check`) close the immediate coverage gaps **without** the refactor. The Shape A path is a *future* optimization for test wall, not for coverage.

**Cross-axis impact:**
- Testability: enables Shape A — but Shape B fixtures already in the works close the gaps. Net: faster tests, not better tests.
- Performance: zero impact on production (function call overhead is negligible vs the work done).
- Robustness: refactor is a regression risk against a hot-path script. Mitigated by tests, but real.

**Recommendation: defer.** The Shape B fixtures from `02-dispatchers/testability.md` give the regression coverage; the per-seam refactor optimizes test wall but not test power. Reopen if dispatcher test wall ever becomes the slowest-file in `make test` (today it's ~1s — far from the ~20s ceiling). Already captured as testability recommendation #5.

## Other clarity findings (not surfaced by other axes)

### The raiz-sim helper is duplicated across both dispatcher test files

`02-dispatchers/testability.md` cross-cutting finding #2 noted this. The pattern in both `test-grouped-bash.sh` and `test-grouped-read.sh`:

```bash
sim_dir=$(mktemp -d)
cp -r "$HOOKS_DIR"/. "$sim_dir/"
rm -f "$sim_dir/<children>"
prev_hooks_dir="$HOOKS_DIR"
HOOKS_DIR="$sim_dir"
# ... batch_run ...
HOOKS_DIR="$prev_hooks_dir"
rm -rf "$sim_dir"
```

~10 LoC duplicated. Could move to `tests/lib/hook-test-setup.sh` as `with_simulated_distribution() { ... }`.

**Pros:**
- DRY. New dispatchers (if any emerge) get the helper for free.
- The helper would be the documented way to test distribution tolerance.

**Cons:**
- Two callsites isn't "duplication enough to extract" by most pragmatic measures. Three would be.
- The current pattern is fully visible in the test file — readers don't need to look up the helper to understand what's happening.
- Bash helpers with stateful `prev_*` save/restore are easy to get wrong (forgetting to restore on test failure leaves `HOOKS_DIR` pointing at a deleted directory). The current open-coded pattern is auditable.

**Recommendation: keep as-is for now.** Two callsites isn't a strong enough signal. If a third dispatcher (e.g. `grouped-permission-request-guard` flagged speculatively in `01-standardized/clarity.md` Proposal 2) ever lands, extract then.

### Dispatcher entrypoint header comment bloat

Comment-density audit on the four dispatcher files (this session, `wc -l` + `grep -c '^[[:space:]]*#'`):

| File | Total LoC | Comments | Code | Comment % |
|------|----------:|---------:|-----:|----------:|
| `grouped-bash-guard.sh` | 117 | 67 | 39 | **57%** |
| `grouped-read-guard.sh` | 89 | 42 | 37 | **47%** |
| `lib/dispatcher-grouped-bash-guard.sh` (generated) | 31 | 7 | 24 | 22% |
| `lib/dispatcher-grouped-read-guard.sh` (generated) | 25 | 7 | 18 | 28% |

The standardized hooks for comparison sit around 25–35% comment ratio. The two dispatcher entrypoints are well above that band. Inspection shows three categories of bloat:

**1. Inline `Current checks` enumeration** (`grouped-bash-guard.sh:16-35` = 20 lines; `grouped-read-guard.sh:16-21` = 6 lines).

A hand-maintained shadow of `dispatch-order.json` + each child's CC-HOOK headers. The block has paraphrased descriptions of what each child does ("blocks rm -rf /, fork bombs, mkfs, dd to disk, sudo, etc."), which duplicates each child file's own `CC-HOOK: PURPOSE:` header. Drift risk is real — adding/removing/reordering a child requires updating both the JSON file and the comment block. The block also rots: the bash-guard header still says "git_safety next (cheap real match)" in line 80 even though `git_safety` is now position 4, not 2 — already out of sync with the actual `dispatch-order.json` ordering.

**2. Substep-outcome enumeration** (`grouped-bash-guard.sh:41-45` = 5 lines).

Documented authoritatively in `relevant-toolkit-hooks.md §5`. Inline duplication.

**3. Dispatcher-loop ordering banner** (`grouped-bash-guard.sh:78-81` = 4 lines).

Says "CHECKS order follows CHECK_SPECS: dangerous first..." — a paraphrase of #1 (which is itself a paraphrase of `dispatch-order.json`).

**Options:**

1. **Delete categories 1, 2, 3; replace with one-line pointers** to `dispatch-order.json` and `relevant-toolkit-hooks.md §5`. Drops ~30 LoC from `grouped-bash-guard.sh` (117 → ~87) and ~10 from `grouped-read-guard.sh` (89 → ~79). Comment ratio falls into the standardized band (~30–35%).
2. **Keep as-is, add a render-time validator** that checks the `Current checks:` block against `dispatch-order.json` and fails CI on drift.
3. **Generate the comment block** from `dispatch-order.json` + child headers via the same generator that produces `lib/dispatcher-grouped-*-guard.sh`.

**Pros of option 1:**
- Removes the duplication entirely. No drift surface to validate or generate.
- Each child's own `CC-HOOK: PURPOSE:` header is the canonical "what does this do" — the dispatcher header pointing to it is enough.
- Aligns with the "hooks used to have lots of commented lines, we have been moving those out" direction the rest of the hook set has been trending.
- Cheap: pure deletion + ~3 lines of pointer comment per dispatcher.

**Cons of option 1:**
- A reader skimming `grouped-bash-guard.sh` no longer sees the child list inline — they have to open `dispatch-order.json` to know what fires. Mitigation: the pointer comment names the file; one extra file-open is the cost.
- The "see `relevant-toolkit-hooks.md §5`" pointer for substep outcomes is one extra hop for a reader debugging a specific outcome string. Minor.

**Pros of option 2:** keeps inline doc readable without manual sync risk.

**Cons of option 2:** ~30 LoC of new validator code (parse the comment block, compare to JSON), permanent test surface to maintain, AND the comment bloat stays. Locks in the wrong shape with infrastructure.

**Pros of option 3:** single source of truth, auto-synced.

**Cons of option 3:** generator now patches two files instead of one. Descriptive prose ("blocks rm -rf /, fork bombs, mkfs, dd, sudo") can't be auto-generated without putting prose into `dispatch-order.json` too — schema creep.

**Recommendation: option 1 — delete the bloat, point at canonical sources.**

This supersedes the earlier "add a render-time drift check for the comment block" idea (`hook-audit-02-header-drift-check` from an earlier draft of this doc): there's no point validating a comment block that shouldn't exist. The right answer is to delete the block and let the existing `make hooks-render` drift check on the *generated lib file* be the only sync surface.

What stays in the entrypoint header:

- The `CC-HOOK:` headers (lines 1-6) — load-bearing, parsed by the framework.
- A 1-2 line "what this is" summary + a pointer to `dispatch-order.json` for the child list and `relevant-toolkit-hooks.md §4` for the dispatch contract.
- The "Dispatcher contract — each check_* function returns: 0 = pass / 1 = block (sets _BLOCK_REASON)" line. Load-bearing for child authors; condense to 2-3 lines.
- The `[ -z "$COMMAND" ]` reasoning + the `PERMISSION_MODE` parsing comment — both explain non-obvious decisions. Keep.
- The `# CHECK_SPECS + sourcing loop are generated...` comment — load-bearing for anyone trying to edit the script. Keep.

What goes:

- `grouped-bash-guard.sh:16-35` (Current checks enumeration) — delete.
- `grouped-bash-guard.sh:41-45` (substep outcomes) — delete; one-line pointer to `relevant-toolkit-hooks.md §5`.
- `grouped-bash-guard.sh:47-50` (where sourced hooks register standalone) — delete; same info is in each child's `CC-HOOK: EVENTS:` header.
- `grouped-bash-guard.sh:78-81` (CHECKS order paraphrase) — delete.
- `grouped-read-guard.sh:16-21` (Current checks) — delete.
- `grouped-read-guard.sh:23-24` (security-check-runs-first prose) — delete; the ordering rationale lives in `dispatch-order.json` if it needs to live anywhere.

**Cross-axis impact:**
- Performance: zero (comments don't affect runtime; bash skips them at parse time).
- Robustness: marginal positive — removes a doc-vs-code drift surface that the audit *already found* drifted (line 80 paraphrase out of sync with the real CHECK_SPECS ordering).
- Testability: zero.

Captured as `hook-audit-02-trim-dispatcher-comments` (P3). Supersedes `hook-audit-02-header-drift-check` (which gets removed — see Backlog tasks section below).

### Substep outcome vocabulary is documented but not enumerated in code

The dispatcher's substep outcomes are `pass | block | not_applicable | skipped`. Documented in `relevant-toolkit-hooks.md` §5 and in the entrypoint header. In code, they're string literals at four callsites in each dispatcher (e.g. `hook_log_substep "check_${name}" "$dur" "block" 0`). A typo (e.g. `"blocked"` instead of `"block"`) wouldn't fail any test today.

**Options:**
1. Define `_OUTCOME_PASS="pass"` etc. constants in `hook-utils.sh`. Use them in dispatchers.
2. Keep string literals.

**Pros of option 1:**
- Typo-proof.
- Single source of truth for the vocabulary.

**Cons of option 1:**
- The four outcome strings are short, well-known, and used in exactly two files (the two dispatcher entrypoints). Extracting them to constants is over-abstraction for this scale.
- `relevant-toolkit-hooks.md` §5 already documents the vocabulary. Anyone touching the dispatchers should be reading that.

**Recommendation: keep as-is.** Two files × four sites = 8 callsites. Not enough mass to abstract. Document-only enforcement is right at this scale.

## What clarity recommends

**Do (high leverage):**

1. **Add per-dispatcher `PERF-BUDGET-MS` headers** (Proposal 1). Numbers: bash `scope_miss=150, scope_hit=220`; read `scope_miss=75, scope_hit=120`. Removes recurring V20 false-positives. Already on backlog as P1.
2. **Formalize the `_BLOCK_REASON` mutation contract** (Proposal 4). Update `relevant-toolkit-hooks.md` §4 (or §8) with the explicit invariant. Land the runtime fallback (option a) AND the validator-side static check (option b). Highest-leverage call in the category — converts a doc convention into enforcement and closes T18.
3. **Land substep buffer-then-flush** (Proposal 6). Buffer substep tuples in bash arrays during the dispatcher loop; emit all rows via one `jq` invocation at the EXIT trap. **Schema unchanged** — same N rows per dispatch in the JSONL output, just one fork instead of N. ~35ms save per real-mode bash dispatch + ~10ms per read dispatch.

**Do (small, opportunistic):**

4. **Add a one-line comment to `grouped-read-guard.sh`** explaining the deliberate absence of `[ -z "$FILE_PATH" ]` early-bail (Proposal 5). ~2 lines.
5. **Add a one-line comment to `render-dispatcher.sh`** explaining why the file-absent branch doesn't log a substep (Proposal 7). ~2 lines.
6. **Trim dispatcher entrypoint comment bloat** (other clarity finding "Dispatcher entrypoint header comment bloat"). Delete the inline Children enumeration, substep-outcome list, and ordering paraphrase from `grouped-bash-guard.sh` / `grouped-read-guard.sh`; replace with one-line pointers to `dispatch-order.json` and `relevant-toolkit-hooks.md`. Drops `grouped-bash-guard.sh` from 117 → ~87 LoC, comment ratio 57% → ~30%. Removes a real drift surface (the existing comment is already out of sync with `dispatch-order.json` ordering). Pure deletion + ~3 lines per file.

**Don't:**

1. Move the source-children loop to session-start (Proposal 2). The save is real but the costs touch distribution tolerance, dev-loop freshness, and session-start budget. Defer; revisit after substep batching lands and dispatcher cost is re-measured.
2. Cache `git rev-parse` (Proposal 3). Save is small, cache invalidation is non-trivial.
3. Add symmetric `[ -z "$FILE_PATH" ]` early-bail to the read dispatcher (Proposal 5). Asymmetry is deliberate; comment instead.
4. Add file-absent traceability rows (Proposal 7). Noise on intentional-distribution-trim outweighs the redundant signal for sync mishaps.
5. Extract dispatcher entrypoint seams as functions (Proposal 8). Shape B fixtures close the coverage gaps without the refactor. Defer.
6. Extract the raiz-sim helper to `tests/lib/hook-test-setup.sh`. Two callsites isn't enough mass; revisit if a third dispatcher emerges.
7. Extract substep outcome strings to constants. Two files × four sites = not enough mass.

**Defer to other axes / future work:**

- Session-start sourcing (Proposal 2). Reopen after substep batching lands.
- Dispatcher entrypoint Shape A refactor (Proposal 8). Reopen if dispatcher tests become the slowest file.
- Raiz-sim helper extraction. Reopen if a third dispatcher is added.

## Confidence

- **High confidence** in Proposal 1 (PERF-BUDGET-MS headers). Numbers backed by N=30 measurement.
- **High confidence** in Proposal 4 (formalize `_BLOCK_REASON` contract). The defect is real (T18), all current children comply, the fix has two layers, and the doc gap is genuine.
- **High confidence** in Proposal 6 (substep buffer-then-flush). The save is real and well-measured; the schema-preserving shape sidesteps the consumer-migration risk entirely. Implementation requires care (four bash array globals, EXIT-trap ordering, post-block skipped-row buffering) but the design is straightforward.
- **High confidence** in the keep-as-is recommendations (Proposals 2, 3, 5, 7, 8). Each has a concrete reason grounded in the data the other axes collected.
- **High confidence** on the comment-bloat trim (other clarity finding). The drift is already empirically verified (line 80 paraphrase out of sync with current ordering); the trim is pure deletion + pointer; the resulting comment ratio matches the rest of the hook set. Supersedes the earlier "add a render-time validator" idea — there's no point validating a comment block that should be deleted.

## Backlog tasks added

Two new items + one removal:

- `hook-audit-02-clarity-comments` (P3) — small comment additions: one-line explanation in `grouped-read-guard.sh` for missing `[ -z "$FILE_PATH" ]`; one-line explanation in `render-dispatcher.sh` for file-absent branch not logging. Two ~2-line patches.
- `hook-audit-02-trim-dispatcher-comments` (P3) — delete inline Children enumeration, substep-outcome list, and ordering paraphrases from `grouped-bash-guard.sh` / `grouped-read-guard.sh`; replace with one-line pointers. ~30 LoC removed from bash dispatcher, ~10 from read dispatcher. Drift surface eliminated.
- **Removed (superseded):** `hook-audit-02-header-drift-check` — the trim above eliminates the comment block entirely, so there's nothing left to validate against `dispatch-order.json` at the comment level. The existing `make hooks-render` drift check on the *generated lib file* remains the only sync surface needed.

Existing items confirmed (not duplicated):

- `hook-audit-02-perf-budget-headers` (P1) — Proposal 1.
- `hook-audit-02-block-reason-contract` (P2) — Proposal 4 (clarity adds: also update `relevant-toolkit-hooks.md` §4/§8 with the invariant; do this in the same PR as the validator/dispatcher patches).
- `hook-audit-02-substep-batching` (P2) — Proposal 6 (clarity adds: implement as buffer-then-flush at EXIT trap; schema MUST stay one row per substep; collapse-to-one-row variant explicitly rejected).
- `hook-audit-02-git-rev-parse-caching` (P3) — Proposal 3 confirmed deferred.
- `hook-audit-02-source-guarded-cost` (P3) — separate, from performance.
- `hook-audit-02-child-source-rc` (P3) — separate, from robustness.

## Open

- **The session-start sourcing question (Proposal 2) is real and large.** Recorded as deferred-pending-substep-batching but not added to backlog as an item. If after Proposal 6 lands the dispatcher real-mode cost is still the long pole, reopen and design the session-start migration carefully (especially the empty-`CHECKS` fail-open guard).
- **Whether Proposal 4's doc update should land as part of `hook-audit-02-block-reason-contract` or as a standalone PR.** Editorial; doesn't change the work.
- **EXIT-trap ordering for substep flush (Proposal 6).** The substep buffer-then-flush has to fire from the EXIT trap path that today emits `_hook_log_timing`. Need to confirm no dispatcher path (e.g. an early `exit 0` from `[ -z "$COMMAND" ]`) bypasses the trap before the buffer is initialized. Falls to the implementation-pass owner.
