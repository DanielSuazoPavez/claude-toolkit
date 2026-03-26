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
| `suggest-read-json.sh` | Suggests /read-json for large JSON files |

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

### Thresholds & Configuration
| Variable | Default | Purpose |
|----------|---------|---------|
| `JSON_SIZE_THRESHOLD_KB` | `50` | Size threshold for JSON blocking |
| `PROTECTED_BRANCHES` | `^(main\|master)$` | Regex for protected branch names |

---

## 4. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's matcher in `.claude/settings.json`
2. Review the hook script comments for expected behavior
3. Some hooks support threshold configuration (e.g., `JSON_SIZE_THRESHOLD_KB`)

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
