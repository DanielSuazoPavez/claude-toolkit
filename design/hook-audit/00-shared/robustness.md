---
category: 00-shared
axis: robustness
status: drafted
date: 2026-05-02
---

# 00-shared — robustness

Failure modes for the lib functions other hooks call. Goal: surface gaps where the contract is documented but not asserted, and where behaviors aren't covered by tests. Each per-axis report for downstream categories can rely on these answers without re-deriving them.

**Convention used in this report:**

- **fail-loud** — emits to stderr, returns non-zero or skips the offending entry
- **fail-soft** — emits to stderr (or not), returns success, lets the caller continue with degraded state
- **fail-closed** — exits non-zero or emits a `block` decision, halting the operation
- **fail-open** — exits 0 with no decision, letting the operation proceed

For PreToolUse hooks, fail-closed is the safety stance; for SessionStart and logging hooks, fail-soft is the right stance because crashing them blocks Claude from starting or makes traceability rows disappear silently.

## Failure-mode inventory by lib

### `hook-utils.sh`

| Function | Failure shape | Stance | Asserted by caller? |
|----------|---------------|--------|---------------------|
| `hook_init` (jq parse, line 261) | `jq` exits non-zero on malformed stdin → `_hook_init_rc != 0` → branch on `HOOK_EVENT` | **PreToolUse: fail-closed** (calls `hook_block` with safety message); **SessionStart: fail-soft + stderr warn**; **PermissionRequest/others: fail-open** (continues with `SESSION_ID=unknown`) | Implicit — branch is in `hook_init` itself |
| `_resolve_project_id` (sqlite3, line 187) | `sqlite3` non-zero swallowed by `2>/dev/null`. Two failure modes: (a) DB missing → basename branch; (b) DB present but `dir_name` not registered → empty `pid` → one-line stderr notice + empty `printf` | fail-soft | No — every caller calls `_ensure_project` and reads `$PROJECT` without asserting non-empty (verified: surface-lessons + session-start both build SQL with empty PROJECT, which simply matches no project-scoped lessons) |
| `hook_get_input` (line 375) | `jq` non-zero swallowed by `2>/dev/null \|\| echo ""` | fail-soft (returns empty string) | No — callers treat empty as "field missing", which collides with "field present but empty" |
| `hook_block` / `hook_approve` / `hook_ask` / `hook_inject` | None — these don't fail, they emit decision JSON and `exit 0` | (terminal) | n/a |
| `hook_extract_quick_reference` (line 326) | File missing → `[ -f "$file" ] \|\| return 0` (empty output) | fail-soft | No — `session-start.sh` doesn't distinguish "file missing" from "Quick Reference block absent" |
| `hook_require_tool` | TOOL_NAME mismatch → `exit 0` (no decision JSON) | fail-open by design | n/a — exit is the design |
| `_strip_inert_content` | Pure-bash, no fork, no I/O. Heuristic limits documented in header (nested/escaped quote edge cases) | fail-silent (just returns whatever it computed) | No — by design; the registry alternation regex absorbs the noise |
| `_now_ms` | `EPOCHREALTIME` always present in bash 5+; fallback to `date +%s%3N`. Pads short `frac` to avoid the documented 10× small bug | fail-silent (no expected failure mode in supported bash range) | n/a |

### `hook-logging.sh`

Every public writer follows the same shape: feature gate → `_ensure_project` → `jq -c -n ... 2>/dev/null` → `_hook_log_jsonl`. Failures are uniformly fail-soft because losing a JSONL row is preferable to crashing a hook on a logging path.

| Function | Failure shape | Stance |
|----------|---------------|--------|
| `_hook_log_jsonl` / `_hook_log_jsonl_unguarded` | `mkdir -p ... 2>/dev/null \|\| return 0`, then `printf '%s\n' >> "$file" 2>/dev/null \|\| true` | fail-soft (drops row silently) |
| `hook_log_section` / `hook_log_substep` / `hook_log_context` / `hook_log_session_start_context` | `jq -c -n ... 2>/dev/null) \|\| return 0` if jq fails to build the row | fail-soft |
| `_hook_log_timing` (EXIT trap) | Same `jq ... \|\| return 0` shape; switches between `stdin: <parsed>` and `stdin_raw: <string>` row shapes via `_HOOK_INPUT_VALID` flag set in `hook_init` | fail-soft |
| `_hook_log_smoketest` | Same shape, writes to `smoketest.jsonl` (separate file) | fail-soft |

**Failure-mode gap for the logging surface as a whole:** there is no signal that a row was dropped. Counts in JSONL are the only ground truth; if the disk fills up or `jq` segfaults mid-row, the only signal is missing rows. This is the right tradeoff for a logging surface — but it means traceability data is upper-bounded by the actual hook firing count, which hook health monitors should know.

### `detection-registry.sh`

