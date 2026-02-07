# Hooks Configuration Reference

## 1. Quick Reference

**ONLY READ WHEN:**
- Configuring or troubleshooting hooks behavior
- User asks about hook environment variables or thresholds

Reference for hook triggers, environment variables, and customization options.

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

### PreToolUse (Read|Bash)
| Hook | Purpose |
|------|---------|
| `secrets-guard.sh` | Blocks reading .env files with secrets |

### PreToolUse (Read)
| Hook | Purpose |
|------|---------|
| `suggest-read-json.sh` | Suggests /read-json for large JSON files |

### PreToolUse (EnterPlanMode|Bash)
| Hook | Purpose |
|------|---------|
| `enforce-feature-branch.sh` | Warns when on main/master branch |

### PostToolUse (Write)
| Hook | Purpose |
|------|---------|
| `copy-plan-to-project.sh` | Copies plans from scratchpad to .claude/plans |

---

## 3. Environment Variables

Set these in your shell or `.envrc` to customize hook behavior.

### Bypass Controls
| Variable | Effect |
|----------|--------|
| `ALLOW_DIRECT_PYTHON=1` | Bypass enforce-uv-run check |
| `ALLOW_DIRECT_COMMANDS=1` | Bypass enforce-make-commands check |
| `ALLOW_DANGEROUS_COMMANDS=1` | Bypass block-dangerous-commands check |
| `ALLOW_COMMIT_ON_MAIN=1` | Allow git commit on protected branches |

### Path Configuration
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_MEMORIES_DIR` | `.claude/memories` | Memories directory |
| `CLAUDE_PLANS_DIR` | `.claude/plans` | Plan copies destination |

### Feature Toggles
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_SKIP_PLAN_COPY` | `0` | Disable plan copying |

### Thresholds & Patterns
| Variable | Default | Purpose |
|----------|---------|---------|
| `JSON_SIZE_THRESHOLD_KB` | `50` | Size threshold for JSON blocking |

---

## 4. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's matcher in `.claude/settings.json`
2. Review the hook script comments for expected behavior
3. Some hooks support threshold configuration (e.g., `JSON_SIZE_THRESHOLD_KB`)

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
