---
category: 01-standardized
axis: clarity
status: drafted
date: 2026-05-02
---

# 01-standardized — clarity

Code shape, naming, where logic lives. Like `00-shared/clarity.md`, this axis is opinion-shaped — the goal isn't to prescribe a "right" structure but to evaluate the proposals queued by the other axes (inventory, performance, robustness, testability) and recommend keep / move / reshape.

## Proposals from other axes

Seven concrete proposals were flagged. Each is evaluated below against what the prior axes measured.

### Proposal 1 — Enforce the `match_*`/`check_*` superset invariant (from robustness)

**Background.** The dual-mode pattern is documented in `.claude/docs/relevant-toolkit-hooks.md` (§3) with explicit semantics:

| | What `match_` says | What happens |
|---|---|---|
| **False positive** | `match_` says yes, `check_` runs, `check_` decides no-op | Acceptable — same work we'd do in standalone mode |
| **False negative** | `match_` says no, `check_` is skipped, a guard that should have fired didn't | **Bug** — safety regression |

The framing matches the user's: `match_` answers "is this input worth running `check_` on?", `check_` answers "does this input deserve the action?". The invariant is **`check_acts(x) ⇒ match_says_yes(x)`** for all inputs `x` — the predicate's set of true-returns must be a superset of the check's act-set.

The doc even calls out the right defensive posture: *"when a check needs normalization that the match can't cheaply replicate (example: `block-config-edits` normalizes `~` to `$HOME` before comparing paths), the match stays deliberately broad."*

**The block-dangerous-commands quote-evasion gap (`robustness.md`) is a violation of an already-codified convention, not a missing one.** The doc says the predicate must stay broad enough; the predicate excludes `'`/`"` from its preceding-character alternation; `check_dangerous` strips quotes and would block `echo 'rm -rf /'` if reached. Predicate too narrow → false negative → safety regression.

**Pros of formalizing the invariant in test:**
- Catches the same class of bug across all 9 dual-mode hooks at fixed cost. Today we caught it in `block-dangerous-commands` only because robustness probed quote-wrapping by hand.
- The Shape A test layer recommended by `testability.md` (`hook-audit-01-shape-a-match-check-pairs`) is the natural test vehicle. For each dual-mode hook, generate inputs that `check_<name>` would block, assert `match_<name>` returns true on each. Cost: ~0ms per case.
- Forces a rule that's already documented to be load-bearing.

**Cons:**
- Requires generating inputs the check would block. For hooks with registry-driven check bodies (`block-credential-exfiltration`, `secrets-guard`, `block-config-edits`), the input set is the registry's pattern alternation — straightforward. For inline-policy hooks (`block-dangerous-commands`, `git-safety`), the input set is a curated list of "known dangerous patterns" — still straightforward but each hook needs its own list.
- Doesn't catch the dual case (false positives in the predicate that *don't* lead to false negatives). That's fine — false positives are explicitly acceptable per the doc.

**Cross-axis impact:**
- Robustness: **directly closes** the class of bug found in `block-dangerous-commands`. Catches it for the other 8 dual-mode hooks too.
- Testability: **enables** the Shape A test layer `testability.md` recommended. The invariant is the *thing* the Shape A tests assert.
- Performance: zero impact on `make test` wall (Shape A is ~0ms per case).

**Recommendation: formalize.** Update `relevant-toolkit-hooks.md` §3 to name the invariant explicitly (`check_acts(x) ⇒ match_returns_true(x)`) and call it the "superset invariant." Wire the Shape A test layer to assert it across all 9 dual-mode hooks. Cost: ~1 paragraph in the doc, ~50 LoC of test-input generators (some per-hook, the registry-driven ones share).

This is the highest-leverage clarity recommendation in the category — it converts a documented convention into an enforced one and closes a real gap.

### Proposal 2 — Refactor `approve-safe-commands` to expose `match_*`/`check_*` (from testability)

**Background.** `approve-safe-commands` is 202 LoC and is the only non-pure-logger, non-fire-once hook in the category that doesn't follow the dual-mode pattern. Its `main` is one function: read command → split on shell separators → strip env-var prefixes per subcommand → reject on subshells/backticks/redirects → match each subcommand against the precompiled allow regex → approve or fall through.

