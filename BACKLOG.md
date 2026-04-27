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
| docs | Reference documentation, conventions, rules (`.claude/docs/` agent-facing or `docs/` user-facing) |
| cli | `claude-toolkit` CLI commands and underlying scripts |

---

## P0 - Critical

(none)

## P1 - High

- **[TOOLKIT]** macOS compatibility for shipped bash scripts (`macos-bash-compatibility`)
    - **scope**: `toolkit`
    - **references**: `output/claude-toolkit/analysis/20260427_1322__analyze-idea__macos-bash-compatibility.md`
    - **notes**: Parent task — see subtasks ~~`macos-grep-pcre`~~ (done, v2.72.5), `macos-find-printf`, `macos-bash4-policy`, `macos-mktemp-md5sum`, `macos-loud-errors`, `macos-ci-runner`, `macos-readme-platform` (ordered by descending impact-per-effort). Toolkit's bash scripts assume GNU userland + bash 4+; on macOS (BSD userland + `/bin/bash` 3.2) several validators and `setup-toolkit-diagnose.sh` produce silent-correctness bugs because errors are suppressed with `2>/dev/null` and downstream comparisons pass vacuously over empty data. Surfaced 2026-04-27 by the toolkit's biggest external consumer running `setup-toolkit-diagnose.sh` on macOS — visible symptom was `grep: invalid option -- P` noise; underlying issue is that `setup-toolkit-diagnose.sh`, `make validate`, and `make backlog` are all structurally broken on stock macOS. Analysis report (referenced above) catalogs 38 hard-break sites across 13 files in three independent classes: PCRE grep (22 hits), GNU `find -printf` (6 hits), bash 4+ features (8 hits). Success criterion: macOS consumer can run `setup-toolkit-diagnose.sh`, `make check`, and `make backlog` cleanly.

- **[TOOLKIT]** Replace `find -printf` with portable enumeration (`macos-find-printf`)
    - **scope**: `toolkit`
    - **relates-to**: `macos-bash-compatibility:depends-on`
    - **references**: `output/claude-toolkit/analysis/20260427_1322__analyze-idea__macos-bash-compatibility.md`
    - **notes**: 6 hits across 2 files. BSD `find` has no `-printf`. `.claude/scripts/validate-resources-indexed.sh:129,144,319,332` (4 hits — `DISK_SKILLS` and `DISK_SCRIPTS` come up empty on macOS, index validation never sees disk files); `.claude/scripts/setup-toolkit-diagnose.sh:518,530` (2 hits — same silent-empty pattern, errors suppressed with `2>/dev/null`). Replacement: for relative paths, `(cd "$dir" && find . -type f ...)`; for `%h\n` (parent dir), pipe through `xargs -n1 dirname`. Mechanical and small. Estimate: 1-2 hours.

