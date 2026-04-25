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

---

## 3. Environment Variables

Set these in your shell or `.envrc` to customize hook behavior.

### Path Configuration
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_DOCS_DIR` | `.claude/docs` | Docs directory |
| `CLAUDE_MEMORIES_DIR` | `.claude/memories` | Memories directory |
| `CLAUDE_ANALYTICS_LESSONS_DB` | `$HOME/.claude/lessons.db` | Global lessons SQLite DB. Set in shell/`.envrc` — Claude Code does not expand `$HOME` in `settings.json` values, so path-valued vars must come from the shell environment |
| `CLAUDE_ANALYTICS_HOOKS_DIR` | `$HOME/claude-analytics/hook-logs` | Directory for hook-logs JSONL files (`invocations.jsonl`, `surface-lessons.jsonl`, `session-start-context.jsonl`). Same `$HOME`-expansion caveat as above |

### Version Pins
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_TOOLKIT_POWERLINE_VERSION` | `1.25.1` | `@owloops/claude-powerline` npm version used by `statusline-capture.sh` |

### Thresholds & Configuration
| Variable | Default | Purpose |
|----------|---------|---------|
| `JSON_SIZE_THRESHOLD_KB` | `50` | Size threshold for JSON blocking |
| `PROTECTED_BRANCHES` | `^(main\|master)$` | Regex for protected branch names |
| `HOOK_PERF` | _(unset)_ | Set to `1` to emit per-phase `HOOK_PERF` timing lines to stderr |

### Ecosystem Opt-Ins
Set in the `env` block of `.claude/settings.json` (not shell) so Claude Code injects them into every hook invocation.

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_TOOLKIT_LESSONS` | `"0"` | `"1"` enables: session-start lessons block, `surface-lessons` injection |
| `CLAUDE_TOOLKIT_TRACEABILITY` | `"0"` | `"1"` enables: hook-logs JSONL writes (via `_hook_log_jsonl`), `statusline-capture` usage-snapshots JSONL |

Pre-opt-in projects (neither key present) get a session-start nudge pointing at `/setup-toolkit`. The nudge self-extinguishes once either key is written — distinguishing "unset" from "explicitly 0" uses `[ -z "${VAR+x}" ]`. `/setup-toolkit` Phase 1.5 writes both keys on first run.

Template shape:
```json
"env": {
  "CLAUDE_TOOLKIT_LESSONS": "0",
  "CLAUDE_TOOLKIT_TRACEABILITY": "0",
  "CLAUDE_TOOLKIT_POWERLINE_VERSION": "1.25.1"
}
```

Hooks read the flags via `hook_feature_enabled <feature>` from `lib/hook-utils.sh` (returns exit 0 when `"1"`, non-zero otherwise). Any value other than `"1"` is treated as disabled.

---

## 4. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's matcher in `.claude/settings.json`
2. Review the hook script comments for expected behavior
3. Some hooks support threshold configuration (e.g., `JSON_SIZE_THRESHOLD_KB`)

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
