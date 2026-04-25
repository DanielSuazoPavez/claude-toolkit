# Project Backlog

## Current Goal

**v3 — Resource workshop reframe complete.** All 5 stages done: identity rewrite, exhaustive code/structure audit, resource revisit (4.7 clarity pass), setup-toolkit health-check, and polish scoping. The tasks below at P2 and P3 are the direct output of the v3 audit — concrete fixes and follow-ups surfaced during the stage-2 skills walk and consolidated in `planning/v3-audit/stage2-decisions.md`. Design: `output/claude-toolkit/design/20260420_2007__brainstorm-idea__claude-toolkit-v3.md`. Distribution tailoring and lessons-ecosystem data analysis are explicitly post-v3.

**See also:** `output/claude-toolkit/exploration/BACKLOG.md` — repo exploration queue (pending reviews, theme searches).

## Scope Definitions

| Scope | Description |
|-------|-------------|
| scripts | Standalone utility scripts |
| toolkit | Core toolkit infrastructure (sync, indexes, versioning) |
| skills | User-invocable skills |
| agents | Specialized task agents |
| hooks | Automation hooks |
| tests | Automated testing and validation |

---

## P0 - Critical

- **[HOOKS]** Extend `secrets-guard.sh` to cover credential-source reads beyond files (`secrets-guard-in-flight`)
    - **scope**: `hooks`
    - **notes**: Existing `secrets-guard.sh` covers credential *files at rest* (`.env`, `~/.aws/credentials`, etc.) plus full `env`/`printenv` dumps. Bm-sop incident (2026-04-24) exposed two gaps in the same domain: (1) **tokenised remote URLs** — block `git remote -v`, `git remote show`, `git config --get remote.*.url`, direct `cat`/`grep`/`Read` of `.git/config` *when* the resolved URL contains `[A-Za-z0-9._-]+:[A-Za-z0-9_]{20,}@`. The detection runs `git config --get remote.origin.url` itself; if it embeds a credential, block with: "This repository's remote URL embeds a credential. Reading it would put a token in your context. Use `git branch --show-current` for the branch, the push-output hint for PR URLs, or ask the user." (2) **Targeted env-var echoes** — current hook catches unfiltered `env`/`printenv`, misses targeted `echo $GITHUB_TOKEN`, `echo $ANTHROPIC_API_KEY`, `printenv GITHUB_TOKEN`, and `env | grep -i (token|secret|key|pass)` / `printenv | grep …`. Match on `*_TOKEN`/`*_SECRET`/`*_API_KEY`/`*_PASSWORD` shaped var names. Same domain (credential source → context), just a finer surface. Both extensions apply in **all permission modes** (not auto-only) — credentials leaking into context is a problem regardless. Settings.json: no new hook entry needed (extending existing `secrets-guard.sh` already wired into `grouped-bash-guard` and Read dispatcher). Pattern lists: `output/claude-toolkit/design/20260424_2152__hook-proposal__02__shared-state-and-credential-guard-hooks.md` §3.2 (subset — only items 2 and 3; item 1 is the separate task below).
    - **depends on**: none

- **[HOOKS]** Block credential-shaped strings in command arguments (`block-credential-exfiltration`)
    - **scope**: `hooks`
    - **notes**: Sibling concern to `secrets-guard-in-flight` but different vector — a token already in context being re-used in a new command (model reads `git remote -v` output, then constructs `curl -H "Authorization: token ghp_…"`). New hook (or new check in dispatcher) matching token-shape regexes in `$COMMAND` itself: `ghp_[A-Za-z0-9]{36,}` (GitHub classic PAT), `github_pat_[A-Za-z0-9_]{60,}` (fine-grained), `gho_/ghu_/ghs_/ghr_[A-Za-z0-9]{36,}` (OAuth/user/server/refresh), `glpat-[A-Za-z0-9_-]{20,}` (GitLab), `xox[baprs]-[A-Za-z0-9-]{10,}` (Slack), `AKIA[0-9A-Z]{16}`/`ASIA[0-9A-Z]{16}` (AWS), `sk-[A-Za-z0-9]{40,}`/`sk-proj-[A-Za-z0-9_-]{40,}` (OpenAI), `sk-ant-[A-Za-z0-9_-]{40,}` (Anthropic), `pat-[a-z0-9-]{36,}` (Airtable). **Prefix-anchored only** — skip the bare-40-hex case (false positives on git SHAs and base64 fragments). Reason string: "Credential-shaped string in command arguments. Don't paste tokens you read from another command into a new command. Read what you need; let the user paste secrets if needed." Open design question: standalone hook (`block-credential-exfiltration.sh`) or extend `secrets-guard.sh` further. Lean: separate hook because the trigger is fundamentally different (credential-as-payload vs. credential-as-source), and stacking too many regex sets in one file hurts readability. Pattern list: `…__02__shared-state-and-credential-guard-hooks.md` §3.2 item 1.
    - **depends on**: none (independent of `secrets-guard-in-flight`)

