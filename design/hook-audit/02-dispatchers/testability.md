---
category: 02-dispatchers
axis: testability
status: drafted
date: 2026-05-02
---

# 02-dispatchers — testability

How testable are the two dispatchers today, what shapes do existing tests take, and where are the coverage gaps. Reuses the **Shape A / Shape B** distinction established in `00-shared/testability.md` and re-applied in `01-standardized/testability.md`:

- **Shape A** — in-process: source the dispatcher's libs, call functions, assert. ~0ms per case. Used today only for lib-level tests.
- **Shape B** — subprocess fork: write stdin to a file, fork a fresh `bash <dispatcher>.sh`, assert on the captured stdout. ~130ms per case for `grouped-bash-guard` (per `02-dispatchers/performance.md` smoke p50), ~61ms for `grouped-read-guard`.

Dispatcher Shape B forks are **3–5× more expensive per case than standardized hooks** (~25ms standardized smoke median vs ~130ms / ~61ms here). The case count is also naturally larger (M command shapes × N children worth of branches), so per-fixture fork cost dominates dispatcher test wall faster than for any standardized hook.

## Coverage today

Per-dispatcher test files in `tests/hooks/test-grouped-{bash,read}.sh` (Shape B) plus the V18-minimum smoke fixture in `tests/hooks/fixtures/<dispatcher>/`. Counts from `grep -cE "(batch_add|expect_)"`:

| Dispatcher | Test cases (Shape B) | Smoke fixtures | Wall (s, parallel) |
|------------|---------------------:|---------------:|-------------------:|
| `grouped-bash-guard` | 7 | 1 | ~1.0 |
| `grouped-read-guard` | 11 | 1 | ~1.4 |

Total: **18 cases across both dispatchers**, both files measured live this session by inspection of `tests/hooks/test-grouped-{bash,read}.sh` line counts (72 and 75 LoC respectively, mostly setup + assertions).

What the existing cases cover:

**`test-grouped-bash.sh` (7 cases, two scenes):**
- Base scene (5 cases): `ls` passes silently, `pytest` blocks via `make` guard, credential-shaped curl blocks via `credential_exfil`, two precedence cases proving `credential_exfil` wins over `git_safety` on a force-push that contains an embedded credential.
- Raiz-sim scene (2 cases): `cp -r $HOOKS_DIR /tmp/sim`, `rm enforce-{make,uv}-*.sh`, point `HOOKS_DIR` at the sim directory, re-run with `pytest` (now passes — no make guard) and a `git push --force` (still blocks — git_safety still loaded). Locks in distribution tolerance.

**`test-grouped-read.sh` (11 cases, two scenes):**
- Base scene (9 cases): `secrets_guard_read` blocks/allows on `.env`, `.env.example`, SSH private/public keys; `suggest_read_json` allows allowlisted (`package.json`), blocks unknown / large `.json`, allows small `.json`; one wrong-tool routing case (`Grep` passes through).
- Raiz-sim scene (2 cases): drop `suggest-read-json.sh`, verify `secrets_guard_read` still blocks `.env` and large `.json` now passes (suggest absent).

The two test files **are well-shaped for what they test** — each pairs a "full distribution" scene with a "raiz-style trimmed distribution" scene, mirroring the dispatcher's two real production targets. The case count is small because the per-child decision logic is tested by the standardized hooks themselves (`tests/hooks/test-block-dangerous.sh` has 28 cases, `test-secrets-guard.sh` has 73, etc.). The dispatcher tests' job is to verify **dispatch behavior**: order, fall-through, distribution tolerance, child-result aggregation.

## Coverage gaps

Five gaps stand out, ordered by defensibility:

### 1. Block-fall-out is untested

The dispatcher's contract: when child *i* blocks, every child *j > i* gets a `skipped` substep recorded. Verified empirically in `02-dispatchers/robustness.md` (T19), but no test fixture asserts the JSONL row contains the right `skipped` count. A regression in `grouped-bash-guard.sh:108–114` (the post-block fall-out loop) would silently drop the skipped substeps without any test failing.

Fixable in Shape B: add a fixture where `child #1` blocks (`rm -rf /` triggers `dangerous`), capture the JSONL row from `$TEST_INVOCATIONS_JSONL`, assert `substeps | length == 8` and `substeps[1..7] | map(.outcome) == ["skipped" × 7]`.

