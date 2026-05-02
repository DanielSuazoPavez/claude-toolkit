---
category: 01-standardized
axis: inventory
status: drafted
date: 2026-05-02
---

# 01-standardized — inventory

Catalog of the 13 standardized hooks in `.claude/hooks/`: event(s) they fire on, libs they source, V20 budget vs current observed time, and a brief description of the check-body work.

**Convention** (from `00-shared/inventory.md`): "hot path" = sourced by every hook firing on PreToolUse(Bash/Read/Write/Edit), PostToolUse, PermissionRequest. "Warm path" = SessionStart, UserPromptSubmit, PermissionDenied, EnterPlanMode-only. "Floor" = lib parse + load cost before the hook's own check body runs.

All 13 hooks share the same shape: `source lib/hook-utils.sh` (transitively pulls `hook-logging.sh`) → optionally source `detection-registry.sh` and/or `settings-permissions.sh` → `hook_init NAME EVENT` → guard or check → `hook_block`/`hook_approve`/`hook_ask`/`hook_inject` (each ends in `exit 0`) or fall through to silent pass.

None of the 13 declare `PERF-BUDGET-MS`. All inherit the framework default `scope_miss=5, scope_hit=50` (validate.sh:fallback). V20 warnings below quote that default.

## Members

Listed in the order from `README.md`. Columns:

- **Event(s)** — the `EVENTS:` and `DISPATCHED-BY:` headers reduced to the events that actually fire this hook in real-session.
- **Libs sourced** — direct `source` calls in the hook file. Transitive `hook-logging.sh` (sourced by `hook-utils.sh`) is implicit and omitted.
- **Lib floor** — predicted from `00-shared/performance.md` "Predicted lib floor (p50)" table. Excludes `hook_init`'s ~4–5ms.
- **V20 (smoke)** — current `make check` V20 outcome. "ok" = within budget on the sampled run; "warn (Nms)" = total `duration_ms` from the smoke fixture. The bash+jq floor on this machine is 5ms; subtract it to get hook work. Numbers below are pass-fixture (scope_miss path) totals from a sample of two `make check` runs. **Variance is ~1.34× p95/p50** (`00-shared/performance.md`); hooks within ~1–2ms of the budget straddle the warn threshold across runs. `detect-session-start-truncation` warned at 6ms on one of the two sampled runs (~1ms hook work, mostly noise) — listed as borderline.
- **LoC** — file length, including header comments.

| Hook | Event(s) | Libs sourced | Lib floor | V20 (smoke) | LoC |
|------|----------|--------------|----------:|-------------|----:|
| `approve-safe-commands.sh` | PermissionRequest(Bash) | hook-utils + settings-permissions | ~11.4ms | ok (no PermissionRequest fixture warns today) | 202 |
| `auto-mode-shared-steps.sh` | dispatched by `grouped-bash-guard` (Bash) | hook-utils + detection-registry + settings-permissions | ~21ms first invocation; ~4.2ms when libs reused inside dispatcher | warn (13ms; ~8ms hook work) | 120 |
| `block-config-edits.sh` | PreToolUse(Write\|Edit); also dispatched by `grouped-bash-guard` (Bash) | hook-utils + detection-registry | ~12.3ms | ok | 339 |
| `block-credential-exfiltration.sh` | dispatched by `grouped-bash-guard` (Bash) | hook-utils + detection-registry | ~12.3ms first child, ~4.2ms reused | ok | 122 |
| `block-dangerous-commands.sh` | dispatched by `grouped-bash-guard` (Bash) | hook-utils only | ~2.5ms | ok | 141 |
| `detect-session-start-truncation.sh` | UserPromptSubmit | hook-utils only | ~2.5ms | borderline (6ms in one of two runs; ~1ms hook work) | 70 |
| `enforce-make-commands.sh` | dispatched by `grouped-bash-guard` (Bash) | hook-utils only | ~2.5ms | ok | 88 |
| `enforce-uv-run.sh` | dispatched by `grouped-bash-guard` (Bash) | hook-utils only | ~2.5ms | ok | 74 |
| `git-safety.sh` | PreToolUse(EnterPlanMode); also dispatched by `grouped-bash-guard` (Bash) | hook-utils only | ~2.5ms | ok | 217 |
| `log-permission-denied.sh` | PermissionDenied | hook-utils only | ~2.5ms | **warn (9ms; ~4ms hook work)** | 32 |
| `log-tool-uses.sh` | PostToolUse | hook-utils only | ~2.5ms | **warn (8ms; ~3ms hook work)** | 30 |
| `secrets-guard.sh` | PreToolUse(Grep); also dispatched by `grouped-bash-guard` (Bash) and `grouped-read-guard` (Read) | hook-utils + detection-registry | ~12.3ms | ok | 496 |
| `suggest-read-json.sh` | dispatched by `grouped-read-guard` (Read) | hook-utils only | ~2.5ms | ok | 103 |

