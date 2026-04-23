# Scripts Index

Internal utility scripts in `.claude/scripts/`.

For user-facing CLI tools, see `cli/` (`backlog/`, `eval/`, `lessons/`).

## Diagnostic

| Script | Status | Synced | Description |
|--------|--------|--------|-------------|
| `setup-toolkit-diagnose.sh` | stable | yes | Consolidated diagnostic — runs all 8 setup-toolkit checks in one pass |

## Validation

| Script | Status | Synced | Description |
|--------|--------|--------|-------------|
| `validate-all.sh` | stable | yes | Orchestrator — runs all validators |
| `validate-resources-indexed.sh` | stable | yes | Checks disk resources match index entries |
| `validate-settings-template.sh` | stable | yes | Checks settings.json matches template |
| `verify-resource-deps.sh` | stable | yes | Validates cross-references between resources |
| `validate-safe-commands-sync.sh` | stable | yes | Checks approve-safe-commands hook prefixes match settings.json |
| `validate-hook-utils.sh` | stable | yes | Checks all hooks source shared library lib/hook-utils.sh |
| `validate-dist-manifests.sh` | stable | no | Checks every entry in dist/raiz/MANIFEST and dist/base/EXCLUDE resolves to a real path on disk |
| `verify-external-deps.sh` | stable | no | Checks external tools declared in skill compatibility fields are installed |

## Statusline

| Script | Status | Synced | Description |
|--------|--------|--------|-------------|
| `statusline-capture.sh` | stable | yes | Captures Claude Code statusline JSON to `~/.claude/usage-snapshots/snapshots.jsonl`, forwards stdin to powerline |
