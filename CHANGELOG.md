# Changelog

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
- `essential-workflow-branch_development` memory: branch-first development workflow conventions
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
- `suggest-json-reader.sh` hook: suggests /json-reader for large JSON files
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