**Pros:**
- Brings the hook in line with the documented dual-mode convention. The "rule is split predicate from check" hits 10/13 hooks if this lands.
- Makes the hook dispatcher-ready. There's no PermissionRequest dispatcher today, but if/when one emerges (`grouped-permission-request-guard`), this hook is already shaped for it.
- The current `main` does conflate "is this approval candidate" (cheap predicate territory: tool=Bash, command non-empty, no subshell/backtick/redirect tokens) with "should we approve" (the per-subcommand allow-regex match). Splitting is a natural seam.

**Cons:**
- 202 LoC is moderate. Refactoring adds risk against test coverage that's solid (43 cases).
- PermissionRequest is the only event today fired by exactly one hook. Dispatcher-readiness is a hedge against a hypothetical future.
- The hook's logic doesn't have a sharp false-positive-vs-false-negative tradeoff — for PermissionRequest, "fall through" means the user gets prompted, which is the safe default. The dual-mode pattern's false-negative-is-a-bug framing applies less directly to PermissionRequest hooks.

**Cross-axis impact:**
- Testability: **slight win** — opens the hook to the Shape A test layer. Current Shape B coverage is already strong (43 cases).
- Robustness: unchanged — the existing `main` already implements the right rejection logic.
- Performance: no change. Same forks, same regex.

**Recommendation: keep as-is, but document why.** The convention applies cleanly to PreToolUse safety hooks (where false negatives are bugs) but maps awkwardly to PermissionRequest (where "fall through" is the safe default). Add a note in `relevant-toolkit-hooks.md` §3 — something like *"the dual-mode pattern is required for PreToolUse hooks dispatched by `grouped-bash-guard` / `grouped-read-guard`. PermissionRequest and SessionStart hooks may use the pattern when the predicate-vs-check split is natural, but it is not required."*

Cost: ~3 lines in the doc. Refactoring 202 LoC of working code is not justified by the current evidence.

### Proposal 3 — Split `secrets-guard` (496 LoC) by branch (from inventory)

**Background.** `secrets-guard.sh` is the largest hook at 496 LoC. It has three branches: Grep (standalone PreToolUse), Bash (dispatched by `grouped-bash-guard`), Read (dispatched by `grouped-read-guard`). The three branches share inline command-shape policy (env-listing detection, credential-shaped `printenv` argument detection) plus the registry-match wrappers.

**Pros:**
- Three single-responsibility files would each be ~150–200 LoC. More navigable.
- Each file would have a clear "this guards the X tool against Y class of leak" framing.

**Cons:**
- The shared inline policy (env-listing, cred-shaped printenv targets) appears in two of the three branches (Bash and Read). Splitting forces one of:
  1. Duplicate the policy across files (two places to change when adding a new env-listing pattern).
  2. Extract the policy into a shared lib (`lib/secrets-policy.sh` or similar). Adds a fourth file just to hold the shared part.
  3. Have one file source another (`secrets-guard-grep.sh` sources `secrets-guard-shared.sh`). Same as option 2 with worse naming.
- The shared dispatch fan-out also gets weirder. Today `secrets-guard.sh` is sourced by both `grouped-bash-guard` and `grouped-read-guard`; the dispatcher's `CHECK_SPECS` array points at it. Splitting would change the dispatcher generator inputs.

**Cross-axis impact:**
- Performance: neutral (same lib loads, same parse cost).
- Robustness: **slight risk** — the consolidated file's three branches share validation code that's been tested as a unit. Splitting opens the question of which split owns which test cases.
- Testability: 73 Shape B cases would need to be re-mapped across the new files. Editorial churn, no semantic change.

**Recommendation: keep as one file.** The 496 LoC reads as a lot, but it's coherent: one responsibility ("block reaches towards sensitive resources") with three tool-specific branches. The shared inline policy is the load-bearing reason — splitting makes it worse, not better. Add a section header / table-of-contents comment block at the top to ease navigation. ~10 LoC of comments, no functional change.

### Proposal 4 — Split `block-config-edits` (339 LoC) by branch (from inventory)

