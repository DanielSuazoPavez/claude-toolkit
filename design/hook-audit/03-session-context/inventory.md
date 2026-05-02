---
category: 03-session-context
axis: inventory
status: drafted
date: 2026-05-02
---

# 03-session-context — inventory

Catalog of the two **context-injection** hooks: events, payload shape, current measured cost, V20 status, downstream context-cost. Per-axis reports (performance, context-pollution, robustness, testability, clarity) reference this file rather than re-deriving the structure.

**Convention:** "context-injection hook" = a hook whose primary effect is to add tokens to the model's context, not to block or approve a tool call. Both members emit `additionalContext`-shaped output (session-start via stdout-as-context per the SessionStart contract; surface-lessons via the `hook_inject` API). Failure-mode and budget framing differ from the PreToolUse safety dispatchers covered in `01-standardized/` and `02-dispatchers/`.

**Asymmetric audit depth.** session-start gets the full multi-axis treatment. surface-lessons gets short-form treatment on every axis except `context-pollution.md` (where it's the headline finding). Reason: surface-lessons' core mechanism is being re-evaluated by `eval-claude-mem` (P1, backlog) — claude-mem and agentmemory are external systems with very different relevance/retrieval models. A thorough audit of the *current* surface-lessons mechanism would re-litigate decisions that may be obsolete within one cycle. The Mega Elephant (relevance / context pollution) gets the full treatment because that's the dominant failure mode regardless of what mechanism replaces today's tag-keyword match.

## Members

| Hook | Event(s) | Firing rate | Payload size (current) | Wall-clock (p50) | V20 status |
|------|----------|-------------|-----------------------:|-----------------:|------------|
| `session-start.sh` | SessionStart | **once per session** | 5426 B (53% of 10240B cap) | ~136ms wall (112ms inside hook) | warns (49ms hook work vs 5ms default budget) |
| `surface-lessons.sh` | PreToolUse(Bash\|Read\|Write\|Edit) | **per-turn, conditional** (only on those tool events; further gated on `_HOOK_ACTIVE`) | up to ~3 lessons × ~200B each ≈ 600B per match | 20–78ms wall depending on match path | warns (~8ms hook work vs 5ms default budget) |

V20 numbers are from this session's `make check`. Wall-clock numbers are from `tests/perf-session-start.sh -n 10` and `tests/perf-surface-lessons.sh -n 10` taken this session. Variance is wider than the 02-dispatchers probe (no N=30 paired smoke/real probe exists for these two hooks — see Open below).

Neither hook declares `PERF-BUDGET-MS`. Both inherit the framework default `scope_miss=5, scope_hit=50`. The 5ms budget is structurally wrong for both, but for **different reasons**:

- session-start: the hook does ~50ms of legitimate work (essential-doc reads, git context, lessons.db query). 5ms is impossible by design. But session-start runs **once per session**, so the cost shape is fundamentally different from per-call dispatchers.
- surface-lessons: at ~8ms hook work, this is closer to the budget than session-start, but still over. It runs **per-turn on the matched tool list**, so it lives on the per-call path.

Both are flagged by V20 on every `make check`, contributing to ongoing warning noise. Per-hook budget recommendations land in `performance.md`.

## session-start.sh

**Event:** SessionStart. Fires once per session at startup. Output is concatenated into the model's initial context per the SessionStart hook contract.

**Sourced libs:**
- `lib/hook-utils.sh` — sourced once at line 43.
- `scripts/lib/settings-integrity.sh` — sourced lazily at line 54 (only when present); writes a one-shot integrity warning to stdout if `.claude/settings.json` changed without a covering commit.

**Phase decomposition** (from `tests/perf-session-start.sh -n 10`, this session):

| Phase | Wall (p50) | What runs |
|-------|-----------:|-----------|
| `hook_init` | 5ms | stdin parse + globals + EXIT trap install (consolidated jq) |
| `settings_integrity` | <1ms | `settings_integrity_check` — silent baseline path |
| `essential_docs` | **38ms** | `for f in essential-*.md`: extract Quick Reference (full inject for `essential-preferences-communication_style`, §1 Quick Reference + path nudge for the rest) |
| `docs_guidance` | 7ms | one-line nudge ("Use /list-docs to discover available context...") |
| `git_context` | **22ms** | `git symbolic-ref refs/remotes/origin/HEAD` + `git rev-parse --abbrev-ref HEAD` + `hook_log_session_start_context` JSONL emit |
| `toolkit_version` | 1ms | gated on `.claude-toolkit-version` file present (this repo: present, but version match → no output) |
| `lessons` | 6ms | branch-lessons SQL query against `~/.claude/lessons.db` (gated on `hook_feature_enabled lessons` + non-protected branch) + `last_manage_run` nudge query |
| `nudge` | 1ms | `_LAST_MANAGE_EXISTS` evaluation + nudge string build |
| `acknowledgment` | 1ms | MANDATORY ACK message composition with optional `ACTIONABLE_ITEMS` |
| **TOTAL inside hook** | **112ms** | sum of phases (delta to wall = bash startup + EXIT-trap teardown) |
| **WALL_CLOCK** | **136ms** | process start → exit, measured from outside the hook |

Two phases dominate: `essential_docs` (38ms) and `git_context` (22ms). Together they're 60ms of the 112ms inside-hook total — **the long pole of session-start is loading and rendering 3 essential docs + reading two refs from git.** Most of the smaller phases are <10ms each.

**Payload composition** (5426 bytes total this session, of 10240 cap):

| Section | Bytes (approx) | What it contributes |
|---------|---------------:|---------------------|
| `essential-conventions-code_style` (Quick Reference) | ~400 | §1 + path nudge |
| `essential-conventions-execution` (Quick Reference) | ~600 | §1 + path nudge |
| `essential-preferences-communication_style` (full) | ~3500 | full file inject (tone-shaping, must reach the model verbatim) |
| `docs_guidance` | ~80 | "Use /list-docs..." line |
| `git_context` | ~50 | "Branch: X / Main: Y" |
| `acknowledgment` | ~150 | "MANDATORY: Your FIRST message..." |

The full-inject of `essential-preferences-communication_style` is **65% of the payload by byte share**. The bytes-vs-cap budget is currently safe (53% utilization) but anything that pushes the communication-style file size meaningfully will move the needle fast.

**Conditional payload growth paths:**
- `ACTIONABLE_ITEMS` accumulator — appends bullet lines for: settings-integrity drift, lessons.db query failure, lessons.db missing, toolkit version mismatch, ecosystems opt-in nudge. Each is small (~50–100 B); current case is empty (none firing).
- Branch-scoped lessons (when on a non-protected branch with active recent lessons matching `branch=<current>`) — adds a "=== LESSONS ===" block of ~100B per lesson surfaced.
- `manage-lessons` nudge — adds one bullet line if `last_manage_run` is older than `nudge_threshold_days` (default 7).
- Toolkit version mismatch — adds a "=== TOOLKIT VERSION ===" block (~100B) plus one bullet to `ACTIONABLE_ITEMS`.

In a worst-case session (all conditional paths firing), the payload could grow by ~500–800 B. Still inside the 10240 cap, but the headroom margin shrinks.

**Cap validator:** `.claude/scripts/validate-session-start-cap.sh` runs in `make validate`. Thresholds: warn at 9500 B, fail at 10000 B. Cap itself is the harness limit (Claude Code 2.1.119+ silently truncates SessionStart hook output past ~10240 B — losing the MANDATORY ACK at the tail is the worst failure mode).

## surface-lessons.sh

**Event:** PreToolUse, matcher `Bash|Read|Write|Edit`. Fires on every tool call of those four tool names. Output (when matched) is injected via `hook_inject "Relevant lessons:\n- ..."`.

**Sourced libs:**
- `lib/hook-utils.sh` — sourced at line 32.

**Path decomposition** (from `tests/perf-surface-lessons.sh -n 10`, this session, six synthetic cases):

| Path | Phases that fire | Wall (p50) | Inside-hook (p50) |
|------|------------------|-----------:|------------------:|
| Wrong tool (e.g. `Glob`) — early exit | hook_init + jq_parse | 20ms | 9ms |
| Tool matches, no keyword hit (`ls -la`) | hook_init + jq_parse + tool_match + tokenize + build_sql + (no sqlite_query — bails before SQL) | 43ms | 17ms |
| Tool matches, sqlite query runs, no rows | hook_init + jq_parse + tool_match + tokenize + build_sql + sqlite_query + (no inject) | ~66ms | ~46ms |
| Tool matches, sqlite returns rows, lessons injected | all phases | ~72–78ms | ~47–51ms |

The dominant phase when the SQL fires is `sqlite_query` (~10–11ms p50). Hook-init + jq + tokenize + build_sql sum to ~14ms across all paths.

The hook self-bails on three independent conditions:
1. `LESSONS_DB` missing (line 30) — exit 0 before sourcing hook-utils.
2. Tool not in `Bash|Read|Write|Edit` (line 41–44) — exit 0 after hook_init.
3. Empty `$WORDS` after tokenization (line 53), or fewer than 2 candidate words after the 3-char filter (line 77) — exit 0.
4. Empty `$LESSONS` from the SQL (line 138) — exit 0 even with traceability logged.
5. `lessons` feature gate disabled (line 142) — exit 0 after context-logging.

**Match algorithm (relevant for context-pollution.md):**
- Tokenize the command/file_path into lowercase alphanumeric+`_-` words.
- Filter to words ≥3 chars.
- Build a SQL `(CASE WHEN keywords LIKE '%word%' THEN 1 ELSE 0 END)` term per word.
- For each `tags` row, sum the CASE terms; require ≥2 distinct hits per tag (line 116 `HAVING ($CASE_SUM) >= 2`). Single-hit matches are intentionally excluded as "too coincidental" (per the comment at lines 56–60).
- Surface up to 3 distinct lessons that have any candidate-tag link (`LIMIT 3` at line 125).
- Cross-DB dedup via `hooks.db.surface_lessons_context.matched_lesson_ids` excludes lesson IDs already surfaced earlier in the session (gated on `SESSION_ID` and the indexer's projection from JSONL → hooks.db).

**Conditional cost paths:**
- `seen_lookup` (lines 86–102) reads `hooks.db` to find lesson IDs already surfaced this session. Adds one sqlite3 fork when the file is present and `SESSION_ID` is set. Degrades gracefully to "no dedup" when absent.
- The ≥2-hit threshold and the `LIMIT 3` are both **relevance gates** — they reduce false-positive injection. See `context-pollution.md` for whether they're calibrated correctly.

**Payload size:** when the hook injects, the payload is `Relevant lessons:\n- <lesson1>\n- <lesson2>\n- <lesson3>` where each lesson's `text` is whatever the user wrote at `/learn` time. Typical lesson texts run ~100–300 B; capped at 3 lessons. Worst case: ~1KB injected per matched dispatch. Multiplied across many matched dispatches in a session — see `context-pollution.md`.

**Output schema:** `hook_inject "..."` emits `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "..."}}` per the `hook_inject` API in `hook-utils.sh`. The string is escaped for JSON via `sed` at line 145.

## Per-event cost shape

The two hooks live on **different cost paths**:

| Hook | Path | Multiplier | Amortization model |
|------|------|------------|--------------------|
| session-start | one-shot | runs **once per session** | wall-clock cost is paid once; payload tokens are paid **per turn × N turns** (the injected string lives in context for the rest of the session) |
| surface-lessons | per-turn (gated) | runs **per Bash/Read/Write/Edit dispatch** when `_HOOK_ACTIVE` | wall-clock is per-turn; injected payload (when present) lives for the remaining session turns starting at injection time |

Both have a **context-cost amortization** dimension that doesn't apply to the safety dispatchers in `02-dispatchers/`. A safety dispatcher's cost is per-call and ephemeral; a context-injection hook's cost is per-call (or one-shot) for wall, **plus a recurring per-turn token cost** for everything it injects. `performance.md` quantifies the token cost; `context-pollution.md` evaluates whether the tokens are earning their keep.

## V20 budget vs reality

Both hooks warn on every `make check`. Numbers from this session:

| Hook | V20 measured (hook work) | V20 budget (default) | Verdict |
|------|------------------------:|---------------------:|---------|
| session-start | 49ms | 5ms (`scope_miss`) | structurally too large for default — needs per-hook `PERF-BUDGET-MS` reflecting "once-per-session, looser bound" |
| surface-lessons | 8ms | 5ms (`scope_miss`) | close to budget; needs a small bump (~10–15ms) to stop false-positives |

Concrete budget recommendations land in `performance.md` once the two-budget framing (wall-clock + context cost) is in place. The bare wall-clock side here is straightforward; the context-cost side needs the framing the perf axis builds.

## Cap discipline

session-start has a dedicated cap validator (`validate-session-start-cap.sh`) running in `make validate`. surface-lessons has no equivalent cap — its injected payload is bounded only by `LIMIT 3` + lesson text length (no byte cap on the injected string). For surface-lessons, the relevant question isn't "are we exceeding a harness cap" (no SessionStart-style cap exists for PreToolUse `additionalContext`) but "are the bytes we inject earning their context cost" — see `context-pollution.md`.

## Verified findings feeding downstream axes

### Performance

- **session-start's long pole is essential-doc loading + git context** — 60ms of the 112ms inside-hook total. The full-inject of `essential-preferences-communication_style` accounts for ~3500 B of the 5426 B payload AND part of the essential_docs phase cost (file read + Quick Reference extraction for the other docs).
- **surface-lessons' long pole is the sqlite_query** — ~10ms p50 when the SQL fires. The early-exit paths (wrong tool, no keyword hit, no candidate words ≥2) are all under ~17ms inside-hook.
- **Context cost is unmeasured today.** Neither perf harness reports tokens-injected. The cap validator measures bytes-injected at session-start time but doesn't track the recurring per-turn cost. Performance axis quantifies this with the two-budget model.

### Context-pollution

- session-start's payload is 65% communication-style (full inject), 35% other essentials + git + ack. The full-inject is **deliberate** (per the `ESSENTIAL_FULL_INJECT` array at line 41 — tone-shaping must reach the model verbatim). Other essentials surface as Quick Reference (§1) which keeps their per-doc cost bounded. The question for context-pollution.md: is each piece earning its slot?
- surface-lessons' relevance gate is the **2-distinct-hits-per-tag** threshold + `LIMIT 3`. The threshold filters single-word coincidences out (right call), but two-hit matches against a tag whose keywords list includes common words (e.g. a `git` tag with `commit, push, pull, branch, merge`) will still fire on most `git ...` commands regardless of whether those specific lessons are *actually relevant* to the current command. The Mega Elephant lives here.

### Robustness

- session-start fail-mode: silent degradation on most error paths. `if [ ! -d "$DOCS_DIR" ]` exits 0 with a one-line warning. lessons.db query failure pushes a bullet to `ACTIONABLE_ITEMS` and continues. The MANDATORY ACK still fires at the end. **No fail-closed path exists** — there's no decision JSON to emit in SessionStart.
- surface-lessons fail-mode: also silent degradation. Missing lessons.db, missing hooks.db, lessons feature disabled, no SQL match — all exit 0 with no inject. The robustness taxonomy from 02-dispatchers (fail-closed/open/soft/loud) doesn't apply directly; replaced by a context-injector failure-mode taxonomy in `robustness.md`.

### Testability

- session-start has dedicated coverage: `tests/hooks/test-session-start.sh` (211 LoC), `test-session-start-source.sh` (56 LoC), `test-session-start-integrity.sh`. Plus the cap validator in `make validate`. Plus `tests/perf-session-start.sh` for per-phase timing.
- surface-lessons has dedicated coverage: `tests/hooks/test-surface-lessons-dedup.sh`, `tests/hooks/test-surface-lessons-two-hit.sh`. Plus `tests/perf-surface-lessons.sh` with synthetic + replay modes.
- **Coverage gap (the dominant testability question):** none of these tests measure **relevance** of injected content. The two-hit test verifies the SQL gate fires correctly; it doesn't measure whether the lessons surfaced are *useful*. Hard problem (relevance is subjective), but the gap is the headline testability finding for surface-lessons.

### Clarity

- Three structural questions feed forward to `clarity.md`:
  1. session-start mixes "ESSENTIAL CONTEXT" + "DOCS GUIDANCE" + "GIT CONTEXT" + "TOOLKIT VERSION" + "LESSONS" + "ACK" in one top-down script with section banners. Is the section-banner ordering legible? Is the policy ("what gets injected when") defensible?
  2. surface-lessons' relevance policy (≥2 hits per tag, LIMIT 3, intra-session dedup, ≥3-char words, no plural-strip) lives entirely in the SQL + tokenizer. The policy is **mechanically clear** (the SQL is one block) but **strategically opaque** (why these specific gates? when should they tighten or loosen?). Documented in code comments at lines 56–60 — assess whether this is enough.
  3. The full-inject vs Quick-Reference split for essential docs is one line (`ESSENTIAL_FULL_INJECT` array at session-start.sh:41). The decision rule ("full inject only when verbatim is needed for tone-shaping") is in the comment. Readers adding a new essential doc need to know this rule.

## Still-open questions (scope for downstream axes, not resolved here)

- **Performance:** what is the per-turn token cost amortization for session-start's payload? For surface-lessons' injected lessons? (Two-budget framing in `performance.md`.)
- **Context-pollution:** is each section of session-start's payload defensible against "remove this and check whether anything breaks"? For surface-lessons, what's the relevance hit-rate on real captured contexts (replay against `surface-lessons-context.jsonl`)? (`context-pollution.md`.)
- **Robustness:** what's the failure-mode taxonomy for context-injectors that replaces fail-closed/open/soft/loud? (`robustness.md`.)
- **Testability:** are the perf-*.sh harnesses measuring the right things? Should they vary inputs (lessons.db size, doc count, cold cache) more aggressively? Is there a relevance metric that's tractable? (`testability.md`.)
- **Clarity:** is the injection policy legible? Is the full-inject rule durable? (`clarity.md`.)

## Open

- **No N=30 paired smoke/real probe exists for these two hooks.** The probe set under `measurement/probe/per-hook-N30.{tsv,summary}` covers the 13 standardized hooks plus the 2 dispatchers, but session-start and surface-lessons aren't in `run-per-hook-probe.sh`. The numbers in this audit come from `tests/perf-session-start.sh` (n=10) and `tests/perf-surface-lessons.sh` (n=10 per case), not from a paired smoke/real comparison. Recorded as a follow-up — running the existing `tests/perf-*.sh` harnesses with N=30 in both `CLAUDE_TOOLKIT_LESSONS=0` (smoke-equivalent) and `CLAUDE_TOOLKIT_LESSONS=1` (real-equivalent) modes would close the data gap. Whether the audit needs that data depends on whether `performance.md` finds the n=10 single-mode numbers are sufficient for budget-setting.
