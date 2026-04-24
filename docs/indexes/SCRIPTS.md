# Scripts Index

Workshop-internal tooling in `.claude/scripts/` — validators, diagnostics, statusline capture, cron jobs. Most of these ship to consumer projects via `claude-toolkit sync` so the same validation/diagnostic contract runs everywhere; a smaller subset is workshop-only (cron maintenance). This index isn't a product catalog — it's a drift check against disk, enforced by `validate-resources-indexed.sh`.

The `Ships` column uses: **base** = synced to base consumers, **raiz** = also in the raiz profile manifest, **no** = workshop-only.

For user-facing CLI tools, see `cli/` (`backlog/`, `eval/`, `lessons/`).

## Diagnostic

| Script | Status | Ships | Description |
|--------|--------|-------|-------------|
| `setup-toolkit-diagnose.sh` | stable | base + raiz | Consolidated diagnostic — runs all 8 setup-toolkit checks in one pass |

## Validation

| Script | Status | Ships | Description |
|--------|--------|-------|-------------|
| `validate-all.sh` | stable | base | Orchestrator — runs all validators |
| `validate-resources-indexed.sh` | stable | base | Checks disk resources match index entries |
| `validate-settings-template.sh` | stable | base | Checks settings.json matches template |
| `verify-resource-deps.sh` | stable | base | Validates cross-references between resources |
| `validate-safe-commands-sync.sh` | stable | base | Checks approve-safe-commands hook prefixes match settings.json |
| `validate-hook-utils.sh` | stable | base | Checks all hooks source shared library lib/hook-utils.sh |
| `validate-dist-manifests.sh` | stable | base | Checks every entry in dist/raiz/MANIFEST and dist/base/EXCLUDE resolves to a real path on disk |
| `verify-external-deps.sh` | stable | base | Checks external tools declared in skill compatibility fields are installed |

## Statusline

| Script | Status | Ships | Description |
|--------|--------|-------|-------------|
| `statusline-capture.sh` | stable | base | Captures Claude Code statusline JSON to `~/.claude/usage-snapshots/snapshots.jsonl`, forwards stdin to powerline |

## Libraries

| Path | Status | Ships | Description |
|------|--------|-------|-------------|
| `lib/profile.sh` | stable | base + raiz | `detect_profile` — prints `workshop`/`base`/`raiz` so shipped scripts can branch on deployment context |

## Maintenance (workshop-only)

Excluded from sync via `dist/base/EXCLUDE` (`scripts/cron/`).

| Path | Status | Ships | Description |
|------|--------|-------|-------------|
| `cron/backup-lessons-db.sh` | stable | no | Nightly backup of lessons.db; planned to move to claude-sessions |