Cost: ~1 fixture + ~1 assertion. Per-case fork cost is ~130ms; one or two cases doesn't move the wall meaningfully.

### 2. Empty `_BLOCK_REASON` defect (T18) is not regression-locked

`02-dispatchers/robustness.md` T18 found that a child returning rc=1 without setting `_BLOCK_REASON` produces `{"decision":"block","reason":""}` — a block with empty reason. All current children comply with the contract, but no test asserts the dispatcher's behavior under contract violation.

Two test shapes available:

- **Shape B regression fixture.** Stage a temp `HOOKS_DIR` (mirroring the raiz-sim pattern already used) where one child has been rewritten to return 1 without writing `_BLOCK_REASON`. Assert the JSONL row's reason field is non-empty (i.e. assert the dispatcher applies the proposed fallback message from `hook-audit-02-block-reason-contract`). Cost: 1 fixture + temp-dir machinery already exists.
- **Validator-side static check** (per `hook-audit-02-block-reason-contract` part b). For every dual-mode hook, grep `check_<name>` body for `_BLOCK_REASON=` near every `return 1`. Runs at `make validate` time, no fork cost. Catches the violation at authoring time, not runtime.

Both belong; the validator is the durable fix. Recorded in robustness; reaffirmed here as a **testability** ask too — without the runtime test, even the validator-side guarantee can drift if a hook author bypasses the convention.

### 3. Distribution-tolerance scenarios are incomplete

The two test files cover **file-absent** distribution tolerance well (raiz-sim removes `enforce-make-commands.sh` / `enforce-uv-run.sh` for bash, `suggest-read-json.sh` for read). Per `02-dispatchers/robustness.md`, there's a second tolerance branch — **file present but `match_<name>` / `check_<name>` functions missing** — that fires the `declare -F` guard and writes `hook_log_substep "check_${name}_missing_match_check" 0 "skipped" 0`. T15 verified this empirically; no test asserts it.

Shape B fixture: stage a temp `HOOKS_DIR`, replace one child's body with a file that does NOT define `match_<name>` / `check_<name>` (e.g. `echo "lol"`), assert the JSONL row contains the `_missing_match_check` skipped substep.

Cost: ~1 fixture + temp-tree setup. Lower defensibility than #1/#2 because the failure mode is unlikely (hook authors don't accidentally remove function definitions), but it does lock in a real behavior the generator promises.

### 4. Order-precedence regressions are loosely guarded

Two of `test-grouped-bash.sh`'s 7 cases test precedence (credential_exfil winning over git_safety on a force-push that contains an embedded credential). That's **the precedence pair**, but other ordering decisions (dangerous before everything; auto_mode before credential_exfil; secrets_guard before config_edits) have no precedence assertions.

If `dispatch-order.json` is reshuffled, T19 (rm -rf / blocks via dangerous) and the credential_exfil-vs-git_safety cases would catch the most consequential regressions. The smaller orderings (e.g. secrets_guard moving after config_edits) would slip through silently.

Fixable in Shape B: add 2–3 more precedence cases. Each is one fixture asserting the *block reason text matches the earlier child*. ~3 cases × ~130ms = ~0.4s wall; rounding error.

### 5. The dispatcher's smoke fixture is pass-only

Both `dispatches-clean-pwd.json` (bash) and `dispatches-clean-read.json` (read) are **pass-fixtures** — no child blocks. The block path through the dispatcher (`hook_block "$_BLOCK_REASON"` at the bottom) is exercised end-to-end only by the per-child block tests inside the dual-mode hooks (e.g. `test-block-dangerous.sh` blocks `rm -rf /`).

Adding a block-path smoke fixture (`dispatches-rm-rf-blocked.json` or similar) would let `tests/hooks/run-smoke-all.sh` walk both paths — useful both for the dispatcher's own coverage and for `02-dispatchers/performance.md`'s open ask "block-path dispatcher fixtures" (so the per-dispatcher probe can measure block-vs-pass dispersion).

Cost: 1 fixture per dispatcher + the corresponding `.expect` file. Per-case fork ~130ms; trivial wall impact.

## Per-fixture fork cost (from performance.md)

