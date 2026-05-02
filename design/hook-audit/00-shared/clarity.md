---
category: 00-shared
axis: clarity
status: drafted
date: 2026-05-02
---

# 00-shared — clarity

Code shape, naming, where logic lives vs where it's invoked. This axis is opinion-shaped — the goal isn't to prescribe a "right" structure but to evaluate the boundary proposals surfaced in the other axes (inventory, performance, robustness, testability) and recommend keep/move/reshape.

## Boundary proposals from other axes

Three concrete moves were flagged in inventory and re-raised in performance and testability. Each is evaluated below against the data those reports collected.

### Proposal 1 — Move `_strip_inert_content` from `hook-utils.sh` to `detection-registry.sh`

**Background.** `_strip_inert_content` is the most complex pure-bash function in the libs (~70 LoC, char-by-char walk, heredoc + quoted-string blanker). Its only consumer is `detection_registry_match_kind`. The detection-registry header already declares the cross-file dependency: *"Requires `_strip_inert_content` from hook-utils.sh to be available."*

**Pros:**
- Localizes the dependency. The function and its only caller live in the same file.
- Shrinks `hook-utils.sh` by ~70 LoC (~15% of file size).
- Makes the registry's "no fork in match path" cheapness contract self-contained instead of reaching into a sibling.

**Cons:**
- Hooks that source `detection-registry.sh` (4 today) would parse the function. Performance impact: parse cost is bounded by LoC, so adding ~70 LoC to a file already consumed by 4 hooks adds ~50–100µs per parse — negligible against the hook's existing ~12ms floor.
- Hooks that **don't** source `detection-registry.sh` would no longer parse `_strip_inert_content`. Same arithmetic in reverse: ~50–100µs saved per non-consumer hook firing. There are 13 such hooks among the 17.
- The function's heuristic limits (heredoc, escaped quotes) are also relevant to **future** non-registry consumers if any emerge. Keeping it in `hook-utils.sh` is a "general-purpose tool" framing; moving signals "this exists for the registry."

**Cross-axis impact:**
- Performance: marginal net positive (saves ~50µs × 13 non-consumer hooks per session, unmeasurable in practice).
- Robustness: unchanged. The function's behavior is the same whether sourced from one file or another.
- Testability: **slight win** — Shape A tests for `_strip_inert_content` (Axis 1 from `testability.md`) would source `detection-registry.sh` directly, which is more honest about what the test is exercising.

**Recommendation: move it.** The dependency is unidirectional, the move is small, and the only argument against (general-purpose tool framing) doesn't have a real second consumer behind it. If one ever emerges, hoist it back. Cost: ~10 minutes of code motion + an updated header comment in both files.

### Proposal 2 — Move `hook_extract_quick_reference` from `hook-utils.sh` to `session-start.sh` (inline)