- **[TOOLKIT]** Decide bash 4+ policy + apply across scripts (`macos-bash4-policy`)
    - **scope**: `toolkit`
    - **relates-to**: `macos-bash-compatibility:depends-on`
    - **references**: `output/claude-toolkit/analysis/20260427_1322__analyze-idea__macos-bash-compatibility.md`
    - **notes**: Stock macOS `/bin/bash` is 3.2 (Apple won't ship GPLv3). Affected features used in this repo: `declare -A` (6 sites in 4 files — `validate-detection-registry.sh`, `verify-external-deps.sh`, `tests/perf-session-start.sh`, `tests/perf-surface-lessons.sh`) and `${var^^}` uppercase expansion (2 sites in `cli/backlog/query.sh`, invoked by `make backlog`). 77 of 83 scripts use `#!/bin/bash`; only 6 use `#!/usr/bin/env bash`. **Decision needed first**: (a) require bash 4+ via `#!/usr/bin/env bash` everywhere + Homebrew bash dependency + a startup version check that tells macOS users to `brew install bash`, or (b) refactor the ~8 affected sites to bash 3.2 syntax (associative arrays → parallel indexed arrays or temp files; `${var^^}` → `tr '[:lower:]' '[:upper:]'`). Option (a) is what most modern dev tools do (asdf, sdkman, etc.). Option (b) keeps the dependency surface smaller but adds friction at every site that wants modern features later. Lean (a). Either way: shebang sweep across the 77 `#!/bin/bash` files. Estimate: half a day for decision + sweep, plus a documented Homebrew prerequisite if (a).

- **[TOOLKIT]** Fix `md5sum` and `mktemp --suffix` (`macos-mktemp-md5sum`)
    - **scope**: `toolkit`
    - **relates-to**: `macos-bash-compatibility:depends-on`
    - **references**: `output/claude-toolkit/analysis/20260427_1322__analyze-idea__macos-bash-compatibility.md`
    - **notes**: Smaller mechanical fixes batched together. **`md5sum`**: macOS ships `md5` (BSD) and `shasum`, not `md5sum`. Hits: `cli/eval/query.sh:44`, `tests/test-evaluation-query.sh:61`. Both suppress errors with `2>/dev/null`, so on macOS every resource gets an empty hash; every resource appears stale on `claude-toolkit eval stale`. Fix: switch to `shasum -a 256` (works on both platforms, drop the conditional) or guard with `command -v md5sum`. **`mktemp --suffix`**: BSD `mktemp` has no `--suffix`. Hits: `tests/hooks/test-grouped-read.sh:31,35,56` — test fails because `small_json`/`large_json` come up unset. Fix: `mktemp` then rename, or append `.json` to the variable. Estimate: ~1 hour.

- **[TOOLKIT]** Stop suppressing errors with `2>/dev/null` in validators (`macos-loud-errors`)
    - **scope**: `toolkit`
    - **relates-to**: `macos-bash-compatibility:relates-to`
    - **references**: `output/claude-toolkit/analysis/20260427_1322__analyze-idea__macos-bash-compatibility.md`
    - **notes**: Discipline issue uncovered by the macOS investigation, orthogonal to platform-specific fixes but causally linked to why the bugs went undetected. The macOS consumer's report framed `grep -P` errors as "cosmetic" because `setup-toolkit-diagnose.sh` kept running — it kept running because errors were silenced. Same pattern in `find -printf` and `md5sum` call sites. Audit `.claude/scripts/*.sh` and `cli/**/*.sh` for `2>/dev/null` and decide per-site whether the failure mode is genuinely expected (keep) or whether the silence is hiding a bug (remove). Heuristic: if the variable downstream of the silenced command is then compared, used in a loop, or written to a report, the silence is dangerous; if it's a "best-effort, missing-is-fine" probe (e.g. optional file), silence is correct. Estimate: 2-3 hours of careful read.

- **[TOOLKIT]** Add macOS CI runner (`macos-ci-runner`)
    - **scope**: `toolkit`, `tests`
    - **relates-to**: `macos-bash-compatibility:depends-on`
    - **notes**: Prevent regression after the fixes land. GitHub Actions provides free macOS runners. Add a `make check` job on `macos-latest` to the existing CI workflow. Catches BSD-vs-GNU divergences at PR time instead of via consumer bug reports. Order-dependent on the upstream fixes: don't enable until at least the grep/find/bash4 subtasks are done, otherwise CI is red from day one. Estimate: 1-2 hours once preconditions are met.

- **[DOCS]** Document supported platforms in README (`macos-readme-platform`)
    - **scope**: `docs`
    - **relates-to**: `macos-bash-compatibility:depends-on`
    - **notes**: Currently neither `README.md` nor `CLAUDE.md` mentions platform support. After the fixes land, document supported platforms (Linux + macOS) and any prerequisites (e.g. Homebrew bash if `macos-bash4-policy` lands as option (a)). Small, but the kind of thing that decides whether a new consumer hits a wall on day 1. Estimate: 30 min.

- **[HOOKS]** SessionStart payload cap guardrails — pre-emptive validation + reactive truncation detection (`session-start-cap-guardrails`)
    - **scope**: `hooks`
    - **notes**: Surfaced 2026-04-26 alongside the `session-start-output-too-large` fix. Two complementary guardrails to prevent recurrence and detect when projection differs from harness reality. **(a) Pre-emptive validation** — a `make validate` (or `make check`) step that runs `session-start.sh` in dry-run, sums section bytes, and warns if the projected total exceeds ~9.5KB (cap is ~10.2KB based on empirical investigation; warn before hitting it). Catches drift when someone adds a new essential doc, lesson surfacing changes shape, or a doc grows past Quick Reference. **(b) Reactive detection** — a hook (likely `UserPromptSubmit` on first prompt of a session, or `SessionStart` post-processing) that detects the truncation marker (`<persisted-output>` / `Output too large`) in the just-emitted SessionStart attachment and surfaces a loud warning to the user + a short note to the model: "session start was truncated — essential docs may not be fully loaded; consider Read'ing them explicitly." Two implementation choices for (b): (i) read the session's transcript JSONL for the marker (depends on JSONL write timing); (ii) check the just-emitted hook output for the marker before exit (cleaner, doesn't depend on transcript timing). Lean: (ii). Background: cap is new in Claude Code 2.1.119 (first banner 2026-04-24, reliable on 2.1.120); empirical threshold ~10,240B (10 KiB). Without 4a/4b, the failure mode is silent — model never sees the mandatory-acknowledgment line at the tail and the user has to ask "did you load essential docs?" to surface it (this happened in the originating investigation session).

