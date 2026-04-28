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

## 3. Environment Variables

The full registry of every env var the toolkit reads (consumer-facing + workshop-internal + test-only) lives in **`relevant-toolkit-env_vars.md`** — naming conventions, scope, defaults, readers, and the rule for which surface (`settings.json` vs `settings.local.json` vs shell) each var belongs to.

Hooks read ecosystem opt-in flags via `hook_feature_enabled <feature>` from `lib/hook-utils.sh` (returns exit 0 when `"1"`, non-zero otherwise — any value other than `"1"` is disabled).

---

## 4. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's matcher in `.claude/settings.json`
2. Review the hook script comments for expected behavior
3. Some hooks support threshold configuration (e.g., `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB`)

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
