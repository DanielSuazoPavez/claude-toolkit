# A/B Experiments with Git Worktrees

## 1. Quick Reference

**ONLY READ WHEN:**
- Setting up a side-by-side comparison of two Claude configurations on the same task
- The variable is something the harness controls (LSP plugin on/off, prompt variant, model variant, permission set)
- You want the results to be analyzable from the session DB after the fact

The formula: pick a real backlog task, create two worktrees from the same starting commit, vary one thing in `settings.local.json` (or in the kickoff prompt), keep everything else symmetric, launch each session yourself in its own terminal. Don't let the parent session drive the runs — that contaminates the experiment.

**See also:** `setup-worktree` skill, `teardown-worktree` skill, `relevant-toolkit-permissions_config` for `settings.local.json` shape.

---

## 2. When to use

This is for **observational comparisons**, not feature flags or rollouts. Use it when:

- You're evaluating a harness-level capability (LSP plugin, a new agent, a hook, a permission shape) and want to know whether it actually changes behavior on real work.
- You have a backlog task that's representative of the kind of work the variable would affect — refactors, multi-file changes, exploration-heavy planning.
- You're willing to keep one branch and discard the other (or merge whichever turned out cleaner).

Don't use it for:

- Synthetic probes ("write me a fizzbuzz with and without X"). The signal-to-noise on toy tasks is bad.
- Anything where the user is in the loop steering both runs simultaneously — the operator's attention becomes the dominant variable.
- One-shot questions where there's no extended session to measure.

n=1 per condition is the default cost. If a single comparison is decisive, ship the decision. If it's mixed, run another batch on a different task — don't keep iterating on the same one.

---

## 3. Setup formula

### 3.1 Pick the task and the starting commit

Pick the **next real backlog task** that's representative of what the variable should affect. Don't pick "smallest possible" (signal too thin) or "biggest possible" (too many confounds). Module-split phases, multi-file refactors, and "lift X out of Y" tasks are good shapes.

Pin the starting commit explicitly. Both runs start from the same SHA — usually the current tip of `main`. Note it down; the comparison doc will reference it.

### 3.2 Create two worktrees via `/setup-worktree`

```
/setup-worktree A on branch <task-id> (control)
/setup-worktree B on branch <task-id>-1 (variant)
```

Worktrees live in `.worktrees/` (gitignored). The `-1` branch-name suffix matches the existing claude-sessions convention for "second take on the same task."

**Known skill gap (as of writing):** `/setup-worktree` does not handle `.claude/docs/` when it's partially tracked (one tracked file + gitignored siblings). After running the skill, check `ls <worktree>/.claude/docs/ | wc -l` against `ls .claude/docs/ | wc -l`. If the worktree is short, hand-symlink the missing doc files. Filed back to claude-toolkit; remove this caveat once fixed upstream.

### 3.3 Write per-worktree `settings.local.json`

This is where the experimental variable usually lives. Copy the main project's `settings.local.json` into each worktree, then change exactly one thing in B. Example for an LSP-on/off comparison:

```json
{
  "enabledPlugins": {
    "pyright-lsp@claude-plugins-official": false   // A: control (off)
  },
  "permissions": { "allow": [ ... ] },
  "env": { ... }
}
```

```json
{
  "enabledPlugins": {
    "pyright-lsp@claude-plugins-official": true    // B: variant (on)
  },
  "permissions": { "allow": [ ... ] },
  "env": { ... }
}
```

Permissions and env must be identical — otherwise you're varying two things at once.

The harness blocks writing to `.claude/settings*.json` from Bash; use the Edit/Write tool, or write the files yourself outside the session.

### 3.4 Symmetric prompts

Both prompts must differ in **exactly one place** — the variable being tested. Everything else (task description, plan-mode framing, review skill usage, hand-off discipline) must be identical.

Example for an LSP comparison:

> A: `explore for task <task-id>, then draft the plan. After the first draft, use the /review-plan skill (inline) to refine it.`
>
> B: `explore for task <task-id>, **use the LSP tool whenever possible (avoid Read/Grep/Bash when you could be using LSP)**, then draft the plan. After the first draft, use the /review-plan skill (inline) to refine it.`

Save both prompts to a file before running so you can paste them verbatim. From-memory typing introduces drift.

### 3.5 Launch externally, don't drive from a parent session

The user opens two terminals, `cd` into each worktree, and runs `claude` in each. Paste the prompt verbatim. Let each session run to "branch ready for review" — both should stop short of `/wrap-up`, merge, tag, or push.

