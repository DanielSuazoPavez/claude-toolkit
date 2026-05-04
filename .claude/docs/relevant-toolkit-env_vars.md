# Toolkit Environment Variables

## 1. Quick Reference

**ONLY READ WHEN:**
- Setting up a consumer project (`/setup-toolkit`)
- Configuring or troubleshooting hook / script / CLI behavior
- User asks about a specific env var or where to set one

Single source of truth for every environment variable the toolkit reads. For consumer-facing onboarding (which vars to set first), see `docs/getting-started.md`.

**See also:** `relevant-toolkit-hooks_config` for hook trigger configuration (non-env), `relevant-toolkit-lessons` for the lessons ecosystem, `relevant-toolkit-permissions_config` for permissions

---

## 2. Where to Set Each Var

Three surfaces, one rule:

| Surface | Use for | Why |
|---------|---------|-----|
| `.claude/settings.json` `env` block | Flags and string values that don't reference `$HOME` (opt-ins, version pins, regexes, thresholds) | Claude Code injects these into every hook invocation. **Does not expand `$HOME` or other shell variables** — values are passed through literally |
| `.claude/settings.local.json` `env` block | Per-user resolved paths (analytics DBs / dirs) | Gitignored, so per-machine paths don't leak; `setup-toolkit` Phase 1.6 writes these |
| Shell / `.envrc` | One-off overrides, test fixtures, CI | Highest precedence; useful when running scripts outside Claude Code |

**Rule:** if the value contains `$HOME` or any other shell variable, it must come from `settings.local.json` or the shell — never `settings.json`.

---

## 3. Registry

Columns:
- **Default** — fallback when the var is unset
- **Scope** — `consumer` (set by users), `workshop-internal` (toolkit-only, no consumer surface), `test-only` (set by test harness)
- **Readers** — files that read the var (`file:line`)

### 3.1 Toolkit-Specific Config (`CLAUDE_TOOLKIT_*`)

Set in `.claude/settings.json` `env` block. Opt-ins are read by hooks via `hook_feature_enabled <feature>` (exit 0 when `"1"`, non-zero otherwise — any value other than `"1"` is disabled).

| Var | Default | Scope | Readers | Purpose |
|---|---|---|---|---|
| `CLAUDE_TOOLKIT_LESSONS` | `"0"` | consumer | `hooks/lib/hook-utils.sh:292`, `hooks/session-start.sh:236` | `"1"` enables: session-start lessons block, `surface-lessons` injection, `/learn`, `/manage-lessons` |
| `CLAUDE_TOOLKIT_TRACEABILITY` | `"0"` | consumer | `hooks/lib/hook-utils.sh:293`, `hooks/session-start.sh:236`, `scripts/statusline-capture.sh:24` | `"1"` enables: hook-logs JSONL writes (via `_hook_log_jsonl`), `statusline-capture` usage-snapshots JSONL |
| `CLAUDE_TOOLKIT_POWERLINE_VERSION` | `1.25.1` | consumer | `scripts/statusline-capture.sh:15` | Pinned `@owloops/claude-powerline` npm version used by the statusline wrapper |
| `CLAUDE_TOOLKIT_PROTECTED_BRANCHES` | `^(main\|master)$` | consumer | `hooks/git-safety.sh:33`, `hooks/session-start.sh:133` | Regex for protected branches — `git-safety.sh` blocks commit / EnterPlanMode on these; `session-start.sh` skips branch-lessons surfacing |
| `CLAUDE_TOOLKIT_HOOK_PERF` | unset | consumer | `hooks/lib/hook-utils.sh:256, 533` | Set to `1` to emit per-phase `HOOK_PERF` timing lines to stderr |
| `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB` | `50` | consumer | `hooks/suggest-read-json.sh:64` | Size threshold (KB) for `suggest-read-json.sh` blocking |
| `CLAUDE_TOOLKIT_SETTINGS_INTEGRITY` | `"1"` | consumer | `scripts/lib/settings-integrity.sh` (sourced by `hooks/session-start.sh`) | `"1"` enables the SessionStart integrity check for `.claude/settings.json` and `.claude/settings.local.json` — surfaces a warning when the file changed since last session without a covering commit. Set to `"0"` to opt out |
| `CLAUDE_TOOLKIT_CLAUDE_DIR` | `.claude` | workshop-internal | `bin/claude-toolkit:255`, `scripts/setup-toolkit-diagnose.sh:26`, `scripts/validate-hook-utils.sh:15`, plus other validate scripts | Override the `.claude` directory location. Used by toolkit-internal scripts |
| `CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY` | `<lib>/detection-registry.json` | workshop-internal | `hooks/lib/detection-registry.sh:48`, `scripts/validate-detection-registry.sh:19` | Path to the secrets-detection registry JSON. Used by the validator and tests |
| `CLAUDE_TOOLKIT_SETTINGS_JSON` | `<claude-dir>/settings.json` | workshop-internal | `hooks/lib/settings-permissions.sh:48` | Path to the `settings.json` file the permissions loader reads. Tests/fixtures override; production hooks fall through to `$CLAUDE_TOOLKIT_CLAUDE_DIR/settings.json` |