## P2 - Medium

- **[HOOKS]** `surface-docs.sh` hook — context-aware doc surfacing (`surface-docs-hook`)
    - **scope**: `hooks`
    - **notes**: Promoted P99→P2 2026-04-26 — direct follow-up to `session-start-output-too-large`. The cap fix shrinks `essential-conventions-{code_style,execution}` to Quick Reference (§1) + path nudge; this hook extends the same surfacing pattern to `relevant-*` docs, matching tool context against doc keywords and injecting a one-liner ("relevant doc available: `.claude/docs/<name>.md` — Read on demand") when a relevant doc hasn't been loaded. Reuses the §1-extraction primitive landed in the cap fix. Same deterministic algorithm as `surface-lessons.sh` — intra-session dedup (v2.63.6) + 2+ keyword-hit threshold (v2.63.7). Original P99 demotion rationale ("observe surface-lessons for a few weeks before replicating") is moot: capacity pressure from the 10KB cap forces the issue earlier than the design-validation timeline anticipated, and the cap fix itself validates the §1-surfacing pattern. Coordinates with `.claude/hooks/` queue item 5.
    - **relates-to**: `session-start-output-too-large:depends-on`

- **[DOCS]** Revisit toolkit documentation for consumers — CLI help, guided introduction (`docs-consumer-experience`)
    - **scope**: `docs`
    - **notes**: Surfaced 2026-04-26. The toolkit ships ~34 skills, 7 agents, 14 hooks, 17 docs to consumer projects via `claude-toolkit sync`, but a downstream user landing on a freshly-synced project has no clear entry point — `README.md` and `docs/` are the only signals, and `claude-toolkit --help` is currently a thin wrapper over its argparse subcommands. Two distinct gaps to address: (1) **CLI help quality** — `claude-toolkit <subcommand> --help` is mostly auto-generated argparse text; could land harder with examples per subcommand and a top-level `claude-toolkit help` that organizes subcommands by purpose (sync resources, query backlog/docs/lessons, send suggestions, version checks). (2) **Guided introduction** — possibly a `/welcome-toolkit` or `/tour-toolkit` skill that walks a downstream user through "here are the resources you got, here's how skills/agents/hooks differ, here's how to discover what's available, here's how `claude-toolkit sync` works, here's how to send feedback." Audience is a Claude Code user opening a project that already has the toolkit synced, not someone setting up the workshop. Open questions: skill vs doc vs both; whether the tour reads `docs/indexes/` directly or has its own narrative; how it stays fresh as resources are added. Inputs: `cli/` module (current help text), `docs/getting-started.md` if it exists, `README.md`, the existing `setup-toolkit` skill (which is workshop-side, not consumer-side). Output: brainstorm doc proposing scope + shape; implementation likely staged.

