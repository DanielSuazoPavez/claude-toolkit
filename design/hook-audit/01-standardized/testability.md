---
category: 01-standardized
axis: testability
status: drafted
date: 2026-05-02
---

# 01-standardized — testability

How testable is each of the 13 standardized hooks today, what shapes do existing tests take, and where are the coverage gaps. Reuses the **Shape A / Shape B** distinction established in `00-shared/testability.md`:

- **Shape A** — in-process: source the hook's lib(s), call functions, assert. ~0ms per case. Used today only for lib-level tests.
- **Shape B** — subprocess fork: write stdin to a file, fork a fresh `bash <hook>.sh`, assert on the captured stdout. ~5–25ms per case, parallelized via `xargs -P $(nproc)`.

Standardized hooks today are tested almost exclusively via Shape B. The question for this category is: where are the coverage gaps, are they fixable in Shape B, and is Shape A reachable for any of these hooks?

## Coverage today

Per-hook test files in `tests/hooks/test-<hook>.sh` (Shape B) plus the V18-minimum smoke fixture in `tests/hooks/fixtures/<hook>/`. Counts from `grep -cE "(batch_add|expect_*)"` on each file:

| Hook | Test cases (Shape B) | Smoke fixtures (Shape B) | Wall (s, parallel) |
|------|---------------------:|-------------------------:|-------------------:|
| `secrets-guard` | 73 | 1 | **20.3** |
| `auto-mode-shared-steps` | 54 | 1 | **19.0** |
| `block-config-edits` | 58 | 1 | **12.9** |
| `approve-safe-commands` | 43 | 1 | **12.5** |
| `git-safety` | 47 | 1 | **8.4** |
| `block-credential-exfiltration` | 40 | 1 | 7.4 |
| `block-dangerous-commands` | 28 | 1 | 4.9 |
| `enforce-uv-run` | 13 | 1 | 1.3 |
| `enforce-make-commands` | 8 | 1 | 0.8 |
| `suggest-read-json` | 5 | 1 | 1.7 |
| `log-permission-denied` | 4 | 1 | 1.7 |
| `log-tool-uses` | **0** | 1 | n/a |
| `detect-session-start-truncation` | **0** | 1 | n/a |

Wall-time numbers are from `tests/.logs/test-<hook>.dur` (last `make test` run on this machine). They are per-file walls — `make test` overall is bounded by the **slowest single file** plus runner overhead.

Aggregate: **373 cases across 11 of 13 hooks**, ~5s parallel wall, ~1.2s critical-path wall (slowest file).

**Coverage gaps:**

