---
category: 01-standardized
axis: robustness
status: drafted
date: 2026-05-02
---

# 01-standardized — robustness

Failure-mode analysis for each of the 13 standardized hooks. Goal: identify gaps between **what the hook header claims** and **what the code actually does** under malformed, missing, or adversarial inputs. Findings here drive fixture work and (where the gap is real) implementation fixes.

**Convention** (inherited from `00-shared/robustness.md`):

- **fail-closed** — emits a `block` decision, halting the operation. Right stance for PreToolUse safety hooks.
- **fail-open** — exits 0 with no decision. Right stance for PermissionRequest, PostToolUse logging, PermissionDenied logging.
- **fail-soft** — silent pass on missing input. Common for "field not present" cases.
- **fail-loud** — emits to stderr and skips the offending entry/operation.

All findings below were **empirically verified** by running each hook against shaped fixtures, not derived from reading code alone.

## Per-event malformed-stdin behavior

`hook_init`'s malformed-stdin branch (verified at the lib level in `00-shared/robustness.md`) was probed against every standardized hook. Results match the documented contract:

| Event | Hooks | Malformed-stdin behavior |
|-------|-------|--------------------------|
| PreToolUse(Bash) standalone or dispatched | auto-mode-shared-steps, block-config-edits, block-credential-exfiltration, block-dangerous-commands, enforce-make-commands, enforce-uv-run, git-safety, secrets-guard | **fail-closed**: emits `{"decision": "block", "reason": "hook <name> received malformed stdin — blocking as safety precaution"}` |
| PreToolUse(Write\|Edit) | block-config-edits | **fail-closed** (same shape) |
| PreToolUse(Grep) | secrets-guard | **fail-closed** |
| PreToolUse(Read) | suggest-read-json | **fail-closed** |
| PreToolUse(EnterPlanMode) | git-safety | **fail-closed** |
| PermissionRequest | approve-safe-commands | **fail-open** (silent pass — no decision JSON) |
| PostToolUse | log-tool-uses | **fail-open** (silent pass) |
| PermissionDenied | log-permission-denied | **fail-open** (silent pass) |
| UserPromptSubmit | detect-session-start-truncation | **fail-open** (silent pass) |

All 13 hooks behave correctly. The PreToolUse safety hooks fail closed; everything else fails open. This is the documented behavior — verified end-to-end here for the first time.

**Coverage gap:** none of these branches has a smoke fixture. The only signal that they continue to work is manual probing. Captured under `hook-audit-00-malformed-stdin-fixtures` (already in backlog).

## Per-hook missing-field behavior

For each hook, what happens when `tool_input.<expected-field>` is missing or empty:

| Hook | Required field | Missing-field behavior |
|------|----------------|------------------------|
| `approve-safe-commands` | `tool_input.command` | silent pass (no auto-approval) — `[ -z "$COMMAND" ] && exit 0` |
| `auto-mode-shared-steps` | `tool_input.command` | silent pass (auto-mode gate also has to fire first) |
| `block-config-edits` | `tool_input.file_path` (Write\|Edit) or `.command` (Bash) | silent pass for both branches — `[ -z "$FILE_PATH" ] && exit 0` |
| `block-credential-exfiltration` | `tool_input.command` | silent pass — `[ -z "$COMMAND" ] && exit 0` |
| `block-dangerous-commands` | `tool_input.command` | silent pass |
| `detect-session-start-truncation` | `transcript_path` | silent pass — `[ -z "$TRANSCRIPT_PATH" ] && exit 0` |
| `enforce-make-commands` | `tool_input.command` | silent pass |
| `enforce-uv-run` | `tool_input.command` | silent pass |
| `git-safety` | `tool_input.command` (Bash) or none (EnterPlanMode) | silent pass for Bash; EnterPlanMode runs the protected-branch check unconditionally |
| `log-permission-denied` | none | always logs (logger semantics — no pre-check) |
| `log-tool-uses` | none | always logs (logger semantics) |
| `secrets-guard` | `tool_input.command` (Bash) / `tool_input.pattern` (Grep) / `tool_input.file_path` (Read) | silent pass for all three branches |
| `suggest-read-json` | `tool_input.file_path` | silent pass |

**Stance:** all 12 hooks with required fields fail-soft on missing field. This is correct — a missing field at PreToolUse means "the upstream harness sent us a malformed event," and crashing the hook is worse than letting the operation proceed (the harness will reject the malformed call elsewhere).

