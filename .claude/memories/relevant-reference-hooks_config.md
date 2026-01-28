# Hooks Configuration Reference

## 1. Quick Reference

**ONLY READ WHEN:**
- Configuring or troubleshooting hooks behavior
- Need to bypass a hook temporarily
- User asks about hook environment variables

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
| `suggest-json-reader.sh` | Suggests /read-json for large JSON files |

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
| `ALLOW_ENV_READ=1` | Allow reading .env files |
| `ALLOW_COMMIT_ON_MAIN=1` | Allow git commit on protected branches |
| `ALLOW_JSON_READ=1` | Bypass /read-json suggestion |

### Path Configuration
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_MEMORIES_DIR` | `.claude/memories` | Memories directory |
| `CLAUDE_PLANS_DIR` | `.claude/plans` | Plan copies destination |

### Feature Toggles
| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_SKIP_PLAN_COPY` | `0` | Disable plan copying |
| `JSON_READ_WARN` | `0` | Warn instead of block for JSON files |

### Thresholds & Patterns
| Variable | Default | Purpose |
|----------|---------|---------|
| `JSON_SIZE_THRESHOLD_KB` | `50` | Size threshold for JSON blocking |
| `SAFE_ENV_EXTENSIONS` | `example,template,sample` | Safe .env extensions |
| `ALLOW_JSON_PATTERNS` | `package.json,tsconfig.json,...` | Always-allowed JSON files |

---

## 4. Troubleshooting

**Hook blocking unexpectedly?**
1. Check the hook's env var bypass (section 3)
2. Set temporarily: `export ALLOW_<HOOK>=1`
3. Or add to `.envrc` for persistent override

**Hook not firing?**
1. Verify `.claude/settings.json` has the hook configured
2. Check hook script is executable: `chmod +x .claude/hooks/<script>.sh`
