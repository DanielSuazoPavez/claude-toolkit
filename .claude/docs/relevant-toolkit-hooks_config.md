# Hooks Configuration Reference

## 1. Quick Reference

**ONLY READ WHEN:**
- Configuring or troubleshooting hooks behavior
- User asks about hook environment variables or thresholds

Reference for hook triggers, environment variables, and customization options.

**See also:** `/create-hook` skill

---

## 2. Active Hooks by Trigger

### SessionStart
| Hook | Purpose |
|------|---------|
| `session-start.sh` | Loads essential memories at session start |

### PreToolUse (Bash)
| Hook | Purpose |
|------|---------|
| `block-dangerous-commands.sh` | Blocks destructive git/rm commands |
| `enforce-uv-run.sh` | Suggests `uv run` instead of direct `python` |
| `enforce-make-commands.sh` | Suggests `make` targets instead of raw commands |

### PreToolUse (Write|Edit|Bash)
| Hook | Purpose |
|------|---------|
| `block-config-edits.sh` | Blocks writes to shell config, SSH, and git config files |

### PreToolUse (Read|Bash)
| Hook | Purpose |
|------|---------|
| `secrets-guard.sh` | Blocks reading .env files and credential files |

### PreToolUse (Read)
| Hook | Purpose |
|------|---------|
| `suggest-read-json.sh` | Blocks Read on large JSON files, points at read-json jq reference |

### PreToolUse (EnterPlanMode|Bash)
| Hook | Purpose |
|------|---------|
| `git-safety.sh` | Blocks unsafe git operations: protected branches + remote-destructive commands |

### PermissionDenied
| Hook | Purpose |
|------|---------|
| `log-permission-denied.sh` | Logs classifier denials into invocations.jsonl for analytics |

---

## 3. Where Tunable Hook Values Live

Three surfaces, by data shape:

| Shape | Surface | Pattern | Example |
|---|---|---|---|
| **List of structured records** (id, kind, target, pattern, message…) | `.claude/hooks/lib/<name>-registry.json` + matching `.sh` loader + JSON schema + validator + perf test | `detection-registry.json` (canonical) — schema at `.claude/schemas/hooks/detection-registry.schema.json`, loader at `lib/detection-registry.sh`, validator at `.claude/scripts/validate-detection-registry.sh` | `block-credential-exfiltration`, `secrets-guard`, `block-config-edits`, `auto-mode-shared-steps` (capability bucket) consume it |
| **Scalar tunable** (one regex, one threshold, one toggle) | `CLAUDE_TOOLKIT_*` env var, declared in `relevant-toolkit-env_vars.md` §3.1 | Read at hook startup with default fallback. `hook_feature_enabled <feature>` for `0`/`1` opt-ins. | `CLAUDE_TOOLKIT_PROTECTED_BRANCHES`, `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB` |
| **Permission-derived list** (mirrors `settings.json` permissions) | Read directly from `settings.json` via `lib/settings-permissions.sh` | `settings.json` is canonical — no derived files, no validators, no drift possible. Hooks load once at source-time, match via pure-bash alternation regex or array iteration. `settings.local.json` is intentionally ignored — per-machine ad-hoc trust shouldn't shape hook semantics. | `approve-safe-commands` (allow), `auto-mode-shared-steps` (ask) |

**Cheapness contract for all three:** jq is allowed once, at hook source-time. Per-call matching must be pure bash — no fork. See `lib/detection-registry.sh:22` for the canonical statement.

**Consumer-specific filtering:** the loader exposes the unfiltered list; consumer-specific exclusions live in the consumer. Example: `permissions.ask` carries `Bash(curl:*)` and `Bash(wget:*)`, but `auto-mode-shared-steps` delegates those to the registry-driven Authorization-header check via inline `BASH_REMATCH[2] != curl/wget` filters (see `auto-mode-shared-steps.sh` step `--- settings.json permissions.ask ---`). A future consumer (e.g. status-line warning that lists every ask entry) gets the unfiltered list.

**Anti-patterns:**

- Generating a derived JSON from `settings.json` and committing it — drift will reappear. Read `settings.json` directly.
- Adding a fourth scalar env var when an existing list-shape has the same data — extend the existing registry instead.
- Inline lists of structured records in a hook script — externalise to a registry as soon as a second consumer or a per-project tuning need appears.
- Filtering settings-derived lists inside the loader — if the exclusion is consumer-specific, do it in the consumer.

---

## 4. Environment Variables

The full registry of every env var the toolkit reads (consumer-facing + workshop-internal + test-only) lives in **`relevant-toolkit-env_vars.md`** — naming conventions, scope, defaults, readers, and the rule for which surface (`settings.json` vs `settings.local.json` vs shell) each var belongs to.

Hooks read ecosystem opt-in flags via `hook_feature_enabled <feature>` from `lib/hook-utils.sh` (returns exit 0 when `"1"`, non-zero otherwise — any value other than `"1"` is disabled).

---

## 5. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's matcher in `.claude/settings.json`
2. Review the hook script comments for expected behavior
3. Some hooks support threshold configuration (e.g., `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB`)

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
