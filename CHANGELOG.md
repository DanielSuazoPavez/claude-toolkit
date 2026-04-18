# Changelog

## [Unreleased]

## [2.59.1] - 2026-04-18 - Fix backlog validate script path

### Fixed
- **cli**: `claude-toolkit backlog validate` exited 127 — `cli/backlog/query.sh` dispatched to `backlog-validate.sh` but the script is named `validate.sh` (per `cli/CLAUDE.md`).

### Notes
- Docs: `BACKLOG.md` reorganized — `drop-hook-timing-tsv` promoted to P1, `tests-rethink-suite-phase3` moved from P2 to P3 (retitled "Re-evaluate grouping runners into subdirs at some point") with a 2026-04-18 review note recording current suite sizes.

## [2.59.0] - 2026-04-18 - Normalize writer timestamps to UTC Z

### Changed
- **hooks**: `lib/hook-utils.sh` lines 174 and 402 now emit `date -u +%Y-%m-%dT%H:%M:%S.%3NZ` (UTC, literal `Z`, millisecond precision) instead of local time + numeric offset. Affects `hook_logs.timestamp` INSERTs and the hook-timing TSV row.
- **scripts**: `statusline-capture.sh` `captured_at` switches from `jq (now | todate)` (second precision) to a shell `date -u` + `jq --arg`, preserving the canonical UTC-Z format and gaining millisecond precision for high-frequency statusline samples. Setup-toolkit skill snippet updated to match.

### Notes
- Aligns toolkit-owned writers with the canonical format claude-sessions uses for cross-source time-window joins via `ATTACH`. Live-DB backfill of pre-change offset-format rows and the `hook_logs.timestamp` schema retype are owned by claude-sessions; offset rows are unambiguously convertible, so no merge-ordering coordination is required.

## [2.58.0] - 2026-04-18 - Unified test runner

### Changed
- **tests**: new `tests/run-all.sh` dispatches every top-level bash suite plus pytest in parallel via `xargs -P`, with a single unified `✓/✗` summary and failing-suite log dumps (same shape as `run-hook-tests.sh`). `make test` now goes through this runner — each top-level `test-*.sh`, `run-hook-tests.sh`, and `pytest` counts as one unit in the tally. Pytest is now wired into `make test` (previously it had to be run standalone). Filter (`bash tests/run-all.sh cli`), verbose (`-v`), and `TEST_JOBS=N` are forwarded to children. Granular `make test-*` targets kept for focused runs; new `make test-pytest` added for symmetry.

## [2.57.2] - 2026-04-18 - Drop is_test from hook log writers

### Removed
- **hooks**: `is_test` column dropped from all hook log writers (TSV + SQL INSERTs in `lib/hook-utils.sh`). Test isolation is now provided entirely by `HOOK_LOG_DB` redirection in `tests/lib/hook-test-setup.sh`, so the column is redundant. The `CLAUDE_HOOK_TEST` env var and `IS_TEST` bash variable that backed the column are also removed. Live DB schema drop (column removal on `~/.claude/hooks.db`) is owned by `claude-sessions`; until that migration lands, INSERTs that omit `is_test` rely on its `NOT NULL DEFAULT 0` — verified against a live-schema clone.

### Notes
- Phase 2 `turn_id` population (referenced in v2.57.0) has been cancelled. Turn analytics (idle-vs-active detection, user→stop cycle grouping) will be derived from transcript data inside `claude-sessions` — which already indexes transcripts — rather than from hook-side state. The `turn_id` column in `hook_logs` stays empty by design.

## [2.57.1] - 2026-04-18 - Hook test suite split + parallel runner

