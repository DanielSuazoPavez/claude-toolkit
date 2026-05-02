---
category: 02-dispatchers
axis: robustness
status: drafted
date: 2026-05-02
---

# 02-dispatchers — robustness

Failure-mode analysis for the two dispatchers and the dispatcher-child contract. Goal: identify gaps between **what the dispatcher header / generator promise** and **what the code actually does** under malformed inputs, missing or broken children, and contract-violating child implementations. Findings here drive fixture work and (where the gap is real) implementation fixes.

**Convention** (inherited from `00-shared/robustness.md` / `01-standardized/robustness.md`):
- **fail-closed** — emits a `block` decision, halts the operation. Right stance for PreToolUse safety dispatchers.
- **fail-open** — exits 0 with no decision.
- **fail-soft** — silent pass on missing input.
- **fail-loud** — emits to stderr and skips the offending entry/operation.

All findings below were **empirically verified** by running each dispatcher end-to-end against shaped fixtures + scratch-tree distributions (probe scripts under `output/claude-toolkit/sessions/dispatcher-*-probe.sh`).

## Dispatcher-level malformed-stdin behavior

| Dispatcher | Malformed-stdin behavior | Source |
|------------|--------------------------|--------|
| `grouped-bash-guard` | **fail-closed**: emits `{"decision":"block","reason":"hook grouped-bash-guard received malformed stdin — blocking as safety precaution"}` | `hook_init` malformed branch in `hook-utils.sh:267-282` (verified at lib level in `00-shared/robustness.md`, re-confirmed end-to-end here) |
| `grouped-read-guard` | **fail-closed** (same shape) | same |

Both dispatchers inherit the lib-level fail-closed contract correctly. Verified with `printf 'not-json' | bash <dispatcher>.sh`.

**Coverage gap (carried over from `01-standardized/robustness.md`):** no smoke fixture exercises the malformed-stdin branch for either dispatcher. Already tracked under `hook-audit-00-malformed-stdin-fixtures` (P0).

### Empty-stdin edge case (lib-level gap surfaced here)

`printf '' | bash <dispatcher>.sh` exits **silent** (rc=0, no decision JSON). Cause: `jq -r '...' <<< ''` exits 0 with empty output — `hook_init`'s rc check doesn't fire (rc=0), so the malformed branch is skipped; `_HOOK_INIT_TOOL_NAME` ends up empty; `hook_require_tool Bash` doesn't match → silent exit.

For PreToolUse safety dispatchers this is an unintended **fail-open** path. In practice the harness always emits valid JSON with a `tool_name` field, so empty stdin is not a real production case — only an edge surfaced by probing. But it diverges from the documented "PreToolUse hooks fail closed on malformed stdin" contract: empty is malformed for any consumer expecting JSON.

This gap is **at the `hook_init` level**, not the dispatcher level — every PreToolUse hook has the same behavior. The fix would be in `hook_init`: treat "empty `_HOOK_INIT_TOOL_NAME` after a successful jq" as malformed for PreToolUse. Recorded as `hook-audit-00-empty-stdin-fail-closed` (low priority — no production trigger known, only probe-surface).

## Per-dispatcher missing-field behavior