**Background.** `block-config-edits.sh` is the second-largest hook. Two branches: Write|Edit (standalone) and Bash (dispatched). Both check against the `kind=path` registry; differ in input shape (file_path vs command).

**Pros:**
- Two smaller files, each branch-specific.

**Cons:**
- Same shared-policy issue as secrets-guard: both branches use the same registry alternation regex and the same response logic ("hook_ask for `.claude/settings*.json`, hook_block under auto-mode, hook_block for everything else").
- Smaller absolute size (339 vs 496) means less navigation pain to begin with.

**Cross-axis impact:** identical to Proposal 3.

**Recommendation: keep as one file.** Smaller than secrets-guard and the same conclusion holds — coherent responsibility, shared policy is load-bearing. No section-header addition needed; the file already has clear branch markers.

### Proposal 5 — Abstract the loggers into a shared helper (from inventory)

**Background.** The two loggers (`log-tool-uses` 30 LoC, `log-permission-denied` 32 LoC) are mostly comments. Their actual code (excluding comments and `set -uo pipefail`) is **5 lines, identical except for one string literal:**

```bash
source "$(dirname "$0")/lib/hook-utils.sh"
hook_init "log-tool-uses" "PostToolUse"      # or: hook_init "log-permission-denied" "PermissionDenied"
TOOL_NAME=$(hook_get_input '.tool_name')
_HOOK_ACTIVE=true
exit 0
```

**Options to consider:**
1. **Keep as-is.** Two near-identical files, each fully self-contained.
2. **Extract a `hook_register_as_logger NAME EVENT` function in `hook-utils.sh`** that wraps the four lines. Hook files become 1-line bodies.
3. **Generate logger files from a template.** New abstraction (codegen) for two files; not worth introducing.

**Pros of option 2:**
- Pins the "logger pattern" as a named convention. New loggers (if any emerge) would call the helper instead of copying.
- Reduces near-duplication.

**Cons of option 2:**
- Adds a function to `hook-utils.sh` (parsed by every hook firing) for a pattern only 2 hooks use. Minor parse-cost addition (~10µs per hook firing).
- The 5-line body is already minimal. Compressing further makes the hook file content 1 line, which is *less* clear than the explicit 5 — a reader has to follow the helper to understand what fires.
- Two near-identical 5-line bodies aren't really duplication — they're the canonical shape, and divergence between them would be a *bug*, not a feature.

**Cross-axis impact:**
- Performance: option 2 adds ~10µs per hook firing across all 17 hooks (parse cost of the helper).
- Robustness: option 2 hides the EXIT-trap reliance. Today the 5 lines make it clear the logger does nothing but invoke `hook_init` and rely on the trap; option 2 hides that chain.
- Testability: neutral. Both shapes are testable with the same fixtures.

**Recommendation: keep as-is.** Two 5-line files are the right size. Treating "logger" as a named convention via doc rather than helper is cheaper. Add a one-line note in `relevant-toolkit-hooks.md` that "pure logger hooks (PostToolUse, PermissionDenied) are 5-line files: `source` → `hook_init` → `hook_get_input '.tool_name'` → set `_HOOK_ACTIVE=true` → `exit 0`. The EXIT trap in `hook-logging.sh` writes the JSONL row." Cost: ~3 lines.

### Proposal 6 — Where does the cost live for the 26-31ms check-body cluster (from performance)

**Background.** Three hooks measured ~26–31ms check-body cost in the per-hook probe: `block-dangerous-commands` (~31ms, minimal lib stack but ~31ms of inline regex + decision JSON build), `git-safety` (~26ms, includes a `git rev-parse` fork), `secrets-guard` (~26ms, registry-driven path matching + inline command-shape policy).

The performance axis flagged the cluster as "code-shape signal" without prescribing action. Clarity's job: is the cost in the right place?

**Per-hook evaluation:**

