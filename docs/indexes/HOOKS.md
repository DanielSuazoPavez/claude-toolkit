# Hooks Index

Automation hooks configured in `settings.json`.

## Opt-in Ecosystems

Two hook behaviors are gated by env vars set in `.claude/settings.json` (`env` block). Defaults to disabled; `/setup-toolkit` prompts on first run.

| Env var | Gates |
|---------|-------|
| `CLAUDE_TOOLKIT_LESSONS` | `session-start.sh` lessons section + lesson count in ack; `surface-lessons.sh` injection (context logging still runs, gated by traceability) |
| `CLAUDE_TOOLKIT_TRACEABILITY` | `_hook_log_jsonl` writes (rows in `~/claude-analytics/hook-logs/*.jsonl` for every hook invocation); `statusline-capture.sh` usage-snapshots JSONL append |

## Included Hooks

| Hook | Status | Trigger | Opt-in | Description |
|------|--------|---------|--------|-------------|
| `session-start.sh` | stable | SessionStart | `lessons` (partial) | Loads essential docs, git context, lessons (if enabled), and toolkit version drift check. Also emits the ecosystems opt-in nudge when neither env key is set. Persists a structured row (branch, main branch, cwd) into `session-start-context.jsonl` for downstream consumers (claude-sessions projector) — gated by `traceability`. |
| `git-safety.sh` | stable | PreToolUse (EnterPlanMode) + Bash via dispatcher | — | Blocks unsafe git operations: protected branch enforcement + remote-destructive commands |
| `auto-mode-shared-steps.sh` | stable | Bash via dispatcher | — | Under `permission_mode=auto`, blocks shared-state/publishing actions: `git push`, `gh` writes, `gh api`, `curl`/`wget` to `api.github.com`, `curl`/`wget` with `Authorization` header. No-op outside auto-mode |
| `block-credential-exfiltration.sh` | stable | Bash via dispatcher | — | Blocks commands carrying credential-shaped tokens in arguments (GitHub PAT, GitLab, Slack, AWS, OpenAI, Anthropic). Sibling to `secrets-guard` — that blocks credential reads at-rest; this blocks the in-flight payload (e.g. token already in context being pasted into `curl -H "Authorization: ..."`) |
| `block-dangerous-commands.sh` | stable | Bash via dispatcher | — | Blocks destructive commands (rm -rf /, fork bombs, etc.) |
| `secrets-guard.sh` | stable | PreToolUse (Grep) + Read via dispatcher + Bash via dispatcher | — | Blocks reading .env files, credential files (SSH, AWS, GPG, etc.), and exposing secrets |
| `block-config-edits.sh` | stable | PreToolUse (Write\|Edit) + Bash via dispatcher | — | Blocks writes to shell config, SSH, and git config files |
| `suggest-read-json.sh` | stable | Read via dispatcher | — | Blocks Read on large JSON files (>50KB, excludes common configs), points at `read-json` jq reference |
| `enforce-uv-run.sh` | stable | Bash via dispatcher | — | Blocks direct `python`/`python3` calls, suggests `uv run python` |
| `enforce-make-commands.sh` | stable | Bash via dispatcher | — | Blocks bare `pytest`/`ruff`/`pre-commit`/`uv sync`/`docker` calls, suggests Make targets |
| `surface-lessons.sh` | stable | PreToolUse (Bash\|Read\|Write\|Edit) | `lessons` (injection only) | Surfaces relevant active lessons as additionalContext based on tool context keywords. Context logging runs independently (gated by `traceability`). |
| `approve-safe-commands.sh` | stable | PermissionRequest (Bash) | Auto-approves chained commands when all subcommands match safe prefixes |
| `grouped-bash-guard.sh` | stable | PreToolUse (Bash) | Default Bash dispatcher — sources `block-dangerous-commands`, `auto-mode-shared-steps`, `block-credential-exfiltration`, `git-safety`, `secrets-guard`, `block-config-edits`, `enforce-make-commands`, `enforce-uv-run` and runs their `match_`/`check_` predicates in order. Amortizes bash+jq startup across 8 guards |
| `grouped-read-guard.sh` | stable | PreToolUse (Read) | Read dispatcher — sources `secrets-guard` (Read branch) + `suggest-read-json` and runs their `match_`/`check_` predicates in order. Amortizes bash+jq startup across both checks |
**Note**: Some hooks have broad matchers (e.g., `Bash` fires on every shell command). Hook UX noise is a known trade-off.

