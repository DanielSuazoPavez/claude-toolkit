---
category: 02-dispatchers
axis: inventory
status: drafted
date: 2026-05-02
---

# 02-dispatchers — inventory

Catalog of the 2 dispatcher entrypoints in `.claude/hooks/` plus their 2 generated `lib/dispatcher-grouped-*.sh` companions: events, children, generation source, V20 budget vs current observed time, dispatch-loop shape. Per-axis reports (performance, robustness, testability, clarity) reference this file rather than re-deriving the fan-out structure.

**Convention:** "child" = one entry in `CHECK_SPECS` for a dispatcher. Every child is a standardized hook (`01-standardized/`); reviewing the child's check-body lives there. This category reviews the **dispatch shell** — the bash startup, the source loop, the for-loop driver, the fall-out logging — and per-event totals (loader + N children).

The two `lib/dispatcher-grouped-*.sh` files are **generated** (`make hooks-render` ⇐ `scripts/hook-framework/render-dispatcher.sh` ⇐ `lib/dispatch-order.json` + `CC-HOOK` headers in each child). They are not authored by hand; treat them as one logical unit with their entrypoint.

## Members

| Hook | Event(s) | Children | LoC (entry+gen) | Lib floor (predicted) | V20 (smoke) |
|------|----------|---------:|---------------:|----------------------:|-------------|
| `grouped-bash-guard.sh` (+ `lib/dispatcher-grouped-bash-guard.sh`) | PreToolUse(Bash) | 8 | 117 + 31 | ~2.5ms (entrypoint) + variable child sourcing | **warn (121ms; ~116ms hook work)** |
| `grouped-read-guard.sh` (+ `lib/dispatcher-grouped-read-guard.sh`) | PreToolUse(Read) | 2 | 89 + 25 | ~2.5ms (entrypoint) + variable child sourcing | **warn (50ms; ~45ms hook work)** |

V20 numbers are from a single smoke run on this machine, this session — the same shape as `01-standardized/inventory.md`'s V20 column. Variance follows the documented ~1.34× p95/p50 ratio (`00-shared/performance.md`); these values can drift ±2–3ms on a quiet box and more under load.

Neither dispatcher declares `PERF-BUDGET-MS`. Both inherit the framework default `scope_miss=5, scope_hit=50` (`validate.sh:592–596`). The 5ms `scope_miss` budget is structural-mismatch with reality: the cheapest possible dispatcher firing pays bash startup (~5ms) + `hook-utils.sh` parse (~2.5ms) + `hook_init` (~5ms) + N child `source` calls + the for-loop overhead — already past 5ms before any check body runs. Both dispatchers warn on every `make check`.

This is the same V20-budget mismatch flagged for the no-op loggers in `01-standardized/performance.md` ("Loggers paying ~10ms for ~0 lines of logic"), but a different shape: loggers warn because they have *no* check body; dispatchers warn because they have *N* check bodies and a multiplier. The fix shape differs — recorded under "Verified findings feeding downstream axes" below.

## grouped-bash-guard

PreToolUse(Bash). The Bash hot path. Replaces ~5–8 standalone Bash hooks (one fork each) with one fork that sources the children inline.

**Children** (in `CHECK_SPECS` order, from `lib/dispatch-order.json`):

