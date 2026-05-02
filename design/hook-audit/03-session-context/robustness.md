---
category: 03-session-context
axis: robustness
status: drafted
date: 2026-05-02
---

# 03-session-context — robustness

Failure-mode analysis for the two context-injection hooks. The fail-closed/fail-open/fail-soft/fail-loud taxonomy from `00-shared/robustness.md` and `02-dispatchers/robustness.md` doesn't apply directly here — there's no `block` decision available to a SessionStart hook, and surface-lessons' `additionalContext` injection is not a control-flow decision. The robustness question for context injectors is different: **what bad shapes can the output take, and what does each mean for the model?**

## Convention: failure-mode taxonomy for context-injectors

Replacing fail-closed/open/soft/loud with five context-injector failure modes:

| Mode | Definition | Severity for session-start | Severity for surface-lessons |
|------|-----------|----------------------------|------------------------------|
| **Total failure** | Hook errors out entirely; no output reaches the model | High — loses MANDATORY ACK and essential docs | Low — model continues without lessons |
| **Partial payload** | Hook produces some output, errors mid-render. Output is structurally incomplete (truncated mid-section, malformed) | Medium — model gets unbalanced context (e.g. essential docs but no git context); the cap-truncation at the harness level is a specific subcase | Medium — model gets partial inject (truncated mid-lesson) |
| **Stale data** | Hook produces well-formed output drawn from outdated source (lessons.db not updated, doc files cached, wrong git ref) | Medium-high — model acts on stale guidance | Medium-high — surfaces inactive/superseded lessons |
| **Cap exceeded** | Output exceeds harness limit; harness truncates silently | High (specific to session-start) — loses tail content (MANDATORY ACK is at the end, deliberately for this reason) | Not applicable — no fixed cap on PreToolUse `additionalContext` |
| **Source unavailable** | An input is missing (lessons.db, docs dir, git repo) — hook handles gracefully | Low if handled; high if not | Low — already handles via early exit |
| **Wrong relevance** | Output is well-formed and on time but not actually useful for the current operation | Not applicable to session-start (universally relevant by design) | **Headline failure mode** — covered fully in `context-pollution.md`, not re-litigated here |

The asymmetry between session-start and surface-lessons holds: session-start's failure modes are mostly about **payload integrity** (did the right bytes reach the model); surface-lessons' are about **payload relevance** (are the right bytes the ones we sent), which is the pollution axis's territory.

## session-start failure modes

### Total failure (low likelihood, high severity)