The dispatcher fork tax is meaningfully larger than for standardized hooks. Smoke p50 from `02-dispatchers/performance.md`:

| Dispatcher | Smoke p50 | Cases today | Naive serial | Parallel (4-core) |
|------------|----------:|------------:|-------------:|------------------:|
| `grouped-bash-guard` | 130ms | 7 | 0.9s | ~0.3s + setup |
| `grouped-read-guard` | 61ms | 11 | 0.7s | ~0.2s + setup |

If we add the recommended cases from §1–§5 (~10 new fixtures total), the wall projection:

| Scenario | Bash cases | Read cases | Naive serial | Parallel (4-core) |
|----------|-----------:|-----------:|-------------:|------------------:|
| Today | 7 | 11 | 1.6s | ~0.5s |
| + recommended | ~14 | ~16 | 3.0s | ~0.9s |

Doubling the case count adds ~0.4s parallel wall — still well under the slowest-file ceiling (~20s for `secrets-guard`). Not a perf concern.

The bigger structural cost is **the per-child source phase repeating per fork**. From `02-dispatchers/performance.md`, ~52ms of every bash-dispatcher fork is the per-child source loop (8 children, hook-utils already loaded). Multiplying that by every test case is exactly the kind of cost Shape A would eliminate — but as the next section argues, Shape A doesn't reach the dispatcher cleanly.

## Shape A reachability for dispatchers

`00-shared/testability.md` and `01-standardized/testability.md` both record that Shape A is reachable for **lib functions** (sourced and called in-process) and for **`match_*` / `check_*` pairs** of dual-mode hooks (`hook-audit-01-shape-a-match-check-pairs`, P2), but NOT for whole standardized hooks because of the `exit 0` baked into the decision API.

For dispatchers, the same blocker applies amplified:

### What Shape A would buy here

- The dispatcher's per-fork floor is ~130ms / ~61ms vs ~25ms for standardized hooks — Shape A would compress dispatcher cases harder.
- The per-child source loop (~52ms) would be paid **once** at test-suite startup instead of per case.
- For ordering tests (§4 above), Shape A would let a hundred command shapes flow through `match_*` / `check_*` in milliseconds instead of seconds.

### What Shape A would cost

The dispatcher is fundamentally a **driver loop over children** that calls `hook_block` (which `exit 0`s) on the first block. To run multiple cases in one process you'd need:

1. **Restructure the dispatcher into a callable function.** Today the dispatch loop runs at top-level in `grouped-bash-guard.sh`. Shape A would need it as e.g. `dispatch_grouped_bash <command> <permission_mode>` returning `(rc, reason)`. Substantial rewrite of the dispatcher entrypoint — and the rewrite has to survive `make hooks-render` regeneration of the `lib/dispatcher-grouped-*.sh` companion.
2. **Decouple `_BLOCK_REASON` from process-global state.** Today every child writes the global `_BLOCK_REASON`; the dispatcher reads it. Shape A across multiple cases needs reset between cases (already done at line 76 `_BLOCK_REASON=""`) — survivable.
3. **Subshell each case anyway.** If we keep `hook_block` as `exit 0`, each case has to run in `( ... )` to scope the exit. Each subshell still forks (cheap-ish, but not free).
4. **Stdin shape.** Dispatchers read stdin via `hook_init` (jq). Shape A would need to either redirect a here-string per case or refactor `hook_init` to accept JSON-as-arg. Neither is a small ask.

### Hybrid: Shape A on the dispatcher's testable seams

The dispatcher's interesting test surface isn't the whole driver loop — it's three smaller things:

- **Block-fall-out logic** (the `if [ "$BLOCK_IDX" -ge 0 ]` block at `grouped-bash-guard.sh:108–114`): given a `BLOCK_IDX` and a `CHECKS` array, does the right number of `skipped` substeps get logged?
- **`_BLOCK_REASON` empty-defect fallback** (proposed in `hook-audit-02-block-reason-contract`): given a `check_<name>` that returns 1 without writing `_BLOCK_REASON`, does the dispatcher emit a fallback message?
- **Distribution-tolerance loop** (the `for spec in "${CHECK_SPECS[@]}"` loop in the generated lib): given a `CHECK_SPECS` array and a sparse `hook_dir`, does the right `CHECKS` array result?