| Function | Failure shape | Stance |
|----------|---------------|--------|
| `detection_registry_load` (file missing) | `[ ! -f "$_REGISTRY_PATH" ]` → stderr "file not found" + `return 1` | **fail-loud** |
| `detection_registry_load` (jq exec) | `jq ... 2>/dev/null` swallows jq failures (line 82) — the read loop just sees no input → `_REGISTRY_IDS` empty → "no entries loaded" stderr + `return 1` | fail-loud (via the empty-array check at line 84) |
| `detection_registry_load` (smuggled SOH byte) | Per-entry SOH check at line 71-76 → stderr "SOH byte in pattern/message at id=…" + `return 1` (aborts whole load) | **fail-loud** |
| `detection_registry_match` (regex empty) | Empty `_REGISTRY_RE__<kind>__<target>` → `return 1` (no match) | fail-soft |
| `detection_registry_match_kind` (load lazily on first call) | `[ "$_REGISTRY_LOADED" = "1" ] \|\| detection_registry_load \|\| return 1` | fail-soft (no match on load failure) |
| `_registry_describe_hit` (no entry matches alternation) | `_REGISTRY_MATCHED_ID="unknown"`, `_REGISTRY_MATCHED_MESSAGE="(no specific entry matched alternation re)"` | fail-soft (returns 0) |

**Asserted by caller?** Caller hooks (secrets-guard, block-credential-exfiltration, block-config-edits, auto-mode-shared-steps) check the return value of `detection_registry_match*` to decide whether to block. Load failures cause silent miss → fail-open at the hook level (no block emitted) — this is the correct stance because a broken registry should not crash sessions, but it should be detected by the validator. `validate-detection-registry.sh` runs in `make check` and asserts all 22 entries are valid; that's the ground-truth check.

### `settings-permissions.sh`

| Function | Failure shape | Stance |
|----------|---------------|--------|
| `settings_permissions_load` (file missing) | stderr "file not found" + `return 1` | **fail-loud** |
| `settings_permissions_load` (jq exec) | `jq ... 2>/dev/null` swallows; empty arrays → "no Bash() entries loaded" + `return 1` | fail-loud (empty-array check) |
| `settings_permissions_load` (ERE metachar in prefix) | `case "$p" in *'*'*\|...) echo "...skipping: $p" >&2; continue` | **fail-loud per entry** (logs, skips that prefix only) |

**Asserted by caller?** `approve-safe-commands` and `auto-mode-shared-steps` check return-value implicitly: load failure → empty regex → no match → no approve. Fail-open at the hook level (commands that would have been auto-approved get the normal user prompt instead). This is the right stance.

## Documented contracts vs code reality

### Contract upheld

- `_resolve_project_id` empty-PROJECT contract is consistently honored — both `surface-lessons.sh:108` and `session-start.sh:176` call `_ensure_project` immediately before reading `$PROJECT`, and the SQL handles empty `PROJECT` by matching no project-scoped rows while still surfacing globals. (Verified in inventory.)
- Idempotency guards (`_HOOK_UTILS_SOURCED`, `_HOOK_LOGGING_SOURCED`, `_DETECTION_REGISTRY_SOURCED`, `_SETTINGS_PERMISSIONS_SOURCED`, `_REGISTRY_LOADED`, `_SETTINGS_PERMISSIONS_LOADED`) are real — re-sourcing or re-loading is a no-op except for `hook_init`'s deliberate global resets.
- Cheapness contracts (no fork in match path) hold for both registries post-2.81.1. Verified by reading match functions: `detection_registry_match*` is pure bash `=~`; `settings_permissions_load` consumers iterate the prefix array or run a single `=~`.
- Smuggled-data defenses are enforced and fail-loud (registry SOH check, settings ERE-metachar reject).
- Malformed-stdin fail-closed branch in `hook_init` for PreToolUse — verified live: `echo 'not-json{' | bash .claude/hooks/git-safety.sh` emits `{"decision":"block","reason":"hook git-safety received malformed stdin — blocking as safety precaution"}` and exits 0.
- Malformed-stdin warn-and-continue branch for SessionStart — verified live: stderr warning emitted, hook continues to produce its session-start output.

### Contract drift / undocumented behavior

- **`hook_get_input`'s "missing field" semantics collide with empty-string fields.** Header just says "JQ_PATH" → returns the value or empty. Callers can't distinguish `{"foo": ""}` from `{}`. No caller currently depends on the difference, but if one ever does, the workaround is the consolidated `hook_init` jq call (which already extracts the 5 hot fields with explicit `// "default"` defaults). Recorded as an issue for `01-standardized/` if any hook needs to disambiguate.
- **`_hook_log_jsonl` row-drop is silent on `jq` failure.** The `2>/dev/null) || return 0` pattern is repeated 7 times in `hook-logging.sh`. There's no counter, no stderr emission. If jq segfaults, the only signal is missing JSONL rows. The right action is probably **none** — but it's worth recording so the hook health monitor (separate concern) doesn't assume row-count reflects firing-count.
- **`detection_registry_load` jq failure path is double-handled.** `2>/dev/null` swallows jq stderr; the read loop emits no entries; the `${#_REGISTRY_IDS[@]} -eq 0` check catches it. Net behavior is fail-loud, but the path is convoluted — a `set -o pipefail` capture or explicit jq-rc check would be more direct. Cosmetic, not behavioral.