A parent Claude session must NOT drive the runs (subagent calls, SendMessage, etc.). Subagents don't get the same harness setup, the same hook gates, or the same plan-mode behavior — and the operator-as-driver loop is part of what the comparison is measuring.

---

## 4. What to keep symmetric

| Dimension | Why it matters |
|---|---|
| **Starting commit** | Different start state = different exploration surface. |
| **Permissions and env** | A blocked tool call in one branch but not the other masquerades as a strategy difference. |
| **Toolkit resources** (hooks, skills, agents, memories, docs) | A missing skill in one worktree silently changes behavior. The `setup-worktree` skill symlinks these from main. |
| **Plan-review usage** | If A runs `/review-plan` and B doesn't, you're measuring "with vs without review", not the variable. |
| **Hand-off discipline** | Both should stop at "branch ready" — running `/wrap-up` in only one branch confounds the comparison heavily (multi-million-token impact). |
| **Time of day** | Within a few hours is fine. Across days changes external noise (model serving, cache state). |

---

## 5. What deliberately *isn't* fixed

Some pre-existing model behaviors are part of the signal you want to capture, not noise to control away. Examples observed in the LSP pilot:

- **Auto-wrap-up boundary trips** (Opus 4.7 marching past plan-mode boundaries). Don't pre-fix the prompt to forbid this — let it recur, and document in the analysis whether the variable made it more or less likely.
- **Tool-discovery dead ends** (e.g. backlog `close-by-removal` idiom). Both branches will trip the same way. That's fine — it's a project-convention point, orthogonal to the variable.
- **Project-convention drift in `/review-plan`'s calibration.** Two reviews on similar plans can land at different verdicts; that's a real signal about the review skill, not a confound.

If you fix these in the prompt or the harness, you mute the data.

---

## 6. Capture and measurement

The session DB (`~/claude-analytics/sessions.db` or wherever the project's `claude-sessions` ingests to) is the system of record. After both branches reach "branch ready", reindex and pull:

```bash
# Reindex (sessions, usage, hooks)
./cron/index-sessions.sh
./cron/index-usage.sh
./cron/index-hooks.sh
```

Recurring caveats — confirm before drawing conclusions:

- **JSONL vs `events_raw` reconciliation.** `wc -l <session>.jsonl` vs `SELECT COUNT(*) FROM events_raw WHERE session_id = ?`. A mismatch of more than a few rows means the indexer silently truncated and the comparison may be incomplete.
- **Branch-label drift.** If a session runs `/wrap-up` end-to-end including merge, `sessions.git_branch` ends up as `main`. Use `last_prompt` and `predecessor_session_id` chains to identify which session belongs to which arm.
- **Per-turn vs per-session token windows.** If a session has 1 turn but ran for minutes, the per-turn aggregate undercounts.

The two LSP-pilot analyses under `output/claude-toolkit/analysis/*lsp-pilot*comparison.md` document the full query set and the order in which to run them. Use them as the working template.

---

## 7. Write-up template

Same shape both LSP-pilot studies converged on:

1. Sessions in scope (table: case / phase / session_id / branch / notes).
2. Headline numbers (table: wall time, activity count, tool counts, token totals per session).
3. Aggregated work-unit comparison (table: control vs variant deltas).
4. What the variable was used for (operations, targets, what was being answered).
5. What the other arm did instead.
6. Plan document comparison (review verdicts, distinctive content, where each is more accurate).
7. Implementation comparison (commit shape, divergences, tool-use shape, honest read).
8. Caveats and confounds.
9. Provisional read.
10. Open questions for next iterations.
11. Appendix — raw queries and commands.

Don't pre-judge the outcome. Write down what surprised you separately from what confirmed your hypothesis.

---

## 8. Teardown

After the analysis is written:

- Pick the branch you want to keep (or merge both — usually only one). Use `--no-ff` to preserve branch history.
- Tag the release if the work shipped.
- For each worktree: `/teardown-worktree`. The skill checks for uncommitted changes, copies any artifacts, removes the worktree, and checks out the branch.
- If the variant branch is being discarded entirely (Phase-3-of-pilot style measurement-only run), the analysis doc is the deliverable; the diff is not kept.

The JSONL transcripts on disk are the durable record. Even after worktree removal, sessions remain queryable from `~/.claude/projects/<project-id>/<session_id>.jsonl` and the indexed DB.
