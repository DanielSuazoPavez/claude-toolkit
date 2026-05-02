---
category: 00-shared
axis: testability
status: drafted
date: 2026-05-02
---

# 00-shared — testability

How testable are the libs today, what shapes do existing tests take, and what would change if the libs were structured for a different test shape. The downstream categories will reuse the testability shape established here.

## Two test shapes coexist

The current test surface uses **two genuinely different shapes** for the same code:

### Shape A — In-process lib tests (already optimal)

Files: `tests/hooks/test-detection-registry.sh`, `tests/hooks/test-settings-permissions.sh`, `tests/hooks/test-call-id.sh`, `tests/hooks/test-session-id.sh`.

Pattern:
```bash
source "$REPO_ROOT/.claude/hooks/lib/hook-utils.sh"
source "$REPO_ROOT/.claude/hooks/lib/detection-registry.sh"
detection_registry_load
detection_registry_match credential raw "$input"
assert_eq "..." "$_REGISTRY_MATCHED_ID" "github-pat"
```

The libs are sourced into the **test process itself**. Each assertion is a function call, not a fork. The `_DETECTION_REGISTRY_SOURCED` and `_REGISTRY_LOADED` idempotency guards mean even the first source pays cost only once.

**Per-test-case overhead: ~0** (a function call). N=391 cases across the lib tests would still complete in well under a second of runtime if structured this way.

The lib tests currently don't cover most of the lib API — they test the detection-registry loader/matcher and settings-permissions loader, plus narrow `hook_init` behaviors (call_id, session_id capture). `_now_ms`, `_strip_inert_content`, `hook_extract_quick_reference`, `hook_feature_enabled` aren't directly tested today, but **could be** with this shape essentially for free.

### Shape B — Subprocess-fork hook tests (where the cost lives)

Files: `tests/hooks/test-*.sh` for every standardized hook (e.g. `test-secrets-guard.sh` with 73 cases, `test-block-config.sh` with 58, `test-auto-mode-shared-steps.sh` with 54).

Pattern (via `batch_add` / `batch_run`):
```bash
batch_add block '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' "blocks cat .env"
# ... ~50 more cases ...
batch_run  # parallel: each case spawns a fresh `bash $HOOK <input` subprocess
```

Each test case is **one full hook firing** — a fresh `bash` interpreter, full lib parse + load, full `hook_init`, full check-body, decision JSON emitted, exit. The runner uses `xargs -P $(nproc)` to parallelize, so wall ≪ serial cost.

**Per-test-case overhead: per-event lib floor + hook_init cost** (from `performance.md`):
- Hooks with no extra loaders (`git-safety`, `enforce-make`, `enforce-uv`): ~5-7ms per case (hook-utils parse + hook_init)
- Hooks with detection-registry-loaded (`secrets-guard`, `block-config-edits`, `block-credential-exfiltration`): ~13-15ms per case
- Hooks with both loaders (`auto-mode-shared-steps`): ~21ms per case
- Dispatcher entrypoints (`grouped-bash-guard`): ~100-120ms per case

Counts (cases per file, from `grep -c batch_add|expect_*`):

| File | Cases | Per-case fork cost | Serial wall | Parallel wall (4 cores) |
|------|------:|-------------------:|------------:|------------------------:|
| test-secrets-guard       | 73 | ~13ms | ~950ms | ~240ms |
| test-block-config        | 58 | ~13ms | ~750ms | ~190ms |
| test-auto-mode-shared    | 54 | ~21ms | ~1.1s  | ~280ms |
| test-git-safety          | 47 | ~7ms  | ~330ms | ~85ms  |
| test-approve-safe        | 43 | ~12ms | ~520ms | ~130ms |
| test-block-credential    | 40 | ~14ms | ~560ms | ~140ms |
| test-block-dangerous     | 28 | ~8ms  | ~225ms | ~57ms  |
| (other 9 files)          | 48 | ~10ms avg | ~480ms | ~120ms |
| **Total**                | **391** | — | **~5s** | **~1.2s** |