## Tests / coverage gaps

### Covered

- Smoke fixtures for every standardized hook exercise the **happy path** (one fixture per hook in `tests/hooks/fixtures/<hook>/`).
- `tests/test-validate-detection-registry.sh` runs in `make check` and asserts all 22 registry entries are valid.
- `tests/test-validate-settings-template.sh` asserts the workshop's `.claude/settings.json` matches the synced template (45 allow rules).
- `tests/hooks/test-detection-registry.sh` and `tests/hooks/test-settings-permissions.sh` cover the loaders specifically.
- `tests/test-hook-utils-smoketest-flag.sh` covers the `CLAUDE_TOOLKIT_HOOK_RETURN_OUTPUT=1` capture path.

### Not covered

- **Malformed stdin to PreToolUse hooks.** Manually verified just now: `echo 'not-json{' | bash .claude/hooks/git-safety.sh` correctly emits the safety-block JSON and exits 0. **No fixture asserts this.** High value — the fail-closed branch is the entire reason `_HOOK_INPUT_VALID` exists.
- **Malformed stdin to SessionStart.** Manually verified: emits stderr warn, continues. No fixture asserts this either.
- **Malformed stdin to PostToolUse / PermissionDenied / UserPromptSubmit / PermissionRequest.** Each has its own intended fail mode (silent pass for logging; fail-open for permissions). Not covered.
- **`_resolve_project_id` registered-but-not-found path.** Smoke harness sandboxes `sessions.db` to a nonexistent path, so the basename branch is exercised — but the **DB present, `dir_name` not registered** branch (the one that emits the stderr notice during real sessions for users with new projects) is not. Lower value (the SQL handles empty cleanly) but the path emits stderr noise.
- **Disk-full / write-permission failure on `_hook_log_jsonl`.** The `mkdir -p ... 2>/dev/null || return 0` and `printf >> ... 2>/dev/null || true` branches are unreachable in normal tests. Probably acceptable — these are catastrophic system states, not contract failures.
- **Smuggled SOH in registry data.** `detection-registry.sh:71-76` rejects entries containing the SOH sentinel. No fixture exercises a malicious `detection-registry.json` with embedded SOH. The validator script doesn't check for it either. Low priority because the registry is workshop-controlled, but the defense is unjustified-by-test.

## Candidates for action (the implementation pass)

Ordered by ratio of risk-reduction to churn:

1. **Add malformed-stdin fixtures** for at least one hook per event type. Cheap (one fixture each, copy/paste from existing template), high coverage value because it locks in the only documented fail-closed behavior.
   - PreToolUse: malformed stdin → block fixture
   - SessionStart: malformed stdin → warn-and-continue fixture
   - PostToolUse: malformed stdin → silent pass (verify the row still appears as `stdin_raw`, not `stdin`)
2. **Add a `validate-detection-registry.sh` SOH check.** One-line addition: `jq -e 'all(.entries[]; (.pattern + .message) | contains("") | not)'`. Workshop-controlled data, but the cost of a check is trivial.
3. **Document `hook_get_input` "empty vs missing"** in the function header. Cheap (5 lines of comment); records the known limitation so future authors don't trip on it.
4. **Add a counter-style stderr emission for dropped JSONL rows** — *only if* hook health monitoring grows up to need it. Currently low priority because nothing consumes it.

Items 3 and 4 are opportunistic — only land them if touching the surrounding code anyway.

## Confidence

- **High confidence** that every documented failure path in the libs is implemented as documented (verified by reading code).
- **High confidence** that the malformed-stdin branch behaves as documented for PreToolUse and SessionStart (manually invoked just now).
- **Medium confidence** that `hook_log_*` row-drop paths are unreachable in practice — they're guarded against the obvious causes (mkdir failure, jq failure) but a long-running session with disk pressure has not been simulated.
- **Lower confidence** for adversarial-input handling at scale — the SOH/ERE-metachar defenses are correct for the data they see today (workshop-authored). If detection-registry ever grows to ingest user-authored entries, the defense surface is the right starting point but not validated against malicious payloads.

## Open

- Whether to upgrade `validate-detection-registry.sh` to also assert "all `target=raw` patterns are unanchored ERE" and "all `target=stripped` patterns are anchored to whitespace boundaries" — that's detection-correctness, not lib-robustness. Falls to `01-standardized/robustness.md` because the hooks themselves use the alternation regex.
- Whether to add a `hook_log_dropped_count` counter to surface row-drops via a SessionStart context line — defer unless someone is actively investigating missing rows.
