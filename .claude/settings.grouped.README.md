# A/B Test: Grouped Bash Guard

`settings.grouped.json.example` is a drop-in `settings.json` that folds
Bash-branch hooks into a single `grouped-bash-guard.sh` dispatcher. Currently
grouped: `block-dangerous-commands`, `enforce-make-commands`, `enforce-uv-run`,
and the Bash branch of `git-safety` (via the match/check pattern — see
`.claude/docs/relevant-toolkit-hooks.md`). `git-safety.sh` still registers
standalone for its `EnterPlanMode` branch.

The goal is to measure whether consolidating hooks meaningfully reduces
per-turn hook cost (bash startup + `hook-utils.sh` sourcing + `jq` reparse
of `tool_input`), plus the work-avoidance gained when `match_` predicates
short-circuit on non-matching Bash calls.

## Swap in the grouped config

```bash
cp .claude/settings.json .claude/settings.split.json.backup
cp .claude/settings.grouped.json.example .claude/settings.json
```

Restart Claude Code so the new settings take effect.

## Restore the split config

```bash
cp .claude/settings.split.json.backup .claude/settings.json
```

## Measuring

After a few turns under each config, run:

```bash
claude-sessions analytics toolkit hook-cost
```

Compare totals and per-section breakdowns. In the grouped config, the
dispatcher emits one sub-step row per check (`section=check_dangerous`,
`check_git_safety`, `check_make`, `check_uv`) plus one totals row — so
per-check cost is still visible for apples-to-apples comparison against
the split baseline. Rows with `outcome=not_applicable` indicate the check's
`match_` predicate returned false and the check body was skipped.

## Rollback

Just restore the backup. `grouped-bash-guard.sh` and the `hook_log_substep`
helper are inert if not registered in `settings.json` — safe to leave in tree.