session-start has no top-level error handler. Bash errors during the script (e.g. unset variable, `set -e` would catch them — but `set -e` isn't set) silently produce partial output. A genuine total failure (the hook process never starts, exits before any output) means the model gets **no MANDATORY ACK and no essential docs**.

In practice the hook is robust against this: every section uses defensive idioms (`|| _content="(Error reading file...)"`, `2>/dev/null || echo 'unknown'`, etc.). The most plausible total-failure scenario is **the hook itself missing or non-executable** — caught by the harness, which would warn that the configured hook script is absent. Captured at the framework level, not session-start's problem.

**Verified behavior** (this session, `bash .claude/hooks/session-start.sh`): produces output unconditionally as long as `.claude/hooks/session-start.sh` itself runs. Early exits only on `if [ ! -d "$DOCS_DIR" ]` (line 67) — and that path emits a warning before exiting.

**Verdict:** structural total failure is unlikely; if it happens, the harness surfaces it. No backlog item.

### Partial payload (medium likelihood, medium severity)

Plausible scenarios:
1. A specific essential-*.md file is corrupted or unreadable mid-loop. The `cat "$f" 2>/dev/null) || _content="(Error reading file - permission denied or corrupted)"` defensive at line 89 handles this — produces the placeholder string, continues.
2. Git is uninstalled or `git rev-parse` fails. Lines 118–120: `_raw=$(git symbolic-ref...) ... || MAIN_BRANCH=""` and `... || echo 'unknown'`. Handled — produces "Branch: unknown / Main: main" fallback.
3. lessons.db is corrupted or sqlite3 errors. Line 209 `if [ "$_DB_EXIT" -ne 0 ]` pushes to ACTIONABLE_ITEMS; the hook continues. Handled.
4. Settings-integrity helper is present but errors. The helper's `_SETTINGS_INTEGRITY_SOURCED` guard prevents re-init issues, but an internal error during sha256 or git-show would produce empty output (helper functions return empty on error). The check passes silently.

**Verified by inspection:** every section defensively handles its known-failure-modes. Partial payload is bounded — a single section can fail and the rest of the payload still reaches the model.

**Edge cases not currently handled:**
- If `hook_extract_quick_reference "$f"` fails partway (e.g. awk script error, file read partially succeeds), the function may return a truncated Quick Reference with no error signal. The placeholder fallback `(no Quick Reference section found...)` only fires when the function returns empty, not when it returns truncated content.
- If a doc file has malformed structure (no `## 1. Quick Reference` header but starts with one in the middle), `hook_extract_quick_reference` may produce unexpected output. No tests exercise this.

Recorded as a watch-item: `hook-audit-03-quickref-extract-edge-cases` (P3) — only worth investigating if a real session ever produces malformed Quick Reference output. No reports of this today.

### Stale data (medium likelihood, medium-high severity)

Most-stale paths:
1. **Doc files updated since last sync.** session-start reads from `${CLAUDE_DOCS_DIR:-.claude/docs}` — local files, always fresh on read.
2. **lessons.db updated since session start.** session-start queries the DB once at startup. New lessons added during the session are not picked up until next session — by design (the hook is one-shot). Stale risk: medium (next session picks them up). Severity: low (the model doesn't act on session-start lessons in the current session anyway; surface-lessons handles the ongoing case).
3. **Git refs stale.** `git rev-parse --abbrev-ref HEAD` returns the actual current branch — fresh on read. No staleness risk.
4. **Toolkit version mismatch.** Read from `.claude-toolkit-version` file vs `claude-toolkit version` command. Only stale if the file was updated externally (via sync) without running the command. Both paths are local and synchronously read.

**Verdict:** session-start has minimal stale-data exposure because all its sources are locally synchronously read at startup. Lessons.db staleness within a session is a non-issue (doesn't update the same session anyway).

### Cap exceeded (low likelihood today, high severity if it happens)

The harness silently truncates SessionStart hook output past ~10240 B. Today's payload is 5426 B (53% of cap), so the immediate risk is low. But:
- Conditional payload growth paths (per `inventory.md`'s "Conditional payload growth paths" list) can add ~500–800 B in a worst-case session.
- Future essential docs added to `ESSENTIAL_FULL_INJECT` would push toward the cap fast (any single full-inject of >5KB content alone overruns).
- The tail content (MANDATORY ACK at line 280–286) is deliberately at the bottom because it's the most important to surface; truncation hits it first.

**Defenses today:**
- `.claude/scripts/validate-session-start-cap.sh` runs in `make validate` with thresholds 9500 B (warn) and 10000 B (fail). Catches it at build time, not session time.
- Conditional growth paths are individually small.
- The `ESSENTIAL_FULL_INJECT` array has only one member today.

**Defenses missing:**
- No runtime check. If a session-start invocation produces >10240 B (e.g. the user added a 5KB full-inject doc and shipped it without running validate), the harness silently truncates — the user only notices if the model fails to follow the ACK contract.
- No per-section cap. The validator measures total output; doesn't catch a single section dominating the payload.
- No cap-headroom alert. Validator passes anything under 9500 B without surfacing the trend.

**Recommendations:**
- **Add per-section soft cap to `validate-session-start-cap.sh`** (this is the same recommendation as `context-pollution.md`'s `hook-audit-03-essential-full-inject-discipline`). Captures the specific risk of one section overrunning the budget for the others.
- **Surface payload-size breakdown when validator runs in CI.** If the cap validator emits "essential_docs: 4500 B / git_context: 50 B / ..." in addition to the total, drift becomes visible session-over-session.

The first is captured in `context-pollution.md`'s backlog. The second is new: `hook-audit-03-cap-validator-breakdown` (P3) — extend the validator to emit per-section bytes.

### Source unavailable (low likelihood, low severity)

session-start's sources:
- `.claude/docs/` directory: handled at line 67 (`if [ ! -d "$DOCS_DIR" ]`) → exit 0 with warning.
- Specific essential-*.md files: globbed at line 77 (`for f in "$DOCS_DIR"/essential-*.md`) → empty glob produces zero iterations; the `[ -f "$f" ] || continue` guard inside is belt-and-braces.
- `lessons.db`: line 170 `elif [ -f "$LESSONS_DB" ]` and the fallback `elif [ -f "$LEARNED_FILE" ]` for the legacy path. Either present or both absent → no LESSONS section emitted.
- `claude-toolkit version` command: line 142 `command -v claude-toolkit &>/dev/null` gate. No CLI → no toolkit-version section.
- Git: line 118 `... || MAIN_BRANCH=""` then default to "main". Handles missing git.
- Settings-integrity helper: line 52 `if [ -f "$(dirname "$0")/../scripts/lib/settings-integrity.sh" ]`. Missing → silent skip.

**All source-unavailable paths handle gracefully.** No dangling reads.

**Verified empirically:** the existing fixture `tests/hooks/fixtures/session-start/runs-on-startup.json` covers the happy path. Header comment in `session-start.sh:24–30` documents three negative cases (no docs dir, empty docs, no git repo). These are documented but not regressed in test fixtures.

**Recommendation:** add fixtures for the three documented negative cases. Cheap (3 fixtures + 3 .expect files) and locks in source-unavailable robustness against future regressions. Captured as `hook-audit-03-session-start-negative-fixtures` (P3).

## surface-lessons failure modes

Short-form treatment per the asymmetric-depth principle (see `inventory.md` and `context-pollution.md`).

### Total failure (low severity)

surface-lessons fails open (no inject) on every error path it handles: missing lessons.db (line 30), tool not in matched list (line 41–44), tokenization yields no candidate words (lines 53, 77), no SQL match (line 138), feature gate disabled (line 142). All exit 0 with no inject.

Severity is low because failed inject = model continues without lessons = model behaves as if `CLAUDE_TOOLKIT_LESSONS=0`. The lessons feature is disabled by default for new projects per `setup-toolkit`; total failure equates to the disabled state.

**Edge case:** if `hook_init` (line 33) errors before sourcing completes, the hook may produce no output but consume the per-call wall-clock time. The bash startup + hook-utils source cost is paid (~7ms). Negligible.

**Verdict:** total failure is benign. No backlog.

### Partial payload (low likelihood)

The hook builds `LESSONS` via SQL (line 110–127), then escapes for JSON via `sed` (line 145), then emits via `hook_inject`. Plausible failure: SQL returns rows whose `text` contains characters that break the `sed` escape. The current escape covers `\` and `"` (`'s/\\/\\\\/g; s/"/\\"/g'`); other JSON-control characters (newlines in text, tabs, control chars) are not explicitly handled.

A lesson text containing a literal newline would produce a malformed JSON additionalContext string. The `hook_inject` API in `hook-utils.sh` may have additional escaping; need to verify.

**Recommendation:** audit the JSON escaping path. If `hook_inject` produces malformed JSON when lesson text contains specific characters, the harness either rejects the inject (no pollution but no lesson) or accepts a malformed string (may cascade into later prompt failures). Captured as `hook-audit-03-surface-lessons-json-escape` (P3).

### Stale data (medium likelihood, **medium-high severity**)

Most-stale paths:
- **lessons.db updated mid-session.** The hook reads on every fire — fresh. Not stale.
- **Lesson `active=1` flag set/cleared mid-session.** Read fresh. Not stale.
- **Tag keywords updated mid-session.** Read fresh. Not stale.
- **The intra-session dedup table.** `hooks.db.surface_lessons_context` is populated by the claude-sessions indexer with ~1min lag from JSONL → DB (per the comment at line 82–83). A lesson surfaced 30 seconds ago may NOT be in the dedup table yet → may surface again. Acceptable per the comment ("the accepted tradeoff for standardizing data ingestion downstream").

**Verdict:** stale data is bounded and accepted. The dedup-lag tradeoff is documented.

### Cap exceeded (not applicable)

PreToolUse `additionalContext` has no documented harness-side cap. The hook self-bounds at LIMIT 3 lessons × per-lesson text length. Worst case ~1KB injected per fire. No cap-exceeded failure mode.

### Source unavailable (low severity)

- `lessons.db` missing → exit 0 at line 30.
- `hooks.db` missing → degrades gracefully to no-dedup (line 86–87 guards).
- `SESSION_ID` unknown → degrades gracefully (line 87).
- Tag table or lesson table missing in `lessons.db` → SQL returns empty (`2>/dev/null` masks errors); hook exits at line 138.

All sources fail-soft. No backlog.

### Wrong relevance — see `context-pollution.md`

This is the headline failure mode. Not duplicated here. Net effect: model receives well-formed, on-time, but **not relevant** content. The robustness axis records it as the dominant context-injector failure mode without re-litigating the data — that lives in pollution.

## Cross-cutting findings

### Context-injector failure-mode taxonomy is new

The fail-closed/open/soft/loud framing from earlier categories maps to one quadrant of context-injector failure (the "what does the hook DO when something goes wrong"). The new dimensions — payload integrity, cap discipline, relevance — are orthogonal.

This taxonomy should propagate to `relevant-toolkit-hooks.md` if more context-injection hooks are added to the toolkit. Captured as part of `hook-audit-03-document-byte-turn-framing` (already in `performance.md`'s backlog).

### Both hooks' robustness is in good shape on the structural axes

session-start: defensive idioms throughout, cap-validator at build time, all source-unavailable paths handled. Three documented edge cases (no docs dir, empty docs, no git) lack regression fixtures — cheap to add.

surface-lessons: fail-soft on every error path. The only structural concern is JSON escaping for lessons containing control characters; rare in practice, worth verifying.

The **non-structural** robustness concern is relevance — covered in pollution. Robustness as traditionally defined (the hook produces correct output for all inputs it accepts) is high.

## Verified findings feeding downstream axes

### Performance

- The failure-mode paths above are all bounded in cost. No path has unbounded retry, slow timeout, or external blocking call. Performance assumes graceful degradation; verified.

### Testability

- session-start has documented negative cases without fixtures. Adding 3 fixtures is cheap and high-defensibility.
- surface-lessons' JSON-escape audit doesn't have a current test. If the audit finds a real escape gap, the corresponding fixture should land alongside the fix.

### Clarity

- The context-injector failure-mode taxonomy belongs in `relevant-toolkit-hooks.md` if generalized. Falls to clarity to weigh the doc update.
- session-start's defensive idioms are good practice but somewhat cargo-culted (every section does its own variant). A consistent helper pattern (e.g. `_safe_section() { ... }` that wraps a section in error-handling) might tighten the code — clarity call. Probably not worth the churn given the current shape works.

## Confidence

- **High confidence** that session-start's structural robustness is sound. Every documented failure mode has a defensive guard; the only gaps are test fixtures for documented negative cases.
- **High confidence** that surface-lessons' fail-soft model is correct for a per-call context-injector. The hook's behavior on every error path matches the "no inject = harmless" expectation.
- **Medium confidence** on the JSON-escape concern. The current `sed` escape covers `\` and `"` but not all JSON control characters. A lesson text with embedded newlines or tabs may produce malformed output. Worth auditing; not yet evidenced as a real bug.

## Open

- **JSON-escape audit for surface-lessons.** Specifically: does `hook_inject` add escaping on top of the hook's `sed`? If not, what happens with lesson texts containing newlines, tabs, or other JSON-control characters? Captured as `hook-audit-03-surface-lessons-json-escape` (P3).
- **Per-section payload breakdown in cap validator.** Extend `validate-session-start-cap.sh` to print bytes-by-section. Adds drift visibility; no runtime cost. Captured as `hook-audit-03-cap-validator-breakdown` (P3).
- **Negative-case fixtures for session-start.** Three documented cases (no docs dir, empty docs, no git) lack fixtures. Captured as `hook-audit-03-session-start-negative-fixtures` (P3).

## Backlog tasks added

- `hook-audit-03-session-start-negative-fixtures` (P3) — add fixtures for the three documented negative cases in `session-start.sh:20–34`. Closes a regression-coverage gap.
- `hook-audit-03-cap-validator-breakdown` (P3) — emit per-section bytes from `validate-session-start-cap.sh`. Drift visibility.
- `hook-audit-03-surface-lessons-json-escape` (P3) — audit JSON-escape correctness for lesson texts containing control characters.
- `hook-audit-03-quickref-extract-edge-cases` (P3, watch-item) — only investigate if real session ever produces malformed Quick Reference output.

Existing items confirmed (not duplicated):

- `hook-audit-03-essential-full-inject-discipline` — covers the per-doc soft cap (from context-pollution.md).
- `hook-audit-03-document-byte-turn-framing` — covers documenting the failure-mode taxonomy alongside the byte-turn framing in `relevant-toolkit-hooks.md`.