## Per-hook check-body description

What each hook actually *does* once the libs are loaded and `hook_init` returns. This is the cost a perf measurement should isolate from the lib floor — `00-shared/performance.md` predicts the floor; `01-standardized/performance.md` will measure check-body cost by subtracting.

### approve-safe-commands.sh (202 LoC)

PermissionRequest(Bash) hook. Loads `settings-permissions.sh` (`_SETTINGS_PERMISSIONS_RE_ALLOW`/`_RE_ASK` regexes built once). Reads `tool_input.command`, splits on shell separators (`&&`, `||`, `;`, `|`), strips env-var prefixes from each subcommand, rejects on subshells/backticks/redirects, and tests every subcommand against the precompiled allow regex. If all match → `hook_approve`. Any miss → silent fall-through (the harness prompts the user as normal).

Pure-bash work after the `settings_permissions_load` jq fork — no extra forks in the check body.

### auto-mode-shared-steps.sh (120 LoC)

Dispatched by `grouped-bash-guard`. Loads both `detection-registry.sh` and `settings-permissions.sh` — the heaviest lib stack of any standardized hook. Gates on `permission_mode=auto`; for any other mode, the dispatch function returns 0 immediately (no work).

Under auto-mode, runs `_strip_inert_content` on `$COMMAND` (one bash call), then matches the stripped command against `permissions.ask` prefixes (for shared-state ops like `git push`, `gh pr create`) and against the `kind=publishing` registry. On match: `hook_block`. Otherwise: silent pass.

### block-config-edits.sh (339 LoC)

PreToolUse(Write|Edit) standalone, also dispatched by `grouped-bash-guard` for the Bash branch. Loads `detection-registry.sh`.

Two distinct check bodies:
- **Write|Edit branch** (standalone): match `tool_input.file_path` against a hardcoded list of shell configs, SSH files, and `.claude/settings*.json`. `hook_block` for the first two; `hook_ask` (or `hook_block` under auto-mode) for `.claude/settings*.json`.
- **Bash branch** (dispatched): pull command, run `_strip_inert_content`, match against `kind=path` registry entries (covers `> ~/.bashrc`, `cat > ~/.ssh/authorized_keys`, etc.). `hook_block` on hit.

### block-credential-exfiltration.sh (122 LoC)

Dispatched by `grouped-bash-guard`. Loads `detection-registry.sh`. Match function tests the **raw** command against `kind=credential, target=raw` registry entries (token literals, Authorization headers, `$VAR` refs to credential-shaped env vars). On hit: `hook_block`. No `_strip_inert_content` call — by design (a token literal inside a heredoc is still an exfiltration risk).

Sibling to `secrets-guard.sh`; the responsibility split is documented in both file headers (`block-credential-exfiltration` = "credential value/reference inside a command", `secrets-guard` = "command reaches towards a sensitive resource").

### block-dangerous-commands.sh (141 LoC)

Dispatched by `grouped-bash-guard`. No registry — uses inline regex literals for `rm -rf /`, `rm -rf ~`, `rm -rf .`, fork bombs (`:(){ :|:& };:`), `mkfs`, `dd of=/dev/sd*`, `chmod -R 777 /`. Pure-bash `=~` against the raw command. The shortest, fastest hook in the category — and the only Bash check that doesn't load detection-registry.

### detect-session-start-truncation.sh (70 LoC)

UserPromptSubmit. Fire-once-per-session: creates a marker file in `~/.claude/cache/` and returns immediately on subsequent prompts. On first run, reads the transcript file path from stdin, greps for the harness truncation marker (`<persisted-output>` + "Output too large" near a SessionStart attachment), and emits a loud `hook_inject` warning if found. Otherwise silent.

The marker-file fast path makes this ~0ms per prompt after the first; the cost is concentrated in the first invocation per session.