All three are extractable as functions and testable Shape A. Cost: ~50 LoC of refactor in the entrypoints to expose them as callables. Benefit: regression coverage for the three branches that today have **zero direct tests** (everything goes through end-to-end forks).

This is the testability addition I'd recommend most strongly. The full-dispatcher Shape A (running entire dispatch through one function) isn't worth the rewrite; the **per-seam Shape A** is.

### Per-child Shape A (already proposed in 01-standardized)

The 9 dual-mode hooks the dispatcher invokes already expose Shape A-callable `match_<name>` / `check_<name>` pairs. `hook-audit-01-shape-a-match-check-pairs` (P2) proposes a single `tests/hooks/test-match-check-pairs.sh` that exercises all 9 in-process. **That work covers the dispatcher's children automatically** — no dispatcher-specific addition needed. The Shape A test file would source each hook, set `COMMAND` / `FILE_PATH`, call `match_<name>` and `check_<name>`, assert. Per case ~0ms.

What `hook-audit-01-shape-a-match-check-pairs` does **not** cover is the *interaction* between children and the dispatcher's loop (precedence, fall-out, `_BLOCK_REASON` contract). That's what the per-seam Shape A proposed above closes.

## Recommendations for the implementation pass

In priority order:

1. **Add a block-fall-out fixture per dispatcher.** Shape B; closes gap §1 and §5 in one fixture each. ~2 fixtures × ~30 min = 1 hour. Each fixture asserts `substeps | length == N` and `substeps[BLOCK_IDX+1:] | all(.outcome == "skipped")`. Highest defensibility — the fall-out loop has no other coverage today.
2. **Add a precedence-coverage fixture for the 2–3 untested ordering pairs.** Shape B; closes gap §4. ~3 fixtures × ~15 min = 45 min. Each fixture sends a command both children would block on, asserts the *block reason* matches the earlier child.
3. **Add the `_BLOCK_REASON`-empty regression fixture.** Shape B; closes gap §2 (the runtime side). Requires staging a temp `HOOKS_DIR` with one child rewritten to return 1 without setting `_BLOCK_REASON` — the raiz-sim machinery already in `test-grouped-bash.sh` shows the shape. ~30 min, ~30 LoC. Pairs with the validator-side check from `hook-audit-02-block-reason-contract` part b.
4. **Add the `_missing_match_check` fixture per dispatcher.** Shape B; closes gap §3. ~2 fixtures × ~30 min = 1 hour. Lower priority — the failure mode is unlikely, but the generator promises this branch.
5. **Defer the per-seam Shape A refactor.** Real value, real cost. Recommend opening as a follow-up only if a future regression in the fall-out loop or `_BLOCK_REASON` contract isn't caught by the proposed fixtures. The fixtures above buy regression coverage without rewriting the dispatcher entrypoints.

## Cross-cutting findings

- **The dispatcher tests' biggest gap isn't case count — it's branch coverage.** With 18 total Shape B cases, both files cover the *happy paths* (one child blocks, others pass) and the *raiz-sim distribution-tolerance branches* well. They don't cover (a) the post-block fall-out loop, (b) the `_BLOCK_REASON`-missing failure, (c) the `_missing_match_check` distribution branch. All three are dispatcher-specific behaviors with no other coverage.
- **The dispatcher's per-fork cost (~130ms / ~61ms) makes Shape B expensive per case, but the case counts are small enough that it doesn't matter for wall.** The dispatcher tests are the cheapest in the entire `make test` suite right now (~1s parallel). Tripling them still keeps them under ~3s parallel.
- **Shape A reachability is structurally limited at the whole-dispatcher level** but reachable at three specific seams (fall-out logic, `_BLOCK_REASON` fallback, distribution-tolerance loop). The per-seam refactor is real work; defer until the proposed Shape B fixtures prove insufficient.

## Verified findings feeding downstream axes / Clarity

Three testability-derived inputs to `clarity.md`:

