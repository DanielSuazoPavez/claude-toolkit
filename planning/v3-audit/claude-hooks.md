# v3 Audit — `.claude/hooks/`

Exhaustive file-level audit of the `.claude/hooks/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`.claude/hooks/` holds 12 hook scripts + 1 shared library. Hooks are one of the four resource types (per identity doc §4: *"Hook — runs automatically on events; consistent enforcement — the one place where auto-triggering is the point"*). Workshop-shaped by definition: each hook is a guardrail that runs inside a consumer's Claude Code instance after sync, not a mechanism to reach into other projects.

Cleanest dichotomy in the directory: **guards** (block/allow) vs **context injection** (session-start, surface-lessons). All guards except `approve-safe-commands` and `session-start` follow match/check + dual-mode. The match/check pattern is well-executed — cheap predicates really are cheap, `_strip_inert_content` solves the heredoc/quote false-positive problem elegantly, and the dispatcher's distribution-tolerance (probe-before-source) means raiz can ship a subset without breaking.

One big live finding validated this session: **`surface-lessons.sh` relevance filter surfaces irrelevant lessons on every tool call** (flagged in `dist/` audit, mid-session we flipped `CLAUDE_TOOLKIT_LESSONS=0` to stop it). That's a real `Rewrite` with a clear root cause now that the code is read.

Findings below. 2 `Rewrite`, 3 `Investigate`, rest `Keep`.

---

## Files

### `lib/hook-utils.sh`

- **Tag:** `Rewrite`
- **Finding:** Shared library — hook init, input parsing, block/approve/inject output, perf probes, SQLite traceability logging. Well-documented: inline comments explain the `_HOOK_UTILS_SOURCED` idempotency guard (load-bearing for dispatcher sourcing), the `_now_ms` fallback logic, and the `_strip_inert_content` heuristic for stripping heredocs/quoted strings from command skeletons (prevents commit-message false positives in secrets/uv guards). Feature-flag gating via `hook_feature_enabled <feature>` is the opt-in mechanism that made the mid-audit fix trivial.

  Two calls:

  1. **`_strip_inert_content` needs unit-test coverage.** It's a bash implementation of a lexer, used by `git-safety`, `secrets-guard`, and `enforce-uv-run`. Any correctness bug there affects multiple hooks at once. Keeping it in bash avoids a python dependency for guards — correct choice — but the complexity buys a test harness. **User confirmed:** add unit tests.

  2. **`HOOK_LOG_DB` default path + lessons path are hardcoded to `$HOME/.claude/`.** Globally-shared databases are correct per canon, but the path itself is ambient rather than configurable. **User call:** make `HOOK_LOG_DB`, `LESSONS_DB` (and any other global-db paths) configurable via env vars in `settings.json`, like `CLAUDE_DOCS_DIR` and `CLAUDE_MEMORIES_DIR` already are. Same pattern, extends the configuration surface consistently.

- **Action:** at decision point: (1) add unit tests for `_strip_inert_content` (parametrize heredoc / single-quote / double-quote / nested / edge cases), (2) surface `HOOK_LOG_DB`, `LESSONS_DB`, and any other db paths as env vars in `settings.template.json` + `_env_config` comment block, keeping current defaults.
- **Scope:** (1) moderate — new test file; (2) small — variable-rename + docs + template update.

### `grouped-bash-guard.sh`

- **Tag:** `Keep`
- **Finding:** Dispatcher for Bash PreToolUse. Sources 6 guards (block-dangerous-commands, git-safety, secrets-guard, block-config-edits, enforce-make-commands, enforce-uv-run) and iterates match→check. Distribution-tolerant: probes files before sourcing so raiz can omit enforce-make/enforce-uv. Logs per-substep outcomes (`pass`/`block`/`not_applicable`/`skipped`) for traceability. The `BLOCK_IDX` pattern correctly marks downstream checks as `skipped` rather than skipping the logging.
- **Action:** none.

### `grouped-read-guard.sh`

- **Tag:** `Keep`
- **Finding:** Mirror of grouped-bash-guard for Read tool. Hosts `secrets_guard_read` + `suggest_read_json`. Same structure, same distribution tolerance, same outcome logging. Doc comment correctly notes *why* Grep isn't dispatched here (single check doesn't amortize).
- **Action:** none.

### `block-dangerous-commands.sh`

- **Tag:** `Keep`
- **Finding:** Classic guard — rm -rf /, fork bombs, mkfs, dd to disk, chmod -R 777 /, sudo. Uses subshell/backtick/eval/bash -c normalization in `check_dangerous` to defeat the obvious obfuscations. Fork-bomb check uses raw `$COMMAND` (not the normalized version) intentionally — normalization could mangle the `(){...|:...}` syntax. That nuance is commented.
- **Action:** none.

### `git-safety.sh`

- **Tag:** `Keep`
- **Finding:** Two branches — EnterPlanMode (protected-branch blocking) and Bash (git push/commit gates). Bash branch goes through match/check; EnterPlanMode stays in `main` because it's not grouping-eligible (different event). Comprehensive push coverage: force push, --mirror, --delete, colon-syntax deletes, cross-branch pushes. Commit-on-protected-branch check uses `git branch --show-current` at execution time, with a note in the reason message that chaining `git checkout && git commit` won't defeat this.
- **Action:** none.

### `secrets-guard.sh`

- **Tag:** `Keep`
- **Finding:** Three branches — Read (file_path matching), Grep (path/glob matching), Bash (command-verb + credential-path regex). Shared data via `BLOCKED_PATHS` array + helper functions (`_env_file_block_reason`, `_credential_path_block_reason`) used by both standalone and match/check paths. Handles cross-platform concerns (literal `~/` normalized to `$HOME`). .example/.template allowlist correctly positioned *before* block checks. Bash branch uses `_strip_inert_content` first — this is exactly what that library function exists for.
- **Action:** none on the hook itself.
- *Minor observation:* the Bash branch has the most complex regex set in the hook suite. Good test coverage (per `tests/test-hooks.sh test_secrets_guard` reference) is the mitigation. See `lib/hook-utils.sh` finding for the related call on `_strip_inert_content` unit-test coverage.

### `block-config-edits.sh`

- **Tag:** `Keep`
- **Finding:** Three branches — Write, Edit (direct path matching via `is_blocked_config`) and Bash (regex for redirect/tee/sed -i/mv targeting home config files). Clean separation: tool-input-shaped branches for Write/Edit (exact path match), pattern branch for Bash (regex). The comment at §line 6-8 references a hypothetical `grouped-write-guard` that doesn't yet exist — it's in the backlog.
- **Action:** none.

### `enforce-make-commands.sh`

- **Tag:** `Keep`
- **Finding:** Redirects `pytest` / `pre-commit` / `ruff check|format` / `uv sync` / `docker up|down` to their equivalent make targets. Only blocks *bare* runs (`pytest`, not `pytest tests/file.py`) — deliberate: targeted invocations are legitimate. `PATTERNS` array uses `:::` delimiter to avoid regex `|` collision — small but correct.
- **Action:** none.

### `enforce-uv-run.sh`

- **Tag:** `Keep`
- **Finding:** Redirects `python`/`python3`/`python3.X` to `uv run python`. Correctly uses `_strip_inert_content` to ignore python tokens inside commit messages and heredoc bodies. Allow-passes when command already contains `uv run`.
- **Action:** none.

### `approve-safe-commands.sh`

- **Tag:** `Rewrite`
- **Finding:** PermissionRequest hook — splits commands on `&&/||/;/|` and auto-approves if every subcommand matches a safe prefix. Two things:

  1. **`SAFE_PREFIXES` duplicates the `settings.json` allowlist.** Doc comment (line 48) says *"must match settings.json permissions.allow Bash entries"* and points at `.claude/scripts/validate-safe-commands-sync.sh`. Worth confirming the validate script still runs in `make check` (per `relevant-toolkit-permissions_config.md` §3 line 63). Silent drift risk otherwise.

  2. **Hook doesn't follow match/check shape.** Monolithic `main`. PermissionRequest isn't grouping-eligible (different event lifecycle), so it doesn't need to participate in a dispatcher — but it *can* still adopt the `match_<name>` / `check_<name>` + dual-mode trigger structure for consistency with every other PreToolUse guard in the directory. **User call:** align this hook to the match/check skeleton (without dispatcher participation). Same shape, same testability benefits, no new grouping mechanics.

- **Action:** at decision point: (1) verify `validate-safe-commands-sync.sh` still runs in `make check`, (2) refactor approve-safe-commands to match/check skeleton (keep monolithic behavior inside `check_` + thin `match_` predicate; standalone `main` retained since no dispatcher).
- **Scope:** (1) grep. (2) moderate — straightforward refactor, ~20-line reorganization, preserves semantics.

### `suggest-read-json.sh`

- **Tag:** `Investigate`
- **Finding:** Follows match/check + dual-mode correctly. Allowlist for common small config files (package.json, tsconfig.json, etc.) and `*.config.json` glob. Size threshold is env-configurable (`JSON_SIZE_THRESHOLD_KB`, default 50). Redirects large JSON reads to `/read-json` skill.

  **User observation:** Claude (the session) has effectively stopped reading `.json` files with Read tool — either delegates to the `/read-json` skill or uses `jq` in Bash directly. If that behavior is now baked in without the hook's nudge, this redirect is redundant. Flagging to reassess: is the hook still earning its place, or has the lesson it was teaching been absorbed?

- **Action:** at decision point: (1) check `hooks.db` for how often this hook fires a `block` outcome vs `not_applicable` — if blocks are rare, Claude's already trained on the behavior and the hook can be retired. (2) If retired, fold the `/read-json` skill's size-threshold logic into the skill itself (so invoking `/read-json` still works, just without the guardrail nudge). (3) If kept, add a decision-point note explaining why.
- **Scope:** (1) small db query. (2) depends on outcome — might be a deletion (smaller) or a no-op (if kept).

### `session-start.sh`

- **Tag:** `Rewrite`
- **Finding:** SessionStart hook — injects essential docs, docs guidance, git context, toolkit-version mismatch warning, lessons surfacing, ecosystems-opt-in nudge, acknowledgment directive. Correctly gated by `hook_feature_enabled lessons` for the lessons section — when we flipped `CLAUDE_TOOLKIT_LESSONS=0` this session, the hook skipped the query + output + nudge cleanly, and the ACK_MSG skipped the "N lessons noted" suffix. Verified the opt-in is wired right.

  Three calls:

  1. **`MAIN_BRANCH` resolution (lines 71-72)** uses `git symbolic-ref refs/remotes/origin/HEAD` and falls back to hardcoded `"main"`. **User call:** `bm-sop` uses `develop` as its main branch — the current fallback chain (symbolic-ref → literal "main") may or may not be working there and is fragile. **Make `MAIN_BRANCH` configurable via env var in `settings.json`**, same pattern as `CLAUDE_DOCS_DIR`/`CLAUDE_MEMORIES_DIR`/`PROTECTED_BRANCHES`. Default to the symbolic-ref lookup, fall back to env override, final fallback to `"main"`. This removes the per-project git-symref dependence and makes the behavior explicit.

  2. **Legacy `learned.json` fallback (lines 206-220).** Fires when lessons.db is missing but learned.json exists. Same cleanup question as `cli/lessons/db.py`'s `cmd_migrate`: grep consumers for remaining `learned.json`; remove the entire fallback branch if zero. Couple this decision with the cli/ audit item so both are ripped together.

  3. **Ecosystems-opt-in nudge (lines 222-230).** Correctly distinguishes "both keys unset" from "explicitly 0" via `[ -z "${VAR+x}" ]`. Sunset tracked in `BACKLOG.md → remove-ecosystems-opt-in-nudge`. Tech debt with a clear removal plan — leave as-is for v3.

- **Action:** at decision point: (1) surface `MAIN_BRANCH` as env var in `settings.template.json` + `_env_config` comment block, update this hook to honor it (symref → env → "main"), (2) coordinate legacy learned.json removal with cli/ audit.
- **Scope:** (1) small — ~5-line change in the hook + template update; (2) depends on the consumer grep outcome.

### `surface-lessons.sh`

- **Tag:** `Rewrite`
- **Finding:** This is the hook that surfaced irrelevant lessons every tool call during the stage-2 audit session. Now that the code is visible, the root cause is clear:

  **Relevance filter is too loose.** Lines 52-68 build the SQL `CONDITIONS` clause by `LIKE '%word%'` matching each tokenized context word against `tags.keywords`. A tag's `keywords` field holds comma-separated terms (e.g., `git,commit,merge,rebase,branch,push,pull,checkout`). Any context word ≥3 chars that substring-matches *any* keyword in *any* tag passes. That means:

  - `Read("planning/v3-audit/dist.md")` tokenizes to include `planning`, `v3`, `audit`, `dist`, `md`. The `git` tag has keyword `branch`. "planning" doesn't match, but other context words routinely do.
  - When the context has broad tokens (like "git" anywhere — and git appears in a lot of commit messages, branch names, paths), the `git`-tagged lessons match pervasively.
  - There's **no relevance threshold**, no scoring, no "skip if a recent injection surfaced the same lesson." First 3 matching lessons win, every tool call.

  The code has `LIMIT 3` to cap output volume but not the *repetition* across successive calls. The three lessons I saw surfaced this session (pushback signal, BACKLOG non-code-changes handling, tag-merge-commit) fired on every single tool call unchanged for ~20 consecutive calls — because the context kept matching `git`-tagged + `recurring`-tagged lessons and there's no dedup window.

  **Suggested fix directions** (not prescribing; decision-point calls):

  - **Dedup window.** Track "lesson IDs surfaced in the last N calls for this session" and skip them. Even just "don't re-surface within 60 seconds" would cut 95% of the noise I saw.
  - **Minimum match specificity.** Require ≥2 keyword matches across ≥2 context words before surfacing, instead of single-keyword-substring.
  - **Exclude trivially-common keywords.** Words like `branch`, `commit`, `file`, `read`, `main` appear in almost every tool call — tag keyword lists should probably exclude them or weight them lower.
  - **Context-type awareness.** A Read call tokenizing a path is different signal than a Bash call tokenizing a real command. Path tokens are often filenames that overlap with unrelated keywords.

  **User framing:** this hook *does* earn its place occasionally — when it's noisy it wastes tokens, but sometimes it re-rails behavior that matters (user cited wrap-up flows where 'you' mention the surfaced lessons and stop merging in auto mode, which is good). The redesign constraint is explicit: **no haiku sidecar to check context relevance** — that was tried and deemed unreliable, the hook must stay deterministic. So the fix has to be algorithmic on the existing signal, not a bolt-on model call. That matches directions 1 and 2 (dedup window + minimum match specificity), not directions 3 and 4 (which drift toward model-assisted filtering even if not explicit).

- **Action:** at decision point: implement **dedup window + minimum match specificity** together. Dedup window is highest-impact per line of code (cuts repetition across successive calls); specificity gate is the filter that prevents lone-keyword-substring drift-ins. Both are deterministic and cheap.
- **Scope:** ~30-40 lines of bash. Dedup tracking can use `hooks.db` (add a `surfaced_lesson_ids` table or reuse `surface_lessons_context`) or a per-session file. Specificity gate is a `HAVING COUNT(DISTINCT matched_word) >= 2` clause plus minimum-word-length tuning.

---

## Cross-cutting notes

- **The hooks directory is a master class in workshop identity done right.** Every hook is an authored-once, synced-to-many artifact. Guards enforce local behavior in each consumer's session, not across consumers. Opt-in flags (`CLAUDE_TOOLKIT_LESSONS`, `CLAUDE_TOOLKIT_TRACEABILITY`) let consumers turn ecosystems off without code changes.

- **Match/check pattern adoption is near-complete** — 7 of 10 guard-style hooks follow it (block-dangerous, git-safety, secrets-guard, block-config-edits, enforce-make, enforce-uv, suggest-read-json). The 3 that don't (approve-safe-commands, session-start, surface-lessons) have defensible reasons (different event semantics), but the docs (`relevant-toolkit-hooks.md` §9) don't spell those reasons out — a finding to feed back to the `.claude/docs/` audit queue.

- **Distribution tolerance is load-bearing for raiz.** Both dispatchers (grouped-bash-guard, grouped-read-guard) probe each source file before sourcing. raiz ships without `enforce-make-commands.sh` and `enforce-uv-run.sh` — the dispatchers silently skip them. This is the mechanism that lets the raiz MANIFEST be a strict subset without breaking.

- **`hooks.db` location.** `HOOK_LOG_DB="${HOOK_LOG_DB:-$HOME/.claude/hooks.db}"` — hooks.db is global (`~/.claude/`), same pattern as lessons.db. Aligns with the v3 canon "global runtime state in ~/.claude/, schema ownership in satellites."

- **One real `Rewrite` (surface-lessons) and one half-rewrite candidate (session-start legacy path).** Everything else is solid.

---

## Decision-point queue (carry forward)

Several items were resolved during the review (calls noted inline):

**Resolved during review (pending execution at decision point):**

1. `lib/hook-utils.sh` — **add unit tests for `_strip_inert_content`** (heredoc / single-quote / double-quote / nested / edge cases).
2. `lib/hook-utils.sh` + `settings.template.json` — **surface global-db paths as env vars** (`HOOK_LOG_DB`, `LESSONS_DB`, any others) in the `env` block and document in `_env_config` comment. Keep current defaults.
3. `approve-safe-commands.sh` — **refactor to match/check skeleton** (standalone, no dispatcher participation). Aligns with every other PreToolUse guard's shape without needing grouping.
4. `session-start.sh` + `settings.template.json` — **surface `MAIN_BRANCH` as env var**. Hook honors symref → env override → "main" fallback chain. Unblocks projects like bm-sop that use `develop`.
5. `surface-lessons.sh` — **implement dedup window + minimum match specificity** together. Deterministic fix only; no haiku sidecar (previously tried, unreliable). Dedup window tracks surfaced IDs per session; specificity gate requires ≥2 keyword matches across ≥2 context words.
6. `suggest-read-json.sh` — **check `hooks.db` for block-outcome frequency**; if rare, Claude has absorbed the `/read-json` redirect behavior and the hook can be retired. Fold any size-threshold logic into the skill if retired.

**Coordinated with other audit directories:**

7. `session-start.sh` legacy `learned.json` fallback — couple with `cli/lessons/db.py` `cmd_migrate` decision. Grep consumers for remaining `learned.json`; remove fallback branch + CLI subcommand together if zero.

**Still open / low-priority:**

8. `approve-safe-commands.sh` — verify `validate-safe-commands-sync.sh` still runs in `make check` (trivial grep).
9. (Cross-reference to `.claude/docs/` audit) `relevant-toolkit-hooks.md` §9 — after approve-safe-commands refactor (item 3), the "doesn't follow match/check" clarification becomes moot for that hook. Still need to document why `session-start.sh` and `surface-lessons.sh` are shaped differently (context injection, not guard).