| # | Child fn stem | Source file | What it gates | Match cost | Check cost (block fixture, from `01-standardized/performance.md`) |
|---|---------------|-------------|---------------|------------|------------------------------------------------------------------:|
| 1 | `dangerous` | `block-dangerous-commands.sh` | rm -rf /, fork bombs, mkfs, dd, sudo | pure-bash regex against `$COMMAND`; no fork | ~31ms |
| 2 | `auto_mode_shared_steps` | `auto-mode-shared-steps.sh` | under `permission_mode=auto`, every `permissions.ask` entry (git push, gh pr create, curl, wget) | gated on `$PERMISSION_MODE=auto`; cheap exit otherwise | ~16ms |
| 3 | `credential_exfil` | `block-credential-exfiltration.sh` | credential-shaped tokens (GitHub/GitLab/Slack/AWS/OpenAI/Anthropic) in command line | pure-bash regex against precompiled `_REGISTRY_RE__credential__raw` | ~10ms |
| 4 | `git_safety` | `git-safety.sh` | `git push --force` to protected, `git commit` on protected, hard reset to remote | pure-bash regex; `check` runs `git rev-parse` (one fork) | ~26ms |
| 5 | `secrets_guard` | `secrets-guard.sh` | reads of `.env`, credential files, `env`/`printenv`, `gpg --export-secret-keys` | pure-bash regex against precompiled `_REGISTRY_RE__credential__raw` | ~26ms |
| 6 | `config_edits` | `block-config-edits.sh` | Bash writes (`>>`, `tee`, `sed -i`, `mv`) to shell/SSH/git config files | `_strip_inert_content` + alternation regex | ~15ms |
| 7 | `make` | `enforce-make-commands.sh` | bare pytest/ruff/uv/docker that should go through a `make` target | pure-bash token check (`pytest`, `ruff`, `uv`, `docker`) | ~10ms |
| 8 | `uv` | `enforce-uv-run.sh` | bare `python` outside an active virtualenv | pure-bash regex on stripped command | ~13ms |

**Order rationale** (from the entrypoint header): `dangerous` first (catastrophic gate, cheap match skips most benign Bash); `auto_mode_shared_steps` second (cheap mode gate); `credential_exfil` third (cheap raw-target match, blocks in-flight exfiltration before any other Bash check could leak through); then the bigger check bodies (`git_safety`, `secrets_guard`, `config_edits`); finally the workflow-enforcement checks (`make`, `uv`).

**Lib stack at dispatch time** (under one bash process, `_<NAME>_SOURCED=1` guards prevent re-sourcing):