**Background.** `hook_extract_quick_reference` is ~10 LoC, used only by `session-start.sh` (the SessionStart event's only hook). Its job is to extract the `## 1. Quick Reference` block from a markdown file using `awk`.

**Pros:**
- Removes a one-caller helper from a "shared utilities" file.
- The function is essentially an `awk` invocation; inlining doesn't lose readability.

**Cons:**
- The function header documents its semantics (early-return on missing file, exit at next `## ` heading or `---` rule). Inlining means duplicating those semantics as comments, or losing them.
- If a future SessionStart-adjacent hook ever needs the same extractor, it'd reach for the helper again.

**Cross-axis impact:**
- Performance: parse cost saved is ~5µs per hook firing × 17 hooks. Real but unmeasurable.
- Robustness: unchanged.
- Testability: Shape A tests still trivially possible; just source `session-start.sh` instead of `hook-utils.sh`.

**Recommendation: keep it.** The savings are theoretical, the move signals "private to session-start" without functional change, and the function's name + header are already self-documenting in their current home. **Do not move.**

### Proposal 3 — Move `_resolve_project_id` + `_ensure_project` to a `project-id.sh` lib

**Background.** ~35 LoC together. Used by every `hook_log_*` writer in `hook-logging.sh` (always — JSONL rows record `project`) and by the two lessons hooks (`surface-lessons.sh:108`, `session-start.sh:176`).

**Pros:**
- Decouples the sqlite3 dependency from the init path. Hooks that don't log JSONL or surface lessons (none today, but hypothetical) wouldn't parse the sqlite-frontend code.
- A hypothetical new "always log to remote" writer would source one focused lib instead of `hook-utils.sh`.
- The lazy-resolution + caching contract (lazy on first read, cached afterward) is cleaner as its own file.

**Cons:**
- **Every hook today reads `$PROJECT` indirectly via the `_hook_log_timing` EXIT trap** (when traceability is enabled). So there are no current consumers that wouldn't pay the parse cost.
- Adds a new file and a new source line for every consumer. Sourcing chain length is already the longest variable in dispatcher startup; one more `source` per consumer is a small but real addition.
- The "lib for sqlite-frontend lookups" framing assumes there will be more such lookups. Today there's exactly one (project_id from sessions.db). Pulling a new file for one function is YAGNI.

**Cross-axis impact:**
- Performance: net **negative**. No current consumer skips parsing it; new file = new source statement = ~30µs each.
- Robustness: unchanged.
- Testability: Shape A tests can already exercise it — sourcing `hook-utils.sh` is the natural setup, and the function works in isolation.

**Recommendation: keep it where it is.** No real consumer benefits from the move; the "what if another sqlite lookup arrives" hedge isn't a currently-paying user. **Do not move.**

## Other clarity findings

### `hook-utils.sh` header structure

The file has two sets of header comments separated by the idempotency guard. Lines 1-9 say "Shared hook utilities... idempotent..." and the guard lives on 13-16. Lines 17-26 then provide the Usage example block. This reads as if the second header was tacked on after the guard during a refactor — it'd be cleaner as one continuous block before the guard.

**Recommendation: minor cleanup** when next touching the file. Move the Usage example up, before the guard. ~5 LoC of motion, no functional change.

### `hook_get_input` empty-vs-missing semantics (from robustness)

Robustness flagged that `hook_get_input` returns `""` for both "field missing" and "field present but empty". The function header doesn't document this collision.

**Recommendation: add a 2-line comment** to the function header (`hook-utils.sh:373-376`):
```
# Returns "" for both missing fields and present-but-empty fields. Callers
# that need to disambiguate should use a custom jq invocation.
```
~5 LoC of comment, no functional change. Opportunistic — only land if touching this function for some other reason.

### Decision-emitter naming

`hook_block`, `hook_approve`, `hook_ask`, `hook_inject` form a coherent decision API. `hook_require_tool` and `hook_get_input` are introspection helpers. `hook_init` is lifecycle. The naming is consistent — all decision functions take `REASON`, all return via process exit. **No issue.**

### Internal-vs-public underscore prefix

`hook-utils.sh` uses leading underscore to mark internal:
- `_now_ms`, `_strip_inert_content`, `_resolve_project_id`, `_ensure_project`, `_hook_perf_probe` — internal helpers
- `hook_init`, `hook_get_input`, `hook_block`, `hook_approve`, `hook_ask`, `hook_inject`, `hook_require_tool`, `hook_extract_quick_reference`, `hook_feature_enabled` — public

This is consistent and machine-greppable. `hook-logging.sh` follows the same pattern (`_hook_log_jsonl` internal, `hook_log_section` public). `detection-registry.sh` is mostly internal-only with a `_REGISTRY_*` global namespace and `detection_registry_*` public functions. `settings-permissions.sh` likewise. **No issue.**

### Globals as the inter-lib interface

`hook-utils.sh` documents (line 28-49) the 18+ global variables `hook_init` populates. `hook-logging.sh` reads many of them (header documents which). `detection-registry.sh` and `settings-permissions.sh` expose `_REGISTRY_*` and `_SETTINGS_PERMISSIONS_*` globals as their public API.

This is the standard bash convention and the only practical option for inter-source-script communication. The headers consistently document which globals each file owns vs reads. **No issue.**

### `set` flags

None of the libs use `set -euo pipefail`. This is correct: hooks need to handle errors carefully (fail-soft logging, fail-closed safety) and `set -e` would force unhandled errors to exit the process at the wrong moment. Each function manages its own error paths explicitly (verified in `robustness.md`). **No issue.**

### File-level idempotency guards

All four libs use `_<NAME>_SOURCED=1` guards. The guard lives **after** the file's header comments but **before** any global initialization. Pattern is consistent. The hook-utils.sh case has the documentation drift mentioned above (header split by the guard) — that's the only inconsistency.

## What clarity recommends

**Do (small, opportunistic):**
1. Move `_strip_inert_content` from `hook-utils.sh` to `detection-registry.sh`. Update both file headers. Verify smoke + lib tests still pass. (~10 minutes)
2. Cleanup `hook-utils.sh` header — fold the Usage block into the top header. (~5 minutes)
3. Document `hook_get_input` empty-vs-missing collision in its header comment. (~5 minutes)

**Don't:**
1. Move `hook_extract_quick_reference` to session-start.sh. Single-caller helper but the move buys nothing.
2. Move `_resolve_project_id`/`_ensure_project` to a separate lib. No current consumer skips it; hedge against hypothetical future lookups is YAGNI.
3. Re-merge `hook-utils.sh` and `hook-logging.sh`. Performance shows the split is ~free; the reason for splitting (evolving JSONL row shape independently of init/decision callers) is documented in `hook-logging.sh:1-10` and still valid.

**Defer to other axes:**
- Decision-API process-exit shape — `testability.md` recommends keeping it. Clarity has nothing to add.
- Adding Shape A tests for `_strip_inert_content`, `hook_feature_enabled`, etc. — those are testability calls, just enabled by clarity move 1 above.

## Confidence

- **High confidence** in the recommendations against moves (proposals 2 and 3) — the cost-benefit is one-sided.
- **Medium-high confidence** in the move-`_strip_inert_content` recommendation — the win is small but real, and there's no realistic loss.
- **High confidence** in the "no other clarity issues" finding — naming, underscore convention, set-flag posture, and idempotency guards are all consistent and correct.

## Open

- Whether `hook-utils.sh` should grow a top-of-file table-of-contents block listing public functions with one-line descriptions. The current shape (banner comment per function) is fine but spread out — readers grepping for "what does this lib offer" have to scan all 457 lines. **Editorial. Defer** unless someone is actively trying to onboard.
- Whether to standardize on `_REGISTRY_*` style (one prefix per file) or move toward more granular prefixes for sub-domains within a lib. Not actionable today; record for whenever a third loader-style file emerges.