### enforce-make-commands.sh (88 LoC)

Dispatched by `grouped-bash-guard`. No registry. `match_make` is a cheap pure-bash predicate that returns 0 only if the command mentions `pytest`, `pre-commit`, `ruff`, `uv`, or `docker`. `check_make` matches more specific patterns (bare `pytest …` not via `make test`, etc.) and emits `hook_block` redirecting to the canonical `make` target. Pure-bash throughout.

### enforce-uv-run.sh (74 LoC)

Dispatched by `grouped-bash-guard`. Calls `_strip_inert_content` once to get the command skeleton, then checks if `python` appears in command-verb position outside an active virtualenv. `hook_block` on hit, recommending `uv run python`. Pure-bash apart from the strip call.

### git-safety.sh (217 LoC)

PreToolUse(EnterPlanMode) standalone, also dispatched by `grouped-bash-guard` for the Bash branch. No registry.

Two check bodies:
- **EnterPlanMode branch** (standalone): block plan mode on protected branches (regex from `CLAUDE_TOOLKIT_PROTECTED_BRANCHES`, default `^(main|master)$`); block on detached HEAD. Calls `git rev-parse` once.
- **Bash branch** (dispatched): match against unsafe git operations — `git commit` on protected branches, `git push --force` to protected, `git push origin :branch` (delete remote), `git reset --hard origin/...`. Calls `_strip_inert_content` for the heredoc-wrapped command shape, then pure-bash regex.

The EnterPlanMode check is the only standardized-hook code path that runs `git rev-parse` (a fork). Hot only when the model enters plan mode — rare enough that it doesn't dominate the budget.

### log-permission-denied.sh (32 LoC)

PermissionDenied. The smallest hook in the category. Sources `hook-utils.sh`, calls `hook_init` (skips `hook_require_tool` because it logs all tools), and exits. The `_hook_log_timing` EXIT trap installed by `hook_init` writes the JSONL row.

**Why it warns at V20 (9ms / ~4ms hook work)**: the work is entirely in `hook_init` + the EXIT trap (`jq -c` row build). It's a budget question, not an implementation question — the hook itself contains no logic. Same shape as `log-tool-uses.sh`.

### log-tool-uses.sh (30 LoC)

PostToolUse. Same shape as `log-permission-denied`. Sources hook-utils, calls `hook_init`, exits. EXIT trap writes the JSONL row.

**Why it warns at V20 (8ms / ~3ms hook work)**: identical reason to `log-permission-denied` — `hook_init` + one `jq -c` fork in the EXIT trap accounts for all of it. The smoke harness embeds the full stdin into the row, so the input size affects the jq cost. Budget vs implementation: same call as the other logger.

### secrets-guard.sh (496 LoC)

PreToolUse(Grep) standalone, also dispatched by both `grouped-bash-guard` (Bash) and `grouped-read-guard` (Read). Largest hook in the category. Loads `detection-registry.sh`.

Three check bodies:
- **Grep branch** (standalone): match `tool_input.pattern` and search-roots against credential-shaped patterns and sensitive paths.
- **Bash branch** (dispatched): match against `kind=path` registry entries (using both `raw` and `stripped` targets via `detection_registry_match_kind`); also inline policy for env-listing commands (`env`, `printenv`, `printenv VAR` for credential-shaped names), `cat ~/.aws/credentials`, etc.
- **Read branch** (dispatched): match `tool_input.file_path` against the same path registry plus the inline list of sensitive directories.

The size comes from the inline command-shape policy (env-listing, cred-shaped printenv targets) and the three branches sharing helpers. Sibling to `block-credential-exfiltration.sh` — same lib stack, complementary direction.

### suggest-read-json.sh (103 LoC)

Dispatched by `grouped-read-guard`. No registry. Reads `tool_input.file_path`, checks the suffix (`.json`), `stat`s the file size, blocks if above `CLAUDE_TOOLKIT_JSON_SIZE_THRESHOLD_KB` (default 50), with a known exclusion list (`package.json`, `tsconfig.json`, `.claude/settings.json`, etc.). One `stat` fork per Read.

## Cross-cutting observations

These observations are inventory-level — surfaced for the per-axis reports to dig into, not resolved here.