- **[TOOLKIT]** Evaluate independence of lessons ecosystem from analytics ecosystem (`lessons-analytics-independence`)
    - **scope**: `toolkit`
    - **notes**: Surfaced 2026-04-26 during the projects-text-id alignment (v2.68.2). The lessons CLI and hooks now defer to `~/.claude/sessions.db` for canonical project_id resolution — a hard cross-ecosystem dependency: `_detect_project()` in `cli/lessons/db.py` errors when sessions.db exists but the encoded dir isn't in `project_paths`, and `_resolve_project_id` in `.claude/hooks/lib/hook-utils.sh` warns + leaves PROJECT empty in the same case. This was the right call to prevent name drift, but it raises a broader question: should the lessons ecosystem (capture + surface + manage rules across projects) work without the analytics ecosystem (sessions.db, hooks.db, project_paths, the indexer)? Today the lessons DB schema is owned by claude-sessions (`schemas/lessons.yaml`), the projects dimension uses claude-sessions' resolution chain (override / git_remote / regex_fallback), and the basename fallback only fires when sessions.db is *entirely absent*. Standalone-toolkit users (no claude-sessions installed) work today; partial-install users (sessions.db present but stale or empty) hit the strict error. Scope of evaluation: (1) catalog every cross-ecosystem coupling — schema ownership, projects table, FK directions, env var conventions (`CLAUDE_ANALYTICS_*`), backup-script ownership (already a P3 item: `move-backup-lessons-to-claude-sessions`); (2) identify which couplings are essential (data correctness — name drift) vs incidental (operational — backup script lives in toolkit but DB is sessions-owned); (3) decide whether lessons should ship a self-contained mode (own its projects dimension, no sessions.db dependency) or whether the current "claude-sessions is required when present" stance is the desired end state. Inputs: the projects-text-id design context (this CHANGELOG 2.68.2), the `move-backup-lessons-to-claude-sessions` P3 task (related question of where utilities live), `.claude/docs/relevant-toolkit-lessons.md` (current ecosystem reference). Output: a brainstorm/analysis doc in `output/claude-toolkit/`, possibly leading to a roadmap of either "decouple" or "formalize the dependency" tasks.

- **[SCRIPTS]** Diagnostic Check 1 picks up `statusLine` command as a hook command (`diag-statusline-scope`)
    - **scope**: `scripts`
    - **notes**: Surfaced 2026-04-27 by macOS consumer. `setup-toolkit-diagnose.sh` Check 1 extracts all `"command"` values from `settings.json` via a global sed regex (line 230), which includes the `statusLine` block's command. When the synced template doesn't have the `statusLine` block (older sync), the diagnostic reports `EXTRA: .claude/scripts/statusline-capture.sh` as a hook mismatch. Fix: scope the sed extraction to only the `hooks` section, or exclude known non-hook command paths.

## P3 - Low

- **[TESTS]** Boundary coverage for `test-suggest-json.sh` (`test-suggest-json-boundary`)
    - **scope**: `tests`
    - **notes**: 5 assertions for a 95-line hook (`suggest-read-json.sh`); missing size-threshold boundary tests (just-under, exactly-at, just-over). Correctness gap (off-by-one in size policy), not a security gap — separated from the P0 settings.json work because it's a different threat class. Add ~3 boundary assertions exercising the threshold value defined in the hook source. Surfaced 2026-04-26 in `output/claude-toolkit/analysis/20260426_1710__design-tests__expect-test-value-audit.md` (Finding 5).

- **[TESTS]** Dedicated test for `verify-resource-deps.sh` (`test-verify-resource-deps`)
    - **scope**: `tests`
    - **notes**: Surfaced 2026-04-27 during `macos-grep-pcre`. `verify-resource-deps.sh` is the most complex validator (~440 lines, 7 sections, 9 grep -oP sites pre-migration), runs on every `make validate`, but has no dedicated test file — only `make validate` integration coverage on the live toolkit's data. The macos-grep-pcre migration's regression net was a manual byte-diff against real data, which caught a multi-match-per-line bug on line 250; a fixture-driven test would have caught it without the manual step. Mirror the shape of `tests/test-verify-external-deps.sh`: temp-dir fixture, plant skills/agents/docs/hooks with known references, assert exit code + counts per section. Estimate: 2-3 hours.