- **`block-dangerous-commands`:** the ~31ms is dominated by stdin parse + decision JSON build, not regex iteration (per `performance.md`'s analysis — single regex hits at the first rule). The cost lives in `hook_init` + `hook_block`, not in `check_dangerous`'s body. **Cost is in the right place** (it's not really *this hook's* cost — it's the framework cost on the block path).
- **`git-safety`:** ~26ms includes one `git rev-parse` fork in the EnterPlanMode branch. Forking `git` from a hook running in the user's repo is the natural way to get the branch name; alternatives (parsing `.git/HEAD`, caching) introduce complexity for marginal savings. **Cost is in the right place** with one open question: dispatcher-level branch caching would amortize across all 8 children (a `02-dispatchers/` concern, not this category's).
- **`secrets-guard`:** ~26ms is registry path matching + inline command-shape policy. The shared inline policy (env-listing, cred-shaped printenv) is what's load-bearing — if it lived in the registry, the policy would be data-driven and the hook would shrink. But the registry's current shape is regex-based, and the policy is positional ("printenv of a credential-shaped name"), which doesn't map cleanly to a regex.

**Cross-axis impact for `secrets-guard`:**
- Performance: registry-driven policy could compress check-body to ~12ms (the same as `block-credential-exfiltration`), saving ~14ms per hook firing on Bash and Read.
- Robustness: a more uniform registry shape (positional matching) is harder to validate. Today `kind=credential, target=raw` is regex-only and `validate-detection-registry.sh` checks pattern shapes; positional matching would need a different validator.
- Testability: data-driven matching is easier to extend without code changes.

**Recommendation:**
- `block-dangerous-commands`: **no action** — cost is framework, not hook.
- `git-safety`: **no action here**, defer the dispatcher-caching question to `02-dispatchers/`.
- `secrets-guard`: **scope a separate proposal** for "registry-driven command-shape policy." Real win (~14ms × ~all-Bash-firings is significant), but it's a substantial change to the registry's shape — it's not a clarity-axis call, it's its own design effort. Captured as a backlog item.

### Proposal 7 — `suggest-read-json` header-vs-code drift (from robustness)

**Background.** The file header says *"Blocks: Large `.json` files (> threshold), Excludes common config files by default"*. The implementation also blocks any **nonexistent** `.json` file regardless of size (the size-check short-circuits return 0, but the no-file branch falls through to block).

**Cross-axis impact:**
- Robustness already captured the fix (`hook-audit-01-suggest-read-json-nonexistent`).
- Clarity question: should the header documentation be updated to reflect actual behavior, or should the code be updated to reflect the documented behavior?

**Recommendation: code follows doc.** The header describes the intended contract, and the user-facing semantics ("don't load large JSON into context, suggest jq instead") only make sense for files that exist and are large. Blocking nonexistent files is a contract violation, not an undocumented feature. The robustness backlog item already proposes the fix; clarity adds: when fixing, **don't** update the header — the header is correct.

## Other clarity findings (not surfaced by other axes)

### Identical 5-line bodies in the loggers

Already covered in Proposal 5. The two loggers being byte-identical except for one event-name string is a clarity *signal* — it confirms the framework is doing its job (the EXIT trap absorbs all the per-event variation). Worth a one-liner in the docs (Proposal 5 recommendation).

### Mixed comment style across hooks

Some hooks use ASCII separator banners (`# ============================================================`) for major sections, some don't. Among the 13:

- **Banners:** auto-mode-shared-steps, block-config-edits, block-credential-exfiltration, block-dangerous-commands, enforce-make-commands, enforce-uv-run, git-safety, secrets-guard, suggest-read-json (9 hooks)
- **No banners:** approve-safe-commands, detect-session-start-truncation, log-permission-denied, log-tool-uses (4 hooks)

The "no banner" group is exactly the four hooks small enough to not need them (the loggers and the fire-once). The "banners" group is exactly the 9 dual-mode hooks. **The styling tracks the structure.** No issue — recorded so a future "consistency" pass doesn't conclude there's a problem.

### Standalone-vs-dispatcher dual entry point

Six hooks have the same shape at the bottom:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

This is documented in `relevant-toolkit-hooks.md` as the "dual-mode trigger." The pattern is identical across all dual-mode hooks. **No issue** — it's the right shape.

### The `_HOOK_ACTIVE=true` line in the loggers

Both loggers have an explicit `_HOOK_ACTIVE=true` line. Reading `hook-utils.sh`, this flag controls whether the EXIT trap writes a row (false = early exit from `hook_require_tool`, no row needed). The loggers skip `hook_require_tool` (they want all tools), so they have to flip the flag manually.

**Clarity question:** is this a leaky abstraction? Today the convention is "PreToolUse hooks call `hook_require_tool TOOL`; loggers don't"; the `_HOOK_ACTIVE` flag should arguably be set by something other than each logger. But: there are only 2 loggers, the line is documented in the file (`# hook_init only auto-activates for SessionStart; other events need hook_require_tool, which we skip because we want all tools`), and changing the default would affect every PreToolUse hook's failure semantics.

**Recommendation: keep as-is.** The leak is small, the comment explains it, the alternative (flipping the default) has a wider blast radius.

## What clarity recommends

**Do (high leverage):**
1. **Formalize the `match_*`/`check_*` superset invariant** (Proposal 1). Update `relevant-toolkit-hooks.md` §3 with the explicit logical statement (`check_acts(x) ⇒ match_returns_true(x)`). Wire the Shape A test layer (already proposed in `testability.md`) to assert it. Highest-leverage call in the category — converts a doc convention into enforcement and prevents the next quote-evasion-class bug.

**Do (small, opportunistic):**
2. **Add a "logger pattern" doc note** (Proposal 5). One paragraph in `relevant-toolkit-hooks.md` describing the 5-line shape. ~3 lines.
3. **Add a "PermissionRequest hooks may but need not be dual-mode" note** (Proposal 2). ~3 lines in `relevant-toolkit-hooks.md`. Closes the "should we refactor approve-safe-commands" question by codifying that we've thought about it and decided no.
4. **Add a top-of-file table-of-contents comment to `secrets-guard.sh`** (Proposal 3 partial). The full split was rejected; a navigation comment is the right substitute.

**Don't:**
1. Refactor `approve-safe-commands` to dual-mode (Proposal 2). PermissionRequest's "fall through is safe" semantics blunt the value.
2. Split `secrets-guard` by branch (Proposal 3). Shared inline policy is load-bearing.
3. Split `block-config-edits` by branch (Proposal 4). Same reason as secrets-guard, smaller scale.
4. Extract a `hook_register_as_logger` helper (Proposal 5). Two 5-line files are the right size.

**Defer to other axes / future work:**
- Registry-driven command-shape policy for `secrets-guard` (Proposal 6 partial). Real win, separate design effort. Backlog.
- Dispatcher-level git-rev-parse caching (Proposal 6 partial). Falls to `02-dispatchers/`.
- The Shape A test layer that asserts the superset invariant. Falls to `testability.md`'s `hook-audit-01-shape-a-match-check-pairs`.

## Confidence

- **High confidence** in Proposal 1 (formalize the superset invariant). The doc already documents it as a rule, the Shape A vehicle is already proposed, the gap from `block-dangerous-commands` proves the rule needs enforcement.
- **High confidence** in the keep-as-is recommendations for Proposals 2, 3, 4, 5. Each has a one-sided cost-benefit when grounded in the data the other axes collected.
- **Medium confidence** in the "no action" calls for Proposal 6 (`block-dangerous-commands` and `git-safety`). The cost characterization is solid; "is this the right place for the cost" is opinion.
- **Lower confidence** on the "scope a separate proposal" call for Proposal 6 secrets-guard. The win is real but the design space (positional matching in the registry) is unexplored. Captured as backlog, not commitment.

## Backlog tasks added

Two new items recorded:

- `hook-audit-01-superset-invariant-doc-and-test` (P1) — formalize the invariant in `relevant-toolkit-hooks.md` §3 + wire Shape A enforcement (combines with `hook-audit-01-shape-a-match-check-pairs` as the test vehicle).
- `hook-audit-01-secrets-guard-registry-policy` (P2, idea) — explore registry-driven command-shape policy as a future design proposal. Real but speculative.

## Open

- **Whether the doc-only changes (Proposals 2, 5; new note in Proposal 1) should land as one combined PR or separately.** Editorial; doesn't change the work.
- **Whether `clarity.md`'s opinion on the secrets-guard registry-policy proposal counts as "scope" or "rejection."** It's neither — it's "real win, deserves its own design pass." The backlog task captures the framing.
