# Hooks Index

Automation hooks configured in `settings.json`.

## Included Hooks

| Hook | Status | Trigger | Description |
|------|--------|---------|-------------|
| `session-start.sh` | stable | SessionStart | Loads essential memories and git context |
| `git-safety.sh` | stable | PreToolUse (EnterPlanMode\|Bash) | Blocks unsafe git operations: protected branch enforcement + remote-destructive commands |
| `block-dangerous-commands.sh` | stable | PreToolUse (Bash) | Blocks destructive commands (rm -rf /, fork bombs, etc.) |
| `secrets-guard.sh` | stable | PreToolUse (Read\|Bash) | Blocks reading .env files, credential files (SSH, AWS, GPG, etc.), and exposing secrets |
| `block-config-edits.sh` | stable | PreToolUse (Write\|Edit\|Bash) | Blocks writes to shell config, SSH, and git config files |
| `suggest-read-json.sh` | stable | PreToolUse (Read) | Suggests /read-json skill for large JSON files (>50KB, excludes common configs) |
| `enforce-uv-run.sh` | stable | PreToolUse (Bash) | Blocks direct `python`/`python3` calls, suggests `uv run python` |
| `enforce-make-commands.sh` | stable | PreToolUse (Bash) | Blocks bare `pytest`/`ruff`/`pre-commit`/`uv sync`/`docker` calls, suggests Make targets |
**Note**: Some hooks have broad matchers (e.g., `Bash` fires on every shell command). Hook UX noise is a known trade-off.

---

### session-start.sh

**Trigger**: SessionStart

Loads essential memories and git context at the start of each session.

- Outputs all `essential-*.md` memories
- Lists other available memories (with category counts)
- Shows current git branch and main branch
- Loads lessons from `learned.json`: key tier (all), recent (last 5), branch-flagged (current branch)
- Nudges `/manage-lessons` when recent count ≥ 10 or recurring flags exist
- Outputs guidance text for memory usage

### git-safety.sh

**Trigger**: PreToolUse (EnterPlanMode|Bash)

Blocks unsafe git operations — protected branch enforcement and remote-destructive commands.

**Protected branch enforcement:**
- Blocks: `EnterPlanMode` when on `main` or `master`
- Blocks: `git commit` commands when on `main` or `master`
- Handles: detached HEAD state (blocks with branch creation suggestion)

**Remote-destructive (severe — irreversible):**
- Blocks: Force push (`--force`, `-f`, `--force-with-lease`) to protected branches
- Blocks: `git push --mirror`
- Blocks: Deleting protected branches on remote (`--delete` or `:branch` syntax)

**Remote-destructive (soft — risky):**
- Blocks: Force push to non-protected branches
- Blocks: Deleting any remote branch
- Blocks: Cross-branch push (`HEAD:other-branch`)

- Config: `PROTECTED_BRANCHES` env var (regex, default: `^(main|master)$`)
- All blocks suggest running the command manually outside Claude

### block-dangerous-commands.sh

**Trigger**: PreToolUse (Bash)

Blocks destructive bash commands that could damage the system.

- Blocks: `rm -rf /`, `rm -rf ~`, fork bombs, `mkfs`, `dd` to disks, `chmod -R 777 /`

### secrets-guard.sh

**Trigger**: PreToolUse (Read|Bash)

Prevents accidental exposure of secrets from .env files and credential files.

- Blocks Read: `.env`, `.env.*` (except `.env.example`, `.env.template`, `.env.sample`)
- Blocks Read: SSH private keys (`~/.ssh/id_*`, not `.pub`), SSH config, GPG dir
- Blocks Read: Cloud creds (`~/.aws/credentials`, `~/.aws/config`), CLI tokens (`~/.config/gh/hosts.yml`, `~/.docker/config.json`, `~/.kube/config`)
- Blocks Read: Package manager tokens (`~/.npmrc`, `~/.pypirc`, `~/.gem/credentials`)
- Blocks Bash: `cat .env`, `source .env`, `export $(cat .env)`, `env`
- Blocks Bash: `cat`/`less`/`head`/`tail` of credential files, `gpg --export-secret-keys`
- Allows: `~/.ssh/known_hosts`, `~/.ssh/authorized_keys` (read), `*.pub` files

### block-config-edits.sh

**Trigger**: PreToolUse (Write|Edit|Bash)

Blocks writes to shell config and SSH files to prevent persistent environment poisoning.

- Blocks Write/Edit: `~/.bashrc`, `~/.bash_profile`, `~/.bash_login`, `~/.profile`, `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.zlogin`
- Blocks Write/Edit: `~/.ssh/authorized_keys`, `~/.ssh/config`, `~/.gitconfig`
- Blocks Bash: redirect/append (`>`, `>>`) to above paths, `sed -i`, `mv` to above paths, `tee -a`
- Allows: read-only commands (`grep ~/.bashrc`), project-level files (`/project/.bashrc`)

### suggest-read-json.sh

**Trigger**: PreToolUse (Read)

Suggests using `/read-json` skill for large JSON files.

- Blocks: `.json` files larger than size threshold
- Allows: Common config files (package.json, tsconfig.json, etc.) and `*.config.json`
- Config: `JSON_SIZE_THRESHOLD_KB` env var (default: 50)
- Reason: Large JSON files are better queried with jq via `/read-json`

### enforce-uv-run.sh

**Trigger**: PreToolUse (Bash)

Blocks direct Python interpreter calls when venv is not activated.

- Blocks: `python`, `python3`, `python3.X` (direct calls)
- Allows: `uv run python` (prefixed calls)
- Suggests: Use `uv run python` instead

**Note**: Python-specific. Remove for non-Python projects. Does not block pip/pytest/ruff — those are handled by `enforce-make-commands.sh`.

### enforce-make-commands.sh

**Trigger**: PreToolUse (Bash)

Blocks bare tool invocations, suggests Make targets.

- Blocks: bare `pytest`, `uv run pytest` (full suite only — targeted `pytest tests/file.py` allowed)
- Blocks: `uv run ruff`, `uv run pre-commit`, bare `pre-commit`, `ruff check/format`
- Blocks: `uv sync`, `docker up/down/build`
- Suggests: `make test`, `make lint`, `make install`, etc.

## Configuration

Hooks are configured in `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "EnterPlanMode",
        "hooks": [
          {"type": "command", "command": ".claude/hooks/git-safety.sh"}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/block-dangerous-commands.sh"},
          {"type": "command", "command": ".claude/hooks/enforce-uv-run.sh"}
        ]
      },
      {
        "matcher": "Read|Bash",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/secrets-guard.sh"}
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {"type": "command", "command": "bash .claude/hooks/suggest-read-json.sh"}
        ]
      }
    ]
  }
}
```

## Creating New Hooks

1. Create `.claude/hooks/your-hook.sh`
2. Make executable: `chmod +x .claude/hooks/your-hook.sh`
3. Add to `settings.json` under appropriate trigger
4. Hook receives tool input via environment variables

### Available Triggers

| Trigger | When | Use For |
|---------|------|---------|
| `SessionStart` | Session begins | Loading context, setup |
| `PreToolUse` | Before tool execution | Validation, blocking |
| `PostToolUse` | After tool execution | Cleanup, side effects |
| `Stop` | Agent finishes responding | Transcript analysis, follow-up prompts |

### Hook Environment

Hooks receive context via environment variables:
- `TOOL_INPUT` - JSON of tool parameters
- `TOOL_NAME` - Name of the tool being used