### Changed
- **tests**: `tests/test-hooks.sh` (monolithic, 1270 lines, ~36.5s sequential) split into 13 per-hook files under `tests/hooks/test-*.sh`. Shared setup extracted to `tests/lib/hook-test-setup.sh` (each file gets its own temp `hooks.db` clone via `HOOK_LOG_DB`, so parallel runs don't contend). Hook `expect_*` helpers moved into `tests/lib/test-helpers.sh`.
- **tests**: new `tests/run-hook-tests.sh` dispatches the per-hook files in parallel via `xargs -P` (default `nproc`, override via `HOOK_TEST_JOBS`). Per-file stdout/stderr go to `tests/.logs/<name>.log` (gitignored); summary shows `✓/✗ test-<name>.sh (Xs)` per file and dumps failing files' full logs after the summary. `make test-hooks` now calls this runner with `-q`.
- **tests**: `make check` drops from ~66s to ~36s on an 8-core dev box.

### Removed
- **tests**: 4 fragile `tail -1 | cut -f1` assertions against `.claude/logs/hook-timing.log` in `test_session_id_from_stdin`. Those patterns were only safe under sequential execution; DB-scoped assertions below already cover the same write contract via id-scoped queries. TSV writer in `hook-utils.sh` untouched (tracked as follow-up backlog `drop-hook-timing-tsv`).

## [2.57.0] - 2026-04-18 - hook_logs.call_id

### Added
- Hook `hook_logs` rows now carry a `call_id` column — prefix-namespaced (`tool:<tool_use_id>` for Pre/PostToolUse, `agent:<agent_id>` for SubagentStop, empty for lifecycle events). Enables per-call grouping of hook perf data without relying on timestamp collation. Schema migration (adds `call_id` + `turn_id` columns and indexes) is owned by `claude-sessions`; this release plumbs `CALL_ID` through the three `hook_logs` INSERTs in `lib/hook-utils.sh`. `turn_id` stays empty — populated in Phase 2 (`hook-logs-turn-id`).

## [2.56.0] - 2026-04-18 - Grouped Read dispatcher

### Added
- **hooks**: `grouped-read-guard.sh` PreToolUse dispatcher folds `secrets-guard` (Read branch) and `suggest-read-json` into one bash invocation for `Read` tool calls. Saves ~30ms per Read by amortizing bash startup, `hook-utils.sh` sourcing, and `jq` parsing across both checks. Grep stays on standalone `secrets-guard.sh` (single check — nothing to fold). Raiz picks up the dispatcher via `dist/raiz/MANIFEST` and settings template; raiz Grep coverage is new (base already ran `secrets-guard` on `Read|Grep`).

### Changed
- **hooks**: `secrets-guard.sh` — extracted `_env_file_block_reason` / `_credential_path_block_reason` helpers and added `match_secrets_guard_read|_grep` + `check_secrets_guard_read|_grep` functions. Existing `check_env_file` / `check_credential_path` become thin wrappers around the reason helpers; standalone `main()` behavior unchanged. Grep match/check pair is unused by the current dispatcher but kept for future folding if Grep gains more checks.
- **hooks**: `suggest-read-json.sh` — dual-mode refactor (standalone `main()` guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, plus `match_suggest_read_json` / `check_suggest_read_json` for the dispatcher).
- **settings**: `.claude/settings.json`, `dist/base/templates/settings.template.json`, and `dist/raiz/templates/settings.template.json` — `Read` matcher now points at `grouped-read-guard.sh`; `Grep` matcher runs `secrets-guard.sh` standalone.

## [2.55.2] - 2026-04-18 - Isolate hooks.db writes in test harness

### Changed
- **hooks**: `lib/hook-utils.sh` — `HOOK_LOG_DB` now honors a pre-set value (`${HOOK_LOG_DB:-$HOME/.claude/hooks.db}`) so tests and other callers can redirect hook_logs writes to an isolated SQLite path. Production behavior unchanged when the env var is unset.
- **tests**: `tests/test-hooks.sh` — sets up a per-run temp DB via `mktemp`, clones the schema from `~/.claude/hooks.db` if present (so toolkit's write contract is still verifiable), exports `HOOK_LOG_DB` to point at the temp path, and traps `rm -f` on EXIT. The three DB-assertion blocks (`session_id propagates`, `dynamic session_id also reaches`, `SessionStart source captured`) now read from the temp DB. Prevents tests from polluting the real hooks.db (owned by claude-sessions). Emits a stderr warning if the real DB exists but the schema clone produced no `hook_logs` table, so silent clone failures don't quietly skip write-contract coverage.

## [2.55.1] - 2026-04-17 - Hook authoring skills teach match/check

### Changed
- **skills**: `create-hook` and `evaluate-hook` now teach and score the match/check pattern shipped in 2.54.0–2.55.0. `create-hook`'s Bash PreToolUse skeleton is the `match_<name>` + `check_<name>` + `main` + dual-mode-trigger shape, uses `${BASH_SOURCE[0]}` for the source path, and documents standalone-vs-grouped registration (including adding to `grouped-bash-guard.sh`'s `CHECK_SPECS`). `evaluate-hook`'s D1/D4 checks and anti-patterns table now cover the cheapness contract for `match_`, the `_BLOCK_REASON` convention, dual-mode trigger presence, `$0` vs `${BASH_SOURCE[0]}`, and dual registration. Edge-case table notes match/check is Bash-PreToolUse-only today.

### Added
- **tests**: `tests/test-hooks.sh` — direct smoke tests for `grouped-bash-guard.sh` dispatcher. Covers base (all 6 guards present) and a raiz simulation (copies hooks to a `mktemp -d`, deletes `enforce-make-commands.sh` + `enforce-uv-run.sh`). Four cases: benign `ls` passes, `pytest` blocks via make guard, raiz-sim `pytest` passes, raiz-sim force-push still blocks via `git_safety`.
- **hooks**: `grouped-bash-guard.sh` — emits `hook_log_substep` with section `check_<name>_missing_match_check` and outcome `skipped` when a guard's source file is present but its `match_/check_` pair is missing. Rename/drift signal; distribution-absent files short-circuit before the event so raiz's normal missing guards stay silent.

### Fixed
- **tests**: `tests/test-raiz-publish.sh` — stale v2.55.0 assertion still expected standalone `block-dangerous-commands.sh` in the raiz template. Replaced with positive assertion for `grouped-bash-guard.sh` and negative assertion that the standalone entry is gone.

## [2.55.0] - 2026-04-16 - Grouped bash guard in raiz

### Changed
- **hooks / raiz**: `grouped-bash-guard.sh` dispatcher now builds `CHECKS` dynamically from `CHECK_SPECS` — guards whose source files aren't present in the current distribution (e.g. `enforce-make-commands`, `enforce-uv-run` in raiz) are silently skipped. Raiz now ships `grouped-bash-guard.sh` as its sole Bash `PreToolUse` hook instead of the four-hook split config, expected to cut per-Bash-turn hook cost roughly 3× (from ~440ms to ~200ms envelope per A/B data in `output/claude-toolkit/exploration/grouped-hook-ab.md`). Non-Bash branches keep standalone entries.

## [2.54.1] - 2026-04-16 - Hook false-positive fix for quoted/heredoc content

### Fixed
- **hooks**: `enforce-uv-run`, `secrets-guard`, and `git-safety` no longer false-positive on tokens (`python`, `.env.local`, `git commit`) that appear inside quoted strings or heredoc bodies of an outer command — e.g. `git commit -m "refactor python hook"`, or `git commit -m "$(cat <<EOF ... Removed .env.local references. ... EOF)"`. All three hooks now strip heredoc bodies and quoted string content from `$COMMAND` before running their Bash-branch regexes.

### Added
- **hooks**: `lib/hook-utils.sh` gained `_strip_inert_content` — shared helper that returns a "command skeleton" with heredoc bodies and quoted strings blanked, so downstream regexes match only content bash would execute. Heuristic (doesn't perfectly handle nested/escaped edge cases); sufficient for guards meant to catch obvious mistakes, not adversaries.

## [2.54.0] - 2026-04-16 - Grouped bash guard as default

### Changed
- **settings**: `.claude/settings.json` and `dist/base/templates/settings.template.json` — `grouped-bash-guard.sh` is now the sole Bash `PreToolUse` hook. `block-dangerous-commands`, `enforce-uv-run`, `enforce-make-commands` no longer register standalone on Bash (dispatcher-only); `git-safety`, `secrets-guard`, `block-config-edits` keep their non-Bash matchers (`EnterPlanMode`, `Read|Grep`, `Write|Edit`) and their Bash branch runs via the dispatcher. Base-profile projects picking up the template via `claude-toolkit sync` inherit the grouped config automatically.
- **dist/raiz**: New `dist/raiz/templates/settings.template.json` override — raiz keeps the split config because `grouped-bash-guard.sh` sources six guards but raiz only ships four of them (no `enforce-make-commands`, no `enforce-uv-run`). Migration tracked by backlog task `raiz-grouped-bash-guard`. `publish.py`'s `resolve_source_file` already honored dist-specific template overrides — no publish changes needed.

### Removed
- **settings**: `.claude/settings.grouped.json.example` and `.claude/settings.grouped.README.md` — grouped is the default now, A/B swap artifacts no longer needed. Historical context preserved in CHANGELOG 2.52.0 and 2.53.0 entries.

### Docs
- **exploration**: `output/claude-toolkit/exploration/grouped-hook-ab.md` — phase-2 re-measurement section added. Grouped dispatcher now runs 6 guards (`dangerous, git_safety, secrets_guard, config_edits, make, uv`) at the same ~202ms envelope as the phase-1 3-guard variant, because 5 of 6 substeps skip to `not_applicable` via cheap `match_` predicates (1.6–2.5ms median). `check_dangerous` dropped 61.5ms → 21.5ms as the only full-body substep. Validates the match-cheapness contract against real `hook_logs` data.
- **docs**: `docs/indexes/HOOKS.md` — entry for `grouped-bash-guard` changed from `experimental` / `opt-in` to `stable` / default. Sourced guards relabeled from standalone Bash triggers to "Bash via dispatcher".
- **docs**: `.claude/docs/relevant-toolkit-hooks.md` §9 simplified — single current-hook table (no more default vs grouped split), with a note pointing at the raiz backlog task.

## [2.53.0] - 2026-04-16 - Match/check hook architecture (phase 2)

### Changed
- **hooks**: match/check architecture for every Bash-touching hook — each now exposes a cheap `match_<name>` predicate (pure bash, no forks/jq/git) and a `check_<name>` guard body, with a thin `main()` for standalone mode and a dual-mode trigger (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) so the same file works sourced or invoked directly. Converted: `git-safety`, `secrets-guard` (Bash branch), `block-config-edits` (Bash branch), `block-dangerous-commands`, `enforce-make-commands`, `enforce-uv-run`. Read/Grep/Write/Edit/EnterPlanMode branches stay in `main` since they don't flow through the Bash dispatcher.
- **hooks**: `grouped-bash-guard.sh` now sources the six hook files as libraries and iterates a `CHECKS` array (`dangerous git_safety secrets_guard config_edits make uv`), calling `match_` first and the `check_` body only when match is true. Inlined placeholder definitions removed — single source of truth per hook, no drift between standalone and grouped mode.
- **hooks**: `hook-utils.sh` added `_HOOK_UTILS_SOURCED` idempotency guard — dispatchers source hook-utils once, then source hook files that also source hook-utils; without the guard, the second source would reset `HOOK_INPUT` / `TOOL_NAME` globals and every check would bail.
- **hooks**: `hook_log_substep` gained a new `not_applicable` outcome — recorded when `match_` returns false (check body skipped by design). Distinct from `skipped` (predecessor blocked, short-circuited). Analytics queries measuring match accuracy filter for `not_applicable`; queries measuring "ran to completion" filter out both.
- **settings**: `.claude/settings.grouped.json.example` narrowed the standalone matchers for the three dual-matcher hooks — `block-config-edits` to `Write|Edit`, `secrets-guard` to `Read|Grep`, `git-safety` to `EnterPlanMode`. Their Bash branches run exclusively via the dispatcher. Bash-only hooks (`block-dangerous-commands`, `enforce-make-commands`, `enforce-uv-run`) have no standalone registration in the grouped variant.

### Docs
- **docs**: `.claude/docs/relevant-toolkit-hooks.md` — authoring pattern reference for match/check hooks. Covers hook events recap, standalone vs grouped registration, the match cheapness contract, dual-mode trigger, outcomes (including `not_applicable`), dispatcher internals, the `hook-utils.sh` idempotency guard, current hook set, and anti-patterns.
- **design**: `output/claude-toolkit/design/20260416_1830__design-doc__match-check-hook-architecture.md` — original architecture proposal. Backlog: `match-check-hook-architecture` (complete).

## [2.52.3] - 2026-04-16 - SessionStart source capture

### Changed
- **hooks**: `.claude/hooks/lib/hook-utils.sh` — now extracts the `source` field from `SessionStart` stdin (`startup | resume | clear | compact`) and includes it in `hook_logs` INSERTs. Unblocks claude-sessions sub-session boundary analytics — the column lets downstream queries distinguish mid-session `/clear` and auto-compact events within a single `session_id`. Non-`SessionStart` events leave the value empty; jq extraction is guarded by event type to avoid hot-path cost on `PreToolUse`. The `source` column itself is managed by the claude-sessions schema.

### Docs
- **design**: `output/claude-toolkit/design/20260416_1730__design__sub-session-boundaries.md` — captures the full sub-session detection design this change enables (copied from claude-sessions).

## [2.52.2] - 2026-04-16 - Fix EPOCHREALTIME ms parsing

### Fixed
- **hooks**: `.claude/hooks/lib/hook-utils.sh` and `.claude/hooks/grouped-bash-guard.sh` — the `${EPOCHREALTIME/./}:0:13` pattern assumed 6 microsecond digits and silently returned a ~10× too small value when the fractional part was shorter, producing negative `end_ms - start_ms` durations in `hooks.db` (observed: -1237ms for `surface-lessons`, -611ms for `block-config-edits`). Extracted a shared `_now_ms` helper that splits on `.`, zero-pads frac to 6, and computes `sec*1000 + frac/1000`. Replaced 3 inline callsites in `hook-utils.sh` and removed the duplicated buggy helper from `grouped-bash-guard.sh` (which already sources `hook-utils.sh`).

## [2.52.1] - 2026-04-16 - Millisecond precision in hook timestamps

### Fixed
- **hooks**: `.claude/hooks/lib/hook-utils.sh` — `_HOOK_TIMESTAMP` and the EXIT-trap `ts` now use `date +%Y-%m-%dT%H:%M:%S.%3N%:z` instead of `date -Iseconds`. Multiple hook rows from the same turn used to share an identical second-precision timestamp, making them unorderable in `hooks.db`. Adds millisecond precision.

## [2.52.0] - 2026-04-16 - Grouped Bash guard hook (A/B)

### Added
- **hooks**: `.claude/hooks/grouped-bash-guard.sh` — consolidates `block-dangerous-commands`, `enforce-make-commands`, and `enforce-uv-run` into a single dispatcher. Amortizes bash startup + `hook-utils.sh` sourcing + `jq` `tool_input` parsing across the 3 checks. Short-circuits on block and logs remaining checks as `outcome=skipped`.
- **hooks**: `hook_log_substep` helper in `.claude/hooks/lib/hook-utils.sh` — records per-sub-step duration and outcome rows (TSV + SQLite) for grouped hooks, keeping per-check cost visible for analytics.
- **settings**: `.claude/settings.grouped.json.example` + `.claude/settings.grouped.README.md` — sibling A/B variant registering the grouped dispatcher in place of the 3 split Bash hooks, plus `cp`-based swap/restore instructions. Default `settings.json` unchanged; grouped config is opt-in.

### Changed
- **hooks**: `session-start.sh` and `surface-lessons.sh` — added rationale comments explaining why single-quote doubling is sufficient for SQL escaping (sqlite3 CLI has no bind-parameter flag; inputs are local `$PWD` and git refs, not external).

### Notes
- Initial A/B measurement (split n=1147/580/767 historical vs grouped n=2 this session) shows ~229ms → ~202ms per Bash turn (~12%, small grouped-n so direction-only confidence). Details in `output/claude-toolkit/exploration/grouped-hook-ab.md`. Phase 2 (folding `secrets-guard` and `git-safety` into the dispatcher) deferred.
- Discovered a latent `EPOCHREALTIME` ms-parsing bug causing rare negative durations in `hooks.db` — filed as P2 backlog task, not fixed in this branch.

## [2.51.1] - 2026-04-16 - Narrow git rm auto-approval

### Changed
- **settings**: `.claude/settings.json`, `dist/base/templates/settings.template.json`, and `.claude/hooks/approve-safe-commands.sh` — `git rm` auto-approval narrowed to `git rm --cached` only. Plain `git rm <file>` deletes from working tree and no longer qualifies as a safe operation.

## [2.51.0] - 2026-04-16 - Statusline capture wrapper

### Added
- **scripts**: `.claude/scripts/statusline-capture.sh` — intercepts Claude Code statusline JSON, appends to `~/.claude/usage-snapshots/snapshots.jsonl`, forwards stdin to powerline. Fail-safe: capture errors never break the statusline.
- **skills**: `/setup-toolkit` statusline step now installs the capture wrapper and pins `@owloops/claude-powerline@1.25.1` (was `@latest`).

### Changed
- **settings**: `.claude/settings.json` and `dist/base/templates/settings.template.json` `statusLine.command` → `.claude/scripts/statusline-capture.sh` (replaces direct `npx` call).

## [2.50.0] - 2026-04-10 - Skill description negative triggers

### Added
- **skills**: Negative trigger disambiguation on 5 skills — `brainstorm`, `brainstorm-idea`, `analyze-idea`, `write-documentation`, `create-docs` now include "Do NOT use for X" exclusion language
- **skills**: `/create-skill` — "Disambiguation" subsection with guidance on negative triggers and 1024-char limit
- **skills**: `/evaluate-skill` D4 — sub-criterion deducting 1-2 pts for missing disambiguation when overlap exists
- **dist**: `analyze-idea` added to raiz MANIFEST (referenced by included brainstorm skills)

## [2.49.1] - 2026-04-10 - Code reviewer test coverage check

### Changed
- **agents**: `code-reviewer` Phase 4 — flags high/medium-risk files with no corresponding test changes as a Risk (defers quality assessment to `/design-tests`)

## [2.49.0] - 2026-04-10 - Skill compatibility field

### Added
- **scripts**: `verify-external-deps.sh` — scans skill frontmatter for `compatibility:` field and checks external tools are installed (warnings only, never fails build)
- **skills**: `compatibility` frontmatter on 9 skills — `jq` (evaluate-agent/batch/docs/hook/skill, read-json, setup-toolkit) and `sqlite3` (learn, manage-lessons)
- **skills**: `/create-skill` template includes commented `compatibility` field
- **skills**: `/evaluate-skill` D4 now checks for missing `compatibility` when `allowed-tools` uses external tools

### Changed
- **validation**: `validate-all.sh` runs `verify-external-deps.sh` as advisory check (between hook-utils and settings-template)

### Tests
- **tests**: 19 tests for `verify-external-deps.sh` — no skills dir, no fields, available/missing/mixed tools, comma parsing, dedup, frontmatter-only parsing

## [2.48.1] - 2026-04-10 - Setup-toolkit statusline step

### Added
- **skills**: `/setup-toolkit` now includes statusline (powerline) configuration step — sets up `@owloops/claude-powerline` with Nord-themed two-line layout (directory/git + model/version/block/context)

## [2.48.0] - 2026-04-10 - Lessons get-by-ID

### Added
- **lessons**: `lessons get <id>` subcommand — shows full detail for a single lesson (all fields including scope, branch, crystallized_from, absorbed_into, promoted, archived)
- **lessons**: `lessons search` and `lessons list` now show lesson IDs in output
- **skills**: CLI quick reference section in `/manage-lessons` skill doc — prevents guessing flags that don't exist
- **tests**: 2 tests for `cmd_get` (existing lesson output, nonexistent ID exit code)

## [2.47.0] - 2026-04-10 - Review-plan subagent delegation

### Changed
- **skills**: `/review-plan` now delegates to a subagent by default — review runs in isolation, writes output to `output/claude-toolkit/reviews/`, and returns a summary to the main agent. Reduces context window pressure from repeated reviews.
- **skills**: `/review-plan inline` flag preserves the previous inline behavior when needed

## [2.46.0] - 2026-04-07 - Lesson scope field

### Added
- **lessons**: `scope` column on lessons table — `global` (default, surfaces everywhere) or `project` (only surfaces in the originating project)
- **lessons**: `--scope` flag on `lessons add` and `lessons list` CLI commands
- **lessons**: `[P]` marker in `lessons list` output for project-scoped lessons
- **lessons**: crystallize inherits `project` scope when all sources are project-scoped for the same project
- **hooks**: `session-start.sh` and `surface-lessons.sh` filter lessons by scope + project name
- **skills**: `/learn` skill includes scope guidance and `--scope` in command examples
- **gitignore**: template now covers `lessons.db`, `session-index.db`, `hooks.db` at project root
- **tests**: 6 new scope tests (insert, default, update, CHECK constraint, crystallize inheritance)

### Removed
- **backlog**: completed `global-configs-dist` task

## [2.45.7] - 2026-04-06 - Wrap-up tag push reminder

### Changed
- **skills**: `/wrap-up` step 9 now reminds user to push the tag after `make tag`

## [2.45.6] - 2026-04-06 - Gapless raiz Telegram notifications

### Fixed
- **toolkit**: `format-raiz-changelog.sh` now emits a minimal "no raiz-relevant changes" message instead of exiting silently when no bullets survive trimming — keeps the Telegram notification chain contiguous across all versions
- **workflow**: `publish-raiz.yml` always calls the formatter and sends a Telegram message, removing the skip conditions that caused version gaps

### Added
- **tests**: new test cases for empty-content formatting — minimal raw message, HTML header with version, and italic "no raiz-relevant changes" line

## [2.45.5] - 2026-04-06 - Wrap-up tagging after merge

### Fixed
- **skills**: `/wrap-up` step 9 now tags on the merge commit on main, not on the feature branch — avoids tag delete/re-create when follow-up changes land after the version bump

## [2.45.4] - 2026-04-06 - Consolidated raiz notification format

### Changed
- **toolkit**: `format-raiz-changelog.sh` — Telegram messages now group bullets by resource type (Skills, Agents, Hooks, etc.) instead of repeating per-version changelog sections. Single version shows date line; ranges show `vX → vY` header only
- **toolkit**: auto-override check simplified — looks for `dist/raiz/changelog/{VERSION}.html` once for the target version, not per-version in the loop

### Fixed
- **toolkit**: bold-prefixed bullets (`- **X**`) in Telegram HTML now correctly get `•` prefix (was dead code due to sed ordering)

## [2.45.3] - 2026-04-06 - Raiz changelog formatter tests

### Added
- **tests**: 62-test suite for `format-raiz-changelog.sh` — covers entry extraction, raiz filtering, version ranges, HTML conversion, override files (both `--override` flag and auto-detected), multi-version output, output modes, and edge cases
- **toolkit**: `FORMAT_RAIZ_PROJECT_ROOT` env var override in `format-raiz-changelog.sh` for test isolation

## [2.45.2] - 2026-04-06 - Multi-version raiz notifications

### Fixed
- **toolkit**: `publish-raiz.yml` now sends Telegram notifications for all versions since last push, not just the latest — reads target repo's `.claude-toolkit-version` to detect the range
- **toolkit**: `format-raiz-changelog.sh` supports `--from <version>` to extract and combine multiple changelog entries into one message

### Changed
- **toolkit**: deduplicated extract+trim logic in `format-raiz-changelog.sh` version loop

### Removed
- **workflow**: `[skip-raiz]` commit message flag — replaced by automatic raiz-relevance detection via MANIFEST trimming

## [2.45.1] - 2026-04-06 - Session ID from stdin JSON

### Fixed
- **hooks**: `hook-utils.sh` reads `session_id` from stdin JSON instead of file-based `.session-id` relay — eliminates race condition when multiple sessions run from the same project folder
- **hooks**: `hook_init` validates stdin JSON — PreToolUse hooks now block on malformed input (fail-closed) instead of silently passing
- **hooks**: removed orphaned perf probe from `session-start.sh` after file-write block removal

### Removed
- **hooks**: debug session-id hooks and relay file `.claude/logs/.session-id`

## [2.45.0] - 2026-04-06 - Token-disciplined reviewer agents

### Changed
- **agents**: implementation-checker — phased investigation protocol (`--stat` first, per-item targeted diffs, incremental report writes), model bumped to opus
- **agents**: code-reviewer — risk-categorized investigation (high→medium→low priority), skeleton written early, incremental report updates
- **agents**: goal-verifier — magnitude-aware depth (trivial/standard/complex), per-must-have verification with immediate writes, restored working-tree intent and stopping criterion

## [2.44.2] - 2026-04-02 - Session-start silent DB failure fix

### Fixed
- **hooks**: session-start — surface lessons.db query failures as actionable items instead of silently reporting 0 lessons (thanks Huskbane)

## [2.44.1] - 2026-04-02 - Review-plan severity calibration

### Changed
- **skills**: `/review-plan` — stop silently auto-fixing plans; review as-is and flag gaps as issues instead
- **skills**: `/review-plan` — agent-guess gaps are Medium minimum (never Low) to prevent false approvals that cause implementation spinning
- **skills**: `/review-plan` — tiered final steps by complexity: code-reviewer always, goal-verifier for medium+, implementation-checker only for strict plans

## [2.44.0] - 2026-03-31 - General-purpose brainstorm skill

### Added
- **skills**: `/brainstorm` — general-purpose brainstorm facilitation (Frame → Explore → Land), converges on clarity instead of design docs
- **dist**: Added brainstorm skill to raiz manifest

## [2.43.8] - 2026-03-31 - Migrate remaining agent See Also to indexes

### Changed
- **agents**: Removed See Also sections from codebase-explorer, code-debugger, pattern-finder, proposal-reviewer (-27 lines total)
- **docs**: Migrated cross-references to `docs/indexes/AGENTS.md` descriptions — all agents now have See Also in index only

## [2.43.7] - 2026-03-31 - Trim reviewer agent prompts

### Changed
- **agents**: code-reviewer — model bumped to opus, effort set to medium, merged 3 "don't" sections into unified What to Skip (-17%)
- **agents**: implementation-checker — compacted beliefs/anti-patterns/scope into single section, removed redundant Tools/What I Don't Do/Status Values (-31%)
- **agents**: goal-verifier — removed duplicate checklists, L3 example, anti-patterns; merged Trust Nothing into core principle, compacted verification depth and negative cases (-41%)
- **agents**: Migrated See Also sections from all 3 agents to `docs/indexes/AGENTS.md`

## [2.43.6] - 2026-03-30 - Skip-raiz flag for publish workflow

### Added
- **workflow**: `[skip-raiz]` commit message flag — skips `publish-raiz` workflow and Telegram notification for versions with no raiz-relevant changes
- **docs**: Raiz evaluation flow in CLAUDE.md Changelog section — check MANIFEST before deciding to skip or draft notification

## [2.43.5] - 2026-03-30 - Powerline config refresh

### Changed
- **config**: Reorganized powerline layout to 2 lines — directory+git on line 1, model+version+block+context on line 2 (auto-wraps on narrow terminals)
- **config**: Pruned git segment (removed sha, timeSinceCommit, repoName), switched block to weighted type
- **config**: Fixed powerline config not being loaded — added `--config=` flag to settings.json command

### Added
- **makefile**: `make tag` target — creates git tag from VERSION file for powerline git tag display
- **skills**: Tagging step (step 9) in `/wrap-up` — runs `make tag` after version bump commit

## [2.43.4] - 2026-03-29 - Adversarial goal-verifier (experimental)

### Changed
- **agents**: goal-verifier now includes mandatory devil's advocate and negative cases sections to reduce false-green rate (experimental)

## [2.43.3] - 2026-03-29 - AWS architecture diagrams for design-diagram

### Added
- **skills**: AWS reference doc for `/design-aws` — two-layer design with checklists (security, monitoring, quotas, backups) and precision corrections (IAM evaluation, cost crossover, API Gateway matrix, Terraform gotchas)
- **skills**: architecture-beta support in `/design-diagram` — AWS service icon mapping, syntax reference, 3 worked examples, rendering compatibility notes

## [2.43.2] - 2026-03-29 - Clear context on plan accept

### Added
- **settings**: `showClearContextOnPlanAccept: true` in settings.json and base template — shows option to clear context and pass plan forward when accepting a plan

## [2.43.1] - 2026-03-27 - Codebase navigation docs

### Added
- **docs**: Codebase Orientation section in root CLAUDE.md — points to explorer reports, indexes, and subfolder docs
- **docs**: `docs/` vs `.claude/docs/` boundary explanation in Structure section
- **docs**: `tests/CLAUDE.md` — file map, shared helpers, running instructions, perf benchmarks

## [2.43.0] - 2026-03-27 - Telegram notifications for raiz distribution

### Added
- **workflow**: Telegram notification step in `publish-raiz.yml` — sends changelog summary after successful raiz sync
- **scripts**: `format-raiz-changelog.sh` — extracts changelog entry, trims to raiz-relevant lines using MANIFEST, formats as Telegram HTML
- **dist**: `dist/raiz/changelog/` override directory — commit a `{version}.html` file to send a hand-written message instead of auto-generated

### Changed
- **workflow**: `publish-raiz.yml` sync step now outputs `pushed=true/false` for downstream gating

## [2.42.0] - 2026-03-27 - Setup-toolkit diagnostic script and cleanup verification

### Added
- **scripts**: `setup-toolkit-diagnose.sh` — consolidated diagnostic that runs all 8 checks in one pass, replacing 15+ individual bash commands in `/setup-toolkit` Phase 1
- **skills**: Check 8 (cleanup verification) in `/setup-toolkit` — detects orphaned resources via MANIFEST, stale hook references, and removal candidates in settings.json
- **cli**: `claude-toolkit validate` subcommand — run diagnostic checks outside of Claude sessions
- **tests**: 40 tests for the diagnostic script covering base and raiz consumer projects
- **dist**: Add `scripts/setup-toolkit-diagnose.sh` to raiz MANIFEST

### Changed
- **skills**: `/setup-toolkit` Phase 1 now invokes a single script instead of inline bash blocks — avoids repeated permission prompts
- **skills**: Check 8 respects `.claude-toolkit-ignore` — project-specific resources not flagged as orphans

## [2.41.0] - 2026-03-27 - Simplify base distribution system

### Changed
- **dist**: Replace `dist/base/MANIFEST` with `dist/base/EXCLUDE` — new resources sync by default, only toolkit-meta resources need explicit exclusion
- **dist**: Sync now generates MANIFEST at sync time for target project validation (was copied from static file)
- **dist**: Add `shape-project`, `refactor`, `review-security` skills to base sync (previously excluded)
- **validation**: Remove MANIFEST check from `validate-settings-template.sh` (failure mode no longer exists)
- **agents**: Bump `goal-verifier` and `code-reviewer` effort to `high` (were failing to write review files at `medium`)

### Removed
- `dist/base/MANIFEST` — replaced by directory walking + EXCLUDE

## [2.40.0] - 2026-03-27 - Add build-communication-style skill

### Added
- **skills**: `/build-communication-style` — guided discovery to build or refine a communication style doc
- **dist**: Add `build-communication-style` skill and `session-start.sh` hook to raiz MANIFEST
- **skills**: `setup-toolkit` now prompts to run `/build-communication-style` after validation
- **docs**: Update `getting-started.md` to reflect current raiz distribution and recommend `/setup-toolkit`

## [2.39.0] - 2026-03-27 - Expand raiz distribution

### Added
- **dist**: Add `draft-pr` and `setup-toolkit` skills to raiz MANIFEST
- **dist**: Add `codebase-explorer` agent to raiz MANIFEST
- **dist**: Add `Makefile.claude-toolkit`, `gitignore.claude-toolkit`, and `PULL_REQUEST_TEMPLATE.md` templates to raiz
- **skills**: Add Check 7 (PR template placement) to `setup-toolkit`
- **templates**: Generic `PULL_REQUEST_TEMPLATE.md` for both distributions

### Changed
- **agents**: `codebase-explorer` output now writes to `.claude/docs/codebase-explorer/{version}/` with automatic version detection (was `output/claude-toolkit/reviews/`)

## [2.38.4] - 2026-03-27 - Fix doc inconsistencies and MANIFEST gaps

### Fixed
- **docs**: HOOKS.md secrets-guard matcher missing `Grep` (now `Read|Bash|Grep`)
- **docs**: HOOKS.md configuration example was stale — replaced with pointer to `settings.json`
- **docs**: HOOKS.md hook environment section incorrectly claimed env vars — hooks use stdin JSON
- **docs**: README doc count was 11, actual is 12
- **docs**: README git clone URL had placeholder username

### Added
- **dist**: Add `relevant-toolkit-lessons.md` to base MANIFEST (now synced to projects)
- **dist**: Add `create-docs` skill to raiz MANIFEST

## [2.38.3] - 2026-03-26 - Fix perf harness instrumentation drift

### Fixed
- **tests**: Replace reimplemented `run_instrumented()` in perf harnesses with `HOOK_PERF=1` probes in actual hooks — eliminates drift between harness and hook logic
- **hooks**: Add `_hook_perf_probe` to hook-utils.sh for opt-in per-phase timing (zero overhead when disabled)
- **tests**: Add `WALL_CLOCK` measurement to harnesses for honest end-to-end timing alongside per-phase breakdown

## [2.38.2] - 2026-03-26 - Add lessons ecosystem reference doc

### Added
- **docs**: `relevant-toolkit-lessons.md` — single reference for the lessons system (schema, tiers, tags, skills, hooks, CLI, lifecycle)
- **docs**: Cross-references from `/learn`, `/manage-lessons` skills, `CLAUDE.md`, and docs index

## [2.38.1] - 2026-03-26 - Fix lessons domain tags and add cli/ docs

### Fixed
- **cli**: Replace `memories` with `docs` in `DOMAIN_TAG_KEYWORDS` (lessons db.py) to match post-migration resource structure

### Added
- **docs**: `cli/CLAUDE.md` — internal reference for CLI module structure, wiring, and conventions
- **docs**: Fix `CLAUDE.md` quick start to use `claude-toolkit backlog` instead of direct script path

## [2.38.0] - 2026-03-26 - Add backlog and eval CLI subcommands

### Added
- **cli**: `claude-toolkit backlog` subcommand — routes to `cli/backlog/query.sh`
- **cli**: `claude-toolkit eval` subcommand — routes to `cli/eval/query.sh`

### Changed
- **cli**: Moved `backlog-query.sh`, `backlog-validate.sh` from `.claude/scripts/` to `cli/backlog/`
- **cli**: Moved `evaluation-query.sh` from `.claude/scripts/` to `cli/eval/`
- **cli**: Fixed `evaluation-query.sh` path resolution for new location (`CLAUDE_DIR` derived from `PROJECT_ROOT`)
- **docs**: Updated all references to moved scripts (CLAUDE.md, Makefile, SCRIPTS.md, workflow doc, evaluate-batch skill, tests)

### Removed
- **backlog**: Removed `cli-list-docs` (partially completed — scripts moved, `/list-docs` migration deferred)

## [2.37.0] - 2026-03-26 - Complete docs migration: rename memory skills to docs skills

### Changed
- **skills**: Renamed `/create-memory` → `/create-docs`, `/evaluate-memory` → `/evaluate-docs`, `/list-memories` → `/list-docs`
- **skills**: Renamed `/write-docs` → `/write-documentation` to avoid confusion with `/create-docs`
- **skills**: Rewrote all three renamed skills for docs scope (`.claude/docs/` creation, evaluation rubric, listing)
- **skills**: Updated cross-references in 10 other skills (create-agent, create-skill, create-hook, evaluate-*, design-diagram, shape-project)
- **skills**: Removed `memories` as evaluate-batch resource type — memories are unstructured, no evaluation needed
- **hooks**: Session-start hook says "essential docs loaded" instead of "essential memories loaded"
- **hooks**: Guidance message references `/list-docs` instead of `/list-memories`
- **scripts**: `evaluation-query.sh` uses `docs` type instead of `memories`
- **docs**: Added `docs/` (user-facing documentation) to directory table in `relevant-toolkit-context`
- **docs**: Updated naming conventions with new skill names
- **dist**: Updated MANIFEST and CLAUDE.md.template for renamed skills
- **cli**: Updated `claude-toolkit` — `memory` type → `doc`, removed `memories` sync category
- **scripts**: `verify-resource-deps.sh` — `memory` ref type → `doc`
- **scripts**: `publish.py` — removed `memories` category, updated ref/bullet patterns to docs
- **tests**: Updated evaluation-query and CLI test fixtures for docs type
- **indexes**: Renamed evaluation keys in `evaluations.json`

### Removed
- **backlog**: Removed `complete-docs-migration` (completed)

### Added
- **backlog**: Added `cli-list-docs` — consider migrating `/list-docs` to CLI

## [2.36.2] - 2026-03-26 - Drop memory prefixes: memories are just files

### Changed
- **memories**: Renamed all memory files — dropped category prefixes (`relevant-context-professional_profile` → `professional_profile`, `personal-context-user` → `user`, `personal-preferences-casual_communication_style` → `casual_communication_style`)
- **memories**: Memories are plain named `.md` files now — no categories, no prefixes, no indexing, no validation
- **hooks**: Session-start hook only loads essential docs, no longer scans memories dir
- **docs**: Simplified memory conventions in `relevant-toolkit-context` and `relevant-conventions-naming` — removed category tables and format patterns
- **skills**: Rewrote `/create-memory` — simple decision tree, plain naming, no category selection
- **skills**: Updated `/evaluate-memory` — D1 evaluates descriptive naming, D4 evaluates relevance/freshness instead of category-based load timing
- **validation**: `verify-resource-deps.sh` sections 6-7 now scan only docs, not memories
- **cli**: Removed `essential-` and `MEMORIES.md` from lesson domain keywords

### Removed
- **index**: Deleted `docs/indexes/MEMORIES.md` — memories are organic, not indexed
- **validation**: Removed MEMORIES section from `validate-resources-indexed.sh` and all memory-specific tests
- **backlog**: Removed `drop-memory-prefixes` (completed)

## [2.36.1] - 2026-03-26 - Post-reshape followups: file moves and idea- removal

### Changed
- **docs**: Moved `relevant-project-identity` and `relevant-philosophy-reducing_entropy` from `.claude/memories/` to `.claude/docs/` (prescriptive, not organic context)
- **docs**: Moved `docs/naming-conventions.md` to `.claude/docs/relevant-conventions-naming.md` with Quick Reference section
- **skills**: `/shape-project` now outputs to `.claude/docs/` instead of `.claude/memories/`
- **skills**: `/review-plan` now looks up project identity in `.claude/docs/`
- **skills**: Removed `idea-` references from `/create-memory`, `/evaluate-memory`, `/list-memories`
- **manifest**: `dist/base/MANIFEST` updated for moved files, removed empty `# memories` section

### Removed
- **memories**: `idea-` memory category — ideas and explorations go to `output/claude-toolkit/drafts/` instead
- **backlog**: Removed `post-reshape-followups` (completed), split remaining items into `drop-memory-prefixes` and `rename-memory-skills-to-docs`

### Added
- **backlog**: `docs-lessons-ecosystem` task — reference doc for the lessons system

## [2.36.0] - 2026-03-26 - Memory system reshape: docs/memories split

### Added
- **docs**: New `.claude/docs/` resource type for prescriptive rules, reference documentation, and toolkit config
- **docs**: `docs/indexes/DOCS.md` — index for the new resource type
- **validation**: Docs validation section in `validate-resources-indexed.sh` with MANIFEST support
- **tests**: `test_docs_indexed`, `test_docs_missing_from_index`, `test_auto_memory_exclusion` test cases
- **cli**: `docs` category support in `categorize_file()` for sync
- **publish**: Internal docs (`.claude/docs/`) routing in `publish.py` — distinguished from repo-root docs
- **auto-memory**: `.claude/memories/auto/` subdirectory with symlink from Claude Code's auto-memory location
- **auto-memory**: `.claude/memories/.gitignore` excludes `auto/` directory
- **backlog**: `post-reshape-followups` task (P3) for remaining consolidation items

### Changed
- **memories→docs**: Moved 8 reference/rules files from `.claude/memories/` to `.claude/docs/` (code style, communication style, hooks config, permissions config, frontmatter spec, backlog schema, testing conventions, context conventions)
- **memories**: `relevant-toolkit-memory.md` renamed to `relevant-toolkit-context.md` and rewritten to define docs/memories boundary
- **hooks**: `session-start.sh` loads essential files from both `.claude/docs/` and `.claude/memories/`
- **validation**: `verify-resource-deps.sh` sections 6-7 scan both memories and docs for cross-references
- **validation**: Memory exclusions now include `auto-*.md` and `MEMORY.md` (auto-memory files)
- **skills**: `/create-memory` decision tree starts with "Is this reference docs? → `.claude/docs/`"
- **skills**: `/evaluate-memory`, `/list-memories`, `/evaluate-batch` updated for new paths
- **manifests**: `dist/base/MANIFEST` and `dist/raiz/MANIFEST` — moved files from `memories/` to `docs/` sections

### Removed
- **backlog**: Removed `review-memory-ecosystem` (superseded by reshape)

## [2.35.4] - 2026-03-26 - Session-start content review

### Changed
- **memories**: Demoted `essential-conventions-memory` → `relevant-toolkit-memory` (5.3KB saved per session — loaded on-demand by skills)
- **memories**: Demoted `essential-toolkit-identity` → `relevant-project-identity` (2.9KB saved — aligns naming with `/shape-project` convention across projects)
- **memories**: Trimmed dated sections from `essential-preferences-communication_style` (removed "Task-Oriented and Systematic" and "Tool-Heavy Workflow" — now built into Claude Code defaults)
- **hooks**: Replaced `session-start` OTHER MEMORIES file list with single `/list-memories` guidance line — richer discovery at lower context cost

### Added
- **skills**: `/review-plan` now checks for `relevant-project-identity` memory as an additional evaluation lens
- **backlog**: Added `review-memory-ecosystem` task (P3)

### Removed
- **backlog**: Removed `review-session-start-content` (done)

### Metrics
- Session-start injection: ~14KB → ~5KB (64% reduction)
- Essential memories: 4 → 2

## [2.35.3] - 2026-03-26 - Session-start hook performance optimization

### Changed
- **hooks**: `session-start` consolidated 6 separate `sqlite3` calls into one using row-prefixed multi-query — eliminates 6 forks plus 2 `date` and 1 `sed` fork for nudge/branch logic
- **hooks**: `session-start` memory loop uses bash builtins (`${f##*/}`, `${name%.md}`) instead of `basename`, and bash glob loop instead of `ls|xargs|sed|grep` pipeline for other memories listing
- **hooks**: `session-start` hoists `CURRENT_BRANCH` to avoid duplicate `git rev-parse`, uses param expansion for `SESSION_ID` and `MAIN_BRANCH`
- **hooks**: `hook_log_section` uses `${#content}` instead of `printf|wc -c` pipe — benefits all hooks (6 forks eliminated per session-start invocation)

### Added
- **tests**: Performance harness for session-start hook (`tests/perf-session-start.sh`)

### Fixed
- **hooks**: `session-start` nudge logic no longer shows false "never run" when `last_manage_run` metadata row has NULL value

### Removed
- **backlog**: Removed `optimize-session-start-hook` (done)

## [2.35.2] - 2026-03-26 - Hook performance optimization

### Changed
- **hooks**: Batch sqlite3 writes — accumulate SQL in memory, flush once in EXIT trap instead of spawning sqlite3 per log call
- **hooks**: Use `$EPOCHREALTIME` for ms timing and cache `date -Iseconds` once per invocation, eliminating 3+ `date` subprocess forks
- **hooks**: Replace `_sql_escape` sed pipe with bash parameter expansion (`${1//\'/\'\'}`)
- **hooks**: `surface-lessons` now extracts tool_name + context in a single `jq` call (was two separate calls)
- **hooks**: `surface-lessons` per-word SQL escaping uses bash expansion instead of `echo|sed` per word

### Added
- **tests**: Performance harness for surface-lessons hook (`tests/perf-surface-lessons.sh`) with synthetic and replay modes

### Removed
- **backlog**: Removed `optimize-heavy-hooks` (surface-lessons portion done; replaced with targeted `optimize-session-start-hook`)

## [2.35.1] - 2026-03-26 - PermissionRequest hook format fix

### Fixed
- **hooks**: `hook_approve` now emits correct `decision.behavior` format for PermissionRequest hooks (was incorrectly using PreToolUse's `permissionDecision` format)
- **docs**: HOOKS_API.md now documents PermissionRequest JSON output format separately from PreToolUse
- **tests**: `expect_approve` asserts PermissionRequest-specific format

### Removed
- **backlog**: Removed `hook-event-name-investigation` (P3, resolved), `rescue-worktree-logs` (P99)

## [2.35.0] - 2026-03-26 - Hook logging to SQLite

### Added
- **hooks**: Dual-write hook logs to `~/.claude/hooks.db` — all hooks now INSERT into `hook_logs` table alongside existing TSV writes. DB write is optional (silently skipped if db doesn't exist)
- **hooks**: `surface-lessons` observability — logs raw context, extracted keywords, match count, and matched lesson IDs to `surface_lessons_context` table
- **hooks**: `is_test` column in hook logs (db + TSV) — detects `CLAUDE_HOOK_TEST=1` env var to distinguish test runs from real usage
- **hooks**: `_sql_escape`, `_hook_log_db`, `hook_log_context` helpers in `hook-utils.sh`

### Changed
- **hooks**: `surface-lessons` query now returns both lesson ID and text in a single query (was text-only)
- **hooks**: TSV log format expanded from 11 to 12 columns (`is_test` appended)

## [2.34.3] - 2026-03-26 - Backlog cleanup, key principles, health check

### Fixed
- **cli**: `lessons health` now warns on historical lessons that are still active (invalid state)

### Changed
- **CLAUDE.md**: Added "no sudo" and "verify before stating" key principles
- **templates**: Trimmed key principles — moved zero-warnings to code_style memory, removed duplicates
- **memories**: Added zero-warnings convention to `essential-conventions-code_style`

### Removed
- **backlog**: Removed hook-router task (P2), lessons-health-historical-active (P3), add-key-principles (P3)

## [2.34.2] - 2026-03-26 - Absorb lessons into skills

### Changed
- **skills**: `review-plan` now verifies listed file paths actually exist (Glob check)
- **skills**: `design-docker` adds bridge subnet pinning anti-pattern and review checklist item
- **skills**: `wrap-up` adds backlog items directly on branch, flags dismissed test failures
- **skills**: `design-tests` adds `__init__.py` re-exports anti-pattern

### Fixed
- **hooks**: `session-start` lesson count now reports only active lessons, not total

## [2.34.1] - 2026-03-26 - Sync feedback fixes from cross-project migration

### Fixed
- **templates**: Gitignore pattern for project memories changed from `project-*` to `*-project-*`
- **templates**: Makefile sync command no longer includes hardcoded path argument

### Added
- **templates/hooks**: `trash-put` added to allowed permissions and approve-safe-commands hook
- **skills**: `wrap-up` now includes guidance to commit `uv.lock` alongside version bumps
- **skills**: `setup-toolkit` detects `mcp.json` at project root and moves it to `.claude/mcp.json`

## [2.34.0] - 2026-03-25 - Session ID propagation to hook timing logs

### Added
- **hooks**: Session ID extraction in `session-start.sh` — writes UUID from `CLAUDE_ENV_FILE` to `.claude/logs/.session-id` for cross-hook access
- **hooks**: `session_id` column added to `hook-timing.log` (now 11 columns, prepended as column 1)
- **backlog**: P0 surface-lessons observability, P99 rescue worktree logs

### Changed
- **hooks**: `hook-utils.sh` reads `.session-id` in `hook_init` and includes it in all log entries

## [2.33.1] - 2026-03-25 - Update skills and validation for hook-utils.sh

### Changed
- **skills**: `create-hook` templates and examples updated to use shared `lib/hook-utils.sh` library pattern
- **skills**: `evaluate-hook` rubric D4/D6 now account for shared library usage; added "Manual boilerplate" anti-pattern

### Added
- **scripts**: `validate-hook-utils.sh` — validates all hooks source `lib/hook-utils.sh` (MANIFEST-aware, 11 tests)

## [2.33.0] - 2026-03-25 - Hook instrumentation shared library

### Added
- **hooks**: Shared library `.claude/hooks/lib/hook-utils.sh` — standardized init, tool parsing, outcome helpers (block/approve/inject), and execution timing
- **hooks**: All hooks now log execution data to `.claude/logs/hook-timing.log` (TSV, 10 columns: invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected) for claude-sessions analytics

### Changed
- **hooks**: All 10 hooks migrated to source shared library, replacing duplicated boilerplate
- **hooks**: `session-start.sh` per-section logging moved from `session-start-sizes.log` to unified `hook-timing.log` format with `bytes_injected` per section
- **hooks**: Log field renamed from `session_id` to `invocation_id` — Claude Code doesn't expose session identity to hooks, so the field is per-invocation not per-session

### Removed
- **hooks**: `session-start-sizes.log` format superseded by `hook-timing.log`

## [2.32.11] - 2026-03-25 - Refactor scripts/ to cli/

### Changed
- **cli**: Renamed `scripts/` Python package to `cli/` — cleaner separation from `.claude/scripts/` bash utilities
- **cli**: `scripts/shared/formatting.py` absorbed into `cli/lessons/formatting.py` (only used by lessons)
- **ci**: `scripts/publish.py` moved to `.github/scripts/publish.py` (tied to GitHub Actions workflow)
- **hooks**: `scripts/cron/` bash scripts moved to `.claude/scripts/cron/` alongside other toolkit bash utilities
- **pyproject.toml**: Package renamed from `claude-toolkit-scripts` to `claude-toolkit`

> **Note for existing installs:** If upgrading in-place, rebuild the venv to remove the old entry point: `rm -rf .venv && make install`

## [2.32.10] - 2026-03-25 - Add session-start size logging

### Changed
- **hooks**: `session-start` now logs each section's byte/token size to `.claude/logs/session-start-sizes.log` with SESSION_ID, timestamp, project, section, bytes, and estimated tokens for traceability across projects

## [2.32.9] - 2026-03-25 - Gitignore .claude/ dir, whitelist project files

### Changed
- **templates**: Gitignore template now ignores entire `.claude/` directory (synced resources), whitelists `settings.json`, `mcp.json` (team config), and `project-*` memories (project-specific context)

## [2.32.8] - 2026-03-25 - Key Principles in templates, CLAUDE.md drift check

### Changed
- **templates**: Renamed "Conventions" to "Key Principles" in both base and raiz CLAUDE.md templates
- **skills**: `setup-toolkit` Check 6 now compares CLAUDE.md key principles against the template and suggests missing ones

## [2.32.7] - 2026-03-25 - Add "plan before building" principle

### Changed
- **templates**: Added "Plan before building" convention to both base and raiz CLAUDE.md templates
- **docs**: Added `dist/CLAUDE.md` documenting intentional differences between base and raiz distribution profiles

## [2.32.6] - 2026-03-25 - Surface actionable items at session start

### Fixed
- **hooks**: `session-start` MANDATORY instruction now includes actionable items (toolkit version mismatch, manage-lessons nudge, lessons migration) so Claude surfaces them in the opening message instead of only acknowledging counts

## [2.32.5] - 2026-03-25 - Improve design-diagram and related skills

### Changed
- **skills**: `design-diagram` — reframed from Mermaid reference to format selection guide (Mermaid vs ASCII vs lists). Added "Diagrams for Documentation" section, backtracking guidance, over-diagramming anti-pattern. Extracted rendering gotchas and syntax patterns to `resources/`
- **skills**: `design-db` — added Large ERD Strategy section (layered approach for 20+ table schemas, dimension vs transactional classification)
- **skills**: `write-docs` — added Diagram Integration section (when/where to include diagrams during doc writing, bidirectional with design-diagram)
- **docs**: Streamlined README — replaced full resource tables with summary counts + link to `docs/indexes/`, added Dependencies section, removed Customization section (covered by create-* skills), expanded Design Philosophy with reducing-entropy reference

### Added
- **skills**: `design-diagram/resources/mermaid-rendering-gotchas.md` — rendering fixes and non-obvious syntax (extracted from SKILL.md)
- **skills**: `design-diagram/resources/mermaid-theme-presets.md` — copy-paste theme configs for docs, review, and presentation contexts

### Fixed
- **toolkit**: `pyproject.toml` version now reads from `VERSION` file via hatchling dynamic versioning — eliminates version drift between the two files

## [2.32.4] - 2026-03-25 - Absorb design-qa into design-tests

### Changed
- **skills**: Absorbed `design-qa` into `design-tests` — QA strategy content now lives in `design-tests/resources/QA_STRATEGY.md`, accessed via decision tree routing. Added fixture scope diagnosis section, inlined highest-value QA heuristics (debt signals, estimation formula). Extracted troubleshooting to `resources/TROUBLESHOOTING.md`.

### Removed
- **skills**: Deleted `design-qa` as standalone skill (content preserved in design-tests resources)

## [2.32.3] - 2026-03-25 - Fix learn skill duplicate detection bias

### Fixed
- **skills**: `/learn` duplicate detection now biases toward capturing with `recurring` tag instead of skipping — crystallization in `/manage-lessons` handles dedup, not the capture step

## [2.32.2] - 2026-03-25 - Audit design-* skills, backlog cleanup

### Changed
- **skills**: Moved `design-db/schema-smith-input-spec.md` into `resources/` subfolder for consistency
- **backlog**: Removed 3 completed audit tasks, added `merge-design-qa-into-tests` (P1) and `improve-design-diagram` (P2)

## [2.32.1] - 2026-03-25 - Remove review-changes skill

### Removed
- **skills**: Deleted `review-changes` — `code-reviewer` agent covers this functionality. Updated cross-references across skills, MANIFESTs, README, docs, and tests.

## [2.32.0] - 2026-03-25 - Extract session scripts

### Removed
- **scripts**: Extracted `scripts/sessions/` (~2,700 lines) to standalone [claude-sessions](~/projects/personal/claude-sessions/) project with unified `claude-sessions` CLI
- **tests**: Removed `test_session_index.py` and `test_session_analytics.py` (moved to claude-sessions)
- **make**: Removed `test-session-index` and `test-session-analytics` targets

### Changed
- **cron**: `index-sessions.sh` now invokes `claude-sessions index` from the extracted project
- **memory**: Updated `relevant-conventions-testing` to reflect removed targets

## [2.31.0] - 2026-03-25 - Session analytics co-occurrence

### Added
- **analytics**: `co-occurrence` subcommand — shows hours where 2+ projects had concurrent activity using 1h time buckets, with project × time grid and top overlapping pairs

## [2.30.2] - 2026-03-25 - Clean test output and faster analytics tests

### Changed
- **tests**: `make check` now runs bash test suites in quiet mode — only summaries and failures shown (~800 lines → ~80)
- **tests**: Shared test helper library (`tests/lib/test-helpers.sh`) replaces duplicated color vars, counters, and summary blocks across 6 bash test files
- **tests**: All bash test suites support `-q` (quiet) and `-v` (verbose) flags

### Fixed
- **tests**: Session analytics fixtures (`indexed_db`, `memory_db`) widened from function to session scope — 15.5s → 0.6s for 65 read-only tests

## [2.30.1] - 2026-03-25 - Cron index-sessions fix

### Fixed
- **cron**: `index-sessions.sh` now adds `~/.cargo/bin` to PATH so `uv` is found in cron's minimal environment

## [2.30.0] - 2026-03-25 - Lessons CLI subcommand

### Added
- **cli**: `claude-toolkit lessons` subcommand — routes to lessons DB via installed `ct-lessons` entry point, works from any project
- **packaging**: `pyproject.toml` now declares `[project.scripts]` entry point with hatchling build system

### Fixed
- **skills**: `/learn` and `/manage-lessons` now work in synced target projects (previously broken — invoked `uv run scripts/lessons/db.py` which only existed in the toolkit repo)
- **imports**: Replaced all `sys.path.insert` hacks with proper package imports across 5 script files

### Changed
- **permissions**: Added `Bash(claude-toolkit:*)` to settings.json, settings.template.json, and approve-safe-commands hook
- **conventions**: Added `sys.path.insert` as anti-pattern in code_style memory

## [2.29.4] - 2026-03-24 - Template→MANIFEST hook sync validation

### Added
- **validation**: `validate-settings-template.sh` now checks that all hooks in the settings template are listed in `dist/base/MANIFEST`, preventing hooks from being configured but not synced

### Fixed
- **templates**: Removed obsolete `.claude/usage.log` from gitignore template

## [2.29.3] - 2026-03-24 - Add missing hook to sync manifest

### Fixed
- **dist**: Added `surface-lessons.sh` hook to base MANIFEST — was referenced in settings template but not synced to projects

## [2.29.2] - 2026-03-24 - Cron script logging

### Fixed
- **scripts**: All three cron scripts (`backup-transcripts`, `backup-lessons-db`, `index-sessions`) now log timestamped output so `cron.log` isn't empty
- **gitignore**: Added `scripts/cron/cron.log`

## [2.29.1] - 2026-03-24 - Stronger session-start hook prompts

### Changed
- **hooks**: `session-start.sh` — stronger prompt language for learned.json migration warning (MANDATORY, surface immediately)
- **hooks**: `session-start.sh` — stronger prompt language for session-start acknowledgment (MANDATORY, FIRST message)

## [2.29.0] - 2026-03-24 - Scripts reorganization and insights migration

### Added
- **scripts**: `tools`, `skills`, `agents`, `hooks` subcommands for `session_analytics.py` — migrated from `insights.py` using SQL queries against the session-index DB
- **scripts**: `scripts/shared/formatting.py` — shared terminal formatting utilities (`_c`, `_fmt_tokens`) used across session and lesson tools

### Changed
- **scripts**: Reorganized flat `scripts/` into domain subdirectories: `sessions/` (db, index, search, analytics, schemas), `lessons/` (db, schemas), `cron/` (shell wrappers), `shared/` (formatting)
- **scripts**: Renamed modules to drop redundant prefixes: `session_db.py` → `sessions/db.py`, `session_index.py` → `sessions/index.py`, etc.
- **settings**: Permission glob `Bash(./scripts/*)` → `Bash(./scripts/**)` for recursive subdirectory matching
- **hooks/skills**: Updated all path references (`lesson_db.py` → `lessons/db.py`, etc.)
- **validation**: `validate-safe-commands-sync.sh` now handles `**` globs in settings.json permissions
- **cron**: Lessons backup changed from daily 3am to hourly :30 (WSL misses overnight jobs)
- **memory**: Updated testing conventions memory for current Makefile targets

### Removed
- **scripts**: `insights.py` — features migrated to `session_analytics.py` subcommands
- **scripts**: `session-search/schema-smith/output/` — generated artifacts (schemas moved to domain dirs)

## [2.28.0] - 2026-03-24 - Lessons DB migration and contextual surfacing

### Added
- **scripts**: `lesson_db.py` — SQLite database layer for lessons with FTS5 full-text search, tag registry, crystallization/absorption lifecycle tracking, and metadata store
- **scripts**: 12 CLI subcommands: `migrate`, `add`, `search`, `list`, `summary`, `set-meta`, `tags`, `clusters`, `crystallize`, `absorb`, `tag-hygiene`, `health`
- **hooks**: `surface-lessons.sh` — PreToolUse hook (pure bash+sqlite3) that surfaces relevant active lessons as additionalContext based on tool context keywords
- **scripts**: `backup-lessons-db.sh` — daily timestamped backup with 30-day retention
- **schema**: `lessons.yaml` schema-smith definition for lessons DB (projects, tags, lessons, metadata, lesson_tags)
- **tests**: 28 tests for lesson_db.py (init, CRUD, FTS, constraints)

### Changed
- **skills**: `/learn` now writes to `lessons.db` via `lesson_db.py add` instead of jq/JSON
- **skills**: `/manage-lessons` reworked for crystallization model — health checks, cluster detection, absorption workflow, tag hygiene
- **hooks**: `session-start.sh` uses sqlite3 for lesson queries with learned.json fallback; nudge logic based on days since last manage-lessons run
- **CLAUDE.md**: Added "capture lessons aggressively" principle

### Removed
- **scripts**: `lessons-query.sh` — replaced by `lesson_db.py` CLI
- **schemas**: `lesson.schema.json` — schema now lives in YAML + DB

## [2.27.1] - 2026-03-24 - Session scripts reorganization

### Changed
- **scripts**: Split `session_search.py` (1,336 lines) into four focused modules — `session_db.py` (shared utilities), `session_index.py` (extraction + indexing), `session_search.py` (FTS search only), `session_analytics.py` (all analytics commands)
- **scripts**: Moved `timeline`, `files`, `stats`, `resource-cost` subcommands from `session_search.py` to `session_analytics.py`
- **scripts**: `index-sessions.sh` cron wrapper now calls `session_index.py`
- **tests**: Renamed `test_session_search.py` to `test_session_index.py`, added `test-session-analytics` Makefile target

### Removed
- **backlog**: Completed `session-analytics-migration` task

## [2.27.0] - 2026-03-24 - Setup toolkit skill and version drift detection

### Added
- **skills**: `/setup-toolkit` — interactive fixer for post-sync toolkit configuration. Diagnoses and fixes settings.json hooks/permissions, MCP config, Makefile targets, .gitignore patterns, and CLAUDE.md. Additive only — never removes existing config
- **hooks**: Version drift detection in `session-start.sh` — compares `.claude-toolkit-version` against `claude-toolkit version` and nudges user to sync
- **cli**: `claude-toolkit version` subcommand — prints toolkit version from VERSION file

### Removed
- **backlog**: Completed `setup-toolkit-skill` task

## [2.26.2] - 2026-03-24 - Teardown worktree rebase check

### Changed
- **skills**: `teardown-worktree` now checks if branch is behind main after checkout — suggests `git rebase main` when needed instead of blindly offering the merge command

## [2.26.1] - 2026-03-24 - Implementation checker git diff support

### Changed
- **agents**: `implementation-checker` now has Bash tool — starts investigation with `git diff main...HEAD` to discover actual changes, aligning with goal-verifier and code-reviewer patterns

### Removed
- **backlog**: Completed `implementation-checker-bash` task

## [2.26.0] - 2026-03-24 - Memory load patterns analytics

### Added
- **scripts**: `memory` subcommand for `session_analytics.py` — memory and CLAUDE.md load patterns per project and globally. Sections: estimated essential loads (SessionStart hook counts), on-demand memory reads ranked by frequency, CLAUDE.md reads split by root vs subfolder, shared memories across projects, diversity metrics
- **scripts**: `project_path` column on `projects` table — actual filesystem path populated from JSONL `cwd` field at index time, enables reliable CLAUDE.md root classification
- **tests**: 11 pytest tests for memory patterns (essential estimates, reads ranking, CLAUDE.md classification, shared memories, diversity, filters)
- **backlog**: Added `implementation-checker-bash` (P2)

### Removed
- **backlog**: Completed `session-analytics-memory` task

## [2.25.1] - 2026-03-24 - Auto-deny sudo commands

### Added
- **hooks**: `sudo` command blocking in `block-dangerous-commands.sh` — sudo can't work without an interactive password prompt, so block it instead of letting it fail

### Removed
- **backlog**: Completed `hook-auto-deny-sudo` task

## [2.25.0] - 2026-03-24 - Resource token cost tracking

### Added
- **scripts**: `resource-cost` subcommand for session-search — measures token cost of skill and agent invocations by tracking input/output deltas from invocation to end boundary. Pre-computed during indexing via `resource_usage` table for instant queries
- **scripts**: `extract_resource_usage()` — linear-scan span detection for skills (next human message boundary), agents (same), interactive skills like brainstorm-idea (file-write boundary), and memory baseline (first-turn input tokens)
- **scripts**: `input_total`/`output_total` cumulative columns on events table — running sums of context size and output per assistant turn
- **scripts**: User event classification — `action_type` distinguishes `human` vs `skill_content` messages for accurate boundary detection
- **tests**: 10 new tests covering cumulative tokens, user classification, resource extraction, and DB round-trip

### Changed
- **scripts**: Agent/Task event detail now prefixed with `subagent_type` (e.g. `Explore: description`) for aggregation in resource-cost reports

### Removed
- **backlog**: Completed `resource-token-cost` task

## [2.24.0] - 2026-03-24 - Session DB analytics

### Added
- **scripts**: `session_analytics.py` — usage pattern analytics over the session-index DB, separate from search. Preprocessing filter excludes hook/progress events from all queries. Subcommands:
  - `sessions` — per-session shape metrics (duration, active time, events, tool diversity, dominant action)
  - `projects` — project lifecycle patterns (activity span, peak weeks, session density)
  - `time` — hourly/daily/weekly distributions with timezone offset (default UTC-3), session gap analysis
  - `branches` — effort per branch, lifetime, session shape by branch
- **scripts**: Active time metric using 1-minute time bucketing — counts minutes with any event activity, filtering out idle periods where sessions were left open
- **tests**: 35 pytest tests for session analytics (preprocessing, active time, session shapes, project patterns, time patterns, branch patterns)
- **backlog**: Added `session-analytics-migration` (P2), `session-analytics-memory` (P2), `session-analytics-work-units` (P2), `session-analytics-co-occurrence` (P2)

### Removed
- **backlog**: Completed `session-db-analytics` task

## [2.23.0] - 2026-03-24 - Worktree skills polish

### Changed
- **skills**: `setup-worktree` — drop mandatory plan file (optional context file instead), add `.claude/scripts` symlink, skip symlinks when `.claude/` is already tracked in git, reframe as branch isolation
- **skills**: `teardown-worktree` — mechanical only (check uncommitted → copy artifacts → remove → checkout), drop implementation-checker agent run, drop Agent from allowed tools

### Removed
- **backlog**: Completed `worktree-polish` task

## [2.22.0] - 2026-03-24 - Session history search with SQLite+FTS5

### Added
- **scripts**: `session_search.py` — SQLite+FTS5 cross-project search across all Claude Code transcripts. Full timeline indexing (user messages, assistant text, tool calls), projects dimension table, token accounting, incremental indexing with dedup, subcommands: index, search, timeline, files, stats
- **scripts**: `index-sessions.sh` — cron wrapper for hourly session indexing alongside backup-transcripts.sh
- **scripts**: Schema-smith YAML design artifact with generated PostgreSQL DDL and Mermaid diagram (`scripts/session-search/schema-smith/`)
- **tests**: 30 pytest tests for session search (extraction, DB round-trip, dedup, incremental)
- **docs**: Resource usage audit report (`output/claude-toolkit/analysis/`)
- **backlog**: Added `resource-token-cost` (P1) and `resource-plugins` (P2) tasks from usage audit findings

### Removed
- **backlog**: Completed `session-search` task, removed `stop-hook-plan-enforcement` (P3)

## [2.21.9] - 2026-03-24 - Tighten review-plan structural requirements

### Changed
- **skills**: `review-plan` — commit-per-step and post-implementation steps are now structural requirements, not suggestions. Reviewer must add missing steps to the plan before presenting the review. "After Approval" section replaced with "Before Presenting the Review"
- **docs**: Completed `exploration-scan` backlog task — reviewed disler/claude-code-hooks-multi-agent-observability, added 4 new backlog items (session-search, review-plan-tighten, stop-hook-plan-enforcement, output-styles-concept)
- **docs**: Moved `aws-toolkit` from P2 to P3, removed completed exploration-scan task
- **docs**: Added CLAUDE.md reminders — remove done backlog tasks, fold unreleased changes into version entries

## [2.21.8] - 2026-03-24 - Fix backlog-query priority column spacing

### Fixed
- **scripts**: `backlog-query.sh` priority column width `%4s` → `%3s` — was sized for P100, now correct for P99 max

## [2.21.7] - 2026-03-24 - Memory index convention alignment

### Changed
- **toolkit**: Moved `exploration/` from `output/claude-toolkit/reviews/` to `output/claude-toolkit/exploration/` — exploration is its own concern, not a review subtype
- **ci**: Raiz publish workflow now stamps `.claude-toolkit-version` in target repo and includes version in commit message
- **indexes**: Removed `personal-*` section from MEMORIES.md — now excluded from index alongside `idea-*` and `experimental-*`, matching validation logic
- **memories**: Added `Indexing:` field to `idea`, `personal`, and `experimental` category definitions in `essential-conventions-memory`
- **skills**: `create-memory` — added missing `personal-` row to category table, index update step, and category-aware duplicate check guidance

### Fixed
- **scripts**: `validate-resources-indexed.sh` and `verify-resource-deps.sh` now exclude `experimental-*` memories alongside `idea-*` and `personal-*`

## [2.21.6] - 2026-03-24 - Permissions config convention memory

### Added
- **memories**: `relevant-toolkit-permissions_config` — documents two-tier permissions architecture (toolkit `settings.json` for globally safe commands + hooks, project `settings.local.json` for per-project trust), with decision guide and reference to `settings.template.json`

## [2.21.5] - 2026-03-24 - Fix evaluation-query hook stale detection

### Fixed
- **scripts**: `evaluation-query.sh` stale detection now works for hooks — `get_resource_path` was missing `.sh` extension, causing hook files to never be found

## [2.21.4] - 2026-03-24 - Test coverage for evaluation-query and validate-resources-indexed

### Added
- **tests**: `test-evaluation-query.sh` — 37 test cases covering all subcommands (list, type, stale, unevaluated, above, verbose, help) and error paths
- **tests**: `test-validate-resources-indexed.sh` — 31 test cases covering toolkit mode (synced, missing, stale, mixed errors, idea/personal exclusion) and MANIFEST mode
- **tests**: `make test-eval` and `make test-validate-indexed` targets

### Fixed
- **backlog**: Added `fix-eval-query-hook-path` for pre-existing bug where `evaluation-query.sh` stale detection silently skips hooks due to missing `.sh` extension in `get_resource_path`

## [2.21.3] - 2026-03-24 - Move indexes and curated-resources to docs/

### Changed
- **toolkit**: Moved `indexes/` and `curated-resources.md` from `.claude/` to `docs/` — these are documentation about resources, not runtime configuration
- **toolkit**: Scripts (`validate-resources-indexed`, `verify-resource-deps`, `evaluation-query`) now use `PROJECT_ROOT` to find indexes in `docs/indexes/`
- **docs**: Fixed misleading `make backlog` ("Query" → "Show") and `make check` ("Run all" → "Run") descriptions in CLAUDE.md

## [2.21.2] - 2026-03-23 - Move dist/ to project root

### Changed
- **toolkit**: Distribution configs (MANIFESTs, templates) moved from `.claude/dist/` to project root `dist/` — cleaner separation of build artifacts from Claude Code config
- **toolkit**: `resolve_manifest()` now resolves `dist/*` entries from project root instead of `.claude/`; all other entries unchanged
- **toolkit**: `publish.py` template resolution updated for root-level `dist/`

## [2.21.1] - 2026-03-23 - Blanket Glob and Grep permissions

### Added
- **permissions**: `Glob(**)` and `Grep(**)` added to settings.json and settings template — both are read-only tools guarded by secrets-guard hook, no longer prompt unnecessarily

## [2.21.0] - 2026-03-23 - Auto-approve safe chained Bash commands

### Added
- **hooks**: `approve-safe-commands` — PermissionRequest hook that auto-approves chained Bash commands (`&&`, `||`, `;`, `|`) when all subcommands match safe prefixes from settings.json permissions
- **scripts**: `validate-safe-commands-sync` — validation script that checks hook's hardcoded prefixes stay in sync with settings.json; added to `make check` via `validate-all.sh`
- **tests**: 41 tests covering chained commands, single commands, env var prefixes, script paths, quoted operators, unsafe commands, subshells, redirects, and sync validation

### Fixed
- **hooks**: `approve-safe-commands` — closed stderr redirect bypass (`2>file`, `&>file`) found during code review

## [2.20.5] - 2026-03-23 - Document prompt/agent hook types in HOOKS_API

### Added
- **skills**: `create-hook` — HOOKS_API reference now documents `prompt` and `agent` hook types (configuration, response format, examples)
- **skills**: `create-hook` — HOOKS_API Stop hook schema now includes `last_assistant_message` field
- **skills**: `create-hook` — HOOKS_API events table updated with 10 newer hook events (StopFailure, PostCompact, InstructionsLoaded, ConfigChange, TaskCompleted, TeammateIdle, Worktree*, Elicitation*)

## [2.20.4] - 2026-03-23 - Deduplicate secrets-guard hook

### Changed
- **hooks**: `secrets-guard` — extracted shared helpers (`BLOCKED_PATHS`, `normalize_path`, `check_env_file`, `check_credential_path`) to eliminate duplicated logic across Read and Grep handlers; adding new credential paths now requires updating one array instead of three

## [2.20.3] - 2026-03-23 - Close grep bypass in secrets-guard hook

### Fixed
- **hooks**: `secrets-guard` — Grep tool could search secret and credential file contents unblocked; added Grep tool handler with path and glob checks
- **hooks**: `secrets-guard` — Bash `grep`/`rg`/`awk`/`sed` commands could read secret and credential files unblocked; added regex checks matching the same patterns as cat/less/head/tail
- **hooks**: `secrets-guard` — suffix-named env files (e.g., `prod`, `staging`) were not caught by Bash handler; added ENV_SUFFIX_RE pattern
- **hooks**: `secrets-guard` — `~/.gnupg` path without trailing slash bypassed directory check in both Read and Grep handlers

### Changed
- **hooks**: `secrets-guard` — credential file regexes now use shared `READ_CMDS` variable with intermediate-arg matching for commands that take patterns before file paths

## [2.20.2] - 2026-03-23 - Move output outside .claude/

### Changed
- **settings**: output path moved from `.claude/output/` to `output/claude-toolkit/` — eliminates built-in `.claude/` directory protection causing permission prompts on every Write/Edit
- **settings**: `plansDirectory` updated to `output/claude-toolkit/plans`
- **settings**: Write/Edit permission grants updated to `output/claude-toolkit/**`
- **gitignore**: single `output/claude-toolkit/` entry replaces per-subdirectory `.claude/output/` entries

### Fixed
- **agents/skills/memories**: all output path references updated (25 files across 6 agents, 10 skills, 2 memories, 1 index)
- **templates**: synced settings template and gitignore template updated for new path

## [2.20.1] - 2026-03-23 - Wrap-up scope awareness

### Fixed
- **skills**: `wrap-up` — address scope tunnel vision: now checks for non-branch artifacts and actively surfaces session issues for backlog consideration

## [2.20.0] - 2026-03-23 - Shared permission allow list

### Added
- **settings**: shared `permissions.allow` in `settings.json` — universally safe patterns (read-only commands, safe git subcommands, hook/script execution, output writes) synced to all projects
- **settings**: matching permissions in `settings.template.json` for new project setup
- **scripts**: `validate-settings-template.sh` — permissions.allow sync check between settings.json and template

## [2.19.0] - 2026-03-23 - Knowledge skills + validation fixes

### Added
- **skills**: `create-skill` — knowledge skill type with `user-invocable: false` guidance and template frontmatter
- **skills**: `evaluate-skill` — D4 criteria for `user-invocable: false` skills (description quality, keyword specificity)

### Fixed
- **scripts**: `validate-resources-indexed.sh` — exclude `idea-*` and `personal-*` memories from index validation
- **scripts**: `verify-resource-deps.sh` — exclude `idea-*` and `personal-*` memories from dependency checks

## [2.18.0] - 2026-03-20 - Agent frontmatter

### Added
- **agents**: `background: true` + `effort: medium` on 4 reviewer agents (code-reviewer, proposal-reviewer, implementation-checker, goal-verifier)
- **agents**: `effort: high` on code-debugger for deeper reasoning during investigations

## [2.17.0] - 2026-03-20 - Native plansDirectory setting

### Added
- **settings**: `plansDirectory: ".claude/output/plans"` — native Claude Code setting replaces custom hook

### Removed
- **hooks**: `copy-plan-to-project.sh` — replaced by native `plansDirectory` setting (75-line hook → 1 JSON key)
- **settings**: `CLAUDE_PLANS_DIR` env var — no longer needed

## [2.16.0] - 2026-03-20 - PermissionRequest hook context

### Added
- **skills**: `create-hook` — PermissionRequest added to decision tree, full example with allowlist pattern matching, settings.json config, and guidance on PermissionRequest vs `allowed-tools`

### Changed
- **backlog**: Removed completed items, added missing IDs, reprioritized `CLAUDE_SKILL_DIR` to P99

## [2.15.0] - 2026-03-20 - allowed-tools audit

### Added
- **skills**: `allowed-tools` frontmatter added to 25 command skills (only 2 of 33 had it before). 6 knowledge-only skills exempt
- **skills**: `evaluate-skill` D4 — tool scoping sub-criterion: checks `allowed-tools` presence and proper scoping for command skills (2-3 pt deduction if missing)

### Changed
- **memories**: `relevant-toolkit-resource_frontmatter` — `allowed-tools` now documented as required for command skills, with pattern examples

## [2.14.1] - 2026-03-20 - draft-pr file output

### Fixed
- **skills**: `draft-pr` — write PR description to `.claude/output/pr-descriptions/` instead of console (console copy/paste loses markdown formatting)

## [2.14.0] - 2026-03-18 - skill argument-hint audit

### Added
- **skills**: `argument-hint` frontmatter added to 10 skills: `evaluate-batch`, `evaluate-skill`, `evaluate-agent`, `evaluate-hook`, `evaluate-memory`, `learn`, `analyze-idea`, `brainstorm-idea`, `write-docs`, `read-json`
- **skills**: `create-skill` — new Arguments section covering `argument-hint` frontmatter, `$ARGUMENTS` usage, positional access (`$0`, `$1`), and empty-case handling
- **skills**: `create-skill` template — commented `argument-hint` example in frontmatter

### Changed
- **templates**: Renamed `feature/` to `feat/` branch prefix in CLAUDE.md dist templates
- **drafts**: Archived stale aws-toolkit and skill-refactor drafts

### Fixed
- **docs**: Removed stale `check-quiet` reference from CLAUDE.md

## [2.13.4] - 2026-03-18 - fix copy-plan test path

### Fixed
- **tests**: `copy-plan-to-project` test updated to use `.claude/output/plans/` path (matching v2.13.2 hook change) and properly export `CLAUDE_PLANS_DIR` env var

## [2.13.3] - 2026-03-18 - professional profile memory and curated resource

### Added
- **memories**: `relevant-context-professional_profile` — data engineering role, stack, tools, and current trajectory
- **curated-resources**: AbsolutelySkilled color-theory skill — OKLCH color systems, semantic tokens, palette recipes

## [2.13.2] - 2026-03-14 - move plan output to .claude/output/plans

### Changed
- **hooks**: `copy-plan-to-project.sh` default destination changed from `.claude/plans/` to `.claude/output/plans/`
- **config**: Updated all references across settings, gitignore, README, memories, skills, agents, and dist templates

## [2.13.1] - 2026-03-14 - memory cleanup and resource housekeeping

### Changed
- **memories**: Renamed `relevant-conventions-backlog_schema` → `relevant-workflow-backlog`, `relevant-reference-hooks_config` → `relevant-toolkit-hooks_config`
- **skills**: `wrap-up` — added rule to never modify older changelog entries
- **backlog**: Pruned 5 speculative items; unblocked aws-toolkit by removing separate-repo dependency
- **indexes**: Promoted `design-qa` and `refactor` to beta; flagged `review-changes`, `setup-worktree`, `teardown-worktree` for removal consideration

### Removed
- **memories**: `relevant-workflow-branch_development` (redundant with git-safety hook + CLAUDE.md template)
- **memories**: `relevant-workflow-task_completion` (superseded by review-plan pipeline + code_style conventions)

## [2.13.0] - 2026-03-14 - schema-smith integration for design-db

### Added
- **skills**: `design-db` schema-smith integration — detects CLI availability, outputs YAML instead of raw DDL, runs `schema-smith generate` for validation and SQL generation
- **skills**: `design-db/schema-smith-input-spec.md` — bundled input format reference for YAML schema authoring

## [2.12.0] - 2026-03-12 - getting-started guide and docs distribution

### Added
- **docs**: `docs/getting-started.md` — standalone orientation guide for raiz distribution recipients
- **publish**: `docs/` support in publish pipeline — files sourced from repo root, output outside `.claude/`

## [2.11.1] - 2026-03-12 - review-plan pipeline and CLAUDE.md cleanup

### Changed
- **skills**: `review-plan` post-approval pipeline expanded — adds `implementation-checker` (5+ step plans) and `code-reviewer` between `goal-verifier` and `/wrap-up`
- **docs**: `CLAUDE.md` trimmed redundant key principles, added common make targets to Quick Start, sharpened See Also with actionable pointers

## [2.11.0] - 2026-03-12 - lessons ecosystem

### Added
- **skills**: `/manage-lessons` — review and manage lesson lifecycle (promote, archive, delete, flag)
- **scripts**: `lessons-query.sh` — query lessons by tier, category, flag, branch, project, ID, or text search
- **schemas**: `lesson.schema.json` — lesson entry schema with tiers, flags, and lifecycle fields

### Changed
- **skills**: `/learn` rewritten — lighter capture flow with auto-metadata, duplicate/recurring detection, and ecosystem cross-references
- **hooks**: `session-start.sh` — surfaces key tier (all), recent (last 5), and branch-flagged lessons; nudges `/manage-lessons` when 10+ recent or recurring flags exist
- **data**: `learned.json` migrated from `{recent: [], key: []}` to `{lessons: [...]}` flat array with tier/flags/id fields

## [2.10.2] - 2026-03-12 - create-memory portability

### Fixed
- **skills**: `create-memory` no longer requires `.claude/indexes/MEMORIES.md` — falls back to listing `.claude/memories/` for duplicate checking

### Changed
- **sync**: added `create-memory` to MANIFEST (dependency of `shape-project`)

## [2.10.1] - 2026-03-12 - fix symlink resolution

### Fixed
- **CLI**: `claude-toolkit send` wrote to `~/.local/suggestions-box/` instead of the toolkit's `suggestions-box/` when invoked via symlink — `TOOLKIT_DIR` now resolves symlinks before computing path

## [2.10.0] - 2026-03-12 - shape-project skill

### Added
- **skills**: `shape-project` — define project identity, scope, and boundaries as a `relevant-project-identity` memory. Hybrid approach: reads repo first, asks targeted questions, drafts through dialogue

## [2.9.1] - 2026-03-12 - deprecate backlog graveyard, backlog triage

### Changed
- **conventions**: removed Graveyard section from backlog schema — dropped items are just removed, no archive needed
- **scripts**: simplified `backlog-query.sh` and `backlog-validate.sh` (no more Graveyard-specific parsing/filtering)
- **templates**: removed Graveyard from `BACKLOG-minimal.md` and `BACKLOG-standard.md`
- **backlog**: triage pass — promoted `lessons-ecosystem` to P1, demoted `aws-toolkit` to P2 (blocked), promoted `skill-design-db-backing-repo` and `toolkit-content-plugins` to P2, dropped `skill-refactor-examples` and `hook-context-suggest`

## [2.9.0] - 2026-03-12 - publish script rewrite in Python

### Added
- **scripts**: `publish.py` — generalized distribution publish script, accepts any dist name as argument (replaces raiz-only bash script), no jq dependency

### Changed
- **CI**: `publish-raiz.yml` workflow updated to use `publish.py` with `setup-python` step
- **tests**: `test-raiz-publish.sh` calls `publish.py` instead of bash script

### Fixed
- **validation**: added `/security-review` to builtin commands allowlist in `verify-resource-deps.sh`

### Removed
- **scripts**: `.claude/dist/raiz/publish.sh` — replaced by `scripts/publish.py`

## [2.8.0] - 2026-03-12 - review-security skill

### Added
- **skill**: `review-security` — targeted security audit of files/modules with trace-based vulnerability analysis (entry → sink), 8 vulnerability domains, trust boundary calibration, false-positive filtering (80% confidence rule), worked example
- **skill**: `review-security` `resources/DOMAINS.md` — safe/vulnerable code comparisons across Python, Node, Django, Go for injection, auth, secrets, crypto, SSRF, deserialization
- **evaluations**: batch re-evaluated 5 stale/unevaluated resources (draft-pr, evaluate-hook, learn, relevant-conventions-testing, code-reviewer)

### Changed
- **agent**: `code-reviewer` — added escalation path to `/review-security` in See Also
- **backlog**: replaced `skill-learn-quality-gate` with broader `lessons-ecosystem` item; updated `agent-security-reviewer` → `skill-review-security` (in-progress)

## [2.7.0] - 2026-03-12 - proposal shaping improvements

### Added
- **skills**: `shape-proposal` — 6 improvements from real usage analysis: validation checklist audience-based splitting, source-type awareness for reshape, core insight surfacing step, source fidelity check post-reviewer, scope creep decision framework, comparison table tradeoff column self-test
- **skills**: `shape-proposal` worked example (`resources/EXAMPLE.md`) — 7 annotated shaping techniques with `<!-- WHY -->` comments
- **skills**: `PROPOSAL_TEMPLATE.md` — tradeoff column self-test (section A), audience-based validation split (section F)

### Changed
- **agents**: `proposal-reviewer` scope creep dimension — checks framing block acknowledgment instead of always flagging implementation detail

## [2.6.1] - 2026-03-12 - insights.py test coverage

### Added
- **tests**: 56 pytest tests for `insights.py` — unit tests (parsing, formatting), record processing, subagent parsing, and integration tests for all commands
- **infra**: pytest infrastructure (`pyproject.toml` config, `make test-insights`, `make install`)

## [2.6.0] - 2026-03-12 - detailed subagent metrics in insights

### Added
- **scripts**: `insights.py` — parse hook events, skill calls, user turns, and output token attribution from subagent transcripts
- **scripts**: `insights.py tools` — Main/Subagent/Total columns when subagents are present
- **scripts**: `insights.py hooks` — aggregate hook events from both main session and subagents with breakdown columns
- **scripts**: `insights.py overview` — Subagent Detail section showing tool calls, hook events, skill calls, user turns
- **scripts**: `insights.py skills` — aggregate skill calls from subagent transcripts
- **scripts**: `insights.py sessions --json` — extended subagent entries with hook_events, skill_calls, user_turns

## [2.5.1] - 2026-03-11 - draft-pr template detection

### Improved
- **skills**: `draft-pr` now checks for PR templates in `.github/` before generating — uses project template when found, falls back to default format

## [2.5.0] - 2026-03-11 - remove letter grades from evaluation system

### Changed
- **evaluations**: Removed letter grades (A/A-/B+/etc.) from all evaluate-* skills — percentage is now the sole quality indicator alongside raw scores
- **evaluations**: Removed `"grade"` field from evaluations.json (all 56 entries)
- **evaluations**: Removed grading scale sections from evaluate-skill, evaluate-agent, evaluate-hook, evaluate-memory
- **scripts**: `evaluation-query.sh` — replaced `grade` command with `above` (percentage threshold, default 85%), display shows percentage with color thresholds
- **skills**: evaluate-batch reporting tables use `%` column instead of `Grade`

### Fixed
- **skills**: `wrap-up` now checks for feature branch as step 1 — previously assumed branch existed, causing work on main

### Changed
- **memories**: Added cross-references to `relevant-conventions-testing` (links to code_style, task_completion, /design-tests)
- **evaluations**: Updated scores for `relevant-conventions-testing` (102 → 106), `relevant-toolkit-resource_frontmatter` (104), and `wrap-up` (102)

## [2.4.0] - 2026-03-11 - agent model targeting

### Changed
- **agents**: Assigned model targets to all 7 agents — sonnet for structured work (code-reviewer, codebase-explorer, pattern-finder, implementation-checker), opus for deep reasoning (code-debugger, goal-verifier, proposal-reviewer)
- **agents**: Removed unnecessary grep/glob tools from proposal-reviewer
- **memories**: Renamed `relevant-reference-skill_frontmatter` → `relevant-toolkit-resource_frontmatter` to reflect coverage of both skills and agents
- **memories**: Added model selection guide section to frontmatter reference memory

### Added
- **memories**: Consolidated `relevant-conventions-testing` and `relevant-toolkit-resource_frontmatter` into project memories (moved from user-level folder)
- **skills**: Added cross-references to frontmatter memory from create-skill, create-agent, evaluate-skill, evaluate-agent

## [2.3.0] - 2026-03-11 - git-safety hook with remote-destructive protections

### Changed
- **hooks**: Renamed `enforce-feature-branch` → `git-safety` — reflects expanded scope beyond branch enforcement
- **hooks**: Added remote-destructive protections: force push, `--mirror`, branch deletion (`--delete` and `:branch`), cross-branch push (`HEAD:other-branch`)
- **hooks**: Two severity tiers — severe (irreversible: force push to protected, mirror, delete protected) and soft (risky: force push non-protected, delete any branch, cross-branch)
- **docs**: Updated all references across settings, templates, MANIFEST, indexes, memories, and README

### Fixed
- **tests**: Fixed git-safety test — broken path from rename and lost subshell counters

### Added
- **tests**: Expanded git-safety test coverage from 20 → 43 tests: severity verification (`expect_contains`), detached HEAD blocking, non-git directory passthrough, master branch protection, same-branch refspec allow, tool passthrough

## [2.2.0] - 2026-03-11 - shape-proposal skill and proposal-reviewer agent

### Added
- **skill**: `shape-proposal` — shapes validated designs into audience-aware proposals with template-based structure, tone calibration, and contextual section selection
- **skill**: `resources/PROPOSAL_TEMPLATE.md` — 8 core + 9 contextual sections, status markers, section ordering guidance
- **agent**: `proposal-reviewer` — reviews proposals for audience fit, tone consistency, blind spots, and dismissive language. Three-tier verdict (CLEAN/ISSUES/REVISE) with automatic-fail triggers
- **exploration**: Added `itsmostafa/aws-agent-skills` to exploration queue — weekly-updated AWS service reference, potential plugin pattern
- **exploration**: Renamed exploration backlog to `BACKLOG.md` for consistency, cross-referenced from main backlog
- **exploration**: Reviewed `CloudSecurityPartners/skills` — security audit skill for vetting plugins. Useful patterns: tool risk matrix, hook severity escalation. Cross-referenced from `agent-security-reviewer` backlog item
- **backlog**: `skill-shape-proposal-example` — reshape v5 through the skill to produce a proper worked example

## [2.1.0] - 2026-03-09 - Raiz distribution and dist/ restructure

### Added
- **dist**: Raiz publish script (`.claude/dist/raiz/publish.sh`) — builds scoped subset for coworkers (6 skills, 3 agents, 5 hooks, 2 memories, 3 templates)
- **dist**: Cross-reference trimming — strips "See also:" and bullet refs to excluded resources
- **dist**: Settings template trimming — filters to raiz-only hooks, removes statusLine
- **dist**: Raiz CLAUDE.md.template with note about potential unresolved resource references
- **ci**: GitHub Action (`.github/workflows/publish-raiz.yml`) — auto-publishes to `claude-toolkit-raiz` on push to main
- **tests**: `test-raiz-publish.sh` — 50 tests covering file list, cross-ref trimming, settings trimming

### Changed
- **dist**: Moved MANIFEST and templates/ into `.claude/dist/base/` — clears `.claude/` root for resource directories only
- **cli**: `target_path()` strips `dist/base/` prefix so target projects still receive templates at `.claude/templates/`
- **cli**: `categorize_file()` handles `dist/*/templates/*` paths
- **cli**: MANIFEST sourced from `.claude/dist/base/MANIFEST`
- **validators**: `validate-settings-template.sh` checks both `dist/base/` and `templates/` locations

## [2.0.2] - 2026-03-09 - Transcript backup and insights enhancement

### Added
- **scripts**: `backup-transcripts.sh` — hourly rsync of `~/.claude/projects/` to `~/backups/claude-transcripts/`, preserves transcripts from Claude Code's ~30-day auto-pruning
- **scripts**: `--transcripts-dir` flag for `insights.py` — point at backup dir for full history including pruned sessions
- **backlog**: `insights-subagent-parsing` — parse subagent transcripts for complete usage data

### Fixed
- **version**: Synced pyproject.toml version with VERSION file (was stuck at 2.0.0)

## [2.0.1] - 2026-03-09 - v2 wrap-up cleanup

### Changed
- **indexes**: Updated resource statuses — promoted 10 resources based on real usage (skills, agents, hooks, memories)
- **indexes**: Added SCRIPTS.md index for `.claude/scripts/` (7 scripts tracked)
- **validators**: `validate-resources-indexed.sh` now validates scripts against SCRIPTS.md
- **hooks**: Fully removed anti-rationalization hook (was partially removed — lingered in settings.json, template, MANIFEST, tests)
- **README**: Fixed stale counts (skills 26→29, hooks 8→9, memories 9→7), added missing entries, fixed settings.local.json description, removed placeholder links
- **memories**: Fixed `backlog_schema` tooling section — wrong script path, added full invocations
- **suggestions-box**: Fixed stale evaluate-agent note

## [2.0.0] - 2026-03-09 - Full resource re-evaluation baseline

### Changed
- **skills**: Re-evaluated all 27 skills (excluding evaluate-skill) across 5 groups with current rubrics
- **skills**: `design-db` — restructured from 330 to 190 lines, removed tutorial content, added migration safety checklist
- **skills**: `design-diagram` — added worked example (e-commerce order system), tightened description keywords, added reasoning to type-selection table
- **skills**: `design-docker` — added cross-references to design-db and design-tests
- **skills**: `design-qa` — sharpened qa/tests boundary, added cross-references
- **skills**: `design-tests` — added fixture scope pollution and conftest anti-patterns, narrowed keywords, sharpened rationalizations
- **skills**: `draft-pr` — restructured from flat checklist to progressive disclosure with supporting file
- **skills**: `create-hook` — moved HOOKS_API.md to resources/ for proper progressive disclosure
- **skills**: `snap-back` — deduplicated by referencing communication_style memory
- **skills**: `evaluate-batch` — added cross-references and workflow improvements
- **skills**: `list-memories`, `read-json` — structural improvements and keyword refinements
- **evaluations**: Full baseline reset — all resource scores current against latest rubrics
- **backlog**: Completed P0 evaluations-refresh task (skills, agents, hooks, memories all done)

## [1.25.5] - 2026-03-09 - Memory See Also, rubric fix, and re-evaluation

### Changed
- **memories**: Added See Also cross-references to all 9 memories for ecosystem connectivity
- **memories**: `essential-conventions-code_style` — merged Core Philosophy into Quick Reference, replaced generic guidelines with project-specific conventions (uv, make, ruff, pathlib)
- **memories**: `essential-conventions-memory` — switched to MANDATORY Quick Reference pattern, added category summary table
- **memories**: `essential-preferences-communication_style` — added casual_communication_style cross-reference
- **skills**: `snap-back` — deduplicated by referencing communication_style memory as source of truth instead of restating 5 content blocks
- **skills**: `evaluate-memory` — scoped D3/D6 duplication checks to synced resources only (memories, skills, agents), not toolkit-internal files (indexes, CLAUDE.md)
- **indexes**: `MEMORIES.md` — replaced duplicated category definitions with reference to essential-conventions-memory
- **memories**: `relevant-reference-hooks_config` — added missing block-config-edits.sh entry
- **backlog**: Added P3 (Low) priority tier to BACKLOG.md matching schema memory
- **evaluations**: Re-evaluated all 9 memories — all Grade A (103-110/115)

## [1.25.4] - 2026-03-09 - Hook evaluations, accuracy fixes, and improvements

### Changed
- **hooks**: Fixed HOOKS.md inaccuracies for 5 hooks (enforce-feature-branch, enforce-uv-run, suggest-read-json, session-start, enforce-make-commands)
- **hooks**: Removed anti-rationalization hook from HOOKS.md and evaluations (deactivated)
- **hooks**: `secrets-guard` — Bash regex now catches `.env.*` variants; refactored Read credentials to array-driven loop
- **hooks**: `enforce-uv-run` — fixed chained-command bypass (`cd /app && python`) by matching after chain operators
- **evaluate-hook**: Updated D3/D4 rubric — removed allowlist/safety-level rewards that penalized strict blocking hooks
- **evaluations**: Re-evaluated all 9 hooks with updated rubric (4 A-grade, 5 B-grade)
- **tests**: Added 11 new hook tests (secrets-guard `.env.*` variants, enforce-uv-run compound commands)

## [1.25.3] - 2026-03-09 - Agent See Also sections and re-evaluation

### Changed
- **agents**: Added See Also sections to all 6 agents with bidirectional cross-references
- **agents**: Fixed broken `test-reviewer` reference in code-reviewer → `/design-tests`
- **agents**: Added explicit PASS/FAIL/PARTIAL status criteria to goal-verifier
- **evaluations**: Re-evaluated all agents — scores improved across the board (D5 Integration was the common weak spot)

## [1.25.2] - 2026-03-08 - Evaluate-* rubric self-critique

### Changed
- **evaluate-skill**: Added calibration tables for D2, D5, D6, D8 (previously lacked them)
- **evaluate-agent**: Sharpened D3 (Coherent Persona) — replaced vague "consistent tone" with verifiable criteria (anti-behaviors, voice directives vs job-title-only)
- **evaluate-hook**: Sharpened D3 (Safety) and D4 (Maintainability) middle bands with verifiable criteria; fixed stale example (was 5/6 dims, now 6/6)
- **evaluate-memory**: Sharpened D3 (Content Scope), D4 (Load Timing), D5 (Structure) middle bands; added Fix column and 2 new patterns to anti-patterns table; fixed example (was missing D6, wrong total)
- **evaluate-agent, evaluate-hook, evaluate-memory**: Added See Also sections linking sister evaluators

## [1.25.1] - 2026-03-08 - Backlog reprioritization for v2

### Changed
- **backlog**: Updated current goal to v2 release preparation
- **backlog**: `skill-eval-self-critique` and `evaluations-refresh` promoted to P0 as v2 gate
- **backlog**: `aws-toolkit` promoted to P1, `skill-refactor-examples` to P2 first place
- **backlog**: `skill-learn-quality-gate` moved to P2, P3 dissolved

## [1.25.0] - 2026-03-08 - Toolkit identity document

### Added
- **memory**: `essential-toolkit-identity.md` — what the toolkit is, resource roles, decision checklist, how we differ from marketplace approaches
- **README**: Design Philosophy section linking to identity document

## [1.24.1] - 2026-03-08 - Rules evaluation and backlog cleanup

### Changed
- **backlog**: Resolved `toolkit-rules` (P0) — `.claude/rules/` evaluated against our memory system, no adoption needed
- **drafts**: Archived `claude-code-rules.md` with decision rationale and comparison table

## [1.24.0] - 2026-03-08 - Command-type skill classification

### Added
- **evaluate-skill**: Skill Types section — `type: knowledge|command` frontmatter field with dimension adjustments for D1, D2, D8
- **evaluate-skill**: Separate D1 scoring calibration table for command-type skills (curation quality vs knowledge delta)
- **evaluate-skill**: `type` field in JSON output format and Evaluation Protocol
- **evaluate-skill**: See Also section linking sibling evaluators (evaluate-agent, evaluate-hook, evaluate-memory, evaluate-batch)
- **evaluate-skill**: Command-type meta-question — "Does this flow produce more consistent results than a natural language prompt?"

### Changed
- **evaluate-skill**: Edge Cases table now includes Classification column mapping to skill types
- **snap-back, wrap-up, write-handoff, setup-worktree, teardown-worktree**: Added `type: command` to frontmatter

## [1.23.0] - 2026-03-08 - Template-first pattern for create-* skills

### Added
- **create-agent**: `resources/TEMPLATE.md` — complete `config-auditor` agent as literal starting point for new agents
- **create-skill**: `resources/TEMPLATE.md` — complete `check-dependencies` skill as literal starting point for new skills
- **create-agent**: Template Modifications by Type table (reviewer/verifier, read-only cataloger, code modifier)
- **create-skill**: Template Modifications by Type table (discipline-enforcing, reference/lookup, minimal)
- **create-hook**: HOOKS_API.md table of contents for navigation

### Changed
- **create-agent**: Replaced inline structure template with template reference using LITERAL STARTING POINT framing (305 → 219 lines)
- **create-agent**: Compressed worked examples into iteration reference (~95 → ~20 lines)
- **create-skill**: Replaced Complete Example with compressed iteration reference (~52 → ~8 lines)
- **create-skill**: Renamed "Getting-started" to "Minimal" in Token Efficiency table
- **create-hook**: Added LITERAL STARTING POINT language to bash script and settings.json sections

## [1.22.1] - 2026-03-08 - Backlog triage and reprioritization

### Changed
- **backlog**: Promoted 3 tasks to P0 (skill-templates-as-starting-points, toolkit-rules, skill-command-type-evaluation) and 2 to P1 (toolkit-identity-doc, skill-learn-quality-gate)
- **backlog**: Updated `skill-templates-as-starting-points` to reference create-* skills (formerly write-*)
- **backlog**: Cleaned up `toolkit-rules` notes — removed incorrect claim about conditional memory loading
- **learned.json**: Strengthened lesson on verifying claims before stating them as fact

## [1.22.0] - 2026-03-08 - Skill integration and design-qa improvements

### Added
- **See Also sections**: Added cross-references to all 4 discipline-enforcing skills (design-qa, review-changes, design-tests, refactor) connecting them to sibling skills, agents, and workflow handoffs. D7 scores improved across all 4.
- **design-qa**: Artifact selection decision table for triage (test plan vs test cases vs regression suite vs bug report vs acceptance criteria review).
- **design-qa**: Test debt signals heuristic replacing standard risk matrix — changelog churn, tribal knowledge gates, regression recidivism, debt accumulation rate formula.
- **design-qa**: Bug triage heuristics replacing basic bug report template — backlog prioritization, close-as-wontfix criteria, duplicate-as-signal pattern.

### Changed
- **design-qa**: Narrowed description keywords — removed over-broad "quality assurance" and "manual testing" triggers.

## [1.21.0] - 2026-03-08 - Apply rationalization tables to discipline skills

### Added
- **design-tests**: 6-entry rationalization table — TDD enforcement counters (too simple, tests after, manual testing, speed, glue code, exploration).
- **refactor**: 5-entry rationalization table — scope discipline counters (skip triage, skip measurement, code works fine, skip lenses, no document needed).
- **design-qa**: 5-entry rationalization table — QA thoroughness counters (unlikely edge cases, code looks correct, catch in prod, minor change, no time).
- **review-changes**: 5-entry rationalization table — review discipline counters (too small, looks straightforward, trust author, flag everything, missing context).
- **Backlog**: P2 task `skill-integration-gaps` for improving cross-references across all 4 discipline skills (D7 gap found during evaluation).

## [1.20.0] - 2026-03-08 - Rationalization tables for discipline skills

### Added
- **create-skill RED phase**: Guidance for discipline-enforcing skills — capture verbatim agent rationalizations during baseline testing and build counter-tables (Rationalization | Counter). Distinguishes procedural skills (forgot step X) from discipline skills (argued out of process).
- **Rationalization vs anti-pattern tables**: New section explaining the distinction with a 4-entry TDD example table.
- **P0 backlog task**: Apply rationalization tables to 4 existing discipline-enforcing skills (design-tests, refactor, design-qa, review-changes).

## [1.19.4] - 2026-03-08 - Backlog triage

### Added
- **P3 - Low priority tier**: New priority level between P2 (Medium) and P100 (Nice to Have) for maintenance and refinement tasks. Updated backlog schema memory.

### Changed
- **`skill-eval-self-critique`**: Moved P1 → P3, reframed from runtime eval step to one-time rubric audit.

### Removed
- **`convention-scripts-black-boxes`**: Graveyarded — YAGNI, no skills bundle scripts yet.

## [1.19.3] - 2026-03-08 - Rename feature/ to feat/ branch prefix

### Changed
- **enforce-feature-branch hook**: Suggests `feat/` instead of `feature/` in all block messages.
- **Branch development memory**: Updated naming table, workflow examples, and worktree examples to use `feat/`.

## [1.19.2] - 2026-03-08 - Remove capture-lesson hook

### Removed
- **`capture-lesson.sh` Stop hook**: Failed experiment — hook expected Claude to emit `[LEARN]` tags spontaneously, but no instruction triggered this. Lesson capture is handled by the `/learn` skill via explicit user invocation.

## [1.19.1] - 2026-03-08 - Learned.json consolidation

### Changed
- **learned.json**: Moved from project root to `.claude/learned.json` for consistency with other Claude artifacts. Updated all references in hooks, skills, and indexes.

### Added
- **Backlog**: `toolkit-identity-doc` (P2) — document what claude-toolkit is and isn't, informed by trigger testing experiment.
- **Lesson**: Skill auto-triggering via descriptions is unreliable for tasks Claude can do with built-in tools — use hooks for consistent enforcement, skills for explicit `/skill-name` invocations.

### Removed
- **Trigger testing infrastructure**: `test-trigger.sh`, eval-triggers.json files, test runner, `make test-triggers` target. Experiment concluded — moved backlog item to graveyard with findings.

## [1.19.0] - 2026-03-08 - CLAUDE.md base template

### Added
- **CLAUDE.md template**: Base skeleton for synced projects with conventions (replace don't deprecate, finish the job, zero warnings, trash-put over rm), git workflow, and toolkit resource references.
- **Post-sync checklist**: Now lists `CLAUDE.md.template → CLAUDE.md` as a configuration reference.

## [1.18.0] - 2026-03-08 - Code-debugger escalation guardrail

### Added
- **code-debugger agent**: Cascading-fixes escalation guardrail — detects whack-a-mole debugging pattern (fix A reveals B in different file, fix B reveals C) and stops after 3+ sequential cascading fixes. New `Fix Attempts` append-only section in debug state template, cascade check in execution flow step 6, and `Checkpoint: cascading-fixes` output format.

## [1.17.1] - 2026-03-08 - Hook evaluation and anti-pattern fix

### Fixed
- **HOOKS.md**: Removed 4 stale `Bypass:` env var references that no hook implements.
- **evaluations.json**: Fresh evaluations for secrets-guard (B, 101/115) and block-config-edits (B, 99/115) on updated 6-dimension rubric.

### Added
- **evaluate-hook skill**: Added "env var bypass" anti-pattern (D3: -5) — defeats hook purpose; user can just run the command directly if needed.
- **create-hook skill**: Added "env var bypass" anti-pattern with same reasoning.

## [1.17.0] - 2026-03-08 - Security settings audit

### Added
- **secrets-guard hook**: Extended to block credential file reads — SSH private keys, AWS credentials, GPG directory, Docker/Kubernetes config, GitHub CLI tokens, and package manager tokens (npm, PyPI, RubyGems). Allows public keys and known_hosts.
- **block-config-edits hook**: New hook preventing writes to shell config files (~/.bashrc, ~/.zshrc, etc.), SSH authorized_keys/config, and ~/.gitconfig. Blocks Write, Edit, and Bash tools (redirect, tee, sed -i, mv).
- **enableAllProjectMcpServers: false**: Added to settings to prevent auto-enabling MCP servers from untrusted repos.
- **Tests**: 17 new test cases for credential file and config edit blocking (96 total hook tests).

## [1.16.0] - 2026-03-08 - Anti-rationalization stop hook

### Added
- **anti-rationalization hook**: Stop hook that detects cop-out phrases (scope deflection, deferral, blame shifting, overwhelm, explicit refusal) and blocks with a constructive nudge to reconsider.
- **anti-rationalization tests**: 10 test cases covering loop prevention, all cop-out categories, matched phrase in block reason, and multi-message transcript handling.

## [1.15.0] - 2026-03-08 - Reviewer agent failure-trigger guidance

### Added
- **evaluate-agent skill**: Reviewer/verifier edge case — D2 must define explicit rejection criteria; anti-pattern detection for rubber-stamp risk.
- **create-agent skill**: Reviewer/verifier edge case section with required elements (default stance, pass/fail states, automatic fail triggers) and checklist item.
- **create-agent skill**: Second worked example showing iteration after `/evaluate-agent` failure (D→B+).
- **Both skills**: Table of contents and cross-references to `/evaluate-skill`, `/create-skill`, and each other.

### Fixed
- **evaluate-agent skill**: Example scoring corrected from /100 to /115 scale.

### Evaluations
- **evaluate-agent**: A- (104/120, 86.7%)
- **create-agent**: A- (105/120, 87.5%)

## [1.14.1] - 2026-03-08 - Dangerous command evasion detection

### Fixed
- **block-dangerous-commands hook**: Add normalization to detect dangerous commands hidden via `$(...)`, backticks, `eval`, `bash -c`, and `sh -c` wrappers — 5 bypass vectors closed.
- **verify-resource-deps**: Skip non-local commands (`npx`, `node`, etc.) in hook command validation — fixes false positive on statusline command.

### Added
- **block-dangerous-commands tests**: 11 new test cases covering command chaining and evasion patterns.

## [1.14.0] - 2026-03-08 - Statusline as recommended default

### Added
- **statusline**: `@owloops/claude-powerline` statusline in `settings.json` and settings template as recommended default.
- **powerline config**: Nord-themed powerline config (`claude-powerline.json`) at project level and in templates for synced projects.
- **post-sync checklist**: Reminds users to copy `claude-powerline.json` to `.claude/claude-powerline.json`.

## [1.13.0] - 2026-03-08 - Review-plan step granularity and post-approval flow

### Added
- **review-plan skill**: "After Approval" section — skill now appends post-implementation steps to the plan: commit per step, `goal-verifier` verification, `/wrap-up`.

### Changed
- **review-plan skill**: Step atomicity check renamed to "commit-sized" — each plan step should be independently committable.
- **Evaluation**: review-plan scored A- (106/120, 88.3%).

## [1.12.3] - 2026-03-08 - Goal-verifier severity alignment

### Changed
- **goal-verifier agent**: Gap severity from Critical/Major/Minor to High/Medium/Low for consistency across resources.
- **goal-verifier agent**: New "What You Verify" section — explicitly states it works on the working tree (committed + uncommitted changes).
- **goal-verifier agent**: Verification depth calibration tree — match scrutiny to risk level, with explicit "when to stop" rule.
- **goal-verifier agent**: Skeptic persona threaded through procedural sections; cross-references to `code-reviewer` and `implementation-checker`.
- **Evaluation**: goal-verifier scored A (103/115, 89.6%).

## [1.12.2] - 2026-03-08 - Review-plan severity calibration

### Changed
- **review-plan skill**: Severity levels from Major/Minor to High/Medium/Low with explicit definitions and criteria.
- **review-plan skill**: Verdict now mechanically derived from issue list — issues set a floor, approach assessment can only raise.
- **review-plan skill**: New "Wishful Delegation" anti-pattern for plans that offload cognitive load to the implementing agent.
- **review-plan skill**: Anti-patterns table includes default severity column; output format includes issue summary table with verdict floor trace.
- **Evaluation**: review-plan scored A- (105/120, 87.5%).

## [1.12.1] - 2026-03-08 - Timestamped output for codebase-explorer

### Fixed
- **codebase-explorer agent**: Output now writes to timestamped directory (`{YYYYMMDD}_{HHMM}__codebase-explorer/`) instead of flat `codebase/` folder that overwrote on reruns.

## [1.12.0] - 2026-03-08 - Shared-patterns lens for refactor skill

### Added
- **Refactor skill 5th lens**: "Shared Patterns" — detects cross-module duplication warranting extraction, with guards against premature abstraction (3+ occurrences threshold).
- **Worked example**: ES query date-range parsing duplicated across route handlers.
- **Anti-pattern**: "Premature extraction" added to refactor skill anti-patterns table.

### Changed
- **BACKLOG.md**: Reprioritized items — promoted `hook-dangerous-commands-chaining`, `toolkit-statusline`, `skill-agent-failure-triggers` to P1; moved `aws-toolkit`, `skill-description-trigger-testing` to P2.
- **Evaluation**: Refactor skill scored A (108/120, 90%).

## [1.11.0] - 2026-03-08 - Standardize resource-creation conventions

### Changed
- **Rename write-* → create-***: `write-skill`, `write-agent`, `write-hook`, `write-memory` renamed to `create-skill`, `create-agent`, `create-hook`, `create-memory`. `write-handoff` and `write-docs` unchanged (they write artifacts, not toolkit resources).
- **Quality gate standardized to 85%**: All four create-* skills now target 85% on evaluation. Previously create-skill targeted B (90+), create-agent targeted B (75+), create-hook and create-memory had no quality gate.
- **Integration Quality dimension**: Added D5 (15 pts) to evaluate-agent, D6 (15 pts) to evaluate-hook, D6 (15 pts) to evaluate-memory — checking reference accuracy, duplication avoidance, ecosystem awareness. All three rescaled to /115 with proportional grade boundaries.
- **Cross-references updated**: indexes, README, naming-conventions, BACKLOG, verify-resource-deps allowlist, evaluations.json all updated to use create-* names.
- **Naming conventions**: Split `write-*` verb into `create-*` (toolkit resources) and `write-*` (artifacts/documents).

## [1.10.0] - 2026-03-08 - Auto-detect project in send

### Changed
- **`claude-toolkit send`**: `--project` flag is now optional — auto-detects project name from git repo basename (or directory name as fallback). Explicit `--project` still works as override.

## [1.9.3] - 2026-03-08 - Triage suggestions box

### Added
- **`personal-context-user` memory**: Personal context (cats, board games, Chilean game scene) accepted from claude-meta suggestions.
- **Suggestions box issue handling**: Updated `suggestions-box/CLAUDE.md` with `_issue.txt` triage workflow into BACKLOG.
- **Suggestions box reference**: Added section to root `CLAUDE.md`.
- **Install step**: Symlink to `~/.local/bin` in README Quick Start.

### Changed
- **BACKLOG.md**: 2 new P0 items (`skill-create-conventions`, `toolkit-auto-detect-project`), 3 new P1 items (`skill-review-plan-steps`, `skill-refactor-shared-patterns`, promoted `skill-review-plan-calibration`), 1 new P2 item (`skill-command-type-evaluation` combining command-style classification + activation knowledge scoring). Removed `skill-rename-create` (absorbed into P0).
- **MEMORIES index**: Added `personal-context-user`.
- **Casual communication style memory**: Cross-linked to `personal-context-user`.

### Removed
- **Suggestions box**: Cleared 5 resource files (1 accepted, 1 duplicate deleted, 3 moved to data_engineering by user) and 8 issue files (triaged into backlog).

## [1.9.2] - 2026-03-08 - Reorganize .claude folder

### Changed
- **`.claude/` structure**: Moved resource indexes (AGENTS.md, HOOKS.md, MEMORIES.md, SKILLS.md, evaluations.json) to `indexes/` subfolder. Moved generated artifacts (analysis, design, drafts, reviews) to `output/` subfolder. Deleted stale session handoff files.
- **Path references**: Updated 25 files (3 scripts, 12 skills, 5 agents, CLAUDE.md, AGENTS.md index, .gitignore, BACKLOG.md) to use new paths.

## [1.9.1] - 2026-03-08 - External repo research

### Added
- **Curated resources catalog** (`.claude/curated-resources.md`): Reference list of quality external skills worth studying (frontend design, creative direction, workflow).
- **Claude Code rules draft** (`.claude/drafts/claude-code-rules.md`): Research on `.claude/rules/` path-scoped instructions.
- **Suggestions-box content**: Research artifacts for claude-meta, data_engineering, and opensearch-dashboard projects.

### Changed
- **BACKLOG.md**: 14 new items from exploration of 5 external repos (anthropics/skills, trailofbits, obra/superpowers, affaan-m/ECC, voltagent).
- **CLAUDE.md**: Fixed Quick Start to use `claude-toolkit sync`.
- **Settings template**: Minor fix.

## [1.9.0] - 2026-02-12 - Refactor skill

### Added
- **`/refactor` skill**: Structural refactoring analysis with four-lens reasoning (coupling, cohesion, dependency direction, API surface). Triage-first classification (cosmetic/structural/architectural) prevents over-analysis. Two entry modes: triage and targeted. Language-agnostic, saves analysis to `.claude/analysis/`.

## [1.8.0] - 2026-02-12 - Sync MANIFEST to projects, scoped validation

### Added
- **`claude-toolkit sync`**: Copies MANIFEST to target projects as infrastructure file (alongside `.claude-toolkit-version`).
- **`validate-resources-indexed.sh`**: MANIFEST mode — when MANIFEST exists without index files (target projects), scopes validation to synced resources only. Extra disk files produce warnings, not errors.
- **`verify-resource-deps.sh`**: MANIFEST mode — only checks dependencies for MANIFEST-listed resources. Cross-references to non-MANIFEST resources warn instead of failing.
- **CLI tests**: 4 new tests covering MANIFEST sync and scoped validation behavior.

### Fixed
- **`verify-resource-deps.sh`**: False positive for "agents/memories" prose pattern in `write-skill/SKILL.md` (added to allowlist).

## [1.7.0] - 2026-02-11 - Evaluation system improvements

### Changed
- **`/evaluate-skill` D7**: Replaced Pattern Recognition (10 pts) with Integration Quality (15 pts) — measures reference accuracy, duplication avoidance, handoff clarity, ecosystem awareness, terminology consistency.
- **`/evaluate-skill` D4**: Reduced Specification Compliance from 15 to 10 pts. Tighter criteria penalizing keyword inflation and over-broad trigger lists.
- **`/evaluate-skill` improvements**: Tagged with `[high]`/`[low]` priority for triage.
- **`/write-skill`**: Quality gate now references D7 Integration Quality. Fixed example description that leaked workflow steps.
- **`evaluations.json`**: Updated dimension metadata (D4 max, D7 name and max). Existing resource scores are stale until re-evaluated.

## [1.6.5] - 2026-02-11 - Fix sync CLI tests & settings template

### Fixed
- **`claude-toolkit sync`**: Respect `TOOLKIT_DIR` env var override for testability.
- **CLI tests**: Added MANIFEST to mock toolkit so sync tests resolve files correctly. Fixed 10 failing sync tests.
- **Backlog tests**: Fixed unblocked count expectation (`idea` tasks without dependencies are also unblocked).
- **Settings template**: Added missing `capture-lesson.sh` Stop hook.

### Changed
- **CLAUDE.md**: Reference `make check` instead of individual validation script.

## [1.6.4] - 2026-02-11 - Makefile improvements

### Added
- **`make backlog`**: New target to run backlog query script.
- **Makefile template**: Added `help` target listing all available targets.

## [1.6.3] - 2026-02-11 - Fix list-memories extraction

### Fixed
- **`/list-memories` skill**: Quick Reference extraction leaked into code block examples in `essential-conventions-memory`. Switched from `sed` to `awk` with early exit.

## [1.6.2] - 2026-02-11 - Add learn skill to manifest

### Fixed
- **MANIFEST**: Added missing `skills/learn/` entry so `/learn` skill syncs to projects.

## [1.6.1] - 2026-02-10 - design-tests audit mode & expert content

### Added
- **`design-tests` audit mode**: Source-to-test mapping, gap classification using priority framework, missing case detection in existing tests, structured output template.
- **Mindset framing**: "Tests Are Specifications" — tests as executable behavior contracts.
- **Async testing section**: Factory cleanup gotcha, sync/async fixture mixing, event loop scope guidance.
- **High-risk scenarios**: Prescriptive patterns for DB transaction rollback testing, auth/authz checklist (403 not 404), external API failure modes.
- **Troubleshooting section**: Fixture not found (conftest resolution), import errors at collection, fixture cleanup failures, flaky test diagnosis tree.

### Changed
- **Trimmed activation knowledge**: Removed redundant pytest basics (fixture scope table, marks table/code, make targets, parametrize syntax) from SKILL.md. Removed Makefile targets, pyproject.toml config, marker registration, simple data fixture from EXAMPLES.md. Expert content density increased.
- **`design-tests` description**: Added audit trigger keywords (test gaps, test audit, coverage audit).

## [1.6.0] - 2026-02-10 - Session lessons capture

### Added
- **`/learn` skill**: Explicit lesson capture with user confirmation — categorizes as correction/pattern/convention/gotcha, writes to `learned.json`.
- **`capture-lesson.sh` Stop hook**: Detects `[LEARN]` tags in Claude's responses, extracts lessons, blocks to prompt for user confirmation. Loop prevention via `stop_hook_active`.
- **`session-start.sh` lessons display**: Surfaces key and recent lessons from `learned.json` at session start with counts in acknowledgment prompt.
- **`learned.json` gitignored**: Per-project lesson storage (JSON, not tracked).
- **7 hook tests** for `capture-lesson.sh`: loop prevention, tag detection, multi-message handling, edge cases.

## [1.5.3] - 2026-02-10 - Backlog grooming & new drafts

### Added
- **Refactor skill draft**: `.claude/drafts/skill-refactor/design-notes.md` — refactoring as a design activity with coupling/cohesion/dependency-direction metrics, structured before/after analysis.
- **Session lessons draft**: `.claude/drafts/session-lessons/design-notes.md` — prototype design for `[LEARN]` tag capture via Stop hook, two-layer JSON structure (recent + key), jq querying, promotion path.

### Changed
- **Backlog reprioritized**: Session lessons promoted to P0 (prototype capture mechanism). Refactor skill and design-tests audit mode added to P1. GH Actions skill moved from P2 to P100. Test-gap-analyzer agent absorbed into design-tests audit mode.
- **Graveyarded 3 items**: `skill-polars` (base knowledge + Context7 sufficient), `skill-logging` (preferences not yet formed), `agent-test-gaps` (behavioral delta too thin).

## [1.5.2] - 2026-02-10 - AWS toolkit pre-research drafts

### Added
- **`.claude/drafts/` folder**: Staging area for pre-research before building resources.
- **AWS toolkit drafts**: Article analysis (12 best practices tiered by agent usefulness), IAM validation tools research (Parliament, Policy Sentry, IAM Policy Autopilot, Access Analyzer), cost estimation tools research (Infracost, AWS Pricing API, Cloud Custodian), and service selection guide placeholder.
- **Backlog updated**: `aws-toolkit` item now references drafts folder.

## [1.5.1] - 2026-02-10 - Hook test fixes

### Fixed
- **`secrets-guard.sh`**: Now allows `.env.template` files (alongside `.example`).
- **`enforce-make-commands` tests**: Updated to match hook behavior — bare `pytest` is blocked but targeted runs like `pytest tests/` are allowed. Added test case for targeted pytest.

## [1.5.0] - 2026-02-10 - Handoff resume prompt & validation script relocation

### Added
- **`write-handoff` resume prompt**: Handoff template now includes a `## Resume Prompt` section that generates a paste-ready sentence combining the file read with intent and next steps. Next session gets both context and direction in one line.

### Changed
- **Validation scripts relocated**: Moved `validate-all.sh`, `validate-resources-indexed.sh`, `validate-settings-template.sh`, and `verify-resource-deps.sh` from `scripts/` to `.claude/scripts/`. Co-locates validation with the resources it validates. Updated MANIFEST, Makefile, CLAUDE.md, and template references.
- **`verify-resource-deps.sh`**: Added allowlist entry for `experimental-conventions-alternative_commit_style` (documentation example in naming conventions).
- **Backlog reprioritized**: Added P0 tier, promoted eval improvements to P1, added rules exploration and session lessons to P2.

### Removed
- **`scripts/analyze-usage.sh`**: Superseded by `scripts/insights.py`.

## [1.4.3] - 2026-02-10 - Resource index updates & personal memory category

### Added
- **`personal` memory category**: Private preferences — not shared, not evaluated. Updated memory conventions, evaluate-memory skill, evaluate-batch skill, and verify-resource-deps script.

### Changed
- **Resource status promotions**: goal-verifier → stable, codebase-explorer → beta, secrets-guard → stable, remaining alpha hooks → beta, review-plan → stable, design-tests/db/diagram/worktrees → beta, reducing_entropy → stable.
- **code-reviewer index**: Updated tools to include Write.
- **`experimental-preferences-casual_communication_style`**: Renamed to `personal-` category, removed from evaluations.json.

## [1.4.2] - 2026-02-10 - Code reviewer agent improvements

### Changed
- **`code-reviewer` agent**: Added persistent output path (`.claude/reviews/`), mechanic persona voice, calibration example showing same issue at different scales, and "reporter, not decider" handoff principle. Re-evaluated: A (91/100).

## [1.4.0] - 2026-02-07 - Transcript analytics

### Added
- **`scripts/insights.py`**: Python analytics script for Claude Code transcripts (`~/.claude/projects/`). Parses JSONL session data with streaming (no full load). Subcommands: `overview`, `projects`, `tools`, `skills`, `agents`, `hooks`, `sessions`, `full`. Global flags: `--project`, `--since`, `--json`, `--output`.
- **`pyproject.toml`**: Minimal project config for `uv run` (stdlib only, no dependencies).

## [1.3.0] - 2026-02-07 - Documentation skill

### Added
- **`write-docs` skill**: Gap-analysis-first documentation writer with two modes (user-docs, docstrings). Soft dependency on codebase-explorer for project cartography. Includes style detection, verification step, and good/bad examples for both modes. Eval: A- (106/120).

### Changed
- **BACKLOG.md**: Moved `review-documentation` to Graveyard — write-docs gap analysis already covers doc review. For docs, reading IS the review.

## [1.2.0] - 2026-02-07 - Explicit sync manifest

### Added
- **`.claude/MANIFEST`**: Opt-in manifest controlling which files sync to projects — replaces find-based scan with hardcoded ignore list
- **`resolve_manifest()`**: Expands manifest entries (directories and files) into file list
- **Post-sync checklist**: Shows configuration references and `.claude-toolkit-ignore` guidance after every sync

### Changed
- **`cmd_sync()`**: Reads manifest instead of scanning all `.claude/` files; hardcoded ignore patterns removed
- **README.md**: Quick Start now uses `claude-toolkit sync` instead of `install.sh`

### Removed
- **`install.sh`**: Fully replaced by `claude-toolkit sync`
- **Hardcoded ignore list**: `plans/`, `usage.log`, `settings.local.json`, `settings.json` no longer needed — manifest excludes by omission

## [1.1.1] - 2026-02-07 - Template sync and drift validation

### Added
- **validate-settings-template.sh**: Detects hook drift between settings.json and settings.template.json (command list + format structure)
- **BACKLOG-standard.md** and **BACKLOG-minimal.md** templates replacing outdated single BACKLOG.md
- **Makefile template**: `claude-toolkit-validate` target for running validations

### Changed
- **settings.template.json**: Synced to current nested hook format with all 8 hooks, `_env_config` block, permissions moved to settings.local.json instruction
- **validate-all.sh**: Now includes settings template drift check

### Removed
- **BACKLOG.md template**: Replaced by standard and minimal variants

## [1.1.0] - 2026-02-07 - Resource dependency verification

### Added
- **verify-resource-deps.sh**: Cross-reference validation for 7 dependency types (settings→hooks, hooks→skills, skills→agents, skills→skills, skills→scripts, memories→memories, memories→skills)
  - Allowlist for documentation examples (template names, worked examples)
  - Built-in command filtering (`/clear`, `/commit`, etc. skip skill lookup)
- **validate-all.sh**: Wrapper running both index and dependency validations
- **BACKLOG.md**: Added `settings-template-update` and `install-sync-manifest` P1 items

### Changed
- `make validate` now runs `validate-all.sh` (both checks) instead of only index validation

## [1.0.3] - 2026-02-07 - Suggestions box triage

### Fixed
- **send command**: Naming collision when sending multiple flat resources (hooks, agents, memories) — now uses filename instead of parent directory
- **sync --force**: Now bypasses version check when versions are equal or project is newer

### Changed
- **review-plan skill**: Added color/formatting guidance to output template (blockquotes, horizontal rules, visual emphasis for verdicts)
- **backlog-query.sh**: Synced from projects/ — added id lookup, summary command, validate command, --path flag, awk display fix
- **backlog-validate.sh**: New standalone backlog format validator (synced from projects/)
- **BACKLOG.md**: Moved write-docs skill to P1; added 4 P100 ideas (telegram bridge, headless suggestions processor, metadata blocks, /insights skill)

### Removed
- 11 processed suggestions-box issue files (2 deferred to separate branches)

## [1.0.2] - 2026-02-07 - Hook hardening

### Changed
- **All hooks**: Removed bypass env vars (`ALLOW_DIRECT_PYTHON`, `ALLOW_DIRECT_COMMANDS`, `ALLOW_DANGEROUS_COMMANDS`, `CLAUDE_SKIP_PLAN_COPY`, `ALLOW_PLAN_ON_MAIN`, `ALLOW_COMMIT_ON_MAIN`) — hooks now enforce unconditionally
- **enforce-make-commands hook**: Only block bare `pytest` (full suite); targeted runs (`pytest tests/file.py`, `pytest -k "pattern"`) pass through
- **copy-plan-to-project hook**: Removed `FILE_PATH_OVERRIDE` testing var, fixed stale path comment
- **enforce-feature-branch hook**: Fixed stale `PROTECTED_BRANCHES` example in comments
- **settings.json**: Only legitimate config vars remain (`CLAUDE_PLANS_DIR`, `CLAUDE_MEMORIES_DIR`, `JSON_SIZE_THRESHOLD_KB`, `PROTECTED_BRANCHES`)
- **hooks_config memory**: Stripped all bypass references

## [1.0.1] - 2026-02-07 - Suggestions box review

### Changed
- **setup-worktree skill**: Merged `.claude/` symlinking procedure, required plan file argument, removed layout options (always inside project)
- **secrets-guard hook**: Removed bypass env vars (`ALLOW_ENV_READ`, `SAFE_ENV_EXTENSIONS`), fixed `.env.api.example` pattern, stripped self-documenting bypass hints from block messages
- **suggest-read-json hook**: Removed bypass env vars (`ALLOW_JSON_READ`, `ALLOW_JSON_PATTERNS`, `JSON_READ_WARN`), hardcoded allowlist, kept size threshold
- **backlog_schema memory**: Generalized from project-specific to toolkit-wide (P100, kebab-case IDs, minimal format, Current Goal section, tooling reference)
- **casual_communication_style memory**: Added accumulated session moments to section 8
- **hooks_config memory**: Removed stale bypass references, updated troubleshooting
- **settings.json**: Cleaned out removed env var documentation

## [1.0.0] - 2026-01-28 - Quality-gated release

### Added
- **Evaluation system**: Track resource quality with dimensional scoring
  - `evaluations.json` with per-resource grades (A/A-/B+/B/C), scores, and improvement suggestions
  - `evaluate-batch` skill for parallel evaluation of multiple resources
  - File hash tracking for staleness detection
  - All skills at A- or better (85%+), all agents at A (90%+)
- **New skills**: `evaluate-batch`, `design-tests`, `teardown-worktree`
- **New memories**: `experimental-preferences-casual_communication_style`, `relevant-conventions-backlog_schema`, `relevant-philosophy-reducing_entropy`, `relevant-reference-hooks_config`
- Automated tests: hooks (45 tests), CLI (25 tests), backlog-query (35 tests)
- `make check` target runs all validation

### Changed
- All skills improved with expert heuristics, edge cases, and anti-patterns
- All agents improved with stronger personas and clearer boundaries
- Skill descriptions standardized to inline keyword format for better routing (`design-db`, `draft-pr`, `wrap-up` improved)
- `session-start` hook enhanced with git context and memory guidance
- Renamed `essential-workflow-*` memories to `relevant-workflow-*` (on-demand, not session-critical)

### Removed
- `analyze-naming` skill (consolidated into other workflows)

### Quality Summary
- **26 skills**: All A- or better (102-112/120)
- **6 agents**: All A grade (90-94/100)
- **8 hooks**: All A grade (90-97/100)
- **9 memories**: All A grade (90-100/100)

## [0.15.0] - 2026-01-27 - CLI redesign

### Changed
- Renamed `bin/claude-sync` → `bin/claude-toolkit` with subcommand structure
- `sync` is now a subcommand: `claude-toolkit sync [path]`
- Files displayed grouped by category (skills, agents, hooks, memories, templates, scripts)
- Interactive category selection: `[a]ll / [s]elect / [n]one`
- Added `settings.json` to built-in ignores (never overwrite project settings)

### Added
- Main help: `claude-toolkit --help`
- Subcommand help: `claude-toolkit sync --help`, `claude-toolkit send --help`
- `--only <categories>` flag for selective sync (comma-separated)
- Post-sync reminders when templates are synced
- Template files for project setup:
  - `templates/Makefile.claude-toolkit` - Suggested make targets
  - `templates/gitignore.claude-toolkit` - Suggested .gitignore entries
  - `templates/settings.template.json` - Reference settings.json
  - `templates/claude-sync-ignore.template` - Default ignore patterns
  - `templates/mcp.template.json` - MCP servers (context7, sequential-thinking)

## [0.14.0] - 2026-01-27 - Worktree lifecycle skills

### Added
- `teardown-worktree` skill: safe worktree closure after agent completion
  - Validates path, checks uncommitted changes, runs implementation-checker
  - GREEN/YELLOW/RED paths with explicit decision criteria
  - Anti-patterns table for common mistakes
- Multi-instance note in `setup-worktree` for agent coordination
- `relevant-reference-hooks_config` memory documenting hook env vars
- Branch-timestamped report filenames in implementation-checker agent

### Changed
- Renamed `essential-reference-commands` to `relevant-reference-commands` (not session-critical)
- `claude-sync` now excludes `usage.log` and `settings.local.json` from sync payload

## [0.13.0] - 2026-01-26 - Testing patterns skill

### Added
- `design-tests` skill: pytest patterns for fixtures, mocking, organization, test prioritization
- `experimental-preferences-casual_communication_style` memory for meta-discussions
- Subagent recommendation in all `evaluate-*` skills to avoid self-evaluation bias

## [0.12.0] - 2026-01-26 - Memory guidance in session start

### Added
- Session-start hook now prompts agent to check `/list-memories` and read relevant memories for non-essential topics
- Inspired by Serena MCP's memory system approach

## [0.11.0] - 2026-01-26 - Enforce feature branch workflow

### Added
- `enforce-feature-branch.sh` now blocks `git commit` on protected branches (main/master)
- `ALLOW_COMMIT_ON_MAIN` env var bypass for git commit blocking
- Hook registered in settings.json for `EnterPlanMode|Bash` matcher

### Changed
- Renamed `scripts/validate-indexes.sh` → `scripts/validate-resources-indexed.sh` (clearer name)

## [0.10.0] - 2026-01-26 - Backlog tooling in sync payload

### Added
- `.claude/templates/BACKLOG.md`: starter template for new projects
- `.claude/scripts/backlog-query.sh`: query tool now synced to projects (moved from `scripts/`)

### Changed
- `claude-sync` now ignores `plans/` directory by default (session-specific, shouldn't sync)

## [0.9.0] - 2026-01-26 - Send subcommand for claude-sync

### Added
- `claude-sync send` subcommand: copy resources from other projects to `suggestions-box/` for review
  - Usage: `claude-sync send <path> --type <skill|agent|hook|memory> --project <name>`
  - Derives resource name from path structure (e.g., `draft-pr` from `.claude/skills/draft-pr/SKILL.md`)

## [0.8.0] - 2026-01-26 - Backlog schema and agent improvements

### Added
- `relevant-conventions-backlog_schema` memory: standardized BACKLOG.md format with priority sections, entry format, categories, status values
- `scripts/backlog-query.sh`: bash-only CLI to query backlog by status/priority/scope/branch

### Changed
- Renamed `plan-reviewer` agent to `implementation-checker` (better reflects purpose)
  - Added Write tool for report persistence to `.claude/reviews/`
  - Added Beliefs, Anti-Patterns, Status Values sections
- Updated `evaluate-agent` skill D4 scoring rule for tool selection
- Converted BACKLOG.md to new schema format

## [0.7.1] - 2026-01-25 - Skill naming conventions

### Changed
- Renamed 13 skills to follow `verb-noun` convention:
  - `*-judge` → `evaluate-*` (agent, skill, hook, memory)
  - `naming-analyzer` → `analyze-naming`
  - `json-reader` → `read-json`
  - `database-schema` → `design-db`
  - `docker-deployment` → `design-docker`
  - `git-worktrees` → `setup-worktree`
  - `mermaid-diagrams` → `design-diagram`
  - `qa-planner` → `design-qa`
  - `quick-review` → `review-changes`
  - `next-steps` → `write-handoff`
- Added naming convention references to `write-skill`, `write-agent`, `write-hook` skills

### Added
- `docs/naming-conventions.md` - naming guidelines for skills, agents, hooks, memories

## [0.7.0] - 2026-01-25 - Progressive disclosure pattern

### Added
- `write-skill`: Progressive disclosure pattern section (500-line rule, resources/ structure)
- `skill-judge`: Supporting files checklist under D5 (evaluates companion file quality)

## [0.6.0] - 2026-01-25 - Enforce feature branch hook

### Added
- `enforce-feature-branch.sh` hook: blocks plan mode on main/master/protected branches
- Handles detached HEAD state with actionable message
- Configurable via `PROTECTED_BRANCHES` env var (regex pattern)

## [0.5.0] - 2026-01-25 - Write-agent skill

### Added
- `write-agent` skill: create agents with proper structure (persona, focus, boundaries, output format)
- Analysis report on resource-writer agent feasibility (`docs/analysis/`)

### Changed
- Completes write/judge skill pairs: skill, hook, memory, agent all have both now

## [0.4.0] - 2026-01-25 - Memory judge & branch workflow

### Added
- `evaluate-memory` skill: evaluate memory files against conventions (category, naming, Quick Reference, load timing)
- `relevant-workflow-branch_development` memory: branch-based development workflow conventions
- README Concepts section: explains difference between skills, memories, agents, hooks

### Changed
- Renamed `essential-preferences-conversational_patterns` → `essential-preferences-communication_style`
- Clarified memory loading: removed unreliable "on-demand" claims, only session-start or user-requested
- README now documents all 23 skills and 9 hooks (was missing several)
- CLAUDE.md now references `scripts/validate-resources-indexed.sh` in "When You're Done"

## [0.3.0] - 2026-01-25 - Safety hooks & usage analytics

### Added
- `block-dangerous-commands.sh` hook: blocks rm -rf /, fork bombs, mkfs, dd to disks
- `secrets-guard.sh` hook: blocks .env reads and env/printenv commands
- `suggest-read-json.sh` hook: suggests /json-reader for large JSON files
- `scripts/analyze-usage.sh`: extracts skill/agent usage from transcripts (captures both user and agent invocations)
- `scripts/validate-resources-indexed.sh`: validates index files match actual resources

### Changed
- All new hooks have configurable bypass env vars, size thresholds, and allowlists

## [0.2.3] - 2026-01-25 - Hooks API documentation

### Changed
- HOOKS_API.md now documents all 13 hook events with input fields, matchers, and output formats
- Plan files now stored in `.claude/plans/` instead of `docs/plans/`
- Added `.claude/usage.log` and `.claude/plans/` to .gitignore (session artifacts)

## [0.2.2] - 2026-01-25 - Hook quality improvements

### Fixed
- All hooks now have jq error handling, documented test cases, and settings.json examples
- `enforce-make-commands.sh`: pattern array for maintainability, catches `python -m pytest` and `ruff check/format`, `ALLOW_DIRECT_COMMANDS` bypass
- `enforce-uv-run.sh`: regex now matches `python3.11`, `python3.12` etc., `ALLOW_DIRECT_PYTHON` bypass
- `session-start.sh`: dynamic main branch detection, configurable `CLAUDE_MEMORIES_DIR`, directory existence check
- `copy-plan-to-project.sh`: configurable `CLAUDE_PLANS_DIR`, source file check, timestamp in fallback filename
- `claude-sync`: warns if jq not installed (required by hooks)

## [0.2.1] - 2026-01-25

### Fixed
- `wrap-up` skill now supports VERSION, pyproject.toml, or package.json

## [0.2.0] - 2026-01-25 - Status tracking & Docker skill

### Added
- Status flags (stable/beta/new) to all index files
- `docker-deployment` skill for Dockerfile and compose patterns
- Reorganized BACKLOG.md with scope definitions and priorities

### Fixed
- `enforce-uv-run.sh` regex syntax error
- `session-start.sh` now requests acknowledgment
- `claude-sync` flag parsing when passed as first argument

## [0.1.0] - 2026-01-25

### Added
- Initial release of Claude Toolkit
- Skills: brainstorm-idea, review-plan, write-memory, naming-analyzer, next-steps, analyze-idea, write-skill, skill-judge, database-schema, list-memories, mermaid-diagrams, json-reader, snap-back
- Agents: goal-verifier, code-reviewer, plan-reviewer, code-debugger, pattern-finder
- Hooks: session-start, copy-plan-to-project, enforce-uv-run, enforce-make-commands
- Memory templates: essential conventions, preferences, and workflow guides
- `install.sh` for one-time project setup
- `claude-sync` for version-aware updates with conflict handling