---

### Shared Library

All hooks source `.claude/hooks/lib/hook-utils.sh` which provides:
- Standardized initialization and stdin parsing
- Outcome helpers (block, approve, inject)
- Execution timing and logging to `~/claude-analytics/hook-logs/invocations.jsonl` — gated on `CLAUDE_TOOLKIT_TRACEABILITY=1`; no-op when disabled
- Section-level tracking for session-start
- `hook_feature_enabled <feature>` helper — checks opt-in env vars (`lessons`, `traceability`); returns 0 when enabled, non-zero otherwise

JSONL files written under `~/claude-analytics/hook-logs/` (override via `CLAUDE_ANALYTICS_HOOKS_DIR`):
- `invocations.jsonl` — one `kind: invocation` row per hook firing (EXIT trap), plus per-`section`/`substep` rows for grouped hooks and session-start. The `invocation` row embeds the full hook stdin as `stdin` (parsed object) or `stdin_raw` (string fallback when stdin failed JSON parse).
- `surface-lessons.jsonl` — one `kind: context` row per `surface-lessons` firing, with raw context, extracted keywords, match count, and matched lesson ids.
- `session-start-context.jsonl` — one `kind: session_start_context` row per SessionStart firing (source, git_branch, main_branch, cwd).

Common fields across `invocations.jsonl` rows: session_id, invocation_id, timestamp, project, hook_event, hook_name, tool_name, section, duration_ms, outcome, bytes_injected, source, call_id. `call_id` is a bare Anthropic id (`toolu_...` for tool-scoped events, `agent_id` for SubagentStop) — tool-vs-agent is derived from `hook_event`, not a prefix. Joins to `claude-sessions.tool_calls.tool_use_id` on `(session_id, call_id)`. For human debugging, tail rows via `tail -f ~/claude-analytics/hook-logs/invocations.jsonl | jq`.

---

### session-start.sh

**Trigger**: SessionStart

Loads essential memories and git context at the start of each session.

- Outputs all `essential-*.md` memories
- Lists other available memories (with category counts)
- Shows current git branch and main branch
- Loads lessons from `lessons.db` (sqlite3): key tier (all), recent (last 5), branch-specific (current branch)
- Falls back to `learned.json` (jq) if lessons.db not found, with migration nudge
- Nudges `/manage-lessons` based on days since last run (metadata-driven threshold, default 7d)
- Checks `.claude-toolkit-version` against `claude-toolkit version`; nudges `make claude-toolkit-sync` + `/setup-toolkit` on drift
- Outputs guidance text for memory usage
- Logs each section's byte/token size to `.claude/logs/session-start-sizes.log` (SESSION_ID, timestamp, project, section, bytes, ~tokens)
- Persists a structured row into `session-start-context.jsonl` (source, git_branch, main_branch, cwd) per firing — consumed by the claude-sessions projector to seed `state_changes` baselines instead of emitting `from_value=NULL` on first-observation rows. Gated by `CLAUDE_TOOLKIT_TRACEABILITY=1` via the same `_hook_log_jsonl` path as `invocations.jsonl`.

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

### auto-mode-shared-steps.sh

**Trigger**: PreToolUse (Bash) — sourced by `grouped-bash-guard`

Re-imposes a human checkpoint for shared-state/publishing actions when running under `permission_mode=auto`. Auto-mode's classifier guards against destructive/malicious actions but not against scope drift (`git push`, `gh pr create`, etc. get auto-approved). `permissions.ask` does not gate under auto-mode either, so this hook is the only deterministic checkpoint for these actions when auto-mode is on.

- Blocks (under `permission_mode=auto` only):
  - `git push` (any form — `-u`, `--tags`, `HEAD:branch`, etc.)
  - `gh pr {create,merge,close,comment,review,edit,reopen,ready}`
  - `gh issue {create,close,comment,edit,reopen,delete,transfer,pin,unpin,lock,unlock}`
  - `gh release {create,edit,delete,upload,download}`
  - `gh repo {create,delete,rename,archive,unarchive,edit,set-default,fork,sync,deploy-key}`
  - `gh secret {set,delete}` / `gh variable {set,delete}`
  - `gh workflow {run,enable,disable}`
  - `gh auth {login,logout,refresh,setup-git}` / `gh ssh-key add`
  - `gh api` (any — even reads authenticate as the user)
  - `curl`/`wget` to `api.github.com`
  - `curl`/`wget` with `Authorization: (token|Bearer|Basic)` header