- **[TESTS]** Diagnostic instrumentation for `test-setup-toolkit-diagnose.sh` orphan-detection assertion (`diag-orphan-flake-instrumentation`)
    - **scope**: `tests`
    - **references**: `output/claude-toolkit/reviews/20260427_1434__code-debugger__diag-orphan-flake.md`, `output/claude-toolkit/reviews/20260420_1903__code-debugger__diag-tmp-collision.md`
    - **notes**: Surfaced 2026-04-27 during `macos-grep-pcre`. One unreproducible failure of `tests/test-setup-toolkit-diagnose.sh:837` under parallel `make check` — `grep -q "ORPHAN:.*removed-hook.sh"` reported no match while `report_detail` printed the matching string from the same `$CHECK8` variable. Code-debugger ran 72 concurrent invocations + 5 serial without recurrence; the known DIAG_TMP race (commit 1a05585) is unrelated and already fixed. Best assessment: transient WSL2 subprocess hiccup, not a toolkit defect. **Action if it recurs**: add `printf '%s' "$CHECK8" | wc -c` and `printf '%s' "$CHECK8" | xxd | head` in the failure branch at line 837 to distinguish NUL/encoding corruption from a true grep miss. Optional fallback: replace the `echo | grep -q` with `[[ "$CHECK8" == *"..."* ]]` (pure bash, no subprocess) — doesn't fix a bug, just bypasses the suspect plumbing. Don't act now; only if a second occurrence happens.


- **[TOOLKIT]** Re-evaluate `suggestions-box/` as satellite convention + `claude-toolkit send --to` (`suggestions-box-satellite-convention`)
    - **scope**: `toolkit`
    - **notes**: Today only the workshop (claude-toolkit) has `suggestions-box/` and a documented triage workflow. Satellites (claude-sessions, aws-toolkit, schema-smith, validation-framework) don't — when sending a note from claude-toolkit *to* claude-sessions on 2026-04-26 (the harness-attachment-types observations), I had to `mkdir -p` the destination ad-hoc. Two related changes to evaluate together: (a) add an optional `--to <project-path>` flag to `claude-toolkit send` so you can write to *another* project's `suggestions-box/` without `cd` — current behavior writes to *this* project's box, which is the receive direction only; (b) standardize `suggestions-box/` (with a tiny CLAUDE.md pointing at the workshop's full triage workflow rather than duplicating it) as part of satellite scaffolding. Deferred to evaluate after the pattern gets organic use — if `--to` lands and gets exercised across satellites, the convention case strengthens; if cross-satellite traffic stays at one note a quarter, the formal convention is overkill. Surfaced 2026-04-26 during the SessionStart cap fix wrap-up.

- **[SKILLS]** `/design-aws` skill — idea to deployable AWS architecture (`design-aws`)
    - **scope**: `skills`
    - **notes**: Reference + satellite ready; user-postponed (no dependency blockers). Phased workflow: understand idea → design architecture (output: structured markdown doc) → generate diagram via `/design-diagram` with AWS icons → translate to aws-toolkit input configs (YAML) → review (security-first, then architecture). Leverages aws-toolkit for deterministic generation. Also depends on aws-toolkit v1 input format stability. When skill ships: enforce satellite-contract rule — link out to aws-toolkit docs via CLI convention (see `satellite-cli-docs-convention` task), no duplicated spec in workshop. Design doc: `output/claude-toolkit/design/20260329_1517__brainstorm-idea__design-aws.md`. Drafts: `output/claude-toolkit/drafts/archive/aws-toolkit/` — pre-research on IAM validation tools, cost estimation tools, service selection.

## P99 - Nice to Have

