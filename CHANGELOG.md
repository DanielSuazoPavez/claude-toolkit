# Changelog

## [2.77.1] - 2026-04-28 - Fix make check failures

### Fixed
- **hooks**: Suppress shellcheck SC2034 false positives in `detect-session-start-truncation.sh` — `OUTCOME` and `BYTES_INJECTED` are read by the `_hook_log_timing` EXIT trap in hook-utils, invisible to static analysis.
- **indexes**: Add `migrate-backlog-to-json.sh` to SCRIPTS.md (Migration section) — was missing from index after 2.77.0.

## [2.77.0] - 2026-04-28 - JSON-backed backlog with CLI mutations

### Added
- **cli**: `BACKLOG.json` is now the source of truth — `BACKLOG.md` is auto-generated via `backlog render` and gitignored. All queries use `jq` instead of markdown parsing with awk + `eval`-interpolated filters (injection vector eliminated).
- **cli**: New mutation subcommands — `backlog add`, `backlog move <id> <priority>`, `backlog remove <id>` write directly to `BACKLOG.json`.
- **cli**: New `backlog render` subcommand — generates `BACKLOG.md` from JSON with priority-grouped sections and metadata.
- **cli**: `backlog summary` now sorts priority groups deterministically (P0→P1→P2→P3→P99), fixing arbitrary awk iteration order.
- **cli**: `backlog validate` rewritten for JSON — checks required fields, enum values, duplicate ids, relates_to token format, and scope definitions.
- **schema**: `task.schema.json` expanded with `id`, `priority`, `title` as required fields; `status` required (defaults to `idea`); `relates-to` renamed to `relates_to`.
- **scripts**: `migrate-backlog-to-json.sh` — reusable migration from `BACKLOG.md` to `BACKLOG.json` (tested on both claude-toolkit and claude-sessions).
- **tests**: Backlog test suite rewritten for JSON fixtures — 113 tests (up from 23) covering queries, mutations, render, validation, and summary sort.

## [2.76.0] - 2026-04-28 - PostToolUse logger for idle-time classification

### Added
- **hooks**: `log-tool-uses.sh` — PostToolUse pure-logging hook that records every tool invocation (all tools, no matcher) to `invocations.jsonl` with `duration_ms` and `tool_response` embedded. Enables idle-time classification in claude-sessions: gap between consecutive tool calls minus execution duration = model thinking time. Follows `log-permission-denied.sh` pattern. Ships to base distribution; gated by `CLAUDE_TOOLKIT_TRACEABILITY=1`.

### Notes
- **exploration**: Completed `re-explore-web-ecosystem` — two rounds across GitHub, blogs, awesome-lists, and marketplaces. 25+ repos/resources reviewed, 3 curated resource entries added (design.md, Crest agent, aipatternbook.com). Deep dives into VILA-Lab (CC architecture paper) and Crosley (95-hook architecture).
- **backlog**: 4 new P0/P1 tasks from exploration findings (log-bash-commands, backlog-json-source, hooks-config-driven, sync-profiles). Full triage pass — reprioritized and reordered across all tiers.

## [2.75.0] - 2026-04-28 - SessionStart payload cap guardrails

### Added
- **hooks**: `detect-session-start-truncation.sh` — `UserPromptSubmit` hook that fires once per session (marker-file guard) to check whether SessionStart output was truncated by the harness ~10KB cap. Uses hook-utils for standardized init and JSONL logging. Warns model when essential docs may be incomplete. Ships to both base and raiz distributions.
- **scripts**: `validate-session-start-cap.sh` — `make validate` step that runs `session-start.sh` in dry-run, measures payload size, and fails at 10KB / warns at 9.5KB. Catches drift before it hits the harness cap. Added to `validate-all.sh` orchestrator. Ships to raiz.
- **tests**: `test-validate-session-start-cap.sh` — 7 tests covering threshold enforcement, dry-run isolation, and edge cases.

## [2.74.0] - 2026-04-27 - PermissionDenied hook for auto-mode classifier observability

### Added
- **hooks**: `log-permission-denied.sh` — pure-logging hook that captures auto-mode classifier denials into `invocations.jsonl`. No stdout output (denial stands); full stdin embedded in the JSONL row for downstream analytics. Ships to both base and raiz distributions.
- **hooks**: `PermissionDenied` handler registered in `settings.json` with no matcher (fires on all tool denials). Both `settings.template.json` templates (base + raiz) updated.
- **tests**: `test-log-permission-denied.sh` — 7 tests covering silent output, JSONL field correctness, stdin payload embedding, traceability gating, and malformed stdin resilience.

## [2.73.0] - 2026-04-27 - platform support docs and bash version check

### Added
- **scripts**: `verify-external-deps.sh` now checks bash version (≥ 4.0 required) as a platform prerequisite before scanning skill-declared tools. On macOS with stock bash 3.2, gives an early signal before hooks fail with `declare -A` or `${var^^}` errors.
- **docs**: Platform Support section in README — documents Linux, macOS, and WSL2 support with macOS bash 4+ prerequisite and Homebrew install instructions.

## [2.72.13] - 2026-04-27 - ship validation scripts and schema to raiz consumers

### Fixed
- **dist**: Added `validate-all.sh` and its 6 sub-validators, `statusline-capture.sh`, and `detection-registry.schema.json` to raiz MANIFEST — the `setup-toolkit` skill calls `validate-all.sh` in Phase 3 but none of those scripts were shipping, so raiz consumers saw them all flagged as orphans by `setup-toolkit-diagnose.sh`.
- **dist**: Removed `claude-toolkit-sync` make target from `Makefile.claude-toolkit` template — the command is interactive and not useful for agentic usage.

## [2.72.12] - 2026-04-27 - require bash 4+ via #!/usr/bin/env bash shebang sweep