- No-op when `permission_mode` is `default`, `acceptEdits`, `plan`, or empty
- Block reason instructs the model to stop and report; the user runs the command themselves or switches out of auto-mode
- Pairs with `permissions.ask` entries in `settings.json` for the same surface — `ask` covers interactive modes, this hook covers auto-mode

### block-credential-exfiltration.sh

**Trigger**: PreToolUse (Bash via dispatcher)

Blocks commands that carry credential-shaped tokens in their arguments — the inverse vector to `secrets-guard`. That hook blocks credential reads at-rest; this one blocks the in-flight payload (a token already in context being re-used as a literal in a new outbound command, e.g. `curl -H "Authorization: token ghp_..."`).

- Detects (prefix-anchored, against the raw command — quoted-string content included so `Authorization: "token ghp_..."` matches):
  - GitHub: `ghp_` (classic PAT), `github_pat_` (fine-grained), `gho_/ghu_/ghs_/ghr_` (OAuth/user-to-server/server-to-server/refresh)
  - GitLab: `glpat-`
  - Slack: `xox[baprs]-`
  - AWS: `AKIA...` (access key), `ASIA...` (temp key) — note: AWS's canned example `AKIAIOSFODNN7EXAMPLE` will block too
  - OpenAI: `sk-` (classic), `sk-proj-`
  - Anthropic: `sk-ant-`
  - Stripe: `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_`
  - Google: `AIza` API keys
- Bare-40-hex is intentionally excluded (false positives on git SHAs and base64 fragments)
- Block reason instructs the model not to paste tokens between commands; the user can run it themselves or allowlist in `settings.local.json`
- Position in dispatcher: after `auto_mode_shared_steps`, before `git_safety` — informative-reason precedence over downstream guards that wouldn't fire for this command anyway

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

Blocks Read on large JSON files and points at the `read-json` jq reference.

- Blocks: `.json` files larger than size threshold
- Allows: Common config files (package.json, tsconfig.json, etc.) and `*.config.json`
- Config: `JSON_SIZE_THRESHOLD_KB` env var (default: 50)
- Reason: Large JSON files are better queried with jq via Bash — the `read-json` skill (`.claude/skills/read-json/SKILL.md`) holds the shell-quoting and malformed-JSON recipes

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

### surface-lessons.sh

**Trigger**: PreToolUse (Bash|Read|Write|Edit)

Surfaces relevant active lessons as additionalContext based on tool context keywords.

- Extracts keywords from tool input (command text or file path)
- Matches against `tags.keywords` in `~/.claude/lessons.db`
- Injects up to 3 matching active lessons as non-blocking `additionalContext`
- Pure bash+sqlite3 — no Python overhead
- Includes basic plural handling (strips trailing 's' for matching)
- Silent exit if no lessons.db, no context, or no matches

### approve-safe-commands.sh

**Trigger**: PermissionRequest (Bash)

Auto-approves chained Bash commands when all subcommands match safe prefixes from settings.json permissions.

- Splits commands on `&&`, `||`, `;`, `|` (respects quotes)
- Checks each subcommand against hardcoded safe prefixes (ls, git status, make, etc.)
- All match → auto-approve via `permissionDecision: "allow"`
- Any don't match → stays silent (normal permission prompt shows)
- Bails on: subshells `$(...)`, backticks, redirects (`>`, `>>`, `<`)
- Validated by `.claude/scripts/validate-safe-commands-sync.sh` (runs in `make check`)

## Configuration

Hooks are configured in `.claude/settings.json`. See that file for the current hook registrations, matchers, and timeouts.

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

Hooks receive tool context as **JSON on stdin**, parsed by `hook_init()` in `lib/hook-utils.sh`. The JSON includes tool name, tool input, and session metadata.

Some hooks also read **environment variables** for configuration:
- `PROTECTED_BRANCHES` — regex for protected branches (default: `^(main|master)$`)
- `JSON_SIZE_THRESHOLD_KB` — size threshold for JSON blocking (default: 50)
