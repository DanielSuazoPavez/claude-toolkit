# Changelog

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