**One edge case worth recording: `git-safety`'s EnterPlanMode branch runs the protected-branch check even with an empty `tool_input`.** This is intentional — EnterPlanMode events legitimately carry no command, the branch check is the entire point. But it means EnterPlanMode is the only hook in the category that does work without a stdin field. Worth noting for fixture authors.

## Real failure modes found by empirical probing

These are issues found by running each hook against shaped inputs — not hypothetical concerns. Each is reproducible from the fixtures in `/tmp/hook-audit-fixtures/` (transient — recreate on demand).

### `block-dangerous-commands`: quote-evasion gap in the cheap predicate

**Reproduce:** `echo '{"tool_name":"Bash","tool_input":{"command":"echo \\u0027rm -rf /\\u0027"}}' | bash .claude/hooks/block-dangerous-commands.sh` — silent pass.

**Why:** `match_dangerous` (the cheap predicate at `block-dangerous-commands.sh:42`) requires the `rm` token to be preceded by start-of-line or one of `[[:space:];&|`(]`. When `rm` is wrapped in single quotes (`'rm -rf /'`), the preceding character is `'` — not in the alternation. `match_dangerous` returns false, so `check_dangerous` (which strips quotes via sed at line 67 and *would* catch this after stripping) is never called.

**Severity:** low for the actual safety case — the literal command `echo 'rm -rf /'` is harmless (it just prints the string). But the *intent* of the hook ("Also detects these patterns when hidden via … shell wrappers" per the file header) is partially defeated by the cheapness gate. Patterns like `eval "rm -rf /"` and `bash -c "rm -rf /"` are in the predicate alternation as `eval` and `bash`, so those still trip — but `echo "..."` doesn't, and neither does any other quoting context where the verb itself isn't a shell-wrapper.

**Recommendation:** add `'` and `"` to the predicate's preceding-character alternation. One-line change at `block-dangerous-commands.sh:46`:

```bash
# Current
local re='(^|[[:space:];&|`(])(rm|mkfs|...)([[:space:]]|$)|...'
# Proposed
local re='(^|[[:space:];&|`("'"'"'])(rm|mkfs|...)([[:space:]]|$)|...'
```

Captured as a `hook-audit-01-*` follow-up below.

### `suggest-read-json`: blocks Read on nonexistent .json files

**Reproduce:** `echo '{"tool_name":"Read","tool_input":{"file_path":"/nonexistent/foo.json"}}' | bash .claude/hooks/suggest-read-json.sh` — emits the "use jq" block.

**Why:** `check_suggest_read_json` at `suggest-read-json.sh:73` only short-circuits to `return 0` (allow) when `[ -f "$FILE_PATH" ]` is true *and* the file is under the size threshold. If the file doesn't exist, neither branch fires and the function falls through to `_BLOCK_REASON` and blocks.

**Severity:** medium for UX. The user's Read on a missing file gets redirected to "use jq via Bash" instead of getting the harness's natural "file not found" error. The user then runs `jq` on the same path, which also fails with "file not found" — a confusing detour.

**Recommendation:** when the file doesn't exist, fall through to silent pass (let the Read tool itself emit the not-found error). One-line change at `suggest-read-json.sh:73-79`:

```bash
# Current: only allow if file exists AND is small
if [ -f "$FILE_PATH" ]; then
    file_size_kb=...
    if [ "$file_size_kb" -lt "$size_threshold_kb" ]; then
        return 0
    fi
fi
_BLOCK_REASON="..."

# Proposed: allow if file doesn't exist OR is small
if [ ! -f "$FILE_PATH" ] || [ "$(stat -c%s "$FILE_PATH" ... / 1024)" -lt "$size_threshold_kb" ]; then
    return 0