- **[CLI]** Refactor backlog query filters off `eval` (`backlog-query-eval-refactor`)
    - **scope**: `cli`
    - **source**: `output/claude-toolkit/plans/2026-04-27_0257__plan__backlog-schema-surface.md`
    - **notes**: `cli/backlog/query.sh` builds awk filter commands as strings (e.g. `filter_cmd="awk -F'\t' '\$3 == \"$status\"'"`) then runs them via `eval "$filter_cmd"`. User-supplied argv (status, scope, kind, source pattern, priority) gets interpolated into shell. Not a real risk for a single-user CLI run against your own backlog, but it would break on weird-but-legal argv (values containing single quotes/backslashes) and is a minor footgun if ever wired into an untrusted-input path. Refactor to bash arrays + `awk -v val="$status" '$3 == val'` style: drops `eval`, properly escapes values as awk variables. The `--exclude-priority` chained-awk path needs to migrate to `"${exclude_cmd[@]}" | "${filter_cmd[@]}"` (same shape, slightly more verbose). Regex filters (`relates-to`, `scope`) need `$0 ~ pattern` with the pattern as an awk variable. Test suite covers the behavior surface, so regressions are catchable. Surfaced by code-reviewer during 2026-04-27 review of `feat/backlog-schema-surface` — flagged as a Nice-to-have, not blocking. ~15 minutes of mechanical work in a focused branch.

- **[HOOKS]** Remove ecosystems opt-in session-start nudge (`remove-ecosystems-opt-in-nudge`)
    - **scope**: `hooks`
    - **notes**: After `ecosystems-opt-in` ships, session-start shows a one-time nudge to projects that predate the new schema (no `CLAUDE_TOOLKIT_LESSONS` / `CLAUDE_TOOLKIT_TRACEABILITY` env keys in settings.json). The nudge is self-extinguishing per-project (setup-toolkit writes the keys → nudge stops firing), but the code itself should be deleted once all user projects have been updated. Triggered manually rather than version-based because toolkit ships faster than the user reaches each project. Signal to remove: user says "remove the opt-in nudge" or equivalent. Delete the relevant section from `.claude/hooks/session-start.sh` and any related tests.
    - **relates-to**: `ecosystems-opt-in:depends-on`

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
    - **scope**: `agents`, `skills`
    - **notes**: Currently agents hardcode `model: "opus"` or `model: "sonnet"`. Some tasks (simple evaluations, pattern searches, file lookups) could route to Haiku for cost/speed without quality loss. Explore: (1) which agents/tasks are candidates for cheaper models, (2) whether this should be a convention in create-agent or a runtime decision by the spawning skill, (3) what the actual cost/quality tradeoff looks like in practice. Start with a discussion pass, not implementation.

- **[AGENTS]** Add structured reasoning activation to select agents (`agent-reasoning-activation`)
    - **scope**: `agents`
    - **notes**: Some agents would benefit from explicit reasoning technique activation (CoT, hypothesis-evidence patterns, structured decomposition). `code-debugger` already does this organically with its hypothesis-elimination approach. Audit other agents — candidates: `code-reviewer` (risk assessment reasoning), `goal-verifier` (backward verification logic), `proposal-reviewer` (audience perspective reasoning). Light touch — add reasoning prompts where they'd improve output, not a framework overhaul.

- **[CLI]** Add `claude-toolkit lessons demote` subcommand (`lessons-demote-cli`)
    - **scope**: `cli`
    - **notes**: Demoted P3→P99 2026-04-26 — workaround (raw SQL one-liner) is documented and the motivating sweep didn't need it. Surfaced 2026-04-26 during the Key-tier crystallization sweep. CLI exposes `promote`/`deactivate`/`absorb`/`crystallize` but no inverse of `promote`. The Key Promotion Contract in `manage-lessons/SKILL.md` §4.5 lists "demote back to recent" as one of three valid paths when revisiting a Key lesson, but the workaround is currently raw SQL: `sqlite3 ~/.claude/lessons.db "UPDATE lessons SET tier='recent' WHERE id='<ID>';"`. Add a thin subcommand mirroring `promote`'s shape (single `--id`, sets tier='recent', no other side effects). Add when convenient. Design context: `output/claude-toolkit/design/20260426_1623__design__key-lessons-review.md`.

