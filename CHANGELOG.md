# Changelog

## [Unreleased]

### Added
- **backlog**: Starter pack design — shared subset for coworker onboarding (6 skills, 5 hooks, 3 agents, 2 memories, 3 templates). Design doc: `.claude/output/design/starter-pack.md`
- **backlog**: Auto-publish starter pack to separate repo via GitHub Action (`toolkit-starter-pack-publish`)
- **backlog**: Human-in-the-loop repo exploration theme (`explore-hitl-repos`)
- **exploration**: Added `itsmostafa/aws-agent-skills` to exploration queue — weekly-updated AWS service reference, potential plugin pattern
- **exploration**: Renamed exploration backlog to `BACKLOG.md` for consistency, cross-referenced from main backlog

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