Pre-opt-in projects (neither lessons nor traceability key present) get a session-start nudge pointing at `/setup-toolkit`. The nudge self-extinguishes once either key is written — distinguishing "unset" from "explicitly 0" uses `[ -z "${VAR+x}" ]`. `/setup-toolkit` Phase 1.5 writes both keys on first run.

Template shape (opt-ins only — tunables are added on demand):
```json
"env": {
  "CLAUDE_TOOLKIT_LESSONS": "0",
  "CLAUDE_TOOLKIT_TRACEABILITY": "0",
  "CLAUDE_TOOLKIT_POWERLINE_VERSION": "1.25.1"
}
```

### 3.2 Analytics Paths (`CLAUDE_ANALYTICS_*`)

Cross-project surface — these are settings the toolkit shares with claude-sessions (the analytics indexer). Path-valued vars **cannot** live in `.claude/settings.json` (the `$HOME` non-expansion rule); `setup-toolkit` Phase 1.6 writes resolved paths to `settings.local.json`.

| Var | Default | Scope | Readers | Purpose |
|---|---|---|---|---|
| `CLAUDE_ANALYTICS_LESSONS_DB` | `$HOME/claude-analytics/lessons.db` | consumer | `hooks/session-start.sh:129`, `hooks/surface-lessons.sh:22`, `cli/lessons/db.py:40` | Global lessons SQLite DB. Read+write by the toolkit |
| `CLAUDE_ANALYTICS_SESSIONS_DB` | `$HOME/claude-analytics/sessions.db` | consumer | `hooks/session-start.sh:167`, `cli/lessons/db.py:41` | Global sessions SQLite DB. Owned by the claude-sessions indexer; the toolkit reads it for session-start context |
| `CLAUDE_ANALYTICS_HOOKS_DB` | `$HOME/claude-analytics/hooks.db` | consumer | `hooks/surface-lessons.sh:78` | Read-only path to `hooks.db`, used by `surface-lessons.sh` for intra-session dedup. Owned and populated by the claude-sessions indexer |
| `CLAUDE_ANALYTICS_HOOKS_DIR` | `$HOME/claude-analytics/hook-logs` | consumer | `hooks/lib/hook-utils.sh:43`, `tests/perf-detection-registry.sh:43`, `tests/perf-surface-lessons.sh:18`, `tests/lib/hook-test-setup.sh:13` | Directory for hook-logs JSONL files (`invocations.jsonl`, `surface-lessons-context.jsonl`, `session-start-context.jsonl`). Write-only from the toolkit's perspective; the claude-sessions indexer projects rows into `hooks.db` |

### 3.3 Toolkit internals (other / bare)

Workshop-internal overrides — exposed for tests and edge cases, not part of the consumer surface.