fi
_BLOCK_REASON="..."
```

Captured as a `hook-audit-01-*` follow-up below.

### `_strip_inert_content` correctly blanks heredocs and quoted strings — empirically verified

The inventory captured a hypothesis that the 5 hooks calling `_strip_inert_content` (auto-mode-shared-steps, block-config-edits, enforce-uv-run, git-safety, secrets-guard) might regress on long heredocs. Empirical results:

- `enforce-uv-run` against `cat <<EOF\npy script.py\nEOF` → silent pass (the heredoc body is blanked; `python` doesn't appear in verb position in the stripped output).
- `enforce-uv-run` against `echo 'py script.py'` → silent pass (quoted string blanked).
- `enforce-uv-run` against bare `py script.py` → blocks correctly.

The strip-then-match approach works as designed for the verb-position regex. **No false negatives observed at fixture-input sizes** (~50–100 char commands). The 8KB-heredoc performance failure mode characterized in `00-shared/inventory.md` (~9.3ms) is a perf concern, not a correctness one.

**However:** this only applies to hooks that call `_strip_inert_content` *before* matching. Hooks that match the raw `$COMMAND` (block-credential-exfiltration deliberately, block-dangerous-commands by omission) operate on the literal heredoc body. For block-credential-exfiltration this is correct (the file header documents it). For block-dangerous-commands this is the source of the quote-evasion gap above.

### `block-credential-exfiltration` matches inside heredocs — corrected from inventory

**Reproduce:** the hook blocks an `Authorization: Bearer` literal whether it appears as a curl `-H` argument or inside a `<<EOF … EOF` heredoc body. The inventory's hypothesis ("a credential literal hidden inside a heredoc would not match … if the raw match misses") was wrong.

**Why:** the regex `_REGISTRY_RE__credential__raw` is applied to `$COMMAND` as a string, with no anchoring or boundary requirement. Heredoc syntax (`<<EOF`, body, `EOF`) is just literal characters in that string at hook-firing time — bash hasn't expanded the heredoc yet because the command hasn't been executed. So the credential pattern matches the substring directly.

The hook header documents this explicitly: "Quoted-string content is included on purpose — the canonical exfil shape is `curl -H "Authorization: token ghp_..."` where the token IS inside a quoted string."

Inventory has been corrected.

### Subshell / backtick / redirect rejection in `approve-safe-commands` — verified

The file header documents that subshells, backticks, and redirects are rejected (silent fall-through, not auto-approve). Empirical confirmation:

- `echo "$(date)"` → silent pass (rejected — `$(...)` substring detected, can't validate inner command)
- `ls > /tmp/out` → silent pass (rejected — redirect detected)

This is the correct stance. `date` would otherwise be on the allow list, but `$(date)` isn't structurally guaranteed to *only* run `date`. The hook errs on the side of asking the user.

**Edge case worth a fixture:** the rejection is on substring match — so `echo "use $() syntax to subshell"` (with empty `$()` inside a quoted string) would also be rejected, even though it's not a real subshell call. Acceptable — the cost is one user prompt; the alternative (parsing shell syntax to disambiguate) is too expensive for a PermissionRequest hook. Recorded as a fixture suggestion.

## Per-hook robustness rollup

| Hook | Malformed stdin | Missing field | Found gap |
|------|-----------------|---------------|-----------|
| `approve-safe-commands` | fail-open ✓ | silent pass ✓ | — |
| `auto-mode-shared-steps` | fail-closed ✓ | silent pass ✓ | — |
| `block-config-edits` | fail-closed ✓ | silent pass ✓ | — |
| `block-credential-exfiltration` | fail-closed ✓ | silent pass ✓ | — (heredoc match works as designed) |
| `block-dangerous-commands` | fail-closed ✓ | silent pass ✓ | **quote-evasion gap in match_dangerous** |
| `detect-session-start-truncation` | fail-open ✓ | silent pass ✓ | — |
| `enforce-make-commands` | fail-closed ✓ | silent pass ✓ | — |
| `enforce-uv-run` | fail-closed ✓ | silent pass ✓ | — |
| `git-safety` | fail-closed ✓ | silent pass ✓ (Bash); EnterPlanMode ignores tool_input by design | — |
| `log-permission-denied` | fail-open ✓ | n/a (logger) | — |
| `log-tool-uses` | fail-open ✓ | n/a (logger) | — |
| `secrets-guard` | fail-closed ✓ | silent pass ✓ | — |
| `suggest-read-json` | fail-closed ✓ | silent pass ✓ | **blocks on nonexistent .json files** |

Two real gaps found across 13 hooks. Both are correctness improvements with one-line fixes; neither is a security-critical issue.

## Verified findings feeding downstream axes

### Performance

- The empirical probing did not surface any new performance concerns. The 5 `_strip_inert_content` callers all behaved correctly at fixture-input sizes; the 8KB-heredoc cost characterized in `00-shared/inventory.md` is a perf concern that performance.md already noted, not a robustness one.

### Testability

- **No fixture asserts the malformed-stdin behavior for any of the 13 hooks.** Every result above came from manual probing. Captured under `hook-audit-00-malformed-stdin-fixtures` at the lib level; the per-hook fixtures should cover at least one representative per event type (PreToolUse-Bash, PreToolUse-Write|Edit, PreToolUse-Grep, PreToolUse-Read, PermissionRequest, PostToolUse, PermissionDenied, UserPromptSubmit).
- **No fixture asserts the missing-field behavior** for the 12 hooks with required fields. Each currently has one fixture (V18 minimum) covering the happy path. Adding a missing-field fixture per hook would multiply the fixture count by ~2x; whether this is the right tradeoff is a `testability.md` call (already noted in performance.md's testability section).

### Clarity

- **`block-dangerous-commands` has a clarity tension** between the cheap-predicate / quote-stripping-check split. The header says "Also detects these patterns when hidden via … shell wrappers" — but the cheapness gate runs *before* the quote-strip, so quote-wrapped patterns never reach the check. The fix is a one-line predicate widening; the deeper question (should the predicate be even more permissive at the cost of more `check_` calls?) belongs to `clarity.md`.
- **`suggest-read-json`'s "block on nonexistent" behavior is a contract clarity issue** — the file header says "Blocks: Large `.json` files" but the implementation blocks any nonexistent `.json` regardless of size. Header-vs-code drift, recorded for `clarity.md`.

## Candidates for action (the implementation pass)

Ordered by ratio of risk-reduction to churn:

1. **Fix `suggest-read-json` to fail-open on nonexistent files.** One-line change. Removes a confusing UX detour with no safety regression. Captured below.
2. **Widen `block-dangerous-commands`'s match-predicate alternation to include `'` and `"`.** One-line change. Restores the documented "patterns hidden via shell wrappers" coverage for quote-wrapping cases. Captured below.
3. **Add malformed-stdin and missing-field fixtures for at least one hook per event type.** Low effort (copy/paste existing fixture, blank/malform the relevant field). High coverage value because both branches are currently asserted only by manual probing. Captured under existing `hook-audit-00-malformed-stdin-fixtures`.
4. **Document the `approve-safe-commands` substring-rejection edge case** in the file header — `$()` inside a quoted string also triggers rejection. Cosmetic; only worth doing if touching the hook anyway.