- **Five hooks load only `hook-utils.sh`** (block-dangerous-commands, detect-session-start-truncation, enforce-make-commands, enforce-uv-run, git-safety, log-tool-uses, log-permission-denied, suggest-read-json — eight if you count the loggers). Their lib floor is ~2.5ms; if they warn at V20, the budget is the question, not the libs.
- **Three hooks load `detection-registry.sh`** (block-config-edits, block-credential-exfiltration, secrets-guard) plus `auto-mode-shared-steps.sh` which loads it alongside `settings-permissions.sh`. All four are the lib's only callers. When all four fire as dispatcher children, the registry load deduplicates inside the dispatcher's single bash process — so the per-event lib floor differs from the per-hook floor (`02-dispatchers/inventory.md` to track).
- **Two hooks load `settings-permissions.sh`** (`approve-safe-commands` standalone on PermissionRequest; `auto-mode-shared-steps` as a dispatcher child). No deduplication opportunity — they fire on different events.
- **Both reliable V20 warnings in this category are loggers** (log-tool-uses, log-permission-denied — 8–10ms across sampled runs). Their hook work is ~3–5ms — entirely `hook_init` + the EXIT-trap `jq -c`. Implementation has nothing to compress; the budget at 5ms doesn't fit a logger that pays for `hook_init` + one jq fork. `detect-session-start-truncation.sh` straddles the 5ms budget too (warned at 6ms in one of two sampled runs) — same shape, same root cause. `01-standardized/performance.md` to recommend either raising the budget for `hook_init`-bound hooks or carving the EXIT-trap row build out of the per-hook duration.
- **`_strip_inert_content` is called by 5 hooks** (auto-mode-shared-steps, block-config-edits, enforce-uv-run, git-safety, secrets-guard). All call it on full command strings; none currently exercise `target=stripped` registry entries (registry is all `target=raw` per `00-shared/inventory.md`). Long heredocs would be the failure mode (~9ms for an 8KB body). `01-standardized/robustness.md` to test heredoc fixtures against these 5.
- **Only `git-safety` forks `git rev-parse`** in its check body (EnterPlanMode branch). Every other hook's check body is pure-bash — the forks all sit in lib loaders. This means real-session check-body cost will track input size and pure-bash regex complexity, not fork count.
- **The standalone-vs-dispatched dual-mode hooks** (block-config-edits, git-safety, secrets-guard) export `match_<name>` and `check_<name>` functions for the dispatcher to source. Code-shape implications are a `clarity.md` call — performance is unaffected because the dispatcher just sources the file (parse cost paid once per dispatcher invocation).

## Verified findings feeding downstream axes

### Performance

- **Two of seven V20 warnings on main belong to this category** (log-tool-uses 8ms, log-permission-denied 9ms; the others are session-context and dispatcher). Both are loggers with no check-body logic — every millisecond is `hook_init` + the EXIT-trap row. `00-shared/performance.md` already noted this as "the budgets, not the implementations, are the question." `01-standardized/performance.md` confirms with the same numbers under the new harness.
- **The five hook-utils-only hooks share a single ~2.5ms floor.** Variation between them at smoke time is check-body work, not lib cost. `01-standardized/performance.md` to publish per-hook check-body deltas.
- **Real-session vs smoke gap is largest for the loggers.** Smoke sandboxes `sessions.db` to a nonexistent path — `_resolve_project_id` takes the basename branch (no fork). Real-session pays ~4.6ms for the sqlite3 fork on every logger firing (`measurement/probe-results.md`). After the lazy-resolution experiment (`measurement/lazy-resolution-experiment.md`), this gap closed to ~0.2ms — but the experiment's not yet in main.

### Robustness

- **`_strip_inert_content` failure modes affect 5 hooks**, but none today rely on the `target=stripped` registry path. The function is parsed and called, but the fall-through to `target=stripped` matching is dead code in the current registry. New `target=stripped` entries would activate it. Robustness fixtures for these 5 hooks should include: long heredocs (>4KB body), nested quoted strings, mixed quote styles. Captured as the `hook-audit-00-malformed-stdin-fixtures` follow-up at the shared-lib level; specific fixtures live here.
- **`approve-safe-commands.sh` rejects subshells/backticks/redirects by design.** This is correct behavior — the precompiled allow regex can't validate the inner command of `$(…)`. Edge case to document in `robustness.md`: `echo "$(date)"` is rejected even though `date` is on the allow list.
- **`detect-session-start-truncation.sh` reads the transcript file path from stdin** without sanitizing it. The transcript path is harness-supplied (not model-supplied), so this is fine — but worth recording as an "input-trust assumption" in `robustness.md`.
- **`block-credential-exfiltration.sh` matches against the raw command string regardless of heredoc/quote wrapping.** Empirically verified (`robustness.md`): a token wrapped in `<<EOF … EOF` still matches because the regex is applied to `$COMMAND` literally — the heredoc syntax is just literal characters in the command string, not interpreted at match time. The hook header explicitly documents this ("Quoted-string content is included on purpose"). The earlier inventory hypothesis that heredoc-wrapped tokens would evade this hook was wrong — left in place above for transparency, corrected here.