- `hook-utils.sh` (sourced by entrypoint at line 58) → transitively pulls `hook-logging.sh`
- `detection-registry.sh` (first child to source it triggers the load — `auto_mode_shared_steps` at child #2; `credential_exfil`, `secrets_guard`, `config_edits` reuse via guard)
- `settings-permissions.sh` (loaded by `auto_mode_shared_steps` at child #2; reused by no other Bash child)

Across all 8 children, the dispatcher sources the registry's two heavy loaders **once each**. Standalone, the same 8 hooks would each pay their own lib load — the dispatcher's structural win.

**Dispatch-loop shape** (`grouped-bash-guard.sh:84–115`):

```
for i in "${!CHECKS[@]}"; do
    name=${CHECKS[$i]}
    start_ms=$(_now_ms)
    if ! match_$name; then
        hook_log_substep "check_${name}" Δ "not_applicable" 0
        continue
    fi
    check_$name
    rc=$?
    Δ=$(( $(_now_ms) - start_ms ))
    if [ $rc -eq 1 ]; then
        hook_log_substep "check_${name}" Δ "block" 0
        BLOCK_IDX=$i
        break
    fi
    hook_log_substep "check_${name}" Δ "pass" 0
done
# If blocked: emit "skipped" substeps for every check after BLOCK_IDX, then hook_block.
```

Substep outcomes recorded in the JSONL row: `pass | block | not_applicable | skipped`. Vocabulary matches `relevant-toolkit-hooks.md` §5.

**Fixture (smoke):** `dispatches-clean-pwd.json` — `tool_input.command = "pwd"`. Hits `match_dangerous` true (the `match_` regex is broad on purpose — false positives OK), `check_dangerous` returns 0; remaining 7 checks all run match_ → false → `not_applicable`. End-to-end smoke wall-clock: 121ms (this run, single sample).

## grouped-read-guard

PreToolUse(Read). The Read hot path. Replaces 2 standalone Read hooks (`secrets-guard` for sensitive files, `suggest-read-json` for large `.json` reads) with one fork.

**Children** (in `CHECK_SPECS` order):

| # | Child fn stem | Source file | What it gates | Match cost | Check cost (from `01-standardized/performance.md`) |
|---|---------------|-------------|---------------|------------|---------------------------------------------------:|
| 1 | `secrets_guard_read` | `secrets-guard.sh` | reads of `.env`, credential files, SSH keys | pure-bash regex against `$FILE_PATH` | (folded into `secrets-guard ~26ms` — Read branch is cheaper than Bash branch) |
| 2 | `suggest_read_json` | `suggest-read-json.sh` | large `.json` reads (suggests `read-json` skill) | file-size stat | ~15ms |

**Order rationale** (from the entrypoint header): security check (`secrets_guard_read`) before suggestion check (`suggest_read_json`) so a sensitive `.json` can't bypass the secrets gate via the suggestion's short-circuit.

**Lib stack at dispatch time:**

- `hook-utils.sh` + `hook-logging.sh` (entrypoint)
- `detection-registry.sh` (loaded by `secrets_guard_read` at child #1)

`suggest_read_json` adds no libs.

**Dispatch-loop shape:** identical to `grouped-bash-guard` (`grouped-read-guard.sh:56–87`). Same `match_` → `check_` → substep-outcome vocabulary, same skipped-after-block fall-out logging.

**Fixture (smoke):** `dispatches-clean-read.json` — `tool_input.file_path` of an ordinary file (not `.env`, not `.json`). Both children match → false → `not_applicable`. End-to-end smoke wall-clock: 50ms (this run, single sample).

## Pre-dispatch input parsing

Both dispatchers do their own `hook_get_input` calls before sourcing the generated `lib/dispatcher-*.sh`:

- `grouped-bash-guard.sh:67–74`: parses `.tool_input.command` into `$COMMAND`; bails early if empty; parses `.permission_mode` into `$PERMISSION_MODE` (consumed by `match_auto_mode_shared_steps`).
- `grouped-read-guard.sh:44`: parses `.tool_input.file_path` into `$FILE_PATH`.

These reads happen **once per dispatcher firing**. Children read `$COMMAND`/`$FILE_PATH` directly — they do not re-parse stdin. This is the dispatcher's second structural win (after lib reuse): one stdin-extract `jq` fork per event, regardless of child count. Compared to N standalone hooks that each call `hook_init` and `hook_get_input` separately.

## Generated dispatcher files

`lib/dispatcher-grouped-bash-guard.sh` (31 LoC) and `lib/dispatcher-grouped-read-guard.sh` (25 LoC). Header on both: `=== GENERATED FILE — do not edit ===`. Source: `lib/dispatch-order.json` + per-hook `CC-HOOK: DISPATCH-FN: <dispatcher>=<stem>` headers in each child. Generator: `scripts/hook-framework/render-dispatcher.sh`. Regenerate: `make hooks-render`. Drift detector: `bash scripts/hook-framework/render-dispatcher.sh --check` (run by `make validate`).

Both files are structurally identical except for the `CHECK_SPECS` array — same source loop, same `declare -F` registration gate, same `hook_log_substep` skipped-fallback when a child file is missing functions.

**Why generated, not authored:** keeps the per-dispatcher structural decisions (child order) in one declarative location (`dispatch-order.json`) instead of two parallel arrays in two hook files. Lets the `parse-headers.sh` infrastructure validate that every child declares `DISPATCHED-BY: <dispatcher>(...)` and `DISPATCH-FN: <dispatcher>=<stem>` headers — a hook that says it's dispatched but isn't in the order file (or vice versa) fails validation.

**Distribution tolerance:** the generated `for spec in CHECK_SPECS` loop probes each child file with `[ -f "$src" ] || continue`. Children missing from the current distribution (e.g. raiz ships without `enforce-make-commands.sh` / `enforce-uv-run.sh`) are silently skipped. The `declare -F match_<name>` / `declare -F check_<name>` guard skips children that source-load but fail to declare both functions, recording a `skipped` substep so the absence is traceable.

## Per-event hot-path summary (dispatcher view)

Refines the `00-shared/inventory.md` per-event table with dispatcher fan-out detail:

| Event | Dispatcher | Children fired | Lib loads pooled | Per-event jq forks (smoke) |
|-------|-----------|---------------:|-------------------|---------------------------:|
| PreToolUse / Bash | `grouped-bash-guard` | up to 8 | hook-utils + hook-logging (1×); detection-registry (1×, by child #2); settings-permissions (1×, by child #2) | 1× `hook_init` consolidated jq + 8× `_now_ms` (no fork) + 8× `hook_log_substep` jq |
| PreToolUse / Read | `grouped-read-guard` | up to 2 | hook-utils + hook-logging (1×); detection-registry (1×, by child #1) | 1× `hook_init` consolidated jq + 2× `_now_ms` (no fork) + 2× `hook_log_substep` jq |

(`hook_log_substep` builds a JSONL row with `jq -c -n` each call. Under `CLAUDE_TOOLKIT_TRACEABILITY=1` it writes; under traceability=0 the call is bumped through a feature gate and most of the cost evaporates — see `00-shared/inventory.md` `hook-logging.sh` notes.)

This is the structural baseline for `02-dispatchers/performance.md`. The probe needs to attribute the 121ms / 50ms totals to: bash startup floor (~5ms) + hook-utils parse (~2.5ms) + `hook_init` (~5ms) + N × child source-time + N × match_ + (1 × check_ where match_ true) + dispatch-loop overhead (`_now_ms` × 2N + array iteration).

## V20 budget vs reality

The V20 default budget (`scope_miss=5`) was set for standardized hooks (one check body, one decision). Both dispatchers warn on every `make check` because their inherent shape — N children sourced inside a single bash process — cannot fit in 5ms even with the cheapest possible children. The handoff captured this; numbers above quantify it.

Three plausible directions for the implement phase, ordered by churn:

1. **Per-dispatcher `PERF-BUDGET-MS` headers.** Cheapest fix. Set `scope_miss=150, scope_hit=200` for `grouped-bash-guard` and `scope_miss=60, scope_hit=120` for `grouped-read-guard` based on this data. Buys headroom for normal variance; lets V20 keep flagging actual regressions. Concrete numbers fall to `02-dispatchers/performance.md` after the per-child probe.
2. **Outcome-aware budget split for dispatchers.** V20 already splits per outcome. A dispatcher's `pass` outcome (no child blocked) is the *expected* path; `block` is rare. The default `scope_hit=50` already accommodates a one-off block. The miss-path budget needs to grow to N-children scale.
3. **Source children at session start, not at dispatch time.** Biggest churn. Move the `for spec in CHECK_SPECS; source ...` loop into a once-per-session lib load, then have the dispatcher only run the `for i in CHECKS` loop. Cuts the per-event source cost. Tradeoff: loses the per-fork distribution tolerance (children missing from the current distribution would have to be probed at load time instead). Recorded for `clarity.md` to weigh against the current shape.

Recommended first move: option 1, gated on the per-child probe in `02-dispatchers/performance.md` producing a defensible number.

## Verified findings feeding downstream axes

### Performance

- **Per-child source cost is the open question.** The 121ms / 50ms totals are end-to-end; the dispatcher's `for spec in CHECK_SPECS; do source ...` loop pays a `source` per child even when the child's libs are already loaded (the function definitions still need to be parsed). Subtract the lib floor from `00-shared/performance.md` and the per-child check-body costs from `01-standardized/performance.md`'s table to estimate per-child parse cost. Probe-based isolation falls to `02-dispatchers/performance.md`.
- **`git-safety`'s `git rev-parse` runs once per Bash dispatch under the current shape** — only when `match_git_safety` returns true. For the smoke fixture (`pwd`), `match_git_safety` returns false → no fork. For real-session, `match_git_safety` returns true on any `git ...` command → one fork per such dispatch. The "cache the rev-parse across the dispatcher's lifetime" idea from `01-standardized/clarity.md` Proposal 6 only matters if `git-safety` is the only consumer. Confirmed at the inventory level: it is. The optimization is real but small (one fork saved per Bash dispatch that happens to be `git ...`); whether it's worth the dispatcher-state-globals it requires is a `clarity.md` call.
- **The 121ms total for `grouped-bash-guard` matches `01-standardized/performance.md`'s child cost arithmetic.** Pass fixture (`pwd`): bash floor (~5ms) + hook-utils parse (~2.5ms) + `hook_init` (~5ms) + 8× child sources × ~2–4ms each + 8× match_ pure-bash (~0.5ms each) + 1× check_dangerous (~31ms but the pass-path is cheap, ~5ms) + 8× `hook_log_substep` jq forks (~5ms each) ≈ 80–130ms. The 121ms sample lands in that band. Probe-based attribution remains the perf-axis job.

### Robustness

- **Distribution tolerance is structurally sound.** Both `[ -f "$src" ] || continue` and `declare -F match_<name>` / `declare -F check_<name>` guards are in the generator — every distribution gets the same protection. The skipped-substep emission means absences are traceable in the JSONL row, not silently dropped.
- **Order-dependent block fall-out is correctly logged.** Both dispatchers emit `skipped` substeps for every check after a `BLOCK_IDX`. The JSONL row shows the full intended sequence even when a block short-circuits the rest. Verified against `grouped-bash-guard.sh:108–114` and `grouped-read-guard.sh:80–86`.
- **`_BLOCK_REASON` is a global mutated by children.** Each `check_<name>` writes `_BLOCK_REASON` on block; the dispatcher reads it after the loop ends. No re-entry guards. If a child both writes and reads `_BLOCK_REASON` (none currently do), the contract would silently break. Recorded for `robustness.md` to assess against the actual children.

### Testability

- **Smoke fixtures exist for both dispatchers** — `dispatches-clean-pwd` (bash) and `dispatches-clean-read` (read). One pass-path fixture each. Block-path coverage at the dispatcher level (does the for-loop correctly emit `block` then `skipped` substeps?) is not in the fixture set today; child-level block fixtures are tested through standalone fixtures of each child hook. Whether dispatcher-level block fixtures should exist at all (the for-loop is generated and dispatcher-agnostic) is a `testability.md` call.
- **In-process multi-case testing has the same structural blocker as standardized hooks.** `hook_block` ends in `exit 0`; testing dispatch-order behavior across multiple commands requires N forks for N cases. The testability follow-up from `01-standardized/testability.md` would benefit dispatchers more than any single hook because the dispatcher's case count is naturally large (N children × M command shapes).

### Clarity

- **Three structural decisions land in `02-dispatchers/clarity.md`:**
  1. Should the source loop move to session-start instead of dispatch time? (Buys per-event time, costs distribution tolerance.)
  2. Should `git-safety`'s `git rev-parse` be hoisted into a dispatcher-level cache? (Saves one fork per Bash dispatch on `git ...` commands; adds dispatcher-level state.)
  3. Should children mutate `_BLOCK_REASON` directly, or should `check_<name>` return a (rc, reason) pair? (Today's contract is "rc=1 ⇒ child wrote `_BLOCK_REASON`"; a stricter return-value contract would un-couple the children from the dispatcher's globals.)

## Still-open questions (scope for downstream axes, not resolved here)

- **Performance:** what is the per-child source cost in the dispatcher's loop, after subtracting lib floors and check-body costs already attributed in earlier categories? (`02-dispatchers/performance.md`.)
- **Robustness:** does any child ever read `_BLOCK_REASON` (vs only writing it)? Audit the 10 children's bodies. (`02-dispatchers/robustness.md`.)
- **Testability:** is dispatcher-level block-fixture coverage warranted, given the for-loop is generated and identical between both dispatchers? (`02-dispatchers/testability.md`.)
- **Clarity:** session-start sourcing vs dispatch-time sourcing — quantify the per-event win against the distribution-tolerance loss. (`02-dispatchers/clarity.md`.)