| Var | Default | Scope | Readers | Purpose |
|---|---|---|---|---|
| `CLAUDE_DOCS_DIR` | `.claude/docs` | workshop-internal | `hooks/session-start.sh:30`, `tests/perf-session-start.sh:15` | Override docs directory used by `session-start.sh` for the docs scan. Used by tests and as an escape hatch |
| `PROJECT_ROOT` | `$(pwd)` | workshop-internal | `scripts/lib/profile.sh:25` | Override the project root used by `detect_profile`. Falls back to `$(pwd)` when unset |

### 3.4 Standard / external

These follow external conventions — do not rename.

| Var | Reader | Notes |
|---|---|---|
| `NO_COLOR` | `cli/lessons/formatting.py:22` | Standard convention (no-color.org) — disables ANSI color in CLI output |

### 3.5 CI-only

Read by `.github/` workflows; not part of the toolkit runtime surface.

| Var | Reader | Notes |
|---|---|---|
| `FORMAT_RAIZ_PROJECT_ROOT` | `.github/scripts/format-raiz-changelog.py:23` | Test-only override for CI script |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | `.github/workflows/publish-raiz.yml:97-98` | Repo secrets injected into the publish-raiz workflow |

### 3.6 Test harness

Set by `tests/lib/hook-test-setup.sh` and per-test setup. Not user-overridable.

| Var | Set by | Purpose |
|---|---|---|
| `TEST_HOOKS_DIR` | `tests/lib/hook-test-setup.sh:11` | Per-process temp dir for hook-logs |
| `TEST_LESSONS_DB` | per-test files | Fixture lessons DB path |
| `TEST_HOOKS_DB` | per-test files | Fixture hooks DB path |
| `TEST_INVOCATIONS_JSONL` | `tests/lib/hook-test-setup.sh:15` | Path to invocations JSONL for assertions |
| `TEST_SURFACE_LESSONS_JSONL` | `tests/lib/hook-test-setup.sh:16` | Path to surface-lessons JSONL for assertions |
| `TEST_SESSION_START_JSONL` | `tests/lib/hook-test-setup.sh:17` | Path to session-start JSONL for assertions |
| `TOOLKIT_DIR` | `tests/test-cli.sh` and friends | Fixture toolkit dir path |
| `TOOLKIT_DIR_OVERRIDE` | `tests/test-cli.sh:77` | Per-test override of `TOOLKIT_DIR` |

---

## 4. Removed

- **`CLAUDE_MEMORIES_DIR`** (removed in v2.70.0) — was declared in `settings.json` and dist templates but had no code reader. Pure documentation ghost.
- **`HOOK_LOG_DB`** (renamed in v2.62.0) — became `CLAUDE_ANALYTICS_HOOKS_DB`. No back-compat alias.
- **`PROTECTED_BRANCHES`, `HOOK_PERF`, `JSON_SIZE_THRESHOLD_KB`, `CLAUDE_DETECTION_REGISTRY`, `CLAUDE_DIR`** (renamed in v2.71.0) — became `CLAUDE_TOOLKIT_PROTECTED_BRANCHES`, `CLAUDE_TOOLKIT_HOOK_PERF`, `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB`, `CLAUDE_TOOLKIT_CLAUDE_DETECTION_REGISTRY`, `CLAUDE_TOOLKIT_CLAUDE_DIR`. No back-compat alias — consumers must update `settings.json` and any shell/`.envrc` overrides on sync.

---

## 5. Naming Conventions

| Pattern | Use for |
|---|---|
| `CLAUDE_TOOLKIT_*` | Consumer-facing toolkit-specific config (opt-ins, version pins, thresholds, regexes) |
| `CLAUDE_ANALYTICS_*` | Cross-project analytics surface shared with claude-sessions (DB paths, log dirs) |
| Bare names | **Avoid** — they collide with consumer-project namespaces. All formerly-bare toolkit vars now live under `CLAUDE_TOOLKIT_*` (see §4 for the v2.71.0 rename) |
| `TEST_*` | Test harness internals — never read by production code |

When adding a new env var, prefer `CLAUDE_TOOLKIT_*`. Use `CLAUDE_ANALYTICS_*` only when claude-sessions also reads or writes the same surface. Justify any bare-name choice in the PR description.