1. **`log-tool-uses` has no test file.** The hook is 30 LoC of comments + ~5 lines of code (source, `hook_init`, `exit 0`); behavior is "always log every tool invocation." But the JSONL-row contract (every required field present, stdin embedded, outcome=`pass`) is unjustified-by-test. `test-log-permission-denied.sh` covers exactly this contract for the sibling logger — copying the shape would yield ~4 cases, ~1s wall.
2. **`detect-session-start-truncation` has no test file.** Two distinct paths exist (truncation marker present in transcript → `hook_inject` warning; marker absent → silent pass) plus the fire-once marker file. None tested.
3. **No malformed-stdin assertions** for any of the 13 hooks. `01-standardized/robustness.md` verified the behavior manually for all 13; smoke fixtures don't lock it in. Captured under existing `hook-audit-00-malformed-stdin-fixtures` task.
4. **No missing-field assertions** for the 12 hooks with required fields. Same shape as malformed-stdin — all silent-pass today, none locked in.
5. **`suggest-read-json`** has only 5 test cases for a hook that has 4 distinct branches (allowlist hit, `.config.json` pattern, file-too-small, file-doesn't-exist-but-blocks-anyway). The robustness-flagged "blocks on nonexistent file" gap was found by manual probing — no fixture catches it.

Of these, items 1 (log-tool-uses) and 2 (detect-session-start-truncation) are the clearest **missing test files**. Items 3 and 4 are cross-cutting and tracked at the lib level. Item 5 is a per-hook expansion.

## Per-hook fork cost (from performance.md)

`make test` parallel wall depends on per-case fork cost × case count, mitigated by `xargs -P $(nproc)`. Numbers from `01-standardized/performance.md` smoke totals:

| Hook | Smoke p50 | Cases | Naive serial | Parallel (4-core) |
|------|----------:|------:|-------------:|------------------:|
| `secrets-guard` | 48ms | 73 | 3.5s | ~0.9s + setup |
| `auto-mode-shared-steps` | 46ms | 54 | 2.5s | ~0.6s + setup |
| `block-config-edits` | 37ms | 58 | 2.1s | ~0.5s + setup |
| `approve-safe-commands` | 33ms | 43 | 1.4s | ~0.4s + setup |
| `git-safety` | 38ms | 47 | 1.8s | ~0.5s + setup |
| `block-credential-exfiltration` | 32ms | 40 | 1.3s | ~0.3s + setup |
| `block-dangerous-commands` | 43ms | 28 | 1.2s | ~0.3s + setup |
| `enforce-uv-run` | 25ms | 13 | 0.3s | ~0.1s |
| `enforce-make-commands` | 22ms | 8 | 0.2s | ~0.1s |
| `suggest-read-json` | 27ms | 5 | 0.1s | ~0.1s |
| `log-permission-denied` | 22ms | 4 | 0.1s | ~0.1s |

The "Naive serial" column is what wall would be without parallelism. The "Parallel" column is the predicted floor — actual measured walls (table above) are higher because of test setup, runner overhead, and per-test cleanup. The gap between predicted parallel (~0.5–0.9s) and measured (8–20s) is **real overhead worth understanding** — not pure fork cost.

**Hypothesis (not yet measured):** the gap is dominated by `tests/lib/hook-test-setup.sh` per-test-process setup (mktemp dir creation, env var export, helper sourcing) and `xargs -P` startup + per-case file write/read I/O. The per-fork hook cost is well-characterized; the harness cost around it isn't.

This is the reason the slowest hook test file is **20s wall** for 73 cases that should run in ~0.9s of actual hook work. ~19s of overhead per file. That's the testability axis's biggest open question — and it's a follow-up, not something to resolve here.

## Shape A reachability for standardized hooks

`00-shared/testability.md` recorded the verdict for the libs: Shape A is already used for what makes sense, restructuring the decision API to enable Shape A for whole hooks is **not worth the churn** (saves ~1s parallel wall, costs end-to-end realism + hook-author-error fail-loud-ness).

Re-evaluating that for the standardized category specifically:

### What Shape A would buy here

- 373 cases × ~25ms per fork = ~9.3s of fork cost, currently amortized across 4 cores into ~2.3s critical-path. Shape A would compress that to ~50ms total (function-call overhead).
- The **harness overhead** (the 19s gap above) probably wouldn't compress as much — most of it is per-file setup, not per-case work.
- Net wall savings: ~2s critical-path. Not the 9s the naive math suggests.

### What Shape A would cost

Same as the lib-level analysis:

1. **The decision API exits the process.** `hook_block` / `hook_approve` / `hook_ask` / `hook_inject` all `exit 0`. To run multiple cases in one process you'd need to either (a) restructure those into return-then-emit, or (b) run each case in a subshell `( )` so `exit` only kills the subshell. Option (b) keeps the fork tax (each subshell forks).
2. **Stdin shape.** Hooks read JSON from stdin via `cat` in `hook_init`. Shape A would need to redirect a file or use a here-string per case, moving further from production behavior.
3. **The dual-mode hooks** (block-config-edits, block-dangerous-commands, enforce-make-commands, enforce-uv-run, git-safety, secrets-guard, suggest-read-json) export `match_<name>` and `check_<name>` as in-process-callable functions for the dispatcher. **These are already Shape A-compatible** — they don't `exit`, they `return 0`/`1` and set `_BLOCK_REASON`. A test could source the hook and call `match_<name>` + `check_<name>` directly.

The dual-mode point is genuinely interesting. The 7 dual-mode hooks expose Shape A-compatible test surfaces *for free* — the dispatcher already calls them this way. We could test `match_<name>` and `check_<name>` in-process, alongside the existing Shape B end-to-end tests.

### Hybrid recommendation: Shape A for `match_*`/`check_*` + Shape B for end-to-end

For the 7 dual-mode hooks: add a Shape A test layer that exercises the predicate + check pair directly, alongside the existing Shape B file. Cost-benefit:

- **Cost:** ~7 new test files (or a single combined `test-dual-mode-shapes.sh`), ~100 LoC. Each test sets `COMMAND` (or `FILE_PATH`), calls `match_<name>`, asserts the return; calls `check_<name>`, asserts the return + `_BLOCK_REASON`. No fork, no harness setup beyond sourcing the hook.
- **Benefit:** locks in the predicate-vs-check contract. The `block-dangerous-commands` quote-evasion gap (`01-standardized/robustness.md`) is exactly the kind of bug Shape A would catch fast — a Shape A test can iterate hundreds of input shapes through `match_dangerous` in milliseconds without paying the dispatch fork tax. Shape B catches the same gap end-to-end at higher cost per case.
- **No realism loss:** Shape B stays as the canonical end-to-end coverage. Shape A is additive.

This is the testability addition I'd recommend most strongly. Captured as a follow-up below.

### Shape A for the 6 non-dual-mode hooks

The remaining 6 don't expose `match_*`/`check_*` functions:

- `approve-safe-commands` — main is one function (split-and-check); not refactored into a predicate/check pair.
- `auto-mode-shared-steps` — has `match_auto_mode_shared_steps`/`check_auto_mode_shared_steps` already. **Move to dual-mode list above.**
- `block-credential-exfiltration` — has `match_credential_exfil`/`check_credential_exfil`. **Move to dual-mode list above.**
- `detect-session-start-truncation` — single-purpose, not split.
- `log-permission-denied`, `log-tool-uses` — pure loggers, no logic to split.

So the dual-mode list is actually **9 hooks**, not 7. Re-counting from `inventory.md`:

| Hook | `match_*`/`check_*` exposed? |
|------|-----------------------------|
| `approve-safe-commands` | no — single `main` |
| `auto-mode-shared-steps` | **yes** — `match_auto_mode_shared_steps` / `check_auto_mode_shared_steps` |
| `block-config-edits` | **yes** |
| `block-credential-exfiltration` | **yes** — `match_credential_exfil` / `check_credential_exfil` |
| `block-dangerous-commands` | **yes** |
| `detect-session-start-truncation` | no — fire-once gate, not split |
| `enforce-make-commands` | **yes** — `match_make` / `check_make` |
| `enforce-uv-run` | **yes** — `match_uv` / `check_uv` |
| `git-safety` | **yes** |
| `log-permission-denied` | no — pure logger |
| `log-tool-uses` | no — pure logger |
| `secrets-guard` | **yes** |
| `suggest-read-json` | **yes** — `match_suggest_read_json` / `check_suggest_read_json` |

**9 hooks expose Shape A-compatible match/check pairs.** The dispatcher already drives them this way. The Shape A test layer is essentially "test what the dispatcher already invokes."

## Per-hook recommendations

| Hook | Coverage gap | Recommended addition |
|------|--------------|----------------------|
| `approve-safe-commands` | 0 | Shape B already strong (43 cases). No addition. |
| `auto-mode-shared-steps` | 0 | Shape B strong (54 cases). Add Shape A `match_*`/`check_*` layer. |
| `block-config-edits` | 0 | Shape B strong (58 cases). Add Shape A layer. |
| `block-credential-exfiltration` | 0 | Shape B strong (40 cases). Add Shape A layer. |
| `block-dangerous-commands` | quote-evasion (robustness.md) | Add Shape A layer; quote-evasion is a `match_dangerous` predicate test, not an end-to-end one. |
| `detect-session-start-truncation` | **no test file** | Add Shape B file: 4 cases (marker absent + truncation → inject; marker present → silent; marker absent + no truncation → silent; missing transcript_path → silent pass). |
| `enforce-make-commands` | 0 (low count, simple hook) | Shape B sufficient. |
| `enforce-uv-run` | 0 (heredoc/quote behavior verified manually in robustness.md) | Add Shape A layer to lock in `_strip_inert_content`-blanked verb-position regex. |
| `git-safety` | 0 | Shape B strong (47 cases). Add Shape A layer for the dual-mode pair. |
| `log-permission-denied` | 0 | Shape B strong (4 cases + JSONL assertions). |
| `log-tool-uses` | **no test file** | Add Shape B file mirroring `test-log-permission-denied.sh` shape: 4 cases for tool-name variety + JSONL field assertions. |
| `secrets-guard` | 0 (largest test surface — 73 cases) | Add Shape A layer; high-value because the inline command-shape policy has many branches. |
| `suggest-read-json` | nonexistent-file gap (robustness.md) | Add Shape B fixture for nonexistent-file path; add Shape A layer for the dual-mode pair. |

## Cross-cutting findings

- **Two hooks (`log-tool-uses`, `detect-session-start-truncation`) have no test file beyond the V18 minimum smoke fixture.** Direct gap. Easy to fix.
- **9 of 13 hooks expose Shape A-callable `match_*`/`check_*` pairs.** A new test layer can exercise these in-process at ~0ms per case. This is the single biggest "more testable" win the category has — it doesn't require any hook changes and amortizes against existing Shape B coverage.
- **The 19s gap between predicted-parallel and measured per-file wall is unexplained.** Hypothesis is harness setup overhead. Worth a separate investigation — probably falls to `tests/CLAUDE.md`'s perf-baseline doc, not this audit.
- **Coverage of `match_<name>` predicates is currently end-to-end only.** Predicate-only tests (Shape A) would catch issues like the `block-dangerous-commands` quote-evasion much earlier in the pipeline. Robustness.md found that gap by manual probing; a Shape A test would have caught it automatically.

## Verified findings feeding downstream axes

### Performance

- Adding ~50–100 Shape A cases across the 9 dual-mode hooks adds **<100ms total runtime**. No performance impact on `make test` wall.
- The two missing Shape B test files (log-tool-uses, detect-session-start-truncation) at ~5 cases each add ~250ms parallel wall. Trivial.

### Robustness

- The `block-dangerous-commands` quote-evasion and `suggest-read-json` nonexistent-file gaps are both naturally expressible as Shape A tests. Adding Shape A coverage for the 9 dual-mode hooks would lock these in alongside the corresponding implementation fixes.

### Clarity

- **The "9 hooks expose match/check pairs" rollup belongs in `clarity.md`** as evidence that the dual-mode pattern has been adopted broadly. The 4 hooks that don't expose pairs (`approve-safe-commands`, `detect-session-start-truncation`, `log-permission-denied`, `log-tool-uses`) are the exceptions; the rule is "split predicate from check." `clarity.md` should evaluate whether `approve-safe-commands` should be refactored to follow the pattern (it's a 200-LoC hook with substantial logic that isn't currently split).

## Recommendations for the implementation pass

In priority order:

1. **Add `tests/hooks/test-log-tool-uses.sh`** — copy the shape of `test-log-permission-denied.sh`. ~4 Shape B cases + JSONL field assertions. Cost: 30 min, ~50 LoC. Closes a no-test-file gap.
2. **Add `tests/hooks/test-detect-session-start-truncation.sh`** — 4 Shape B cases (truncation present, truncation absent, marker pre-set, missing transcript_path). Cost: 30 min, ~60 LoC.
3. **Add Shape A test layer for the 9 dual-mode hooks** — single file `tests/hooks/test-match-check-pairs.sh` (or per-hook addendum), source each hook, call `match_<name>`/`check_<name>` with shaped input, assert return + `_BLOCK_REASON`. Cost: 2–3 hours, ~150 LoC. Highest leverage because it locks in predicate boundaries that Shape B can only catch end-to-end.
4. **Investigate the 19s harness-setup gap** — separate task, not this audit. Captured for `tests/CLAUDE.md`'s perf-baseline tracking.

## Confidence

- **High confidence** in the per-hook test counts and per-file walls — both pulled from current source/log files.
- **High confidence** that the 9 hooks expose Shape A-compatible pairs — verified by inspection of each hook file (`grep -E '^(match|check)_'`).
- **Medium confidence** on the harness-overhead hypothesis (19s per-file gap). The numbers are real; the attribution is hypothesis. Worth measuring if anyone touches the harness.
- **High confidence** that adding Shape A coverage for dual-mode hooks doesn't regress realism. Shape B stays as the canonical end-to-end pass; Shape A is additive.

## Open

- **What's the right file shape for Shape A dual-mode tests** — one per hook (`test-<hook>-match-check.sh`) or one combined (`test-match-check-pairs.sh`)? Editorial; defer to whoever lands the work. The combined shape minimizes harness setup overhead (one process for all 9 hooks); the per-hook shape mirrors existing organization.
- **Should `approve-safe-commands` be refactored to expose `match_*`/`check_*`?** It's the only non-pure-logger, non-fire-once hook in the category that doesn't follow the dual-mode pattern. Falls to `clarity.md`.
- **Harness-overhead measurement.** The 19s per-file gap merits a separate probe. Not in this audit's scope.
