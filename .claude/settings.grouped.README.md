# A/B Test: Grouped Bash Guard

`settings.grouped.json.example` is a drop-in `settings.json` that replaces the 3
split Bash PreToolUse hooks (`block-dangerous-commands`, `enforce-uv-run`,
`enforce-make-commands`) with a single `grouped-bash-guard.sh` dispatcher.

The goal is to measure whether consolidating hooks meaningfully reduces
per-turn hook cost (bash startup + `hook-utils.sh` sourcing + `jq` reparse
of `tool_input`).

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
`check_make`, `check_uv`) plus one totals row — so per-check cost is still
visible for apples-to-apples comparison against the split baseline.

## Rollback

Just restore the backup. `grouped-bash-guard.sh` and the `hook_log_substep`
helper are inert if not registered in `settings.json` — safe to leave in tree.