- **[HOOKS]** Per-project customization of detection registry (`hooks-detection-registry-per-project`)
    - **scope**: `hooks`
    - **notes**: Demoted P3→P99 2026-04-26 — speculative pre-design with no user yet (note already says "defer until v1 ships and we have real-world signal"). Follow-up to `hooks-detection-target-convention`. Once the shared detection registry (`detection-registry.json` + JSON Schema + jq loader) is in place and its schema has stabilized, add a layered resolution path so downstream projects can extend or override the toolkit defaults without forking the synced file. Likely shape: project-local `detection-registry.local.json` (gitignored or committed per project preference) merged on top of the synced toolkit registry at hook-load time. Open questions to resolve at design time: (1) merge strategy — replace-by-id, append-only, or deep-merge per field; (2) whether projects can *disable* a toolkit-shipped entry (e.g. `{"id": "github-pat", "disabled": true}` override) or only add new ones; (3) whether the local file is project-private or syncs out via `claude-toolkit send` for cross-project sharing; (4) precedence rules when both files define the same `id` with different `kind`/`target`. Defer until v1 ships and we have real-world signal on which downstream projects need custom patterns (likely: aws-toolkit for AWS-specific shapes, schema-smith for DB-specific shapes). Design context: `output/claude-toolkit/brainstorm/20260425_1349__brainstorm-feature__hooks-detection-target-convention.md`.
    - **relates-to**: `hooks-detection-target-convention:depends-on`

- **[HOOKS]** Fold `surface-lessons.sh` into `grouped-bash-guard.sh` (`surface-lessons-fold`)
    - **scope**: `hooks`
    - **notes**: Demoted P3→P99 2026-04-26 — pure perf (~40ms avg savings) on a baseline that may already be lower after dedup work. Re-measure first before any implementation. `surface-lessons.sh` currently averages ~106ms with ~30-40ms of that being bash+jq startup overhead. Fold the Bash branch into `grouped-bash-guard.sh` to skip a second process spawn; keep Read/Write/Edit path separate or extend `grouped-read-guard.sh` to cover Write|Edit. Constraints: async-injection contract (PreToolUse additionalContext), 5s timeout, current matcher is `Bash|Read|Write|Edit` (wider than grouped-read's `Read`). P2 in `output/claude-toolkit/analysis/20260423_2309__analyze-idea__improve-lessons-lifecycle.md`; the 106ms baseline predates dedup + 2-hit threshold and may already be lower.

- **[SKILLS]** `review-security` — worthyness diagnostic (`review-security-worthyness`)
    - **scope**: `skills`
    - **notes**: Demoted P3→P99 2026-04-26 — skill has never been invoked, which is already the answer in spirit. Run invocation-frequency check (same approach as pattern-finder agents diagnostic). Based on data: (a) Keep — content already solid; (b) Sharpen — broaden description triggers and/or add surfacing-hook path; (c) Deprecate — CC's built-in /security-review may cover enough of the surface. Do alongside pattern-finder diagnostic for consistency.

- **[TOOLKIT]** Rename `.claude/docs/` to `.claude/conventions/` (`rename-claude-docs-to-conventions`)
    - **scope**: `toolkit`
    - **notes**: Demoted P3→P99 2026-04-26 — note's own framing is "schedule when nothing else is touching those paths", which is a P99 timing constraint even though the rename has architectural value. `.claude/docs/` is overloaded — name suggests user-facing docs but contents are agent-loaded conventions/rules (`essential-*`, `relevant-*`, `codebase-explorer/`). Shared name with top-level `docs/` hides the audience split (agent context vs user-facing). "rules" conflates with Claude Code's native rules concept, so `conventions/` is the preferred name. Coordinated rename: (1) move files, (2) update session-start loader and surface-* hooks, (3) update sync paths in CLI + dist profiles (base and raiz MANIFESTs), (4) update CLAUDE.md "Structure" section, (5) update `claude-toolkit docs` command and any skill references (grep for `.claude/docs/`), (6) update downstream satellites' synced copies via next sync. Non-trivial churn.

