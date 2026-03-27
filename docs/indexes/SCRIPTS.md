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