### Fixed
- **scripts**: Swept all 69 `#!/bin/bash` shebangs to `#!/usr/bin/env bash` across hooks (16), scripts (11), and tests (36+). Stock macOS `/bin/bash` is 3.2 (Apple won't ship GPLv3); the hardcoded shebang bypassed Homebrew bash even when installed, causing `declare -A` and `${var^^}` failures. With `env bash`, PATH resolution picks up Homebrew bash 5.x automatically. Policy decision: require bash 4+ (option a) — no syntax downgrades to bash 3.2. Closes `macos-bash4-policy`.

## [2.72.11] - 2026-04-27 - remove dangerous 2>/dev/null from validators and diagnose script

### Fixed
- **scripts**: Removed `2>/dev/null` from 13 jq/sed/grep call sites in `validate-settings-template.sh` (1 site), `validate-safe-commands-sync.sh` (1 site), and `setup-toolkit-diagnose.sh` (8 sites) where error suppression turned real failures into silent-correctness bugs. All sites already have file-existence guards upstream — the suppression was hiding unexpected errors, not expected ones. On macOS (or any environment where the command fails), variables came up empty and downstream comparisons passed vacuously. Closes `macos-loud-errors`. Eval-related scripts deferred as P99 (`eval-macos-loud-errors`).

## [2.72.10] - 2026-04-27 - replace GNU mktemp --suffix with portable alternative

### Fixed
- **tests**: Replaced 3 GNU `mktemp --suffix=.json` calls in `tests/hooks/test-grouped-read.sh` with `mktemp` + `mv` rename. BSD `mktemp` (macOS) has no `--suffix` flag; the old calls failed, leaving test variables unset and breaking the grouped-read hook test suite. Partially closes `macos-mktemp-md5sum` (`md5sum` portion deferred — eval core not yet shipped).

## [2.72.9] - 2026-04-27 - replace GNU find -printf with portable alternatives

### Fixed
- **scripts**: Replaced all 6 GNU `find -printf` calls in `validate-resources-indexed.sh` (4 hits) and `setup-toolkit-diagnose.sh` (2 hits) with POSIX-portable equivalents. BSD `find` (macOS) has no `-printf`; the old calls produced empty output silently, causing index validation to never see disk files and orphan detection to miss scripts/schemas. Closes `macos-find-printf`.

## [2.72.8] - 2026-04-27 - dedicated test for verify-resource-deps.sh

### Added
- **tests**: `tests/test-verify-resource-deps.sh` — 57 fixture-driven tests covering all 7 validator sections (settings→hooks, hooks→skills, skills→agents, skills→skills, skills→scripts, docs→docs, docs→skills) plus MANIFEST mode, scope-skip behavior, and integration against the real toolkit. Mirrors `test-verify-external-deps.sh` structure. Wired into `Makefile` (`test-verify-res-deps`) and auto-discovered by `run-all.sh`. Closes `test-verify-resource-deps`.

### Notes
- **tests**: Added diagnostic instrumentation (byte length + hex dump) in failure branches of `test-backlog-query.sh` (all 5 assertion functions) and `test-setup-toolkit-diagnose.sh` (orphan-detection assertion). If the transient WSL2 grep flake recurs under parallel `make check`, the output now distinguishes NUL/encoding corruption from a genuine grep miss. Closes `backlog-query-scope-flake`, `diag-orphan-flake-instrumentation`.

## [2.72.7] - 2026-04-27 - scope hook extraction to exclude statusLine

### Fixed
- **scripts**: `setup-toolkit-diagnose.sh`, `validate-settings-template.sh`, and `verify-resource-deps.sh` now extract hook commands from `.hooks` only (via `jq` recursive descent) instead of matching all `"command"` values globally with `sed`. The old regex included the `statusLine` block's command, causing a false `EXTRA: .claude/scripts/statusline-capture.sh` in Check 1 when the synced template predated the `statusLine` addition. Hook count corrected from 9 to 8. Closes `diag-statusline-scope`.

### Added
- **tests**: 4 new assertions in `test-setup-toolkit-diagnose.sh` and `test-validate-settings-template.sh` covering statusLine exclusion from hook comparison — both "statusLine in both files" and "statusLine only in settings" cases.

## [2.72.6] - 2026-04-27 - template alignment for macOS consumers

### Fixed
- **templates**: added `bash` prefix to `session-start.sh`, `git-safety.sh`, and `approve-safe-commands.sh` hook commands in both base and raiz `settings.template.json`. Consumer projects already invoked these with `bash`, causing the diagnostic to report 3 MISSING + 3 EXTRA on every run. Toolkit's own `.claude/settings.json` updated to match.
- **templates**: removed `lessons.db`, `session-index.db`, `hooks.db` entries from `gitignore.claude-toolkit`. These global databases live in `~/.claude/` and don't belong in project-level `.gitignore` — their presence caused false MISSING reports in Check 5 for projects that (correctly) don't track them.

### Added
- **templates**: `claude-toolkit-ignore.template` now ships in the raiz distribution. Raiz consumers get a smaller resource subset, so extra resources from base (or project-local additions) show up as orphans in Check 8 — the template gives them a starting point for suppressing those warnings.
- **docs**: `docs/official-references.md` — curated index of Anthropic's official Claude Code documentation (17 pages + bonus env-vars and commands references). Covers canonical URLs (domain moved from `docs.anthropic.com` to `code.claude.com`), key platform env vars for resource authoring, gaps the toolkit fills (topic-scoped docs, tiered loading, design guidance), and terminology collisions (memories, rules vs docs, "custom commands" vs skills). Closes P1 `official-docs-index`.

## [2.72.5] - 2026-04-27 - portable regex extraction (PCRE → POSIX) for macOS

### Fixed
- **scripts**: replaced all 22 `grep -oP` (PCRE) call sites across 6 scripts with portable `sed -nE` / `grep -oE` / `awk` equivalents. BSD `grep` on macOS does not support `-P` and was emitting `grep: invalid option -- P` while letting downstream comparisons run vacuously over empty data — a silent-correctness bug, not just noise. Affected scripts: `verify-resource-deps.sh` (9 sites), `setup-toolkit-diagnose.sh` (6), `validate-resources-indexed.sh` (5), `validate-settings-template.sh` (1), `validate-safe-commands-sync.sh` (1), `verify-external-deps.sh` (1). End-to-end output of `verify-resource-deps.sh` is byte-identical to pre-change on real toolkit data; counts unchanged (9 / 0 / 17 / 124 / 3 / 28 / 37). Closes P1 `macos-grep-pcre`.

### Added
- **tests**: `tests/test-validate-settings-template.sh` and `tests/test-validate-safe-commands-sync.sh` — dedicated coverage for the two scripts that previously had only one `grep -oP` site each and no test file. Both wired into `Makefile` (`test-validate-settings-template`, `test-validate-safe-commands-sync`) and auto-discovered by `tests/run-all.sh`.

### Notes
- Pattern 3 (multi-match-per-line in prose) used `awk` loops; Pattern 1/2 (one-match-per-line in JSON / markdown tables) used `sed -nE`; Pattern 4 (literals) used `grep -oE`. Translation was per-site, not a one-size helper.
- One pre-flight gotcha worth flagging: POSIX awk silently treats `\b` as literal `b`. The first multi-match audit on line 250 of `verify-resource-deps.sh` (``\`name\` agent``) used `\b` and returned a false negative; the byte-diff verification step caught it (3 missed references on `review-plan/SKILL.md:9`). Replacement uses `[^[:alnum:]_]` for the boundary. Captured as a global lesson.
- Linux behavior unchanged. Awaiting macOS consumer re-run of `setup-toolkit-diagnose.sh` to confirm the visible `grep: invalid option -- P` errors are gone.

## [2.72.4] - 2026-04-27 - relocate `backup-lessons-db.sh` to claude-sessions

### Removed
- **scripts**: `.claude/scripts/cron/backup-lessons-db.sh` deleted from the toolkit. The script now lives at `cron/backup-lessons-db.sh` in the **claude-sessions** repo, which owns the `lessons.db` schema. With it gone, `.claude/scripts/cron/` is empty and removed entirely.
- **dist/base/EXCLUDE**: dropped the `.claude/scripts/cron/` exclusion (the directory no longer exists, so nothing to exclude).
- **.gitignore**: dropped `.claude/scripts/cron/cron.log` (directory gone).
- **Makefile** (`lint-bash`): dropped `.claude/scripts/cron/*.sh` from the shellcheck glob.

### Changed
- **docs/indexes/SCRIPTS.md**: removed the `cron/backup-lessons-db.sh` row from the Maintenance section and updated the section preamble to reflect that only `validate-dist-manifests.sh` remains.
- **.claude/docs/relevant-toolkit-lessons.md** (§9 Backup): repointed the script reference to claude-sessions' `cron/backup-lessons-db.sh`.

### Notes
- **Crontab heads-up**: anyone with a crontab pointing at the old path (`.../claude-toolkit/.claude/scripts/cron/backup-lessons-db.sh`) needs to repoint at the claude-sessions location.
- **Closes**: P1 `move-backup-lessons-to-claude-sessions` (was deferred from 2.62.0).

## [2.72.3] - 2026-04-27 - block interpreter-bodied writes to `.claude/settings*.json`

### Fixed
- **hooks** (`block-config-edits.sh`): close the bypass where `python -c`, `python3 -c`, `bash -c`, `sh -c`, and `python <<EOF` could write to `.claude/settings.json` / `.claude/settings.local.json`. Quoted/heredoc bodies were blanked by `_strip_inert_content` before the existing verb-shaped rules saw them; the new arm runs against the raw command and is gated by an interpreter token (`(python[0-9.]*|bash|sh)\s+(-c|<<)`) AND a registry hit pinned to the new `claude-settings` entry. Out-of-scope per current toolchain: ruby/perl/node interpreter bodies (one-line regex extension when needed). Symlink redirection remains a documented gap.

### Added
- **detection-registry.json**: `claude-settings` entry (`kind=path, target=raw`, pattern `\.claude/settings(\.local)?\.json`) — first `path/raw` entry. Single source of truth for the settings-path shape, reusable by future settings-aware hooks.

### Changed
- **tests** (`test_lesson_db.py`): converted the `db` fixture to class-scoped (`db_shared`) for the data-only test classes (`TestProjects`, `TestTags`, `TestLessons`, `TestTagLesson`, `TestMetadata`, `TestFTS`, `TestConstraints`), with a per-test `_wipe_db` cleanup that clears `lessons`/`tags`/`projects`/`metadata` (FTS + `lesson_tags` follow via triggers/cascade). `TestInitDb`, `TestCmdGet`, and `TestLifecycleCommands` keep the function-scoped `db` because they exercise fresh init / re-open by path. Pytest standalone wall ~7s → ~3s (40 tests). Closes `tests-perf-review`.
- **tests/CLAUDE.md**: added a "Perf Baseline" section with current numbers and drift signals; corrected stale test counts (`test_lesson_db.py` 28 → 40; aggregate "36 Python tests" → "Python tests").

## [2.72.2] - 2026-04-27 - Read allowlist catalog + `Glob`/`Grep` syntax fix in settings templates

### Changed
- **settings template** (base + raiz): fixed `Glob(**)` → `Glob(/**)` and `Grep(**)` → `Grep(/**)`. Bare `**` is not a documented permission-rule shape; `/**` is the project-relative form used by `Read(/**)` and `Edit(/...)`. Likely silently mis-matched (cwd-relative rather than project-relative) when Claude ran from a subdirectory.
- **settings template** (base + raiz): added explicit Read-tool allowlist for out-of-project paths Claude routinely opens — user-global Claude config (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`), session transcripts (`~/.claude/projects/**/*.jsonl`), auto-memory entries (`~/.claude/projects/**/memory/**`), user-global agents/skills (`~/.claude/agents/**`, `~/.claude/skills/**`), and `/tmp/**` for test fixtures. Replaces the previous pattern of letting these accumulate ad-hoc in per-user `settings.local.json`.
- **settings template** (base only): also adds `Read(~/claude-analytics/**)` for the hook-log JSONL stream. Raiz doesn't ship the analytics hooks, so the rule is omitted there.

### Notes
- **Tilde syntax verified empirically**: `Read(~/path)` rules are honored by the permission engine (positive + negative control 2026-04-27). See `output/claude-toolkit/analysis/20260427_0852__analyze-idea__read-permission-tighten.md` for the full survey, including the related finding that `env` block values do **not** expand `~` or `$HOME` (relevant to env-var-audit).
- **Sqlite databases excluded**: `.db` files are accessed via `sqlite3` through Bash, not the Read tool — already covered by `Bash(sqlite3:*)`.
- **Closes**: P3 `read-permission-tighten`.

## [2.72.1] - 2026-04-27 - CLI quick reference in base `CLAUDE.md.template`

### Added
- **template**: `dist/base/templates/CLAUDE.md.template` — new "CLI Quick Reference" subsection under `## Toolkit` lists `claude-toolkit` subcommands (`backlog`, `lessons`, `send`, `docs`, `eval`, `sync`, `validate`) with one-line descriptions and a pointer to `claude-toolkit <cmd> --help`. Closes P1 `claudemd-template-cli-quickref` — new projects now learn the day-to-day CLI surface from the synced template instead of stumbling onto `--help`.

### Notes
- **Raiz**: not affected. Raiz consumers don't ship the `claude-toolkit` CLI (no `cli/` or `bin/` entries in `dist/raiz/MANIFEST`), so the raiz template is unchanged. Sidecar marks this version `skip: true`.
- **Coordinates with**: P2 `docs-consumer-experience` (guided introduction). This is the minimal stopgap.

## [2.72.0] - 2026-04-27 - backlog schema surface: JSON schema, `relates-to`, schema subcommand

### Added
- **schema**: `.claude/schemas/backlog/task.schema.json` — JSON Schema (draft-07) becomes the canonical source of truth for BACKLOG.md task metadata. Field names, status enum, `relates-to` kinds, and descriptions all live here. Validator and parser load from it via `cli/backlog/lib/schema.sh` (jq-backed).
- **cli**: `claude-toolkit backlog schema` — new subcommand renders the metadata vocabulary from the schema (fields, descriptions, status values, `relates-to` kinds). Surfaces what was previously hidden inside bash variables.
- **cli**: `claude-toolkit backlog relates-to <kind>` — filter by relationship kind. Kinds: `depends-on`, `independent-of`, `supersedes`, `split-from`, `relates-to`.
- **cli**: `claude-toolkit backlog source <pattern>` — filter by `source` field (substring match).
- **cli**: `claude-toolkit docs backlog-schema` — registers the workflow doc as a contract so agents can fetch it via the standard `docs` surface.
- **schema**: New fields `relates-to` (multi-value, replaces `depends-on`), `source` (provenance), `references` (pointers to read while working).

### Changed
- **schema (breaking)**: `depends-on` field removed in favor of `relates-to: \`<id>:<kind>\``. Validator emits a migration warning if it sees the old field name; downstream BACKLOG.md files must migrate.
- **schema (breaking)**: minimal-format BACKLOG entries (no `[CATEGORY]` tag) are no longer valid. Standard format with `[CATEGORY]` tags is now the only supported format.
- **format**: multi-value fields (`scope`, `relates-to`, `references`) use **per-value** backticks: `` `a`, `b` `` (canonical), not `` `a, b` `` (legacy). Legacy form still parses with a transition warning.
- **template**: `dist/base/templates/BACKLOG-standard.md` renamed to `dist/base/templates/BACKLOG.md.template`. `dist/base/templates/BACKLOG-minimal.md` deleted.
- **parser**: `parse_backlog` tab-separated emit grew from 10 to 12 columns. Column 8 changed semantics (now `relates-to`, was `depends-on`); columns 11–12 added (`source`, `references`). Filters and display updated in lockstep.
- **doc**: `.claude/docs/relevant-workflow-backlog.md` rewritten — minimal-format section dropped; per-value backticks rule documented; `relates-to` kinds and `source` conventions explained.

### Fixed
- **validator**: typo'd field names (e.g. `**depends on**:` with a space, which the old `[a-z-]+` regex silently dropped) now produce errors with a "did you mean" hint. The original BACKLOG.md had **14** silently-dropped lines that broke `claude-toolkit backlog blocked`/`unblocked` filters; this branch makes such drift loud.
- **filter**: `claude-toolkit backlog source <pattern>` switched from regex to fixed-string matching — the old form broke when patterns contained `/` (the awk regex delimiter).
- **schema-loader**: `bsl_split_multivalue` no longer expands glob metacharacters — paths in `references` like `output/*.md` are kept as literal tokens. (Latent today; would have surfaced the first time anyone wrote a glob in `references`.)

### Notes
- **Migration**: this repo's own `BACKLOG.md` was migrated as part of the branch (commit `c2656a2`). 14 typo'd `**depends on**: none` entries removed; 3 valid `**depends on**: \`<id>\`` entries rewritten to `**relates-to**: \`<id>:depends-on\``; 2 legacy single-pair `scope` lines converted to per-value backticks.
- **Closes**: P1 `backlog-schema-surface`. New P3 `backlog-query-eval-refactor` filed for a follow-up (refactor `cli/backlog/query.sh` filters off `eval`).
- **Test coverage**: 86 tests (was 43). New sections cover schema subcommand, `relates-to` filter + edge cases (single value, trailing comma, invalid kind, missing kind/id), `source` filter, legacy `depends-on` warning, typo detection, legacy vs canonical scope formatting.
- **Raiz consumers**: not affected (no raiz-shipped resources were touched). Sidecar marks this version `skip: true`.

## [2.71.0] - 2026-04-27 - bare env vars renamed under `CLAUDE_TOOLKIT_*` namespace

### Changed
- **settings**: Five bare-name env vars moved under the `CLAUDE_TOOLKIT_*` namespace to avoid collisions with consumer-project namespaces. Hard cutover, no back-compat alias — consumers must update `.claude/settings.json` `env` block (and any shell / `.envrc` overrides) on sync.
  - `PROTECTED_BRANCHES` → `CLAUDE_TOOLKIT_PROTECTED_BRANCHES` (read by `git-safety.sh`, `session-start.sh`)
  - `HOOK_PERF` → `CLAUDE_TOOLKIT_HOOK_PERF` (read by `hook-utils.sh`; the stderr wire-format marker is still the literal `HOOK_PERF` — only the env var name changed)
  - `JSON_SIZE_THRESHOLD_KB` → `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB` (read by `suggest-read-json.sh`)
  - `CLAUDE_DETECTION_REGISTRY` → `CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY` (read by `detection-registry.sh`, `validate-detection-registry.sh`)
  - `CLAUDE_DIR` → `CLAUDE_TOOLKIT_CLAUDE_DIR` (read by `bin/claude-toolkit` and 7 toolkit-internal scripts)
- **docs**: `.claude/docs/relevant-toolkit-env_vars.md` §3 collapsed — former §3.3 (bare-name vars) and rename candidates from former §3.4 folded into §3.1 under the unified `CLAUDE_TOOLKIT_*` table. Sections 3.5–3.7 renumbered to 3.4–3.6. §4 "Removed" gains a v2.71.0 rename entry. §5 naming-conventions table updated — bare names are now categorically discouraged with no historical exceptions.
- **docs**: `docs/getting-started.md` "Customization" tunables, `docs/indexes/HOOKS.md` config sections, `.claude/docs/relevant-toolkit-hooks_config.md` troubleshooting tip, `.claude/docs/relevant-toolkit-lessons.md` protected-branch gate, and `tests/CLAUDE.md` perf instructions all updated to the new names.
- **settings**: Both `dist/base/templates/settings.template.json` and `dist/raiz/templates/settings.template.json` `_env_config` blocks updated to declare all five renamed vars (plus existing `CLAUDE_DOCS_DIR`).

### Notes
- **Migration**: Consumers running `claude-toolkit sync` after upgrading must rename any `PROTECTED_BRANCHES` (or other four) entries in their `.claude/settings.json` `env` block. Hooks reading the old name will fall back to defaults silently — `git-safety.sh` reverts to `^(main|master)$`, `suggest-read-json.sh` to 50 KB, etc. No errors, just default behavior.
- **Closes**: P0 `env-var-rename-bare-namespaces`. The `official-docs-index` cross-check on `CLAUDE_DIR` was deemed unnecessary — the toolkit-side audit found zero platform usage, and a hard cutover with the new name as the only reader makes any platform-side override a no-op even if one exists (the platform would set `CLAUDE_DIR`, not `CLAUDE_TOOLKIT_CLAUDE_DIR`).

## [2.70.0] - 2026-04-26 - centralized env-var registry doc + dead-var cleanup

### Added
- **docs**: New `.claude/docs/relevant-toolkit-env_vars.md` — single source of truth for every env var the toolkit reads. Grouped by namespace (`CLAUDE_TOOLKIT_*`, `CLAUDE_ANALYTICS_*`, bare names, toolkit internals, standard/external, CI-only, test harness) with default / scope / readers columns and a "where to set each var" rule (`settings.json` vs `settings.local.json` vs shell). Replaces the partial registry that lived in `relevant-toolkit-hooks_config.md` §3. Shipped to raiz consumers via `dist/raiz/MANIFEST`; also reaches base consumers via the default-include rule. Closes the env-var-audit half of backlog `env-var-audit` (P2); the rename half is split into a follow-up task `env-var-rename-bare-namespaces`.
- **docs**: `docs/getting-started.md` "Customization" subsection expanded into a full "Environment variables" section covering the consumer-facing minimum: must-set analytics paths (Phase 1.6), ecosystem opt-ins (Phase 1.5), and tunable thresholds/regexes. Points at the registry for the full reference.
- **skills**: `setup-toolkit` Phase 1.6 ("Analytics Paths") now captures four paths instead of three — adds `CLAUDE_ANALYTICS_SESSIONS_DB` (read by `session-start.sh:167` and `cli/lessons/db.py:41` for session-start context). Detection, prompts, confirm-before-writing block, and `jq` apply step all updated.

### Changed
- **docs**: `.claude/docs/relevant-toolkit-hooks_config.md` §3 collapsed to a one-paragraph pointer at the new env-vars registry. Hook trigger configuration (the actual hook-specific content) stays put.
- **docs**: `docs/indexes/DOCS.md` adds the new env_vars row; `dist/CLAUDE.md` raiz doc count 4 → 5.

### Removed
- **settings**: `CLAUDE_MEMORIES_DIR` removed from `.claude/settings.json` `_env_config`, `dist/base/templates/settings.template.json`, and `dist/raiz/templates/settings.template.json`. Audit confirmed zero code readers across the toolkit and sibling repos (claude-sessions, claude-meta) — pure documentation ghost. Anyone who set it in their `settings.json` `env` block can drop the entry.

### Fixed
- **tests**: `tests/perf-detection-registry.sh` orphan comment referencing `CLAUDE_ANALYTICS_RUN_TAG` removed. The var was never implemented (toolkit nor claude-sessions); the comment described intended behavior that didn't ship.

### Notes
- **docs**: New `dist/raiz/CLAUDE.md` consolidates raiz-sidecar authoring rules in one place — schema, two-step skip check (path filter via MANIFEST + behavioral judgment for feature-gated cases like lessons), `kind` selection table, HTML-override conditions, and two worked examples (skip-only 2.68.3, cross-cutting 2.65.0). Root `CLAUDE.md` replaces the two long sidecar bullets (and the `When You're Done` raiz-preview bullet) with pointers to the new doc. Doc is workshop-internal — not in `dist/raiz/MANIFEST`, doesn't sync to consumers. Backlog `raiz-sidecar-instructions` (P2) closed.
- **ci**: `publish-raiz.yml` Telegram steps (`Build Telegram message`, `Notify Telegram`) now gate on `steps.sync.outputs.pushed == 'true'`. Previously they ran unconditionally, so any push that triggered the workflow (e.g. a `dist/**` change that didn't alter the built raiz output) sent a `<i>no raiz-relevant changes</i>` message even when the sync-to-target step correctly no-op'd. Symptom: the `dist/raiz/CLAUDE.md` doc commit (workshop-internal, not in MANIFEST) sent a Telegram notification with an empty body. If false-positive workflow runs continue after this gate, narrow `paths:` next.

## [2.69.3] - 2026-04-26 - anti-rampage coverage rationale documented in `relevant-toolkit-hooks.md`

### Docs
- **docs**: New §12 "Anti-Rampage Coverage for Security-Boundary Tests" in `.claude/docs/relevant-toolkit-hooks.md` codifies the workaround-tree coverage requirement that the Read/Bash/Grep cross-coverage in `tests/hooks/test-secrets-guard.sh`, `test-block-credential-exfil.sh`, and `test-auto-mode-shared-steps.sh` is enforcing. Pin each `{tool, target, verb}` triplet an agent could reach for as a workaround; the regex may collapse them, the tests must not. Worked example: the `.env` Read/Bash/Grep matrix. Cites `09a886a`/`be97214`/`4b0674d`/`b924e8c` as the development-history evidence — every "extend hook to cover X via Bash" commit was a fix-forward after an agent (typically auto-mode wrap-up) had walked the workaround tree successfully. Without this section, the next audit (human or agent) hits the "this looks redundant" reflex, repeats the git archaeology, reaches the same conclusion, and a future "test simplification" PR could silently strip the coverage. New row in §10 anti-patterns points at §12. Closes P0 `hooks-anti-rampage-coverage-rationale`. Unblocks P3 `tests-perf-review` (now safe to scope without re-deriving the rationale).

### Notes
- **backlog**: Triaged two claude-sessions suggestions-box issues into P1 tasks. `backlog-schema-surface` (CLI/docs) — backlog metadata vocabulary lives only as a bash variable in `backlog-validate.sh`; not surfaced via `claude-toolkit backlog --help` or `claude-toolkit docs`, and there is no positive-relationship field (`independent-of`, `supersedes`, `split-from`) so independence assertions get folded into `notes` prose where they are not queryable. Suggested deliverables: `claude-toolkit backlog schema` subcommand, relationship fields in the schema/validator/parser, doc reachable via `claude-toolkit docs`. `claudemd-template-cli-quickref` (docs) — synced `CLAUDE.md.template` mentions `claude-toolkit` only for paths and `sync --force`; new projects don't discover the day-to-day CLI surface (`backlog`, `lessons`, `send`, `docs`, `eval`) until they read `--help` by accident. Suggested: minimal "Toolkit CLI quick reference" subsection with one-liners + pointer to `--help`. Coordinates with P2 `docs-consumer-experience` (broader guided-introduction work). Both issue files deleted after triage.

## [2.69.2] - 2026-04-26 - consumer `make claude-toolkit-validate` passes — schemas ship + orphan detection covers scripts/schemas

### Fixed
- **cli**: `bin/claude-toolkit sync` now ships `.claude/schemas/` to base consumers. The walker hardcoded five categories (`skills agents hooks docs scripts`) and silently skipped everything else, so the detection-registry schema never reached consumers regardless of `dist/base/EXCLUDE`. `validate-detection-registry.sh` ships in base (via the default-everything-not-excluded rule) but failed at runtime with `schema file missing: .claude/schemas/hooks/detection-registry.schema.json` — exiting `make claude-toolkit-validate` non-zero on every base consumer's first post-sync interaction. Adding `schemas` to the walker, to `categorize_file`, and to the category iteration arrays (display, dry-run, interactive selection, file-collection loop) makes the schema flow through the same pipeline as every other category. Closes P1 `consumer-validate-paths`. Repro: `cd <consumer> && claude-toolkit sync --force && make claude-toolkit-validate`.
- **scripts**: `setup-toolkit-diagnose.sh` Check 8 (cleanup) now scans `.claude/scripts/` and `.claude/schemas/` recursively for files not listed in MANIFEST. Pre-fix coverage was four categories (skills/agents/hooks/docs), so a script removed from MANIFEST after a previous sync (e.g. `validate-dist-manifests.sh` once 25e1d8d added it to `dist/base/EXCLUDE`) lingered indefinitely on disk in already-synced consumers without ever surfacing as an `ORPHAN`. Honors `.claude-toolkit-ignore`. New `MANIFEST_SCRIPTS` and `MANIFEST_SCHEMAS` arrays loaded alongside the existing four; the cleanup logic mirrors the per-category pattern used for skills/agents/hooks/docs but uses recursive `find` since both trees have nested directories (`scripts/lib/`, `scripts/cron/`, `schemas/hooks/`).

### Tests
- New `tests/test-sync-then-validate.sh` end-to-end test (8 cases). Syncs the real toolkit into a fresh fixture (no mocks), bootstraps `settings.json` from the synced template, then runs `validate-all.sh`, the individual validators it dispatches, `setup-toolkit-diagnose.sh`, and a stale-script orphan-detection scenario. Catches the original `consumer-validate-paths` failure shape and any future drift between sync output and validator path assumptions pre-release. Auto-discovered by `tests/run-all.sh` (no runner edit needed). Indexed in `tests/CLAUDE.md`.
- `tests/test-setup-toolkit-diagnose.sh` raiz fixture MANIFEST extended with `setup-toolkit-diagnose.sh` (raiz does ship it; the fixture was incomplete and surfaced once the new orphan check started covering `scripts/`).

### Docs
- `dist/raiz/MANIFEST` gains an inline comment next to the detection-registry `.json`/`.sh` entries documenting that the schema and `validate-detection-registry.sh` are intentionally omitted from raiz: registry edits are rare in raiz consumers, and `validate-all.sh` / `make claude-toolkit-validate` aren't part of the raiz Makefile template, so the validator would have no driver. Prevents a future "this looks asymmetric" reflex from reverting the decision without context.

## [2.69.1] - 2026-04-26 - SessionStart payload trimmed under the 10 KiB inline cap

### Fixed
- **hooks**: `session-start.sh` payload trimmed below the ~10 KiB inline cap introduced in Claude Code 2.1.119. When the cap fires, the harness persists full hook stdout to a sidecar file and replaces it with a `<persisted-output>` envelope showing only the first ~2KB — the mandatory acknowledgment line at the tail silently never reaches the model. New `ESSENTIAL_FULL_INJECT` array (default: `essential-preferences-communication_style`) lists essentials that must inject verbatim (tone/voice — Quick Reference loses the prose). All other `essential-*.md` docs now surface as their `## 1. Quick Reference` block + a "Full doc: …" path nudge for Read-on-demand. Section names in `hook_logs` unchanged (`essential:<name>`); §1-only entries get a `(Quick Reference)` suffix in the rendered header to make the distinction visible in transcripts. `ESSENTIAL_COUNT` semantics preserved. Total payload drops from ~11.1KB to ~5.6KB on a typical session (claude-toolkit, no branch lessons), leaving headroom for branch lessons and the manage-lessons nudge.

### Added
- **hooks**: New `hook_extract_quick_reference FILE_PATH` primitive in `lib/hook-utils.sh`. Emits the `## 1. Quick Reference` block (heading included) up to the next `---` rule or top-level `## <digit>` heading. Empty output (no stderr noise) when the file is missing or the block is absent — caller decides fallback. Awk over sed for clearer range semantics and to match the `surface-lessons.sh` convention. Will be reused by the deferred `surface-docs-hook` (P2) for the same §1-surfacing pattern on `relevant-*` docs.

### Notes
- **backlog**: Closed `session-start-output-too-large` (P1) — fixed in this release. Filed P3 `suggestions-box-satellite-convention` to re-evaluate `suggestions-box/` as a satellite-project convention plus a `claude-toolkit send --to <project>` flag, after the cap-fix wrap-up exposed that satellites don't have an inbox today (had to `mkdir -p` the destination ad-hoc when sending observations to claude-sessions).

## [2.69.0] - 2026-04-26 - block .claude/settings*.json writes — close the disableAllHooks kill switch

### Added
- **hooks**: `block-config-edits.sh` now covers `.claude/settings.json` and `.claude/settings.local.json` — closes the documented one-line hook kill switch (`{"disableAllHooks": true}` in `.claude/settings.local.json` "completely disables all hooks and custom status lines" per https://code.claude.com/docs/en/settings.md) and the `settings.local.json` precedence override of `permissions.ask`. Mode-aware: under `permission_mode=auto` writes are hard-blocked (auto-mode's classifier guards against destructive/exfiltration patterns, not scope drift — exactly the rampage shape the existing assertions did not cover); under `default`/`acceptEdits`/`plan` the hook emits `permissionDecision: ask` so the user confirms (settings have legitimate edit flows — the user accepts project-local exceptions in `settings.local.json` regularly). Pattern matches `auto-mode-shared-steps`' treatment. Bash branch always blocks (no ask path mid-command — the user can re-run the command themselves). Path detection runs against `_strip_inert_content` output (same convention as `secrets-guard` and the registry's `path/stripped` target) so a settings basename appearing inside a heredoc or single-quoted JSON arg does not false-positive. Header documents two known unprotected vectors as gaps: symlink redirection (deferred until seen in the wild) and interpreter-bodied writes (filed as `block-settings-edits-interpreter-bodies` P3 backlog follow-up).
- **hooks**: New `hook_ask` helper in `lib/hook-utils.sh` emits `{"hookSpecificOutput": {... "permissionDecision": "ask", ...}}`. Mirrors `hook_approve`'s escaping. Sets `OUTCOME="asked"`. First user is the settings-edit ask path; available to any future hook needing the same routing.

### Changed
- **settings**: `.claude/settings.json` `permissions.allow` adds `Edit(/BACKLOG.md)` and `Edit(/CHANGELOG.md)` — both files are tracked, recoverable, and edited routinely by `/wrap-up` and `/learn`. Confirmed via official docs that the leading `/` is project-root, not filesystem-root, so `dist/base/templates/settings.template.json` propagates the same two rules — consumers without these files get harmless no-op rules, and template parity stays clean. Backlog `read-permission-tighten` (P3) tracks the broader follow-up: change `Read(/**)` → `Read(**)` and add an explicit allowlist for legitimate out-of-project paths once those are surveyed.

### Tests
- `tests/hooks/test-block-config.sh`: 26 new assertions (35 total, was 9). Full Write/Edit × {default, acceptEdits, plan, auto} × {settings.json, settings.local.json} matrix; all five Bash write verbs (>>, tee, sed -i, mv, single >); absolute-path variants; negatives (output/x.json, settings.template.json, .claude/skills/...); three Bash read-only negatives (cat/jq/grep on settings.json) confirming the Bash branch only blocks writes — inspecting settings remains free.
- `tests/lib/test-helpers.sh`: New `expect_ask` helper parallels `expect_block`/`expect_approve`, asserts on `permissionDecision: ask` in stdout.

### Notes
- **backlog**: Filed two P0 tasks from the test-suite audit conversation. `block-settings-edits` (this release) extends `block-config-edits.sh` and is now closed. `hooks-anti-rampage-coverage-rationale` (still P0) codifies the workaround-tree coverage requirement in `relevant-toolkit-hooks.md` before perf-review tempts trimming what looks like regex redundancy. Filed P3 `test-suggest-json-boundary` for size-threshold off-by-one coverage and P3 `block-settings-edits-interpreter-bodies` for the `python -c`/`node -e` workaround vector. Rescoped existing P3 `tests-perf-review` from broad investigation to its actual recommendation (pytest `db` fixture-scope tightening in `tests/test_lesson_db.py:28`, ~5–7s pytest wall savings). Triaged claude-sessions suggestions-box issue 20260426_091630 into P1 `consumer-validate-paths` (`make claude-toolkit-validate` fails in every consumer repo because two validators reference toolkit-source-only paths). Demoted six speculative P3 tasks to P99 (`lessons-demote-cli`, `hooks-detection-registry-per-project`, `surface-lessons-fold`, `surface-docs-hook`, `review-security-worthyness`, `rename-claude-docs-to-conventions`); kept `official-docs-index` at P3. Extended scope-definitions table with `docs` and `cli`.

## [2.68.4] - 2026-04-26 - Key tier reframe lands in skills + new execution conventions doc

### Added
- **docs**: New `essential-conventions-execution.md` (loaded at session-start by the existing `essential-*.md` glob, indexed in `docs/indexes/DOCS.md`). Hosts shell/git command hygiene rules previously orphaned in lessons.db: no sudo (provide commands for the user); relative paths from project root, no `cd` / no absolute; no `git -c` unless explicitly asked (almost always a bypass smell); no hook/safety bypasses (`--no-verify`, `--no-gpg-sign`); push tags via explicit `git push origin main v<version>` (never `--tags`); tag the merge commit on main after `--no-ff` merge, not the feature-branch bump commit; authorization is per-request, not session-wide.

### Changed
- **skills**: `/manage-lessons` realigned with the v2.68.3 Key-tier reframe. The promote prompt copy at `manage-lessons/SKILL.md:86` ("eligible for surfacing") is replaced with the crystallization-candidate framing. New §4.5 **Key Promotion Contract**: every Key promotion picks a path — crystallize into `.claude/docs/essential-*.md`, fix the underlying problem, or demote (SQL workaround documented). Crystallization Guide signal table gains a row for stale Key candidates (7+ days without a decision). Anti-Patterns table replaces "Promoting everything" with "Promoting without a crystallization plan → Key tier becomes a graveyard."
- **skills**: `/learn` Process section gains a short capture-time note: promotion to Key is a deliberate `/manage-lessons` decision, Key is a holding state, not a "more important" tier. Don't promote during capture.
- **skills**: `/review-plan` "Always required" final-step rule flipped from "Run `/wrap-up`" to "Hand off to user." `/wrap-up` is now framed as a *post-implementation user action*, not part of the implementing agent's plan. New **Auto-Wrap-Up** anti-pattern (High severity) catches plans that instruct the agent to run `/wrap-up`, `make tag`, `git merge`, or `git push`, or describe wrap-up actions inline. Wrap-up, merge, tag, and push are user actions. The previous Inlined Wrap-Up (Medium) row is folded in — same blast radius post-Branch 2.
- **docs**: `essential-preferences-communication_style.md` extended with new §2 subsections (load-bearing framing pulled to the top): **Epistemic Honesty** (no "you're absolutely right", don't mirror user claims, say "I don't know" explicitly), **Pushback = re-investigation signal** (re-read entire function before defending; partial reads of long code lead to false confidence), **Concise Answers** (direct questions get direct answers, no headers when a paragraph works), **Read Before Asking** (read available context — files, conversation, docs — instead of asking; not a license to run speculative commands). Section ordering revised: Code-First → Epistemic Honesty → Pushback → Concise → Read → Test Your Work. "Verification-Focused" renamed to "Test Your Work" to disambiguate from Read Before Asking.
- **docs**: `docs/indexes/HOOKS.md` `session-start.sh` description corrected. Was claiming "key tier (all), recent (last 5), branch-specific" — stale since v2.68.3. Now describes branch-scoped lessons only, with cross-references to `relevant-toolkit-lessons` §4 (Key as crystallization holding state) and `surface-lessons.sh` (Recent surfaces contextually via PreToolUse).

### Lessons
- One-time sweep of all 7 active Key lessons under the new framing. Outcome: every lesson absorbed (Key tier is now empty in `~/.claude/lessons.db`). Targets — `essential-preferences-communication_style`: epistemic honesty (`agentic_20260418T1657_001`), pushback re-investigation (`bm-sop_20260116T1235_001`). `essential-conventions-execution`: push tags explicit (`claude-toolkit_20260410T2115_001`), tag merge commit on main (`claude-toolkit_20260406T1802_001`), no sudo (`bm-sop_20260318T1524_001`), relative paths (`claude-toolkit_20260210T0000_001`). `skill:wrap-up`: BACKLOG.md pre-existing changes (`aws-toolkit_20260330T0103_001`) — already covered by `/wrap-up` step 2; just recorded the absorption.

## [2.68.3] - 2026-04-26 - session-start narrowed to branch lessons + nudge

### Changed
- **hooks**: `session-start.sh` no longer surfaces Key or Recent tier lessons. Branch-scoped lessons still surface but the SQL query is skipped entirely when `CURRENT_BRANCH` matches `PROTECTED_BRANCHES` — handoff signal lives only on feature branches, never on stabilization lines. The "N lessons noted" acknowledgment suffix is dropped (it nudged performative mentions without ever exposing the lessons themselves). `/manage-lessons` nudge and migration warning are unchanged. PreToolUse `surface-lessons.sh` is untouched. Key tier survives in the schema as a holding state for crystallization candidates — relevant-toolkit-lessons.md §4 reframes it as "promote → crystallize into `.claude/docs/essential-*.md`, fix the underlying problem, or demote." Skill prompt updates for `/learn` and `/manage-lessons` plus a one-time review pass over current Key lessons are deferred to branch 2 (`lessons-key-tier-crystallization`).
- **settings**: `.claude/settings.json` env block sets `PROTECTED_BRANCHES="^(main|master)$|^release/"`. Both `git-safety.sh` (commit / EnterPlanMode block) and `session-start.sh` (branch-lesson gate) read this env var; setting it once treats `main`, `master`, and `release/*` as stabilization branches across both hooks. Hook fallback default stays `^(main|master)$` so unset environments behave the same as before.
- **docs**: `.claude/docs/relevant-toolkit-lessons.md` rewritten in §2 (integration table), §4 (Tiers — Key reframed), §7 (`session-start.sh` section — protected-branch gate documented), and §10 (lifecycle ASCII). `docs/indexes/HOOKS.md` `CLAUDE_TOOLKIT_LESSONS` row drops the "lesson count in ack" mention.

### Tests
- New `tests/hooks/test-session-start.sh`: 16 cases covering Key/Recent suppression, branch-lesson surfacing on feature branches, protected-branch gating (default + custom regex), absence of "lessons noted" suffix, and full suppression when `CLAUDE_TOOLKIT_LESSONS=0`. Registered in `tests/CLAUDE.md`.

## [2.68.2] - 2026-04-26 - lessons projects schema aligned with TEXT-keyed dimension

### Changed
- **cli**: `cli/lessons/db.py` `INIT_SQL` now declares `projects(id TEXT PRIMARY KEY)` (no surrogate `name` column) and `lessons.project_id TEXT`, matching claude-sessions v0.48.0 which retyped the canonical projects dimension to a kebab-case repo id and added the `project_paths` lookup table. Live `~/.claude/lessons.db` data was already TEXT — the change brings declarations into line with reality and with the upstream yaml. Display queries in `cmd_search` / `cmd_get` / `cmd_list` / `cmd_crystallize` drop their `JOIN projects` (the id IS the display name) and the scope-resolution and project-lookup SELECTs in `cmd_crystallize` read `lessons.project_id` directly. `get_or_create_project` renamed to `ensure_project`; `insert_lesson(project_name=)` renamed to `project_id=`.
- **cli**: `_detect_project()` resolves the canonical project_id by querying `sessions.db.project_paths` (read-only URI mode) keyed on the encoded git-root dir name. When sessions.db is present but the encoded dir isn't registered, the CLI errors with a message pointing at the indexer — falling back to basename here would create a row that disagrees with claude-sessions and accumulate drift. Falls back to git-root basename only when sessions.db is absent entirely (standalone toolkit deployment with no claude-sessions). New `CLAUDE_ANALYTICS_SESSIONS_DB` env var overrides the default `~/.claude/sessions.db` path.
- **hooks**: new `_resolve_project_id` helper in `lib/hook-utils.sh` (called from `hook_init`) replaces the previous `PROJECT="$(basename "$PWD")"`. Same sessions.db lookup as the CLI, but soft-warn semantics: when the row is missing the helper emits one stderr line and returns empty, leaving project-scoped lesson scope filters as no-match while global lessons still surface. Hooks must not crash sessions on a resolver miss. Ships to both base and raiz (hook-utils.sh and session-start.sh are in the raiz MANIFEST).
- **hooks**: `session-start.sh` and `surface-lessons.sh` SQL drops the `LEFT JOIN projects p` and rewrites scope filters from `p.name = '${SAFE_PROJECT}'` to `l.project_id = '${SAFE_PROJECT}'`.

### Tests
- `tests/test_lesson_db.py` updated for the rename: `ensure_project` import + assertions (TEXT id round-trips, idempotent insert), `project_name=` → `project_id=` across 28 call sites, two `cmd_crystallize`-mirroring SQL queries reshaped to the new join-less form.

## [2.68.1] - 2026-04-25 - setup-toolkit aligned with JSONL+DB split

### Changed
- **skills**: `/setup-toolkit` Phase 1.6 ("Analytics Paths") now captures three env vars instead of two: adds `CLAUDE_ANALYTICS_HOOKS_DIR` (write path for hook-logs JSONL, default `$HOME/claude-analytics/hook-logs`) and reframes `CLAUDE_ANALYTICS_HOOKS_DB` as read-only (owned by the claude-sessions indexer, used by `surface-lessons.sh` for intra-session dedup). Detection now triggers when any of the three keys is missing. Resolves the `setup-toolkit-hooks-jsonl-migration` follow-up flagged in 2.68.0's `Deferred` section.

### Deleted
- **backlog**: Removed `setup-toolkit-hooks-jsonl-migration` from P0 (completed).

## [2.68.0] - 2026-04-25 - hook-logs JSONL with stdin embed

### Changed
- **hooks**: hook execution telemetry now writes JSONL files under `~/claude-analytics/hook-logs/` instead of inserting rows into `~/.claude/hooks.db`. Three files: `invocations.jsonl` (one `kind: invocation` row per hook firing via the EXIT trap, plus `kind: section`/`substep` rows for grouped hooks and session-start), `surface-lessons-context.jsonl` (one `kind: context` row per surface-lessons firing), and `session-start-context.jsonl` (one `kind: session_start_context` row per SessionStart). The invocation row embeds the full hook stdin as a parsed `stdin` object (or `stdin_raw` string when stdin failed JSON parse) — the previous SQLite path persisted only extracted fields. Path overridable via the new `CLAUDE_ANALYTICS_HOOKS_DIR` env var; data lives outside `~/.claude/` to standardize on the `~/claude-analytics/` namespace shared with usage-snapshots.
- **hooks**: `surface-lessons.sh` intra-session dedup still reads `hooks.db.surface_lessons_context`, now read-only — the claude-sessions indexer projects JSONL rows into the table on a ~1min cadence. Accepted tradeoff: a lesson re-surfacing within one ingestion window in exchange for standardizing how downstream consumers ingest hook telemetry. `CLAUDE_ANALYTICS_HOOKS_DB` retained as a read-only path env var.
- **hooks**: `_hook_log_jsonl` replaces `_hook_log_db` / `_hook_flush_db` / `_sql_escape`. JSON rows are built via `jq -c -n --arg ...` (safer than the prior inline-SQL string interpolation — no escape footguns) and appended directly per call, no batching. Lazy `mkdir -p "$HOOK_LOG_DIR"` runs only when the first write fires.
- **settings**: project + base/raiz dist templates rename `CLAUDE_ANALYTICS_HOOKS_DB` → `CLAUDE_ANALYTICS_HOOKS_DIR` for the write-side path (default `$HOME/claude-analytics/hook-logs`). The DB env var is restored as a read-only override for surface-lessons dedup. `CLAUDE_TOOLKIT_TRACEABILITY` description updated to mention JSONL writes.
- **docs**: `relevant-toolkit-hooks_config.md`, `relevant-toolkit-lessons.md`, `docs/indexes/HOOKS.md`, `tests/CLAUDE.md` updated to describe the JSONL layout, per-file row schemas, sample tail command (`tail -f … | jq`), and the read+write asymmetry (toolkit writes JSONL → indexer projects to `hooks.db` → surface-lessons reads `hooks.db`).

### Fixed
- **hooks**: `surface-lessons.sh` `MATCH_COUNT` was `"0\n0"` (3 chars including embedded newline) when no lessons matched, because `grep -c . || echo "0"` ran the fallback *additionally* to grep's own `0` output. The migration's `--argjson match_count` rejected this, silently dropping the row. Switched to a clean `grep -c . | [ -z ] && 0` pattern.
- **hooks**: `kind: context` and `kind: session_start_context` rows now include `hook_name` (was missing in initial JSONL emit, surfaced as `null` downstream).

### Tests
- `tests/lib/hook-test-setup.sh` allocates a temp directory per process (`CLAUDE_ANALYTICS_HOOKS_DIR`) instead of cloning the global hooks.db schema. Exports `TEST_INVOCATIONS_JSONL` / `TEST_SURFACE_LESSONS_JSONL` / `TEST_SESSION_START_JSONL` for assertions, plus a non-existent `CLAUDE_ANALYTICS_HOOKS_DB` so other tests can't read the user's real DB.
- 6 hook tests rewritten to assert via `jq` over JSONL rather than `sqlite3` SELECTs against fixture DBs (`test-call-id`, `test-session-id`, `test-session-start-source`, `test-ecosystems-opt-in`, `test-surface-lessons-dedup`, `test-surface-lessons-two-hit`). `test-call-id` and `test-session-id` defensively `export CLAUDE_TOOLKIT_TRACEABILITY=1` so they don't depend on parent-shell env.
- `test-surface-lessons-dedup.sh` exercises the full pipeline: hook writes JSONL → test stands in for indexer (jq @tsv → INSERT into fixture hooks.db) → hook re-runs and reads DB. Asserts dedup correctness across the boundary instead of stubbing one half.
- `tests/perf-detection-registry.sh` and `tests/perf-surface-lessons.sh` (--replay mode) migrated from `sqlite3` aggregations to `jq` over the JSONL files. Per-hook p50/p95/max stats now built via sort + percentile-pick on the run-tail slice. Replay-case builder reads `surface-lessons-context.jsonl` instead of `hooks.db.surface_lessons_context`.

### Deferred
- `/setup-toolkit` skill still prompts for `CLAUDE_ANALYTICS_HOOKS_DB` and writes it into `settings.local.json`. Tracked as P0 backlog (`setup-toolkit-hooks-jsonl-migration`) — needs new `CLAUDE_ANALYTICS_HOOKS_DIR` capture, reframed `*_HOOKS_DB` prompt copy, and diagnose-script updates.

## [2.67.0] - 2026-04-25 - wrap-up hands off shared-state ops to user

### Changed
- **skills**: `/wrap-up` now stops at the merge boundary. Step 9 no longer runs `make tag` itself; step 10 outputs an explicit `## Next steps for you` handoff block with two paths (direct-merge for personal projects, PR-flow for team projects). Both paths place tagging *after* the merge commit lands on main, matching the "tag the merge commit, not the version bump" lesson. New `Self-Merge` anti-pattern row covers `git merge`, `git push`, `git push origin v<version>`, `gh pr create`, and `/draft-pr` invocations from wrap-up.
- **skills**: `/review-plan` now flags inlined wrap-up steps. New `Inlined Wrap-Up` anti-pattern row (Medium) catches plans that paraphrase finalization actions ("update changelog, bump version, commit docs") instead of invoking `/wrap-up` literally. The always-required final-steps tier now requires the literal string `/wrap-up`.
- **docs**: New "User owns shared-state ops" principle in project `CLAUDE.md` and both distribution templates (`dist/base/templates/CLAUDE.md.template`, `dist/raiz/templates/CLAUDE.md.template`). Claude does not merge to main, push, open pull requests, push tags, or invoke `/draft-pr` — branch work ends at handoff. `/draft-pr` is also user-invoked: it writes the description, the user opens the PR.

### Deleted
- **backlog**: Removed `wrap-up-skill-update` from P0 (completed).

## [2.66.1] - 2026-04-25 - secrets-guard Read/Grep registry migration

### Changed
- **hooks**: `secrets-guard.sh` Read and Grep handlers (and their `match_secrets_guard_read` / `match_secrets_guard_grep` siblings used by `grouped-read-guard`) now consume the `path` kind from the detection registry instead of the inline `BLOCKED_PATHS` array. Adding a new credential-file path is now a 1-line edit in `detection-registry.json` that covers Read, Grep, and Bash uniformly. Folded the previously-separate `_env_file_block_reason` and `_credential_path_block_reason` into a single `_path_block_reason` that walks the registry's path-kind entries and applies hook-side allowlists per id (`.example`/`.template` for `env-file`, `.pub` for `ssh-private-key`, deferred `.git/config` for the runtime credential-remote check). Verb-aware block messages stay in the hook keyed by registry id. SSH config (`~/.ssh/config`) is not in the registry; the hook keeps the explicit equality check. Closes the `hooks-secrets-guard-read-grep-registry` follow-up flagged in 2.66.0.

### Deleted
- **backlog**: Removed `hooks-secrets-guard-read-grep-registry` from P0 (completed).

## [2.66.0] - 2026-04-25 - shared hook detection registry

### Added
- **hooks**: New shared detection registry (`.claude/hooks/lib/detection-registry.json` + JSON Schema at `.claude/schemas/hooks/detection-registry.schema.json`) holds the credential / path / capability regex catalog that previously lived inline across `secrets-guard`, `block-credential-exfiltration`, and `auto-mode-shared-steps`. 22 entries across three kinds (`credential`, `path`, `capability`) and two targets (`raw`, `stripped`). Adding a new credential shape or sensitive path is now a 1-line registry edit instead of a per-hook regex change. Loader (`.claude/hooks/lib/detection-registry.sh`) builds pre-compiled bash alternation regexes per `(kind, target)` once at startup and exposes `detection_registry_match`, `detection_registry_match_kind`, plus the underlying `_REGISTRY_RE__<kind>__<target>` variables — pure-bash `=~` matches, no fork in the steady state. Validator (`validate-detection-registry.sh`) runs in `make validate` and pins id format (kebab-case), uniqueness, kind/target enums, required fields, and bash-ERE compilability for every pattern.
- **docs**: New §11 "Detection Target — Raw vs Stripped" in `.claude/docs/relevant-toolkit-hooks.md`. Documents the previously-undocumented decision every hook author was making implicitly: when matching credential/path/capability regexes against `$COMMAND`, do you match raw input (catches tokens inside double-quoted Authorization headers) or `_strip_inert_content` output (avoids false positives from token-shaped names in commit messages)? Decision matrix, worked examples, registry-backed `match_` skeleton, "when NOT to use the registry" guidance, and a scope-boundary subsection covering the secrets-guard / block-credential-exfiltration split. Triggered by the `block-credential-exfiltration` implementation cycle where a wrong-default cost a full test cycle.
- **tests**: `tests/hooks/test-detection-registry.sh` (23 assertions covering loader idempotency, bucket population, exact and kind-based match APIs, describe-on-hit side effects, re-source guard) and `tests/test-validate-detection-registry.sh` (10 assertions, synthesizes broken registries in temp dirs and asserts the validator rejects each violation type). `tests/perf-detection-registry.sh` benchmarks per-invocation `duration_ms` for the migrated hooks across a 20-command corpus, sourced from `~/.claude/hooks.db` — not part of `make test`.

### Changed
- **hooks**: `block-credential-exfiltration.sh` migrated to consume the `credential` kind (raw target) from the registry. Behavior broadened to cover Authorization-header literals (`Authorization: token|Bearer|Basic`) and credential-shaped env-var references (`$GH_TOKEN`, `${ANTHROPIC_API_KEY}`, `*_TOKEN`/`*_SECRET`/`*_API_KEY`/`*_PASSWORD`/`*_PASS` shapes) — both legitimate exfil signals even without a token-shape literal.
- **hooks**: `auto-mode-shared-steps.sh` migrated to consume the `credential/raw` kind for Authorization-header detection and the `capability/stripped` kind for the `api.github.com` host gate. The `gh pr/issue/release/repo` writes and `git push` command-shapes stay inline as auto-mode-specific policy (per §11 "When NOT to use the registry").
- **hooks**: `secrets-guard.sh` Bash branch migrated to consume the `path/stripped` kind. Read and Grep handlers consume the same registry-sourced regex via `_SECRETS_MATCH_RE`. Hook-specific policy stays inline: per-tool block reasons, `.example`/`.template` allowlist, `.git/config` credential-remote check, `normalize_path`, env-listing capabilities (`env`, `printenv`, `env|grep` on credential keywords, `printenv VAR` on credential-shaped names).
- **hooks**: Deduplicated the `echo $CREDENTIAL_VAR` detection that previously fired in both `secrets-guard` and `block-credential-exfiltration`. The exfil hook owns it now (registry entry `credential-env-var-name`, target=raw). Documented scope boundary in §11: same direction (keep credentials out of context), different responsibility field — exfil owns "credential value/reference inside a command", secrets-guard owns "command reaches towards a sensitive resource". Accepted false positive: literal `$VAR_NAME` mentions inside single-quoted strings (e.g. `echo 'use $GH_TOKEN in CI'`) now block, since target=raw is required to catch the canonical exfil shape `echo "$GH_TOKEN"` (the strip helper would blank double-quoted content).
- **scripts**: `validate-detection-registry.sh` now uses base64 transport for pattern/message extraction (jq's `@tsv` mangles backslashes, breaking patterns like `\$\{?...`). The pattern-compile check now correctly fails on malformed regexes — the previous `|| true` swallowed the failure unconditionally. Adds `CLAUDE_DETECTION_REGISTRY` env override matching the loader, used by tests to point the validator at fixture registries.

### Performance
- A/B benchmark via `tests/perf-detection-registry.sh` against `d70a8e4` (last commit pre-Phase-1) shows the migration is a pure performance win — every migrated hook got faster, not slower:
    - `secrets-guard`: p95 207ms → 75ms (−132ms)
    - `block-credential-exfiltration`: p95 152ms → 69ms (−83ms)
    - `auto-mode-shared-steps`: p95 154ms → 82ms (−72ms)
- The improvement comes from the loader's pre-compiled alternation regexes per `(kind, target)`: each `match_` becomes a single bash `=~` against a pre-built variable instead of multiple independent regex passes. Reproduce: `bash tests/perf-detection-registry.sh -t migrated > /tmp/migrated.txt`, `git checkout d70a8e4`, `bash /tmp/perf-detection-registry.sh -t baseline > /tmp/baseline.txt`, `git checkout -`, `diff /tmp/baseline.txt /tmp/migrated.txt` (full procedure documented in the script header).

### Deleted
- **backlog**: Removed `hooks-detection-target-convention` from P0 (completed — shipped as the registry foundation, §11 docs convention, and three hook migrations).

### Notes
- Two follow-ups remain in BACKLOG and are intentional: `hooks-secrets-guard-read-grep-registry` (P0 — secrets-guard Read/Grep handlers still hold inline `BLOCKED_PATHS` array; v1 only migrated the Bash branch) and `hooks-detection-registry-per-project` (P3 — layered project-local override file, deferred until v1 ships and we have signal on which downstream projects need custom patterns).

## [2.65.1] - 2026-04-25 - validate-dist-manifests excluded from consumer syncs

### Fixed
- **scripts**: `validate-dist-manifests.sh` no longer ships to consumer projects. It validates `dist/raiz/MANIFEST` and `dist/base/EXCLUDE` against disk — both are workshop-source-tree artifacts absent in synced consumers, so the validator failed with `Missing: dist/raiz/MANIFEST` / `Missing: dist/base/EXCLUDE` even on healthy installs (reported by claude-sessions during `/setup-toolkit` Phase 3 against 2.64.1). Added to `dist/base/EXCLUDE` (already absent from `dist/raiz/MANIFEST`); `validate-all.sh` now guards the call with `[ -f ... ]` so the orchestrator silently skips when the validator is absent. `docs/indexes/SCRIPTS.md` moves the row to "Maintenance (workshop-only)" with `Ships: no`.

### Deleted
- **backlog**: Removed `validate-all-fails-in-consumers` from P0 (completed).

## [2.65.0] - 2026-04-25 - block-credential-exfiltration hook

### Added
- **hooks**: New `block-credential-exfiltration.sh` hook blocks commands whose arguments contain credential-shaped tokens. Sibling to `secrets-guard.sh` — that hook covers credential reads at-rest; this one covers the inverse vector (a token already in the model's context being re-used as a literal in a new outbound command, the canonical case being `curl -H "Authorization: token ghp_..."`). Detection runs against the raw command (not `_strip_inert_content`) so the token inside the quoted Authorization header matches; false positives on token-shaped fixture names in commit messages are accepted. Patterns: GitHub (`ghp_`, `github_pat_`, `gho_`/`ghu_`/`ghs_`/`ghr_`), GitLab (`glpat-`), Slack (`xox[baprs]-`), AWS (`AKIA`/`ASIA`), OpenAI (`sk-`, `sk-proj-`), Anthropic (`sk-ant-`), Stripe (`sk_live_`/`sk_test_`/`rk_live_`/`rk_test_`), Google (`AIza`). Bare-40-hex excluded (false positives on git SHAs and base64). Wired into `grouped-bash-guard.sh::CHECK_SPECS` between `auto_mode_shared_steps` and `git_safety` for informative-reason precedence. Standalone-capable via dual-mode trigger. Ships in both `base` (auto-synced via `dist/base/EXCLUDE`) and `raiz` (`dist/raiz/MANIFEST`).

### Changed
- **docs**: `.claude/docs/relevant-toolkit-hooks.md` §9 "Current Hook Set" — added `auto-mode-shared-steps` (was missing since 2.64.0) and `block-credential-exfiltration`; replaced the stale "raiz uses split config" paragraph (which referenced a phantom backlog task) with the actual contract: dispatcher probes `[ -f "$src" ] || continue` before sourcing, and raiz ships the dispatcher plus 6 of 8 guards (no `enforce-make-commands`, no `enforce-uv-run`).

### Deleted
- **backlog**: Removed `block-credential-exfiltration` from P0 (completed).

## [2.64.1] - 2026-04-25 - secrets-guard in-flight credential reads

### Changed
- **hooks**: `secrets-guard.sh` extended to cover two gaps surfaced by the 2026-04-24 incident, both in the same domain (credential source → context):
  - **Tokenised remote URLs**: blocks `git remote -v`, `git remote show <name>`, `git remote get-url <name>`, `git config --list`, `git config -l`, `git config --get remote.*.url`, and `cat`/`grep`/`Read` of `.git/config` — but only when the resolved remote URL embeds `[A-Za-z0-9._-]+:[^@/[:space:]]+@` (i.e. `user:secret@host`). Clean repos pass through unchanged. Writes (`git remote add`, `git remote set-url`) always pass — they're how the user fixes the leak. Resolution uses `git config --get-regexp '^remote\..*\.url$'` from cwd (Bash) or `git config --file <path>` (Read of `.git/config`) — never spurious blocks on non-git directories.
  - **Targeted env-var echoes**: blocks `echo $X`, `echo "${X}"`, `printenv X`, and `env|grep <token-keyword>` / `printenv|grep <token-keyword>` when `X` matches `*_TOKEN`/`*_SECRET`/`*_API_KEY`/`*_PASSWORD`/`*_PASS` shape or is a well-known literal (`GH_TOKEN`, `GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). Single-quoted token names (`'$GITHUB_TOKEN'` — no interpolation) stay allowed via `_strip_inert_content`. The double-quoted interpolation form is detected against the raw command, since the stripper would otherwise blank `"${VAR}"`.
- Both extensions apply in **all permission modes** (not auto-only). Settings.json: no new entries — existing `secrets-guard.sh` wiring covers the new surface via the same `match_`/`check_` pair plus the standalone Read branch.

### Deleted
- **backlog**: Removed `secrets-guard-in-flight` from P0 (completed).

## [2.64.0] - 2026-04-25 - auto-mode shared-steps gate

### Added
- **hooks**: New `auto-mode-shared-steps.sh` hook gates shared-state/publishing actions when `permission_mode == "auto"`. Auto-mode's classifier guards against destructive/malicious actions but not against scope drift — `git push`, `gh pr create`, `gh api`, and authenticated `curl`/`wget` get auto-approved, and `permissions.ask` does not gate under auto-mode either. The hook re-imposes a human checkpoint by blocking these actions and instructing the model to stop and report. No-op outside auto-mode (default / acceptEdits / plan). Wired into `grouped-bash-guard.sh::CHECK_SPECS` at position 2 (after `dangerous`, before `git_safety`); standalone-capable via dual-mode trigger. Surface: `git push` (any form), `gh pr/issue/release/repo` write subcommands, `gh secret/variable/workflow/auth/ssh-key` writes, `gh api` (any — even reads authenticate as the user), `curl`/`wget` to `api.github.com`, and `curl`/`wget` with `Authorization: (token|Bearer|Basic)` headers. Triggered by bm-sop session 2026-04-24 — auto-mode pushed unrequested branch, attempted PR creation, then probed PAT from `git remote -v` and curled api.github.com.
- **settings.json**: `permissions.ask` block covering the same surface as the new hook. `ask` covers interactive modes (default/acceptEdits/plan); the hook covers auto-mode. Together they form a checkpoint across all modes for `git push`, `gh` writes, `gh api`, and `curl`/`wget`.

### Changed
- **hooks**: `grouped-bash-guard.sh` now sources 7 guards (was 6); the new `auto_mode_shared_steps` check sits between `dangerous` and `git_safety`. Dispatcher parses `permission_mode` once into a global so the new hook's `match_` predicate stays O(1) per the cheapness contract in `relevant-toolkit-hooks.md` §4.

### Deleted
- **backlog**: Removed `auto-mode-together-steps` from P0 (completed — shipped as `auto-mode-shared-steps.sh`).

### Notes
- Renamed task `secrets-guard-in-flight` (P0) to scope it tightly: tokenised remote URLs + targeted secret-env-var echoes only. The separate token-shape-in-command-arguments work was split into a new P0 task `block-credential-exfiltration`.
- Added P3 task `official-docs-index` — curated index of official Anthropic/Claude Code documentation references to reduce reverse-engineering.

## [2.63.16] - 2026-04-24 - manifest paths from project root

### Changed
- **dist**: `dist/raiz/MANIFEST` and `dist/base/EXCLUDE` now use project-root-relative paths throughout (`.claude/skills/foo/`, `.claude/docs/bar.md`, `docs/getting-started.md`). Previously most entries were `.claude/`-relative while `docs/getting-started.md` was project-root-relative, forcing every parser to special-case the fallback. The new convention: the path in MANIFEST/EXCLUDE is exactly where the file lives in the toolkit repo and where it ships in the consumer project. Only exception is `.claude/templates/*` — source lives under `dist/<profile>/templates/` but ships to `.claude/templates/`.
- **scripts**: Collapsed the `docs/*` fallback + `.claude/`-prepending branches in `publish.py` (`resolve_source_file`/`resolve_source_dir`), `validate-dist-manifests.sh` (`resolve_manifest_entry`), `validate-resources-indexed.sh`, `setup-toolkit-diagnose.sh`, `verify-resource-deps.sh`, and `bin/claude-toolkit` (`categorize_file`/`target_path`/`resolve_syncable_files`). The consumer MANIFEST generated by `claude-toolkit sync` now emits project-root-relative entries too.
- **templates**: `dist/base/templates/claude-toolkit-ignore.template` switched to project-root-relative examples. Users have one mental model for all path lists (MANIFEST, EXCLUDE, `.claude-toolkit-ignore`) — patterns can be copied between them.
- **docs**: `dist/CLAUDE.md` documents the new convention under Resource Selection.

### Deleted
- **backlog**: Removed `manifest-paths-from-project-root` from P0 (completed).

### Notes
- Behavior change for consumers with hand-maintained `.claude-toolkit-ignore` files: old-style entries (`skills/foo/`, `hooks/bar.sh`) will silently stop matching after upgrading, since the walker now emits `.claude/`-prefixed paths. Users should prefix their existing entries with `.claude/`. New syncs copy the updated template, which makes the convention visible.
- Unblocks `rename-claude-docs-to-conventions` (P3) — that task rewrites the same MANIFEST/EXCLUDE lines but with a different token (`docs` → `conventions`), so rebasing is mechanical.

## [2.63.15] - 2026-04-24 - scripts index accuracy + structure visibility

### Changed
- **scripts**: `validate-resources-indexed.sh` now recurses into `.claude/scripts/` subdirectories when scanning disk (was `-maxdepth 1`), so indexed subdir entries like `lib/profile.sh` and `cron/backup-lessons-db.sh` validate correctly. MANIFEST mode was already subdir-aware; this aligns local mode with it.
- **docs**: `docs/indexes/SCRIPTS.md` reframed as workshop-internal tooling (not a product catalog), renamed the `Synced` column to `Ships` with `base`/`raiz`/`no` values (replacing the boolean that conflated base vs raiz), and added Libraries (`lib/profile.sh`) and Maintenance (`cron/backup-lessons-db.sh`) sections for full coverage.

### Fixed
- **docs**: `docs/indexes/SCRIPTS.md` corrected `validate-dist-manifests.sh` and `verify-external-deps.sh` rows — both ship to base (not excluded in `dist/base/EXCLUDE`), previous `Synced: no` was wrong.

### Updated
- **docs**: `CLAUDE.md` Structure diagram now lists `.claude/scripts/` alongside skills/agents/hooks/docs/memories, pointing at `SCRIPTS.md` for the ships/doesn't-ship split.

### Deleted
- **backlog**: Removed `shipped-scripts-first-class` task from BACKLOG.md (completed — scope was an index/visibility audit, not a parallel ecosystem).

### Added
- **backlog**: P0 `manifest-paths-from-project-root` — standardize `dist/raiz/MANIFEST` and `dist/base/EXCLUDE` on project-root-relative paths to drop the `.claude/`-stripping logic scattered across sync/publish/validators.

### Notes
- Scripts stay workshop-internal tooling, not product. Audit confirmed ~10 small bash utilities (validators, diagnostic, statusline, profile lib) with narrow contracts — no value in a parallel `create-script`/`evaluate-script` skill pair. Index accuracy + CLAUDE.md visibility were the real gaps.

## [2.63.14] - 2026-04-24 - satellite consumer convention

### Added
- **docs**: `.claude/docs/relevant-toolkit-satellite-consumers.md` — consumer-side convention for workshop skills that call satellite contracts. Defines pointer file structure (`resources/<contract-name>.md`), invocation pattern (4-step runtime ladder), failure ladder (missing/error/malformed → fallback), and skill documentation refactor guidance. Pairs with `relevant-toolkit-satellite-contracts` (satellite maintainer view).
- **skills**: `.claude/skills/design-db/resources/schema-smith-input-spec.md` — pointer file for the schema-smith input-spec contract. Defines "Using the satellite" (fetch via `schema-smith docs input-spec`, min v1.6.0) and "No satellite" fallback (produce raw SQL DDL).

### Changed
- **skills**: `design-db` SKILL.md § Schema Smith Integration refactored to use the new satellite consumer convention. Removed inlined schema-smith invocation logic and replaced with a reference to the pointer file for invocation pattern and fallback path.

### Updated
- **indexes**: `docs/indexes/DOCS.md` now registers `relevant-toolkit-satellite-consumers` as a stable doc.

### Deleted
- **backlog**: Removed `satellite-consumer-convention` task from BACKLOG.md (completed).

### Notes
- Formalizes the consumer-side pattern. This doc + pointer file pattern becomes the standard for all new skill ↔ satellite integrations.

## [2.63.13] - 2026-04-24 - design-db: call schema-smith docs at runtime

### Changed
- **skills**: `design-db` SKILL.md now fetches the input spec at runtime via `schema-smith docs input-spec` (requires schema-smith ≥ 1.6.0) instead of carrying a local copy. Removes dependency drift — the spec is always current. If the command fails, falls back to raw SQL DDL (existing fallback behavior preserved).
- **docs**: `.claude/docs/relevant-toolkit-satellite-contracts.md` schema-smith status row updated: now shows "Yes" (has `docs` command) and "No" (no duplicated contract in workshop).

### Deleted
- **skills**: `.claude/skills/design-db/resources/schema-smith-input-spec.md` — 305-line local copy removed; runtime call is the source of truth.

### Notes
- This completes `satellite-cli-docs-convention` sub-task 3: schema-smith workshop-side removal after satellite shipped `docs input-spec` (schema-smith v1.6.0).

## [2.63.12] - 2026-04-24 - backlog CLI resolves from CWD

### Fixed
- **cli**: `claude-toolkit backlog` and `claude-toolkit backlog validate` now resolve `BACKLOG.md` from the current working directory only. The script-relative fallback (which preferred the toolkit's own `BACKLOG.md` over the caller's) is gone — invoking the tool from a consumer project correctly surfaces that project's backlog. `--path FILE` remains the override. `make backlog` in the workshop is unaffected (make runs from the repo root).

### Notes
- Backlog (non-version-bumping, folded from `[Unreleased]`):
    - Added `## P0 - Critical` and `## P1 - High` empty headers to `BACKLOG.md` so `claude-toolkit backlog validate` stops flagging missing required headings.
    - Added `rename-claude-docs-to-conventions` (P3) — rename `.claude/docs/` to `.claude/conventions/` to disambiguate agent-loaded conventions from user-facing `docs/`. "rules" avoided because it collides with Claude Code's native rules concept.
    - Added `shipped-scripts-first-class` (P3) — scripts under `.claude/scripts/` ship via sync but lack an index, evaluation treatment, and CLAUDE.md structure coverage. Audit + index + conventions pass, coordinates with the backup-lessons-db.sh move to claude-sessions.
    - Added `satellite-consumer-convention` (P2) — companion to `satellite-cli-docs-convention`. Defines the skill side of satellite contract consumption: `resources/<contract>.md` pointer layout, versioning source-of-truth (contract-embedded), hard-coded contract discovery, failure ladder (missing/error/malformed → fallback with user-visible report for malformed), fallback path choice (reduced-quality vs. refuse). Unblocks `design-db` as first concrete consumer; schema-smith's satellite side already shipped `docs` + `version` (v1.6.0).
- Distribution: the CLI scripts live at `cli/backlog/` and are driven by `bin/claude-toolkit`; neither path is in any sync manifest, so raiz and base consumers are unaffected at sync time.

## [2.63.11] - 2026-04-24 - claude-toolkit docs command (dogfood satellite contracts convention)

### Added
- **cli**: New `claude-toolkit docs` base command, living at `cli/docs/query.sh` and dispatched from `bin/claude-toolkit`. Bare `claude-toolkit docs` lists available contracts; `claude-toolkit docs <name>` emits the contract markdown to stdout (UTF-8, exit 0, read-only). Unknown contract names exit 1 with the available-names list on stderr. First contract: `satellite-contracts` → `.claude/docs/relevant-toolkit-satellite-contracts.md`. This is the workshop dogfooding its own convention: satellites that need to read the contracts doc can now fetch it at runtime via `claude-toolkit docs satellite-contracts` instead of carrying a copy.
- **backlog**: `satellite-cli-docs-convention` (P2) sub-task 2 (CLI discoverability) closed out. Sub-task 3 (schema-smith workshop-side removal after satellite ships `schema-smith docs input-spec`) still open, now unblocked on the workshop side — schema-smith has a concrete `claude-toolkit docs` reference to mirror.

### Changed
- **docs**: `.claude/docs/relevant-toolkit-satellite-contracts.md` §6 Current State gains a `claude-toolkit` row (workshop dogfooding). Closing note explicitly points satellite maintainers at the new command as the reference implementation.
- **cli**: `cli/CLAUDE.md` structure block and "How Subcommands Are Wired" updated for the new `docs/` subdirectory.
- **tests**: New `tests/test-docs-query.sh` (10 assertions) — list contracts, emit known contract to stdout, unknown contract → non-zero + stderr name list, `--help` surfaces usage. Registered in `tests/CLAUDE.md` file map. Picked up by `run-all.sh` automatically.

### Notes
- Distribution: the CLI script lives at `cli/docs/query.sh` and is driven by `bin/claude-toolkit`; neither is in any sync manifest, so raiz and base consumers are unaffected at sync time. Consumers that have the `claude-toolkit` binary installed get the new command automatically.
- Scope: deliberately narrow — only `satellite-contracts` is exposed. Internal docs (`code_style`, `resource_naming`, etc.) are agent-facing context, not stable cross-project contracts, and stay out of `docs`.

## [2.63.10] - 2026-04-24 - satellite CLI contracts convention

### Added
- **docs**: `.claude/docs/relevant-toolkit-satellite-contracts.md` — advisory convention for satellite maintainers whose CLIs pair with workshop skills (schema-smith ↔ `/design-db`, aws-toolkit ↔ `/design-aws`, claude-sessions ↔ workshop hooks). Recommends exposing agent-facing contracts via a `<satellite> docs <contract>` base command so workshop skills can fetch the contract at runtime instead of carrying drifting copies (current example: `.claude/skills/design-db/resources/schema-smith-input-spec.md`). Covers command form, wire contract (stdout / markdown / exit 0 / read-only / UTF-8), content shape, versioning, and when not to adopt.
- **backlog**: `satellite-cli-docs-convention` (P2) sub-task 1 marked done; sub-tasks 2 (CLI discoverability) and 3 (schema-smith workshop-side removal after satellite ships `docs input-spec`) remain open.

### Notes
- Distribution routing: doc ships to **base** automatically (not in `dist/base/EXCLUDE`). Does **not** ship to raiz (not added to `dist/raiz/MANIFEST`) — raiz consumers are not satellite maintainers.

## [2.63.9] - 2026-04-24 - artifacts doc: save vs inline convention

### Changed
- **docs**: `.claude/docs/relevant-toolkit-artifacts.md` gains a new §4 "Save vs Inline" documenting the deliberate split between file-saving skills (`analyze-idea`, `refactor`, `shape-proposal`, `review-plan`, `brainstorm-feature`) and inline-findings skills (`review-security`, `list-docs`, `read-json`, `snap-back`). Half-life framing: security findings age poorly, saved artifacts should be worth reviewing later or by someone else, knowledge skills are inline by default. "When It Doesn't Apply" and "Gotchas" renumbered §5/§6.
- **docs**: `.claude/docs/relevant-toolkit-context.md` See-also now points to `relevant-toolkit-artifacts` for skill output shape.

## [2.63.8] - 2026-04-24 - backlog: hide P99 by default in `make backlog`

### Changed
- **cli**: `cli/backlog/query.sh` gains `--exclude-priority <csv>` (e.g. `P99` or `P99,P3`). Applied as a pre-filter, so it composes with every subcommand (`summary`, `priority`, `status`, `scope`, `blocked`/`unblocked`, `branch`, `id`) — not just the default list view.
- **makefile**: `make backlog` now passes `--exclude-priority P99`, so nice-to-haves stay out of the everyday view. Bare `claude-toolkit backlog` (or `bash cli/backlog/query.sh`) still shows everything; `claude-toolkit backlog priority P99` still works for the explicit view.
- **dist/base**: `dist/base/templates/Makefile.claude-toolkit` now ships a `backlog` target with the same default, so base-dist consumers inherit the behavior via `claude-toolkit backlog --exclude-priority P99`.
- **docs**: `.claude/docs/relevant-workflow-backlog.md` documents the flag and the Makefile default.

### Added
- **tests**: `tests/test-backlog-query.sh` — new `test_exclude_priority` block (single exclude, comma list, lowercase, composition with `priority` subcommand, missing-value error). Fixture grew a `## P99 - Nice to Have` row with `status: deferred` so the flag has something to hide without perturbing existing status/unblocked counts.

### Notes
- Raiz is unaffected: the raiz distribution does not ship the `claude-toolkit` CLI, so the new Make default only applies to base-dist consumers.

## [2.63.7] - 2026-04-24 - surface-lessons 2+ keyword-hit threshold

### Changed
- **hooks**: `surface-lessons.sh` matching now requires **2+ distinct context-word hits against the same tag's keywords** for a lesson to surface. Previously a single substring hit (e.g. `reset` alone against the `git` tag) was enough, which fired the same 3-lesson combo on underspecified triggers. Replaced the flat `OR` across keyword `LIKE`s with a CTE whose `HAVING` sums per-word `CASE` terms per tag. Per-tag, not cross-tag: a lesson carrying tag A (1 hit) + tag B (1 hit) does not qualify.
- **hooks**: Dropped the plural-strip `CASE` term. Substring `LIKE` already matches plural→singular (keywords `hook` hits context `hooks`); the reverse case was rare, and the extra term became a double-count footgun under arithmetic matching.
- **settings**: Flipped `CLAUDE_TOOLKIT_LESSONS` from `0` to `1` in `.claude/settings.json` — lessons injection now enabled by default in this repo. Safe to flip now that the filter is tight enough to avoid the noise that kept it off.

### Added
- **tests**: `tests/hooks/test-surface-lessons-two-hit.sh` — four assertions: single-hit suppressed, two-hit same-tag surfaces, hits split across two tags suppressed (validates per-tag semantics), plural single-hit suppressed.
- **tests**: Extended `tests/hooks/test-surface-lessons-dedup.sh` fixture — added `head` to the `git-hazard` seed keywords so the existing `git rebase -i HEAD~3` test command continues to 2-hit under the new rule.

### Notes
- Behavior risk: a legitimately unambiguous single keyword (e.g. a future tag whose only keyword is very specific) won't surface under the new rule. Mitigation is tag-side curation — split such a keyword into two synonymous entries so a matching command still hits twice. Lower maintenance cost than a per-tag min-hits override.
- Stacking with v2.63.5 (narrowed git keywords) and v2.63.6 (intra-session dedup): single-hit coincidental matches should stop surfacing, and the hazard commands that still hit 2 (e.g. `git reset --amend`, `git push --force`) surface exactly once per session.
- Workshop-internal: `surface-lessons.sh` is not in `dist/raiz/MANIFEST`, so raiz consumers are unaffected.

## [2.63.6] - 2026-04-24 - surface-lessons intra-session dedup

### Changed
- **hooks**: `surface-lessons.sh` now dedupes by `session_id`. A lesson already surfaced earlier in the session is excluded from further matches until the session ends. Implementation is a pre-query against `surface_lessons_context` (existing log table — no schema change) plus a `NOT IN` splice on the main SELECT. Graceful fallback: if `hooks.db` is missing or `SESSION_ID='unknown'`, the filter is omitted and behavior matches prior versions.

### Added
- **tests**: `tests/hooks/test-surface-lessons-dedup.sh` — three-case coverage (first surface, second surface excluded, fresh session not deduped).

### Notes
- Combined with v2.63.5's keyword narrowing, a single session that does trip a git-hazard keyword now surfaces its matches once rather than on every subsequent tool call. The `matched_lesson_ids` log column remains honest: each row records what was surfaced *that* invocation (post-dedup).

## [2.63.5] - 2026-04-24 - narrow git tag keywords to hazard scenarios

### Changed
- **lessons**: `DOMAIN_TAG_KEYWORDS['git']` in `cli/lessons/db.py` narrowed from `git,commit,merge,rebase,branch,push,pull,checkout` to `rebase,cherry-pick,force-push,reset,--force,--no-verify,--amend`. The old list substring-matched every `git status`/`git diff`/`git log` via the PreToolUse `surface-lessons.sh` filter, firing the same 3-lesson combo on 76% of tool invocations (2,730 / 3,590 over 14 days). The new list only matches genuine git-hazard scenarios. Affects (a) new `lessons add` auto-inference via `_infer_domain_tags` and (b) fresh-install tag seeding in `cmd_migrate`.

### Notes
- Existing users need a one-shot DB update to see the effect on their current `git` tag row (the code change only affects new seeds / new `lessons add` calls): `sqlite3 ~/.claude/lessons.db "UPDATE tags SET keywords='rebase,cherry-pick,force-push,reset,--force,--no-verify,--amend' WHERE name='git';"`
- Tradeoff: lessons containing generic `commit`/`merge`/`branch` wording no longer auto-tag as `git`. Explicit `--tags git` on `lessons add` still works.

## [2.63.4] - 2026-04-23 - manage-lessons CLI routing

### Added
- **cli**: Two new `claude-toolkit lessons` subcommands — `promote --id <ID>` (sets `tier='key'`, `promoted=today`) and `deactivate --id <ID>` (clears `active`, auto-refreshes tag counts). Both reuse `update_lesson()` and exit 1 on missing id.
- **docs**: New `cli/lessons/CLAUDE.md` — lifecycle reference grouped by stage (capture / inspect / cluster-merge / promote-retire / maintain), with DB-path override and pointers to the skill, ecosystem doc, and parent CLI. The `lessons --help` description now points readers at this doc.

### Changed
- **skills**: `manage-lessons` routes every lifecycle op through the CLI. Dropped `Bash(sqlite3:*)` from `allowed-tools` and the `compatibility: sqlite3` frontmatter key; removed inline `sqlite3 UPDATE/DELETE` snippets. Per-lesson decision menu is now `promote / absorb / deactivate / skip` — delete is intentionally not exposed (real deletions happen outside the skill surface).
- **tests**: New `TestLifecycleCommands` class in `tests/test_lesson_db.py` (4 tests) covers both commands on success and missing-id paths; deactivate test observes the 2→1 tag-count decrement (not a spurious 1→0 edge).

### Fixed
- **lessons**: Deactivating a lesson via the skill now refreshes `tags.lesson_count`. The prior inline `sqlite3 UPDATE ... SET active=0` path silently skipped the count refresh; the new CLI route goes through `update_lesson()` which calls `_refresh_tag_counts` when `active` changes.

## [2.63.3] - 2026-04-23 - rewrite raiz changelog formatter in Python with JSON sidecars

### Changed
- **ci**: `.github/scripts/format-raiz-changelog.sh` rewritten as `format-raiz-changelog.py` (stdlib only). The new formatter reads structured `dist/raiz/changelog/<version>.json` sidecars instead of parsing free-form CHANGELOG markdown and keyword-matching the MANIFEST. Same CLI surface (`<version|latest> [--raw|--html] [--out] [--from] [--override]`) and identical Telegram output shape; no workflow API change beyond the `.sh → .py` swap at the call site. Root cause for the swap: the bash script's ~30 nested `$(echo | …)` command substitutions flaked under scheduling pressure (~2% in isolated runs).
- **tests**: `tests/test-raiz-changelog.sh` replaced with `tests/test_format_raiz_changelog.py` (pytest, 48 tests across 8 suites — sidecar loading, single/range rendering, HTML escaping, overrides, output modes, edge cases). Covers the assertion matrix of the bash suite.
- **workflow**: `.github/workflows/publish-raiz.yml` call site updated to invoke the Python script.

### Notes
- On each version bump the raiz sidecar is now authored by hand (CLAUDE.md §Changelog documents the obligation). Workshop-internal bumps that genuinely have nothing to announce can set `skip: true` and get a minimal Telegram message. Pre-existing `.html` auto-overrides at `dist/raiz/changelog/<version>.html` still take precedence in `--html` mode.
- This release's sidecar (`2.63.3.json`) is itself a dogfooding example — announces the formatter rewrite to the raiz channel.

## [2.63.2] - 2026-04-23 - reframe MANIFEST-mode project-local resource reports

### Changed
- **scripts**: `validate-resources-indexed.sh` no longer emits yellow "Extra file not in MANIFEST" warnings for disk resources outside MANIFEST. Reframed as neutral blue "Project-local (not toolkit-owned): …" info lines, with a matching summary count. MANIFEST is a toolkit-ownership whitelist, not a disk allowlist — base projects carry their own skills/agents/hooks/docs and should not be warned about them.
- **scripts**: `validate-resources-indexed.sh` now also honors `.claude-toolkit-ignore` in MANIFEST mode. Paths matching ignore patterns (same directory-trailing-slash / exact-file logic as `setup-toolkit-diagnose.sh` and `bin/claude-toolkit`) are suppressed entirely. Opt-in silence for known project-local paths; unknown extras still surface as info.
- **scripts**: MANIFEST-mode detection for skills/agents/hooks/docs/scripts now runs whenever the resource directory exists (previously gated behind the index file also existing — which is false in base projects, so the branch was effectively dead). Toolkit-mode behavior unchanged.
- **scripts**: `verify-resource-deps.sh` cross-MANIFEST reference reports retoned the same way — yellow "not in MANIFEST, skipped" → blue "not in MANIFEST, scope-skipped", counter renamed to `SCOPED_REFS`, summary wording updated.

### Notes
- Exit codes unchanged (still 0 for both conditions); this is output retone only.
- Both scripts ship in `dist/raiz/MANIFEST` — raiz consumers receive the updated output on the next publish.

## [2.63.1] - 2026-04-23 - dist-manifest existence validator

### Added
- **scripts**: New `.claude/scripts/validate-dist-manifests.sh` — checks every entry in `dist/raiz/MANIFEST` and `dist/base/EXCLUDE` resolves to a real path on disk. Resolution mirrors `.github/scripts/publish.py` (`docs/*` → `.claude/docs/` with repo-root fallback, `templates/*` → `dist/base/templates/`, otherwise `.claude/`). Trailing-slash entries checked as dirs, others as files. Catches rename/delete drift on every `make check` instead of only at CI publish time.
- **scripts**: Wired into `.claude/scripts/validate-all.sh` as a sixth stanza.

## [2.63.0] - 2026-04-23 - profile marker for .claude/MANIFEST + detect_profile helper

### Added
- **dist**: Auto-generated `.claude/MANIFEST` now carries a `# profile: base|raiz` marker on its first non-blank line — base sync emits it from `bin/claude-toolkit`, and raiz publish (`.github/scripts/publish.py`) now ships a MANIFEST at all (previously omitted) with `# profile: raiz` prepended and the source documentary header stripped. Source `dist/raiz/MANIFEST` unchanged.
- **scripts**: New shared library `.claude/scripts/lib/profile.sh` exposing `detect_profile()` → `toolkit | base | raiz | unknown`. Precedence: toolkit (presence of `docs/indexes/SKILLS.md`) wins over MANIFEST marker, marker wins over absence, `unknown` returns last. Idempotent source guard mirrors `.claude/hooks/lib/hook-utils.sh`. Added to `dist/raiz/MANIFEST` so it reaches raiz consumers.
- **tests**: New `tests/test-profile-lib.sh` (10 cases covering all four outcomes, 5-line scan window, positional/env/pwd overrides, `##` rejection). `tests/test-raiz-publish.sh` now asserts MANIFEST presence + marker + lib; `tests/test-cli.sh` asserts base marker.
- **docs**: `.claude/docs/relevant-toolkit-context.md` §7 documents `detect_profile`. `dist/CLAUDE.md` notes the profile-marker convention under resource selection.

### Notes
- No existing caller is migrated in this release — `setup-toolkit-diagnose.sh`, `verify-resource-deps.sh`, `validate-resources-indexed.sh`, and `validate-settings-template.sh` still use directory-presence checks. Follow-up tasks adopt the lib.
- Raiz consumer repos receive the new file automatically on the next `publish-raiz.yml` run (workflow does `rm -rf target-repo/.claude && cp -r dist-output/raiz/.claude …`).

## [2.62.0] - 2026-04-23 - centralized env-var surface for analytics DBs + powerline pin

### Added
- **skills**: `setup-toolkit` gains Phase 1.6 — "Analytics DB Paths." Consumer projects are prompted once for the lessons/hooks DB paths (defaults offered: `$HOME/.claude/lessons.db`, `$HOME/.claude/hooks.db`); resolved paths are written to `.claude/settings.local.json` `env` block. Runs for all consumer projects (no profile gating). Skipped when either key already exists. The anti-pattern "never edit settings.local.json" carves out this specific exception — per-user resolved paths belong in the gitignored local file, not the shared one.

### Changed
- **settings**: Added `CLAUDE_TOOLKIT_POWERLINE_VERSION` (scoped to the toolkit) to the `env` block of `.claude/settings.json` and both dist templates (`dist/base/templates/settings.template.json`, `dist/raiz/templates/settings.template.json`). `_env_config` documentation block expanded to cover every env var the hooks/scripts actually read — previously only 4 of them were documented.
- **hooks**: `HOOK_LOG_DB` env var renamed to `CLAUDE_ANALYTICS_HOOKS_DB` (no back-compat alias — `lib/hook-utils.sh`, `tests/lib/hook-test-setup.sh`, `tests/hooks/test-ecosystems-opt-in.sh`, `tests/CLAUDE.md`). The internal bash variable name `HOOK_LOG_DB` inside `lib/hook-utils.sh` is unchanged; only the externally-set env var name changed.
- **hooks**: `session-start.sh` and `surface-lessons.sh` now read the lessons DB path from `CLAUDE_ANALYTICS_LESSONS_DB` (falling back to `$HOME/.claude/lessons.db`) — previously hardcoded.
- **cli**: `cli/lessons/db.py` reads `LESSONS_DB_PATH` from `CLAUDE_ANALYTICS_LESSONS_DB` with the same fallback.
- **scripts**: `.claude/scripts/statusline-capture.sh` now reads the pinned `@owloops/claude-powerline` npm version from `CLAUDE_TOOLKIT_POWERLINE_VERSION` (fallback: `1.25.1`).
- **docs**: `.claude/docs/relevant-toolkit-hooks_config.md` env-var tables updated with the new variables; `cli/CLAUDE.md` notes the `CLAUDE_ANALYTICS_LESSONS_DB` override.

### Notes
- Path-valued analytics vars (`CLAUDE_ANALYTICS_LESSONS_DB`, `CLAUDE_ANALYTICS_HOOKS_DB`) are intentionally **not declared in `.claude/settings.json`** because Claude Code passes JSON `env` values through literally — `"$HOME/..."` is not expanded. The natural override surface for these is `.claude/settings.local.json`, written by `setup-toolkit` Phase 1.6 with fully-resolved paths. Scripts fall back to `$HOME/.claude/*.db` when the vars are unset.
- `CLAUDE_TOOLKIT_POWERLINE_VERSION` is scoped to the toolkit (not `CLAUDE_ANALYTICS_*`) because the powerline statusline is a toolkit-specific integration, not a cross-project analytics surface.
- `backup-lessons-db.sh` still lives in `.claude/scripts/cron/` — it's a candidate to move to claude-sessions (schema ownership) but that move is deferred.

## [2.61.7] - 2026-04-23 - raiz MANIFEST: include artifacts convention doc

### Changed
- **raiz**: Added `docs/relevant-toolkit-artifacts.md` to `dist/raiz/MANIFEST` (missed in 2.61.6). 11 of 17 raiz-included resources declare `output/claude-toolkit/` paths, and two (`draft-pr`, `review-plan`) now explicitly reference the new doc. `dist/CLAUDE.md` doc count updated from 3 → 4.
- **base**: Updated stale path in `dist/base/EXCLUDE` — `docs/relevant-conventions-naming.md` → `docs/relevant-toolkit-resource_naming.md` (followup to the 2.61.6 rename; without this the excluded doc would have started syncing to base projects).

## [2.61.6] - 2026-04-23 - rename naming doc + add artifacts convention doc

### Changed
- **docs**: Renamed `.claude/docs/relevant-conventions-naming.md` → `relevant-toolkit-resource_naming.md` to align with the `relevant-toolkit-*` family (parallels `relevant-toolkit-resource_frontmatter.md`). Updated the 4 referencing skills (`create-hook`, `create-skill`, `create-agent`, `create-docs`) and `docs/indexes/DOCS.md`.
- **skills**: `draft-pr` output path tightened — was `{timestamp}_{branch-name}` (date-only, no source segment), now `{YYYYMMDD}_{HHMM}__draft-pr__{branch-name}`. `review-plan` output path tightened — was `{timestamp}__review_plan__{plan-name}` (underscore source, unspecified timestamp), now `{YYYYMMDD}_{HHMM}__review-plan__{plan-name}`; also corrected the `date` format hint from `+%Y%m%d_%H%M%S` (seconds) to `+%Y%m%d_%H%M` to match the standard.

### Added
- **docs**: New `.claude/docs/relevant-toolkit-artifacts.md` documents the output-artifact filename convention (`output/claude-toolkit/<category>/{YYYYMMDD}_{HHMM}__<source>__<slug>.md`). Covers components, rationale, exceptions (`shape-project`, `evaluate-*`, `build-communication-style`), and gotchas. Audit of all declared `Save to:` paths found 12 files already on-pattern and the two above drifting — both now fixed and anchored to the new doc.
- **docs**: `relevant-toolkit-resource_naming.md` now lists Docs in the resource-pattern table (pointing at `relevant-toolkit-context` for the full `{essential\|relevant}-{context}-{name}` spec). `CLAUDE.md` Changelog rule tightened to name "shipped docs in `.claude/docs/` or `docs/`" explicitly as resource changes requiring a version bump — removes the previous ambiguity with "docs-only changes."

## [2.61.5] - 2026-04-23 - v3 C3: document opus rationale in evaluate-* skills

### Changed
- **skills**: Added opus-model rationale note to the Invocation block of all 4 evaluate-* skills (`evaluate-skill`, `evaluate-agent`, `evaluate-hook`, `evaluate-docs`) plus an inline comment next to `model: "opus"`. The choice is judgment-heavy rubric scoring, not checklist execution — future readers shouldn't mistake it for an unreviewed default and downgrade without revisiting.

## [2.61.4] - 2026-04-23 - v3 C1: read-json knowledge reshape + raiz MANIFEST sync

### Changed
- **skills**: `read-json` reshaped from user-invocable command to knowledge reference (`type: knowledge`, `user-invocable: false`). Stripped redundant sections (categorical rule, progressive inspection, file-size table, anti-patterns) — modern sessions already default to jq for JSON. Kept the load-bearing content: shell-quoting traps (`--arg`/`--argjson`) and malformed-JSON recipes (BOM, JSONL, trailing commas, truncated, embedded). `suggest-read-json` hook's block-reason now points at the skill path instead of the `/read-json` command. User-facing references updated across `README.md`, `docs/getting-started.md`, `docs/indexes/SKILLS.md`, `docs/indexes/HOOKS.md`, `.claude/docs/relevant-toolkit-hooks_config.md`, and the `grouped-read-guard` dispatcher comment.
- **raiz**: Dist MANIFEST synced to reflect brainstorm rename (`brainstorm` → `brainstorm-feature`) and `write-documentation` addition (12 skills total). `dist/CLAUDE.md` skill list updated.

## [2.61.3] - 2026-04-21 - skill path references + adaptive thinking gating

### Changed
- **skills**: Updated 3 path references across `analyze-idea`, `create-agent`, and `review-plan` to align with workshop literal paths (output/claude-toolkit/...).
- **settings**: Disabled adaptive thinking in base distribution template and toolkit repo settings — reduces API cost and latency overhead for deterministic operations.
- **skills**: `write-handoff` updated (audit v3 B4); `create-hook` refactored (audit v3 B4).
- **skills**: Increased line limits in `create-skill` skill for longer skill source files.

## [2.61.2] - 2026-04-21 - v3 A2: brainstorm pair rename + audit completion

### Changed
- **skills**: Renamed `/brainstorm-idea` → `/brainstorm-feature` (software design skill — more specific purpose). Renamed `/brainstorm` → `/brainstorm-idea` (general-purpose skill — name freed up by above). Updated all cross-references across 6 related skills (`analyze-idea`, `build-communication-style`, `refactor`, `review-plan`, `shape-project`, `shape-proposal`), 2 index files (`docs/indexes/SKILLS.md`, `docs/indexes/AGENTS.md`), 2 docs (`docs/getting-started.md`, `README.md`). Fixed `/brainstorm-idea` output path from generic `output/{project}/design/` to specific `output/claude-toolkit/brainstorm/` — consistent with workshop's literal paths. Coordinated single-commit rename resolves naming confusion (brainstorm-idea was the software design skill; now brainstorm-feature is clearer) and output-path drift.

### Notes
- **v3 audit complete (stages 1–5, execution ongoing).** Full exhaustive audit of all repo directories against the resource-workshop canon. Stage 1: identity rewrite (orchestrator → resource workshop) across `relevant-project-identity.md`, `CLAUDE.md`, `README.md`, `docs/getting-started.md`, `suggestions-box/CLAUDE.md`. Stages 2–5: per-directory findings in `planning/v3-audit/` (one file per directory); consolidated skills decisions in `planning/v3-audit/stage2-decisions.md`. Execution tasks spawned to backlog at P2 (`v3-b*`, `v3-c*`) and P3 (`v3-e*`, plus `manage-lessons-cli-routing`, `review-security-worthyness`, `surface-docs-hook`, `satellite-cli-docs-convention`). A1 and A2 execution tasks completed.

## [2.61.1] - 2026-04-21 - session_start_context row for claude-sessions projector

### Added
- **hooks**: `session-start.sh` now persists a structured `session_start_context` row (source, git_branch, main_branch, cwd) into `hooks.db` on each firing. New helper `hook_log_session_start_context` in `lib/hook-utils.sh` — sibling of `hook_log_context`, uses the same batched `_hook_log_db` flush path (zero extra sqlite3 invocations). Consumed by the claude-sessions projector to seed `state_changes` baselines instead of emitting `from_value=NULL` on first-observation rows. Table DDL ships in claude-sessions (mirrors the `surface_lessons_context` sibling pattern). Gated by `CLAUDE_TOOLKIT_TRACEABILITY=1`; no-op when disabled or when the table isn't present. Tests: `test-session-start-source.sh` extended with `session_start_context` assertions that skip cleanly if the table hasn't been created yet. Suggestion originated upstream from claude-sessions.

## [2.61.0] - 2026-04-20 - Ecosystems opt-in (lessons + traceability)

### Changed
- **hooks, toolkit**: Lessons and traceability ecosystems are now opt-in per project. Two env vars in `settings.json` gate the behavior: `CLAUDE_TOOLKIT_LESSONS` controls session-start lesson surfacing + the `surface-lessons` injection; `CLAUDE_TOOLKIT_TRACEABILITY` controls `hooks.db` writes (timing/section logs, `surface_lessons_context`) and `usage-snapshots` capture in `statusline-capture.sh`. Both default to `"0"` in `dist/base` / `dist/raiz` templates. The toolkit repo's own `.claude/settings.json` ships with both `"1"` (dogfood). Run `/setup-toolkit` to configure — new Phase 1.5 prompts per-ecosystem and writes the env block. Pre-opt-in projects (neither key present) get a session-start nudge until they choose; the nudge self-extinguishes once either key is written.

## [2.60.4] - 2026-04-20 - Relocate backup-transcripts.sh to claude-sessions

### Removed
- **scripts**: `backup-transcripts.sh` relocated to the claude-sessions repo (`claude-sessions/cron/backup-transcripts.sh`) — the script backs up data owned by that repo's indexing pipeline, so it now lives alongside its consumers. The user's crontab has been repointed; no behavior change. See claude-sessions `0.32.1`.

## [2.60.3] - 2026-04-20 - Fix /tmp collision in setup-toolkit-diagnose

### Fixed
- **scripts**: `setup-toolkit-diagnose.sh` — concurrent invocations no longer corrupt each other's intermediate check state. Replaced shared `/tmp/ct-setup-diag-*` paths (8 distinct filenames, 18 references) with a per-invocation `mktemp -d -t ct-setup-diag.XXXXXX` directory; `EXIT` trap now `rm -rf`s the scoped dir instead of a wildcard glob. Reproduced as intermittent MISSING/EXTRA/PASS drift across Checks 1/2/3 under paired concurrent runs (6 of 8 rounds flaked before the fix). No interface change; no test change needed — the test harness already isolates each case via its own `mktemp -d`.

## [2.60.2] - 2026-04-20 - Shellcheck gate on shipped bash

### Added
- **build**: `make lint-bash` target runs `shellcheck -S warning` over shipped bash (`.claude/hooks/`, `.claude/scripts/`, `cli/backlog/`, `cli/eval/`). Wired into `make check` between `test` and `validate`. Target fails clearly with an install hint if `shellcheck` is missing. Bash-first application of the §4 verification convention that covers Python in consumer projects.

### Fixed
- **hooks**: `session-start.sh` — the essential-docs loop `for dir in "$DOCS_DIR"` (SC2066) iterated exactly once regardless of intent; collapsed to a direct glob over `"$DOCS_DIR"/essential-*.md`. No behavioral change in practice (there was only ever one dir), but the loop was misleading scaffolding.
- **hooks**: `approve-safe-commands.sh` — removed 6 dead `prev_char` assignments and its `local` declaration inside the tokenizer loop; the variable was assigned but never read (SC2034). No behavior change.
- **scripts**: `validate-resources-indexed.sh` — `case "$line" in skills/*/|skills/*/)` had a duplicate pattern (SC2221/2222); collapsed to a single branch. Also switched `find ... -exec dirname {} \; | xargs` to `find ... -printf '%h\n' | xargs` for null-safety (SC2038).
- **scripts**: dead-variable cleanup across `setup-toolkit-diagnose.sh` (SCRIPT_DIR, GREEN, CURRENT_CHECK_NUM, unused `local total`), `validate-settings-template.sh` (unused `label` param + matching call-site args), `cli/backlog/validate.sh` (DIM — never referenced), `cli/eval/query.sh` (BLUE — never referenced).

### Changed
- **hooks**: `lib/hook-utils.sh` — added `# shellcheck disable=SC2034` on `INPUT="$HOOK_INPUT"` with a note that it's read by sourcing hooks/scripts (`statusline-capture.sh`, `test-validate-hook-utils.sh`). The "backward compat" intent is now explicit to shellcheck and readers.
- **hooks**: `grouped-read-guard.sh` — added `# shellcheck disable=SC2034` on `FILE_PATH=...` documenting the contract (dispatcher sets, sourced check modules read). The variable had been removed in an earlier pass of this change and broke 5 `test-grouped-read.sh` assertions; suppression with a comment is the right fix.
- **hooks**: `block-config-edits.sh`, `secrets-guard.sh` — added `# shellcheck disable=SC2088` on `[[ "$x" == "~/"* ]]` tilde-prefix matches. This is an intentional literal-tilde match (detecting a `~/`-prefixed path the user typed), not a failed tilde expansion. SC2088 is a false positive in this context.

### Notes
- Contributors now need `shellcheck` locally (`sudo apt install shellcheck` / `brew install shellcheck`). Documented in `README.md` under a new **Contributing to this repo** sub-section of Dependencies — kept separate from the consumer-facing runtime deps list so synced projects don't inherit a phantom requirement.
- Backlog: `shellcheck-shipped-bash` removed (completed). New P3 entry `diag-tmp-collision` surfaced during this work — `setup-toolkit-diagnose.sh` uses shared `/tmp/ct-setup-diag-*` paths for cross-check state, causing intermittent test flakes and a real-world multi-invocation collision risk.

## [2.60.1] - 2026-04-20 - Drop tool:/agent: prefix from hook_logs.call_id

### Fixed
- **hooks**: `lib/hook-utils.sh` now writes the bare Anthropic id into `hook_logs.call_id` (`toolu_...` for Pre/PostToolUse, `agent_id` for SubagentStop) instead of the prefix-namespaced form (`tool:<id>` / `agent:<id>`) introduced in 2.57.0. The prefix broke the documented cross-DB join `tool_calls.tool_use_id = hooks.hook_logs.call_id` (on `session_id`) shipped by claude-sessions 0.31.0. Tool-vs-agent is already derivable from `hook_event`, so the prefix was redundant. `tests/hooks/test-call-id.sh` assertion updated to match. No toolkit read path parsed the prefix.

### Changed
- **docs**: `docs/indexes/HOOKS.md` hook_logs column reference now documents `call_id` as a bare id and names the `(session_id, call_id) ↔ claude-sessions.tool_calls.tool_use_id` join.

### Notes
- claude-sessions 0.31.0 ships a one-shot backfill that strips existing `tool:` / `agent:` prefixes from `hook_logs.call_id` on first open of `hooks.db`. After this release, the backfill becomes a permanent no-op — no migration coordination required.

## [2.60.0] - 2026-04-20 - Verification flow standard (make check read-only, formatting in pre-commit)

### Added
- **docs**: `.claude/docs/essential-conventions-code_style.md` §4 Verification — defines the standard for consumer Python projects. `make check` = `make lint` (`ruff check` + `ty`, no `--fix`) + `make test` (pytest, `--tb=short -q`). Both read-only; `make check` never mutates files. Formatting lives in pre-commit (`ruff format`, whitespace hooks) and runs at `git commit`, not from `make check`. No `make format` target. Deferred-until-slow guidance for pytest markers (`unit`/`integration`/`slow` + `make test-all`) included. Rationale section calls out the reformat-on-exit-1 vs flaky-test confusion that motivated the separation.
- **docs**: Python Tooling bullet in §3 updated to mention `ty` and point at §4 for the format-vs-lint split.

### Changed
- **docs**: `CLAUDE.md` `make check` rule tightened from "never pipe through head/tail/grep" (defensive) to "verification is `make check`, invoked bare" (prescriptive), with a pointer to the new §4. This repo stays bash-first — `make check` here remains `make test + make validate` (no lint target, no Python code to lint).

### Notes
- Backlog: new P3 entry `shellcheck-shipped-bash` — lint `.claude/scripts/`, `.claude/hooks/`, and shipped `cli/**/*.sh` with shellcheck. Skip test scripts. Trigger: next bash bug that shellcheck would have caught.
- Design: `output/claude-toolkit/design/20260420_1229__brainstorm-idea__verification-flow-standard.md` (local, gitignored) captures the full problem framing (truncation, reformat confusion, slow-tests-latent).

## [2.59.4] - 2026-04-20 - Clarify /wrap-up version-bump triage and [Unreleased] fold rule

### Changed
- **skills**: `/wrap-up` step 4 now uses a 5-row decision table (Major/Minor/Patch + two explicit no-bump → `[Unreleased]` rows) instead of the previous flowchart+prose. Step 5 adds an explicit fold rule: check `[Unreleased]` before writing the new version entry, fold any existing content into the new section, then clear it. New anti-pattern row "Stale Unreleased" flags the same bug in the quick-scan table. Redundant pre-release block collapsed into a single line.

### Notes
- Docs: `BACKLOG.md` reorganized (previous cycle) — removed `tests-rethink-suite-phase3` and `skill-token-density`; demoted `agent-model-routing` and `agent-reasoning-activation` from P3 to P99; added two P1 tasks: `ecosystems-opt-in` (make lessons + traceability/logging ecosystems opt-in per project) and `revisit-wrap-up` (now partially addressed by this release — backlog item removed).
- Docs: `BACKLOG.md` — `revisit-wrap-up` removed. The stale-`[Unreleased]` symptom and bump-triage ambiguity were the core pain points and are addressed inline. Broader decomposition concerns (`/bump-version` split, hook-enforced ordering, edge-case extraction) are not yet done — reopen as a new task if they prove worth tackling.

## [2.59.3] - 2026-04-18 - Move canonical lessons schema to claude-sessions

### Changed
- **schema**: lessons schema ownership moved to claude-sessions repo — canonical `lessons.yaml` now lives at `claude-sessions/schemas/lessons.yaml` (moved in claude-sessions v0.19.0). Toolkit retains `INIT_SQL` in `cli/lessons/db.py` for runtime bootstrap (writer-owned pattern — the two must stay byte-compatible). Coordinates with the cross-repo data-model redesign. No user-facing behavior change.

### Removed
- `cli/lessons/schemas/lessons.yaml` (and the now-empty `cli/lessons/schemas/` directory).

## [2.59.2] - 2026-04-18 - Drop TSV hook-timing.log writes

### Removed
- **hooks**: TSV writes to `.claude/logs/hook-timing.log` dropped from `lib/hook-utils.sh` (`hook_log_section`, `hook_log_substep`, `_hook_log_timing`). `HOOK_LOG_FILE` global and `mkdir -p .claude/logs` removed from `hook_init`. No programmatic consumers remained — `hooks.db` is authoritative; tests no longer assert against the TSV. Human debugging: `sqlite3 ~/.claude/hooks.db`.

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