### Testability

- **Each fixture forks a fresh bash process.** Confirmed at the lib level (`00-shared/testability.md`); the same constraint applies here. 13 hooks × N fixtures means 13×N bash forks per `make check`. The smoke harness runs in ~3–5s on this machine — bound by fork count, not check-body work.
- **No standardized hook today has more than one fixture under `tests/hooks/fixtures/<hook>/`.** That's V18-minimum coverage (one fixture per hook). The `hook-audit-00-shape-a-lib-tests` follow-up proposes a multi-case-per-fixture structure for the libs; the same shape applies here. `01-standardized/testability.md` to recommend per-hook fixture expansion (heredoc cases, edge inputs, dispatcher-child vs standalone divergence).
- **The `match_<name>`/`check_<name>` dual-mode functions in the three dual-mode hooks are testable in-process** when sourced into a parent bash that doesn't `exit` on `hook_block`. The dispatcher already does this. A test harness for `match`/`check` directly (without the dispatcher's source-children loop) would let us assert match-set behavior per case without paying the full bash fork. Captured for `testability.md`.

### Clarity

- **`secrets-guard.sh` at 496 LoC is the largest hook**, almost 4× the median. Three branches (Grep / Bash / Read) plus inline command-shape policy plus the registry-match wrappers. Splitting by branch is one option — but the three branches share the inline policy (env-listing, cred-shaped printenv), and splitting would duplicate it. `clarity.md` to evaluate.
- **`block-config-edits.sh` at 339 LoC** is the next-largest, also dual-mode (Write|Edit + Bash). Same tradeoff as secrets-guard — the two branches share the registry-match wrapper but apply different policies. `clarity.md` to evaluate.
- **The two loggers (log-tool-uses, log-permission-denied) at 30 and 32 LoC are mostly comments.** Their actual code is ~5 lines each — `source`, `hook_init`, `exit 0`. Whether this is a sign of a missing abstraction (a single `register-as-logger` helper) or correct minimum-viable code is a `clarity.md` call.
- **The dual-mode pattern** (`match_<name>`/`check_<name>` for dispatcher; standalone `main` for direct firing) is documented in `relevant-toolkit-hooks.md` and used by 3 hooks. Code shape is consistent across the 3 — the cost is one extra layer of indirection in each. `clarity.md` to evaluate against the alternative ("dispatcher children only, no standalone branch").

## Still-open questions (scope for downstream axes, not resolved here)

- **Performance:** under the new harness with the lazy-resolution patch applied, do the two logger warnings remain? (Falls to `01-standardized/performance.md`. Hypothesis: ~4ms drops to ~2ms, but still over the 5ms budget for outcome=pass — the budget itself is the binding constraint.)
- **Performance:** what's the per-hook check-body cost (total minus lib floor minus `hook_init`) for each of the 13 hooks? `00-shared/performance.md` published the floor; this category publishes the deltas.
- **Robustness:** which of the 5 `_strip_inert_content` callers (auto-mode-shared-steps, block-config-edits, enforce-uv-run, git-safety, secrets-guard) regress under malformed/long-heredoc inputs? (Falls to `01-standardized/robustness.md`.)
- **Testability:** is per-hook fixture expansion (multi-case per fixture file) a worthwhile project, or should we wait for the lib-level shape work first? (Falls to `01-standardized/testability.md`, blocked on `hook-audit-00-shape-a-lib-tests`.)
- **Clarity:** are the two large hooks (`secrets-guard`, `block-config-edits`) better split by branch, or is the shared inline policy load-bearing enough that splitting would duplicate it? (Falls to `01-standardized/clarity.md`.)
