<!-- Auto-generated from scripts.json — do not edit directly. Run `make render` after editing scripts.json. -->

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
| `validate-all.sh` | stable | base + raiz | Orchestrator — runs all validators |
| `validate-resources-indexed.sh` | stable | base + raiz | Checks disk resources match index entries |
| `validate-settings-template.sh` | stable | base + raiz | Checks settings.json matches template |
| `verify-resource-deps.sh` | stable | base + raiz | Validates cross-references between resources |
| `validate-hook-utils.sh` | stable | base + raiz | Checks all hooks source shared library lib/hook-utils.sh |
| `validate-detection-registry.sh` | stable | base + raiz | Validates `.claude/hooks/lib/detection-registry.json` against schema (id format, enums, regex compilability) |
| `validate-session-start-cap.sh` | stable | base + raiz | Checks session-start hook output stays within harness ~10KB cap (warn at 9.5KB, fail at 10KB) |
| `verify-external-deps.sh` | stable | base + raiz | Checks external tools declared in skill compatibility fields are installed |

## Statusline

| Script | Status | Ships | Description |
|--------|--------|-------|-------------|
| `statusline-capture.sh` | stable | base + raiz | Captures Claude Code statusline JSON to `~/.claude/usage-snapshots/snapshots.jsonl`, forwards stdin to powerline |

## Libraries

| Path | Status | Ships | Description |
|--------|--------|-------|-------------|
| `lib/profile.sh` | stable | base + raiz | `detect_profile` — prints `workshop`/`base`/`raiz` so shipped scripts can branch on deployment context |
| `lib/settings-integrity.sh` | stable | base + raiz | `settings_integrity_check` — SessionStart tripwire for `.claude/settings.json` rewrites; sourced by `hooks/session-start.sh` |

## Migration

| Script | Status | Ships | Description |
|--------|--------|-------|-------------|
| `migrate-backlog-to-json.sh` | stable | base | Migrates `BACKLOG.md` to `BACKLOG.json` — parses goals, scope definitions, tasks with metadata |

## Maintenance (workshop-only)

Excluded from sync via `dist/base/EXCLUDE` (`validate-dist-manifests.sh`). `validate-all.sh` ships to consumers and skips the dist-manifest validator when the file is absent.

| Path | Status | Ships | Description |
|--------|--------|-------|-------------|
| `validate-dist-manifests.sh` | stable | no | Checks every entry in dist/raiz/MANIFEST and dist/base/EXCLUDE resolves to a real path on disk; toolkit-source-tree only |
| `hook-framework/parse-headers.sh` | stable | no | Parses a hook file's `# CC-HOOK:` header block into one JSON object on stdout (declaration order, pass-through, no defaults); workshop-only build-time tool feeding the future hook validator and dispatcher codegen |
| `hook-framework/validate.sh` | stable | no | Validates `# CC-HOOK:` headers across `.claude/hooks/` against `settings.json` and dispatcher source — covers V1–V7, V9, V10, V13–V15, V17 (see design/hook-framework-refactor.md C4); workshop-only |