Smoke fixtures add 28 cases at one fork each: ~150-300ms more.

**Total testing wall is dominated by a few slow files** — `test-validate-hook-headers.sh` ran at 31.3s in the most recent `make check`, and that test covers V20 budget validation across all 17 hooks (each hook's smoke fixture replayed 3-5× under timing). The hook-tests' fork tax is real but already mitigated by parallelism.

## Why Shape B exists at all

If Shape A is essentially free, why do the hook tests use Shape B? Three reasons, all sound:

1. **End-to-end realism.** Shape B exercises the full pipeline: dispatcher routing → hook_init → check-body → decision-JSON output → process exit. A bug in any one of those layers shows up. Shape A would miss a `hook_init` regression, an EXIT-trap regression, or a decision-JSON serialization regression.
2. **The decision API exits the process.** `hook_block` / `hook_approve` / `hook_ask` / `hook_inject` all end in `exit 0`. Even if Shape A could exercise check-body logic, a single test case ends the host process when the hook reaches a decision. **You cannot run two cases in one Shape A invocation today** — verified in the inventory and `robustness.md`.
3. **Stdin shape.** Hooks read JSON from stdin via `cat` (in `hook_init`). Shape A would need to mock the stdin source (e.g. write to a file, redirect on the function call) — doable but moves the test further from production behavior.

The shape isn't a mistake; it's a tradeoff that buys realism at the cost of fork overhead.

## What "more testable" would even mean

Two distinct improvement axes:

### Axis 1 — Cover more lib functions in Shape A (cheap, do anyway)

Functions that lack direct tests today:

- `_now_ms` — pin the `EPOCHREALTIME`-padding fix that prevents the documented 10× small bug. One Shape A test (force a 1-digit `_frac`, assert the result).
- `_strip_inert_content` — pin behavior on heredoc, single-quoted, double-quoted, escaped quote, nested quotes. ~10 cases. **High value** because it's the most complex pure-bash function in the libs and the inventory + robustness flagged it as the heuristic-limits surface.
- `hook_feature_enabled` — three branches (`lessons` / `traceability` / unknown). Trivial.
- `hook_extract_quick_reference` — file-missing path, file-present-no-block path, file-present-with-block path. Trivial.

These are all **Shape A additions** — they cost ~0ms per case at runtime and would lock in behavior the inventory and robustness reports treat as load-bearing.

**Recommended for the implementation pass.** Estimated ~30 new test cases, ~50 LoC of test code, no fork tax.

### Axis 2 — Restructure the decision API to enable in-process multi-case testing (real churn)

Today: `hook_block "reason"` → emits JSON to stdout, calls `exit 0`.

Alternative shape: `hook_block "reason"` → sets `HOOK_DECISION_JSON="..."`, returns 0. A separate `hook_emit_decision_and_exit` (called once at the end of `hook_init`'s EXIT trap or by an explicit `main` wrapper) prints the captured JSON and exits.

Implications:

- Shape A could then run multiple test cases in one host process by clearing `HOOK_DECISION_JSON` between cases.
- `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1` already does roughly this for the smoketest writer — `_HOOK_RECORDED_DECISION` captures the JSON instead of printing it. The pattern exists; it's currently smoke-only.
- The churn surface is wide: every hook calls one of the four decision APIs; the EXIT trap + `_hook_log_timing` would need to know whether a decision was reached.
- Risk: a hook that "forgets" to emit becomes silently fail-open instead of fail-closed. Today's `exit 0` model fails loudly — control-flow ends at the decision call site.

**Cost-benefit estimate:**
- Wall time saved on `make test`: ~1s parallel wall (most hook-test files are already < 250ms parallel; the big ones get split across 4 cores).
- Realism cost: lose the end-to-end pipeline check on every case.
- Churn: ~17 hooks × ~3-5 LoC each + harness changes + EXIT-trap rework.

**Verdict for `testability.md`:** **don't do it.** The fork tax is real but parallelism mitigates it; the realism Shape B gives is genuinely valuable; the churn-to-savings ratio is poor. Recorded as a "considered and rejected" option so a future audit doesn't re-discover it as a fresh idea.

If `make test` wall ever climbs past the 90s drift signal documented in `tests/CLAUDE.md`, revisit — but the right answer there is likely "split a slow file" or "skip a redundant fixture", not a decision-API rewrite.

## Idempotency guards make Shape A safer than it looks

A worry with Shape A is that re-sourcing libs across many test cases would corrupt state — globals from case N-1 bleed into case N. The lib idempotency guards (`_HOOK_UTILS_SOURCED`, `_DETECTION_REGISTRY_SOURCED`, etc.) prevent **re-source corruption**, but not **state corruption**: if case N-1 sets `_REGISTRY_MATCHED_ID="github-pat"` and case N expects it cleared, case N has to clear it itself.

Existing Shape A tests handle this by clearing the relevant globals between assertions:
```bash
_REGISTRY_MATCHED_ID=""
_REGISTRY_MATCHED_MESSAGE=""
detection_registry_match credential raw "$input"
```

This is a real test-authoring constraint, not a defect. New Shape A tests added in Axis 1 above should follow the same pattern. Recorded for the test conventions doc, not as a lib change.

## Smoke fixtures vs hook tests — different shapes for different goals

Same code, three test surfaces:

| Surface | Shape | Cases | Goal |
|---------|-------|------:|------|
| `tests/hooks/test-<hook>.sh` | B (fork per case, parallel) | 391 total | Logic coverage with stdin variety |
| `tests/hooks/fixtures/<hook>/*.json` | B (fork per fixture, sequential per hook in `run-smoke-all.sh`) | 28 | V20 perf-budget validation + outcome assertion |
| `tests/hooks/test-detection-registry.sh` etc. | A (in-process) | ~30 | Lib-level contract pinning |

The split is intentional: smoke fixtures pay the fork tax in exchange for V20 timing measurement (which requires a real subprocess to time meaningfully). Hook tests pay the fork tax in exchange for logic coverage at scale.

There's no shape consolidation that makes sense here.

## Recommendations for the implementation pass

In priority order:

1. **Add Shape A tests for `_strip_inert_content`** (highest value). The function is the most complex pure-bash piece in the libs and is unjustified-by-test for its heuristic boundaries (heredoc opener, escaped quotes, nested quotes). ~10 test cases, ~30 LoC.
2. **Add Shape A tests for `hook_feature_enabled` and `hook_extract_quick_reference`** (trivial, do anyway). ~5 cases combined.
3. **Add Shape A tests for `_now_ms` `EPOCHREALTIME` padding** (pin the documented bug fix). 1-2 cases.
4. **Add malformed-stdin Shape B fixtures** (from `robustness.md`). One per event type. Cost: 4 fork-per-case fixtures, ~50ms wall-time impact. Justified by locking in fail-closed semantics.
5. **Don't restructure the decision API.** The Shape B fork tax is real but parallelism-mitigated; Shape B's end-to-end realism is genuinely valuable; the churn is high; the savings (~1s parallel wall) don't justify it.

## Confidence

- **High confidence** in the in-process vs subprocess characterization — read both shapes' source code and the runner mechanics.
- **High confidence** in the per-case cost estimates — they're derived from `performance.md`'s per-event lib-floor table plus a fixed `hook_init` cost (~4-5ms).
- **Medium confidence** in the parallel-wall estimates — they assume `nproc=4` and uniform per-case cost; a single slow case in a batch (e.g. one with a long heredoc that triggers `_strip_inert_content`) skews wall time but doesn't change the conclusion.
- **High confidence** in the "don't restructure decision API" call — the realism argument is strong, the savings small.

## Open

- Whether the lib tests should grow into a single consolidated `test-libs.sh` Shape A file, or stay as per-lib files. Editorial — defer to whoever lands the new tests.
- Whether to add a "perf-validate-hook-headers benchmark" that measures the fork tax explicitly so future regressions surface. Probably overkill — `tests/CLAUDE.md` already documents the drift signals (slowest hook file > 50s, total wall > 90s).