## P1 - High

## P2 - Medium


## P3 - Low

- **[HOOKS]** Fold `surface-lessons.sh` into `grouped-bash-guard.sh` (`surface-lessons-fold`)
    - **scope**: `hooks`
    - **notes**: `surface-lessons.sh` currently averages ~106ms with ~30-40ms of that being bash+jq startup overhead. Fold the Bash branch into `grouped-bash-guard.sh` to skip a second process spawn; keep Read/Write/Edit path separate or extend `grouped-read-guard.sh` to cover Write|Edit. Expected ~40ms avg savings. Constraints: async-injection contract (PreToolUse additionalContext), 5s timeout, current matcher is `Bash|Read|Write|Edit` (wider than grouped-read's `Read`). P2 in `output/claude-toolkit/analysis/20260423_2309__analyze-idea__improve-lessons-lifecycle.md`; deferred to P3 now that the relevance work (v2.63.5–v2.63.7) is shipped and the noise problem is handled — this is pure perf. Re-measure avg latency first; the 106ms baseline predates dedup + 2-hit threshold and may already be lower.
    - **depends on**: none (v2.63.5–v2.63.7 shipped)

- **[HOOKS]** Remove ecosystems opt-in session-start nudge (`remove-ecosystems-opt-in-nudge`)
    - **scope**: `hooks`
    - **notes**: After `ecosystems-opt-in` ships, session-start shows a one-time nudge to projects that predate the new schema (no `CLAUDE_TOOLKIT_LESSONS` / `CLAUDE_TOOLKIT_TRACEABILITY` env keys in settings.json). The nudge is self-extinguishing per-project (setup-toolkit writes the keys → nudge stops firing), but the code itself should be deleted once all user projects have been updated. Triggered manually rather than version-based because toolkit ships faster than the user reaches each project. Signal to remove: user says "remove the opt-in nudge" or equivalent. Delete the relevant section from `.claude/hooks/session-start.sh` and any related tests.
    - **depends on**: `ecosystems-opt-in`

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Reference + satellite ready; user-postponed (no dependency blockers). Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability. When skill ships: enforce satellite-contract rule — link out to aws-toolkit docs via CLI convention (see `satellite-cli-docs-convention` task), no duplicated spec in workshop. Design doc: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`. Drafts: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection.

- **[SKILLS]** `review-security` — worthyness diagnostic (`review-security-worthyness`)
    - **scope**: `skills`
    - **notes**: Skill has never been invoked in the wild (to user's knowledge). Run invocation-frequency check (same approach as pattern-finder agents diagnostic). Based on data: (a) Keep — content already solid; (b) Sharpen — broaden description triggers and/or add surfacing-hook path; (c) Deprecate — CC's built-in /security-review may cover enough of the surface. Do alongside pattern-finder diagnostic for consistency.

- **[HOOKS]** `surface-docs.sh` hook — context-aware doc surfacing (`surface-docs-hook`)
    - **scope**: `hooks`
    - **notes**: New hook matching tool context against `relevant-*` doc Quick References and injecting a one-liner suggestion when a relevant doc hasn't been loaded. Same deterministic algorithm as `surface-lessons.sh` — intra-session dedup (v2.63.6) + 2+ keyword-hit threshold (v2.63.7). Validate by observing surface-lessons behavior for a few weeks before replicating the pattern. Coordinates with `.claude/hooks/` queue item 5.


- **[SCRIPTS]** Move `backup-lessons-db.sh` to claude-sessions (`move-backup-lessons-to-claude-sessions`)
    - **scope**: `scripts`
    - **notes**: `.claude/scripts/cron/backup-lessons-db.sh` backs up a DB whose schema is owned by claude-sessions. Flagged in `planning/v3-audit/claude-docs.md:101` as arguably belonging there. Deferred from 2.62.0 (the env-var centralization touched it but left it in place). Coordinated move: (1) drop script into claude-sessions with the same path or a parallel `scripts/cron/` location, (2) update `.claude/docs/relevant-toolkit-lessons.md:205-209` to point readers at the new location, (3) delete from toolkit, (4) add changelog entry in both repos. Anyone currently running it from a crontab needs a heads-up to update their schedule.

- **[TOOLKIT]** Rename `.claude/docs/` to `.claude/conventions/` (`rename-claude-docs-to-conventions`)
    - **scope**: `toolkit`
    - **notes**: `.claude/docs/` is overloaded — name suggests user-facing docs but contents are agent-loaded conventions/rules (`essential-*`, `relevant-*`, `codebase-explorer/`). Shared name with top-level `docs/` hides the audience split (agent context vs user-facing). "rules" conflates with Claude Code's native rules concept, so `conventions/` is the preferred name. Coordinated rename: (1) move files, (2) update session-start loader and surface-* hooks, (3) update sync paths in CLI + dist profiles (base and raiz MANIFESTs), (4) update CLAUDE.md "Structure" section, (5) update `claude-toolkit docs` command and any skill references (grep for `.claude/docs/`), (6) update downstream satellites' synced copies via next sync. Non-trivial churn — schedule when nothing else is touching those paths.

- **[DOCS]** Index of official Anthropic/Claude Code documentation references (`official-docs-index`)
    - **scope**: `docs`
    - **notes**: Create a single doc (e.g. `.claude/docs/reference-official-docs.md` or `docs/official-references.md`) collecting URLs + short summaries of Anthropic's own Claude Code docs — hooks reference (`code.claude.com/docs/en/hooks`, `/hooks-guide`), sub-agents (`/sub-agents`), skills (`/skills` — note: pitched as "custom commands", not as a first-class developer surface), plugins (`/plugins`), settings (`/settings`), agent SDK (`docs.anthropic.com/en/docs/claude-code/sdk/*`), hook-development SKILL in `anthropics/claude-code` repo (`plugins/plugin-dev/skills/hook-development/SKILL.md`). Purpose: we've been reverse-engineering a lot (the PostToolUse redaction investigation on 2026-04-24 is the canonical example — third-party tutorials misread the contract, only the official reference + empirical probe settled it), and keeping a curated index means future "is this actually supported?" questions start from authoritative sources. Also flag the gaps the toolkit fills — skill authoring beyond the /en/skills "custom commands" framing, agent design beyond the subagent contract, `.claude/docs/` conventions (no official equivalent). Related context: Anthropic's "memories" concept landed after the toolkit's `.claude/memories/` convention, causing a terminology collision — note this and the `rename-claude-docs-to-conventions` task (P3) as part of the same "upstream concepts overlapping with toolkit conventions" theme. Also mention skill-creator (seen in Claude Cowork) as the "overblown create-skill" — full UX with HTML rendering for feedback, A/B testing, multiple rounds — potential reference point when evolving `create-skill`. Not blocking; nice to have for onboarding and for settling future design debates.

## P99 - Nice to Have

- **[SKILLS]** v3 E5 — frontmatter field ordering normalization across skills (`v3-e5-frontmatter-ordering`)
    - **scope**: `skills`
    - **notes**: `build-communication-style` uses non-standard frontmatter order (`name, description, argument-hint, allowed-tools, type`); most skills use `name, type, description, ...`. The A1 sweep resolves `type:` placement but doesn't normalize broader ordering. Could be automated with a small ruff-style linter or a sed pass. Polish, not v3-blocking.

- **[SKILLS]** v3 E3 — `teardown-worktree` artifact-copy scope decision (`v3-e3-teardown-artifact-scope`)
    - **scope**: `skills`
    - **notes**: Currently copies only `output/claude-toolkit/reviews/*` from worktree to parent at teardown. Does not copy `pr-descriptions/`, `design/`, `plans/`, `sessions/`. Decide: (a) deliberate — keep per-worktree ephemera scoped, only review artifacts persist; or (b) broaden to include other `output/claude-toolkit/` subdirs a user is likely to want after teardown. No clear right answer; needs a decision before implementing.

- **[SKILLS]** Add interactive option selection to skills that ask questions (`skill-interactive-options`)
    - **scope**: `skills`
    - **notes**: AskUserQuestion supports single-select, multi-select, and preview panes — but most skills default to open-ended questions. Audit skills that use AskUserQuestion (brainstorm-idea may already use options organically) and convert categorical decision points to structured option selection where it fits. Keep free-text for creative/descriptive input.

- **[AGENTS]** Explore resource-aware model routing for agent spawning (`agent-model-routing`)
    - **scope**: `agents, skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