1. **The dispatcher entrypoint mixes "input parse → setup → driver loop → fall-out emit" in one top-level script.** Three of those phases have no direct test coverage today. Whether to extract them into named functions for testability vs leave the entrypoint as a top-down readable script is a clarity-axis call. The per-seam Shape A proposal above is the testability side of that question.
2. **The raiz-sim pattern (`cp -r $HOOKS_DIR /tmp/sim; rm -f children; HOOKS_DIR=$sim_dir`) is duplicated across both dispatcher test files.** It's the canonical way to test distribution tolerance, and it works, but it's ~10 LoC each that could live in `tests/lib/hook-test-setup.sh` as `with_simulated_distribution() { ... }`. Editorial; clarity to weigh.
3. **Per-child block coverage lives inside each child's standalone test file** (`test-block-dangerous.sh`, `test-secrets-guard.sh`, etc.) — the dispatcher tests don't re-test child decisions. That's the right separation, but the dispatcher tests' purpose isn't documented in the file headers; both `test-grouped-{bash,read}.sh` headers describe what the dispatcher does, not what the test scope is. A one-line "this file tests dispatch behavior; per-child decisions live in test-<child>.sh" header would make the boundary explicit.

## Verified findings feeding downstream axes / Performance

- **Adding ~10 new Shape B fixtures adds ~1.3s naive serial / ~0.4s parallel wall.** Trivial; nothing to weigh.
- **Per-seam Shape A refactor would compress the dispatcher tests' wall to <50ms total** (function calls, no forks). Real but not worth the refactor cost yet — see deferred recommendation #5.
- **Block-path dispatcher fixtures (per recommendation #1) unblock the perf-axis open ask** for "measure block-vs-pass dispersion in the per-dispatcher probe." After the fixtures land, re-running `run-per-dispatcher-probe.sh` against them would give a clean smoke block-mode number.

## Verified findings feeding downstream axes / Robustness

- **Recommendations #1, #2, #3 are exactly the runtime-test side of three robustness findings.** Without these fixtures, the `02-dispatchers/robustness.md` table of "verified by probe" findings is locked in by *manual probes* (the throwaway scripts under `output/claude-toolkit/sessions/dispatcher-*-probe.sh`) but not by *regression tests*. Promoting the probes to fixtures is what closes the loop.

## Confidence

- **High confidence** in the per-dispatcher test counts and per-file walls — both pulled from current source/log files and grep counts.
- **High confidence** in the gap analysis (§1–§5). All five are derived from `02-dispatchers/robustness.md`'s empirical T-numbers (T13–T19) cross-referenced against the test files. Each gap has a corresponding empirically-verified behavior with no test fixture covering it.
- **High confidence** that recommendations #1, #2, #4 are cheap and high-defensibility. Each is a single fixture; the temp-tree machinery they need already exists in `test-grouped-bash.sh`.
- **Medium confidence** on the per-seam Shape A defer call. The refactor is workable; the value depends on whether the proposed Shape B fixtures actually catch future regressions. Reopen if a fall-out-loop or `_BLOCK_REASON`-contract bug ever ships despite the fixtures.

## Open

- **Whether the block-fall-out fixture should be one-per-dispatcher or one shared.** Editorial. One-per-dispatcher mirrors existing test organization; one shared (parametrized) would centralize the substep-count assertion logic. Defer to whoever lands the work.
- **Whether to factor the raiz-sim helper into `tests/lib/hook-test-setup.sh`.** Falls to clarity (cross-cutting finding #2 above).
- **Whether `tests/hooks/run-smoke-all.sh` should require both pass and block fixtures per dispatcher** (V18-style minimum: two fixtures per dispatcher instead of one). Falls to a future minimum-fixture-spec revision; not in this audit's scope.

## Backlog tasks added

- `hook-audit-02-block-fallout-fixture` (P2) — add a block-fall-out fixture per dispatcher asserting `substeps[BLOCK_IDX+1:]` are all `skipped`. Closes gap §1 + §5.
- `hook-audit-02-precedence-fixtures` (P3) — add 2–3 precedence-coverage fixtures (secrets_guard before config_edits, dangerous before everything, auto_mode before credential_exfil). Closes gap §4.
- `hook-audit-02-distribution-functions-missing-fixture` (P3) — add a `_missing_match_check` fixture per dispatcher. Closes gap §3.

(The `_BLOCK_REASON`-empty regression fixture is already covered by the existing `hook-audit-02-block-reason-contract` (P2) item — recommendation #3 above is the runtime-test deliverable inside that task's scope.)