| Dispatcher | Required field | Missing-field behavior | Notes |
|------------|----------------|------------------------|-------|
| `grouped-bash-guard` | `tool_input.command` | silent pass — `[ -z "$COMMAND" ] && exit 0` (`grouped-bash-guard.sh:68`) | Children rely on `$COMMAND` being non-empty; the early bail prevents undefined-state child invocation. |
| `grouped-read-guard` | `tool_input.file_path` | silent pass (no early `[ -z ]` bail; children's `match_*` predicates handle empty `$FILE_PATH` themselves) | Verified: each child returns false on empty `$FILE_PATH`, so the dispatch loop just emits `not_applicable` substeps and exits clean. |

**Asymmetry note.** `grouped-bash-guard` has an explicit `[ -z "$COMMAND" ] && exit 0` at line 68; `grouped-read-guard` does not have a corresponding `[ -z "$FILE_PATH" ]` bail. Both are correct end-to-end, but the asymmetry means a future child added to `grouped-read-guard` that *doesn't* handle empty `$FILE_PATH` would inherit a different contract than its bash-guard sibling. Not a defect today; recorded for clarity-axis review.

## Wrong-tool routing

The dispatchers register against specific `(event, tool)` pairs in `settings.json`. If the harness mis-routes (delivers a Read payload to `grouped-bash-guard`, etc.):

- `grouped-bash-guard` with `tool_name=Read` → silent exit. `hook_require_tool Bash` returns 0 without setting `_HOOK_ACTIVE=true`; the hook exits before the dispatcher loop.
- `grouped-read-guard` with `tool_name=Bash` → silent exit (same shape).

Verified empirically. Wrong-tool routing is a harness-side bug if it ever fires; the dispatcher is correctly defensive.

## Per-child distribution tolerance

The generator produces `for spec in "${CHECK_SPECS[@]}"; do source "$src"; done` with two guards per child:

1. `[ -f "$src" ] || continue` — skip if file is absent.
2. `if declare -F "match_$name" >/dev/null && declare -F "check_$name" >/dev/null; then CHECKS+=(...); else hook_log_substep "check_${name}_missing_match_check" 0 "skipped" 0; fi`

Empirical results:

| Scenario | Behavior | Notes |
|----------|----------|-------|
| **T13: 2 children absent** (raiz-style profile without `enforce-make`/`enforce-uv`) | **silent skip** — dispatcher runs the 6 present children normally | The `[ -f ] || continue` guard works; no traceability signal in this branch. |
| **T14: same scratch tree, dangerous command** | **block** correctly via `block-dangerous-commands` | Distribution tolerance doesn't compromise safety: catastrophic-gate child is still ordered first. |
| **T15: child file present but missing `match_/check_` functions** | **silent registration skip** (no `CHECKS+=` for that name); `hook_log_substep "check_make_missing_match_check" 0 "skipped" 0` recorded | The `declare -F` guard works; the JSONL row records the absence so the omission is traceable. |

Distribution tolerance is **structurally sound**. Both guards fire as designed. The **traceability difference** between scenarios is worth noting:
- File absent → no log signal at all (the `continue` happens before any `hook_log_*` call).
- File present but functions missing → `skipped` substep written.

If a future operator sync-mishap leaves a partial distribution, the file-absent branch is silently undetectable from the JSONL row — only `make validate`'s drift detector (`render-dispatcher.sh --check`) can catch it. Recorded for clarity-axis as "consider whether file-absent should also write a `skipped` substep for symmetry." Cost: a non-zero number of substep rows in raiz distributions where some children are intentionally absent. Tradeoff: signal noise vs missed-mishap signal. Not a fix-priority defect.

## Child error-during-source

The dispatcher's `source "$src"` runs without rc check (`grouped-bash-guard.sh:25` in the generated dispatcher: `source "$src"` is the bare statement). If a child file has a syntax error, `source` would print to stderr but continue. If the child's top-level `return`s non-zero (e.g. dependency missing, programmatic abort), `source` returns that rc — also unchecked.

| Scenario | Behavior | Severity |
|----------|----------|----------|
| **T16: child top-level returns rc=99** | **dispatcher continues silently**; later children run as if T16-child was absent | The `declare -F` guard catches "function missing" but not "function present but partially-initialized." If the child errors *after* defining `match_<name>` but *before* defining `check_<name>`, the dispatcher would still fail the `declare -F check_<name>` check and skip the registration. If both functions are defined before the error, the registration succeeds and the dispatcher invokes them on inputs they may not expect. |

Real-world likelihood: low (every child in the distribution defines its functions atomically near the top of the file, no conditional definitions). But the contract is brittle. Recorded as `hook-audit-02-child-source-rc` (P3) — propose: log a `skipped` substep with reason="source_failed" if `source $src` returns non-zero. Cheap to add; small additional traceability signal.

## `_BLOCK_REASON` global-mutation contract

Carried over from `inventory.md` "Verified findings feeding downstream axes / Robustness."

The contract: **a child's `check_<name>` function returns rc=1 ⇒ that child has written `_BLOCK_REASON`. The dispatcher reads `_BLOCK_REASON` after the loop ends and emits `hook_block "$_BLOCK_REASON"`.**

Empirical audit of all 10 child contracts (8 bash + 2 read):

| Child | `check_<name>` return-1 paths | All paths write `_BLOCK_REASON`? |
|-------|------------------------------|----------------------------------|
| `block-dangerous-commands.sh` (`check_dangerous`) | 8 patterns (rm-rf-/, rm-rf-~, rm-rf-., fork-bomb, mkfs, dd, redirect-/dev, chmod 777, sudo) | ✅ each path sets `_BLOCK_REASON` immediately before `return 1` |
| `auto-mode-shared-steps.sh` (`check_auto_mode_shared_steps`) | 1 path (auto-mode + match) | ✅ sets `_BLOCK_REASON` before `return 1` |
| `block-credential-exfiltration.sh` (`check_credential_exfil`) | 1 path | ✅ uses pre-built `$_CRED_BLOCK_REASON` constant |
| `git-safety.sh` (`check_git_safety`) | 7 paths (mirror, force, delete, force+lease, ambiguous-target, etc.) | ✅ each path sets a path-specific reason |
| `secrets-guard.sh` (`check_secrets_guard`) | ~14 paths | ✅ each path sets `_BLOCK_REASON` |
| `block-config-edits.sh` (`check_config_edits`) | 5 paths | ✅ each path sets `_BLOCK_REASON` (some via `$(_settings_reason '...')`) |
| `enforce-make-commands.sh` (`check_make`) | 1 path | ✅ sets `_BLOCK_REASON="$message"` |
| `enforce-uv-run.sh` (`check_uv`) | 1 path | ✅ sets `_BLOCK_REASON` |
| `secrets-guard.sh` (`check_secrets_guard_read`, read dispatcher) | shared with bash branch | ✅ |
| `suggest-read-json.sh` (`check_suggest_read_json`) | 1 path | ✅ sets `_BLOCK_REASON` |

**All 10 children comply with the contract today.** No gaps in current code.

But the contract is **convention, not enforced**. Empirically verified the failure mode:

- **T18: child `check_*` returns 1 without writing `_BLOCK_REASON`** → dispatcher emits `{"decision":"block","reason":""}` — a block with empty reason. The user / harness gets no explanation.

This is a **silent-defect class**. A future child writer who forgets to set `_BLOCK_REASON` ships a hook that blocks but provides no message; the smoke fixture might pass (the row records `outcome=block`) without anyone noticing the empty reason. Two plausible hardenings:

a. **Dispatcher-side validation.** After `check_$name` returns 1, assert `[ -n "$_BLOCK_REASON" ] || _BLOCK_REASON="(child '$name' returned block but did not set _BLOCK_REASON — bug in $name)"`. Defensive: the user still gets a block, with an actionable diagnostic instead of silence.

b. **Test-side validation.** Add a check to `validate-hook-headers.sh` (or a sibling validator): for every dual-mode hook with `DISPATCH-FN`, grep for `_BLOCK_REASON=` near every `return 1` in `check_<name>`. Fails CI if missing. More durable than runtime check.

Recommendation: **both**. (a) is cheap (3 lines in each dispatcher) and gives runtime safety; (b) is the durable fix. Recorded as `hook-audit-02-block-reason-contract` (P2).

**T17 (top-level `_BLOCK_REASON` write doesn't leak):** verified — both dispatchers reset `_BLOCK_REASON=""` before the dispatch loop (`grouped-bash-guard.sh:76`, `grouped-read-guard.sh:51`). A child that writes `_BLOCK_REASON` at file top-level (during sourcing) is correctly overwritten by the reset. Right design.

## Order-after-block fall-out

The dispatcher's contract: when a child blocks, every later child gets a `skipped` substep recorded; the dispatcher emits `hook_block` and exits.

| Scenario | Behavior |
|----------|----------|
| **T19: `rm -rf /` triggers `dangerous` block** | `make` (replaced with a probe child that would also block) **does not run** (no MAKE_MATCH_RAN / MAKE_CHECK_RAN stderr); dispatcher emits the dangerous-block decision JSON and exits |

Verified the break-on-first-block + `skipped`-substep emission paths in both dispatchers. Working as designed.

**Implication:** when multiple children would block on the same input, only the first wins. This is intentional (block decisions are terminal) but worth recording: if order changes in `dispatch-order.json`, the *winning block reason* changes too. Today's order (`dangerous` first) means catastrophic patterns get the loudest message; if `make` were ever moved before `dangerous`, an `rm -rf /` issued through a `pytest --do-bad-thing` invocation would get a "use make" message instead of a "rm -rf /" message. Recorded for clarity-axis as ordering rationale.

## Adversarial input shapes

Limited probing (matches `01-standardized/robustness.md`'s scope — full fuzzing is out of audit scope). Tested:

| Shape | grouped-bash-guard | grouped-read-guard |
|-------|--------------------|--------------------|
| Embedded ` ` in command (T8) | silent pass; matchers ignore NUL | n/a |
| 8KB command (T9) | silent pass on `echo xxx...` (no danger token); the 70-LoC `_strip_inert_content` walk is `O(len)` per `00-shared/robustness.md` micro-bench so 8KB pays ~9ms — still under any budget concern | n/a |
| Missing `tool_name` (T12) | silent exit (`hook_require_tool` matches against empty `$_HOOK_INIT_TOOL_NAME`, no match → exit 0) | same |

Same caveats as the standardized-hook robustness section: unicode normalization, control characters beyond NUL, and very long inputs (>100KB) are not covered. The toolkit's hooks are guardrails, not security perimeters; full fuzzing is for a future audit if the threat model changes.

## Generator drift defenses

`scripts/hook-framework/render-dispatcher.sh --check` (run by `make validate`) compares the on-disk `lib/dispatcher-grouped-*.sh` files against a fresh render. Any drift between `dispatch-order.json` + child `CC-HOOK` headers and the generated files fails CI.

Tested by inspection of the generator (`render-dispatcher.sh:126-130`). Drift detection covers:
- Child added to `dispatch-order.json` without re-rendering.
- Child renamed in headers (`DISPATCH-FN`) without re-rendering.
- Manual edit to a generated file.

Not tested at runtime here (the generator's own test suite is `tests/fixtures/hook-validator/v8-*` and `v11-stale`, exercised by `make test`). Generator drift is a **build-time** robustness concern; runtime can't recover from a stale generated file. The drift check is the right layer.

## Verified findings feeding downstream axes

### Performance

- The malformed-stdin fail-closed branch fires before any child source loop, so its cost is just `hook_init` + the block-emit path. ~7ms wall-clock per `01-standardized/performance.md`'s `hook_init` floor. No N-children multiplier applies. Dispatcher robustness adds no perf cost over standardized hooks.

### Testability

- **Dispatcher-level block fixtures don't exist.** The four scenarios T13–T19 above are scratch-tree probes, not fixtures under `tests/hooks/fixtures/`. They run via the throwaway scripts in `output/claude-toolkit/sessions/dispatcher-*-probe.sh`. Whether to convert any of these to permanent fixtures is `02-dispatchers/testability.md`'s call. The `_BLOCK_REASON`-empty-on-block defect (T18) is the most defensible candidate — a regression there would silently degrade UX and is otherwise undetectable.
- **Probing dispatchers from inside Claude Code triggers the dispatchers themselves.** Bash commands containing `rm -rf /tmp/...`, fixture files containing credential-shaped strings, and even commit messages with `rm -rf` are caught by the very dispatchers being audited. The workaround documented in the prior session's handoff (write probe scripts to files, run via `bash file.sh`) is what made the empirical probing in this section feasible. Captured under `hook-audit-01-test-token-allowlist` (P2).

### Clarity

- Three robustness-derived inputs to `clarity.md`:
  1. The `_BLOCK_REASON` mutation contract is convention, not enforced. Two-pronged hardening (dispatcher-side fallback + validator) recommended; clarity weighs whether to formalize the contract in `relevant-toolkit-hooks.md` §X.
  2. The `[ -z "$COMMAND" ] && exit 0` asymmetry between dispatchers (bash has it, read doesn't) is a minor code-shape question — does the read dispatcher want symmetric early-bail, or is the children-handle-empty contract preferred?
  3. File-absent vs functions-missing produce different traceability rows. Symmetric "skipped (source_missing)" + "skipped (functions_missing)" rows would tighten the JSONL signal at the cost of noise on intentionally-thin distributions.

## Hooks flagged for follow-up

- `hook-audit-02-block-reason-contract` (P2) — enforce/diagnose the `rc=1 ⇒ _BLOCK_REASON set` contract. Two parts: dispatcher-side fallback message + validator-side static check. Defended by T18.
- `hook-audit-02-child-source-rc` (P3) — log a `skipped (source_failed)` substep when `source $src` returns non-zero. Defended by T16.
- `hook-audit-00-empty-stdin-fail-closed` (P3) — `hook_init` should treat "empty `_HOOK_INIT_TOOL_NAME` after rc=0 jq" as malformed for PreToolUse events. Lib-level fix; dispatchers inherit.
- Existing `hook-audit-00-malformed-stdin-fixtures` (P0) covers the dispatcher malformed-stdin fixture work.

## Confidence

- **High confidence** in the malformed-stdin and missing-field behavior table — every cell verified end-to-end with shaped fixtures.
- **High confidence** in the distribution-tolerance findings (T13–T15) — scratch-tree probes ran clean and the file-absent / functions-missing branches both fired exactly once.
- **High confidence** in the `_BLOCK_REASON` contract audit — every child's `check_<name>` return-1 paths were grepped and visually verified; the empty-reason defect (T18) reproduces deterministically.
- **Medium confidence** that no other dispatcher-level robustness gaps exist. The probe set covered: malformed JSON, empty stdin, missing fields, wrong tool name, child file absent, child functions missing, child top-level rc!=0, child writes `_BLOCK_REASON` at top-level, child blocks without writing `_BLOCK_REASON`, multi-child block ordering, embedded NUL, 8KB long input, missing `tool_name`. Not covered: race conditions (two dispatchers firing concurrently), filesystem-level child-file modification mid-source, signal handling during dispatch loop. Captured as adversarial-fuzz scope.

## Open

- **Adversarial-input fuzzing** — same scope/decision as `01-standardized/robustness.md`. Not in this audit.
- **Concurrent dispatch.** When two PreToolUse events fire near-simultaneously (rare but possible if the harness ever parallelizes), do the two dispatcher processes interfere via shared state? The dispatchers don't write to any shared file beyond per-process JSONL rows; lib globals are per-process. Theoretically clean, not empirically tested.
- **Generator-side fuzzing.** `dispatch-order.json` accepts arbitrary strings as child names; `parse-headers.sh` validates `DISPATCH-FN: <dispatcher>=<stem>` shape. A malformed entry (e.g. shell-metachar in `<stem>`) would land in the generated `CHECK_SPECS=("<malicious>:..." ...)` array. The current entries are alphanumeric-with-underscore so the surface is unused, but recorded as a clarity/security note for the generator's input validation.