## Backlog tasks added

Two new `hook-audit-01-*` tasks recorded as P1 (correctness improvements, not P0 because neither is a security regression):

- `hook-audit-01-suggest-read-json-nonexistent` — fail-open on missing files
- `hook-audit-01-block-dangerous-quote-predicate` — widen match-predicate to cover quote-wrapped patterns

Existing `hook-audit-00-malformed-stdin-fixtures` covers the per-event fixture work and is already in backlog at P0.

## Confidence

- **High confidence** in the malformed-stdin and missing-field behavior tables — every cell was verified by running the hook end-to-end against shaped stdin.
- **High confidence** in the two found gaps. Both reproduce reliably and the root cause is identified at the line level.
- **Medium confidence** that no other gaps remain. The probing covered: malformed JSON, missing required field, empty required field, heredoc-wrapped values for the 5 strip-callers, quote-wrapped values for the 4 hooks that use `_strip_inert_content` and for `block-dangerous-commands` (which doesn't), wrong-tool routing, and one fixture per documented edge case in each hook's header. Adversarial / large-input fuzzing was *not* run — captured as an open question below.

## Open

- **Adversarial-input fuzzing.** The probing covered shapes documented in each hook's header plus a few cross-cutting cases (malformed JSON, quote-wrapping, heredoc). It did not cover unicode normalization, control characters, very long inputs (>8KB commands), or NUL-byte injection. Whether to invest in fuzzing depends on the threat model — the toolkit's hooks are guardrails, not security perimeters. Recorded as scope for a future audit, not this one.
- **Detection-registry coverage gaps.** `00-shared/robustness.md` open question 1 ("upgrade `validate-detection-registry.sh` to assert pattern shapes") still applies. Falls to that validator, not the hooks themselves.
- **Per-hook `match_*`/`check_*` symmetry.** The dual-mode hooks (block-config-edits, block-dangerous-commands, enforce-make-commands, enforce-uv-run, git-safety, secrets-guard, suggest-read-json) all split their logic into `match_<name>` (cheap predicate) and `check_<name>` (full check). The block-dangerous quote-evasion gap is a symptom of this split — the predicate gates the check. A clarity question worth `clarity.md`'s attention: should every dual-mode hook's predicate be a strict subset of its check's match set? Today, predicates are hand-tuned for "false positives OK, false negatives bugs" — but no test asserts that property.
