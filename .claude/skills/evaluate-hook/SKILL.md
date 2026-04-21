---
name: evaluate-hook
metadata: { type: knowledge }
description: Evaluate Claude Code hook quality. Use when reviewing, auditing, or improving hooks before deployment. Keywords: hook quality, hook review, evaluate hook, audit hook.
argument-hint: "[hook-name-or-path]"
compatibility: jq
allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)
---

# Hook Judge

Evaluate hook quality against hook-specific best practices.

## Contents

1. [When to Use](#when-to-use) - Triggers
2. [Core Philosophy](#core-philosophy) - What makes a good hook
3. [Evaluation Dimensions](#evaluation-dimensions-115-points) - 6-dimension rubric
4. [JSON Output Format](#json-output-format) - Required output structure
6. [Invocation](#invocation) - How to run evaluations
7. [Evaluation Protocol](#evaluation-protocol) - Step-by-step process
8. [Anti-Patterns](#anti-patterns) - Named failures with fixes
9. [Edge Cases](#edge-cases) - Scoring adjustments by hook type
10. [Example Evaluations](#example-evaluations) - Before/after worked examples

## When to Use

- Reviewing a hook before deployment
- Auditing existing hooks for quality
- Improving a hook that's causing issues

## Core Philosophy

**What is a Hook?** A safety/automation gate, not application logic.

**The Formula:** `Good Hook = Correct Behavior + Testable + Maintainable`

Hooks must be reliable (they guard critical operations), testable (stdin/stdout), and fail gracefully.

## Evaluation Dimensions (115 points)

### D1: Correctness (25 pts) - Most Critical

| Score | Criteria |
|-------|----------|
| 22-25 | Correct event, matcher, output format; handles edge cases; Bash PreToolUse hooks use match/check + dual-mode trigger |
| 17-21 | Mostly correct, minor edge case gaps, or monolithic shape where match/check would apply |
| 10-16 | Works for happy path, misses important cases |
| 0-9 | Wrong event type, broken output format, or logic errors |

**Check:**
- Right hook event? (PreToolUse for blocking, PostToolUse for reactions)
- Output format correct? (`hook_block` for blocks, empty for allow)
- Early exit for non-matching tools via `hook_require_tool`?
- **Bash PreToolUse hooks**: split into `match_<name>` (cheap predicate) + `check_<name>` (guard body) + `main` (standalone entry)? Dual-mode trigger `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` at the bottom?
- **Match/check false-negative risk**: is `match_` broad enough that it won't skip a case `check_` should catch? False positives are fine; false negatives are safety regressions.
- Source path uses `${BASH_SOURCE[0]}` (not `$0`), so the hook works both standalone and when sourced by the dispatcher?

### D2: Testability (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Can test via stdin/stdout, clear block/allow cases documented |
| 13-17 | Testable but test cases not documented |
| 7-12 | Hard to test (external dependencies, side effects) |
| 0-6 | Untestable (hardcoded paths, no clear inputs/outputs) |

**Check:**
- Can run `echo '{"tool_name":...}' | ./hook.sh` ?
- Are block and allow test cases obvious?

### D3: Safety & Robustness (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Handles errors gracefully, logs failures, false positives are rare or impossible |
| 13-17 | Handles jq/parse failures (won't crash), but no logging. Minor false-positive risk |
| 7-12 | No error handling — bad input causes silent pass-through or crash. No consideration of false positives |
| 0-6 | Crashes on bad input, blocks legitimate work |

**Check:**
- What happens if jq fails or input is malformed?
- Are false positives possible? If so, how are they mitigated?
- For blocking hooks: strictness is a feature, not a bug. Don't penalize for lack of allowlists — guardrails should be strict

**Safety-vs-UX tension:** The core hook design tradeoff. A secrets-guard hook that's too strict blocks `.env.example` commits (false positive noise). One that's too loose misses `.env.local` (security gap). Score based on how thoughtfully this tension is resolved — not just whether it works.

### D4: Maintainability (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Sources shared library, uses standardized outcome helpers; clear structure, patterns in arrays/variables, easy to extend |
| 13-17 | Sources shared library but patterns are inline rather than in variables. Extending requires editing logic |
| 7-12 | Manual stdin parsing and raw JSON output instead of shared library. Deeply nested conditionals or magic values |
| 0-6 | Spaghetti logic, magic values everywhere, no library usage |

**Check:**
- Sources `lib/hook-utils.sh`? Uses `hook_init`/`hook_require_tool`/`hook_block` instead of manual boilerplate?
- Uses `$HOME` or env vars instead of hardcoded paths?
- Logic easy to extend with new patterns?
- Patterns in arrays/variables rather than scattered through logic?
- **Match cheapness contract (Bash PreToolUse)**: `match_<name>` uses only bash pattern matching — no `$(...)` subshells, no `jq`, no `git`, no file I/O, no DB reads. Violating this defeats the dispatcher's work-avoidance.
- **`_BLOCK_REASON` convention**: `check_<name>` sets `_BLOCK_REASON` before returning 1 (not a different variable name, not inline `hook_block` — the dispatcher reads `_BLOCK_REASON`).
- **No duplicated logic**: if the hook is registered in the dispatcher, its `check_` body is the only copy of that guard — not also inlined into the dispatcher.

**Performance note:** Hooks run synchronously on every matched tool call. A hook that spawns subprocesses, does network calls, or reads large files adds latency to every action. Penalize unnecessary complexity that slows the feedback loop. The match/check split exists precisely so expensive work happens only when the cheap predicate says it's worth it.

### D5: Documentation (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Purpose clear, test commands documented, settings.json example |
| 9-12 | Purpose clear, minimal docs |
| 4-8 | Unclear what it does or how to configure |
| 0-3 | No documentation |

### D6: Integration Quality (15 pts)
Does it work well within the resource ecosystem?

| Score | Criteria |
|-------|----------|
| 13-15 | Seamless integration — correct references, no conflicts, follows conventions, sources shared library |
| 10-12 | References exist and are correct, minor overlap or missed connections |
| 6-9 | Some conflicts with other hooks, doesn't follow toolkit patterns |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | Conflicts with other hooks, contradicts conventions |

**Check:**
- **Reference accuracy** — points to settings patterns and hook APIs that exist
- **Non-interference** — doesn't conflict with other hooks on same event
- **Ecosystem awareness** — knows what other hooks exist and avoids overlap
- **Convention alignment** — follows toolkit hook patterns (naming, output format)
- **Shared library** — sources `lib/hook-utils.sh` for standardized instrumentation
- **Terminology consistency** — uses same terms as hook documentation

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "score": <total>,
  "max": 115,
  "percentage": <score/max * 100>,
  "dimensions": {
    "D1": <score>, "D2": <score>, "D3": <score>, "D4": <score>, "D5": <score>, "D6": <score>
  },
  "top_improvements": ["...", "...", "..."]
}
```

Compute file_hash with: `md5sum <hook-file> | cut -c1-8`

## Invocation

**Launch a subagent** for fresh, unbiased evaluation.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the hook at <path> using the evaluate-hook rubric.
    Read .claude/skills/evaluate-hook/SKILL.md for the full rubric.

    Perform FRESH scoring. Do NOT read evaluations.json or prior scores.

    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from prior evaluations.

## Evaluation Protocol

1. Identify hook event and matcher
2. Verify output format matches spec
3. Check for early exit on non-matching tools
4. Look for error handling and allowlists
5. Verify testability via stdin/stdout
6. Score each dimension with evidence
7. Generate report with JSON output including file_hash and top 3 improvements
8. Update `docs/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.hooks.resources["<name>"] = $result' docs/indexes/evaluations.json > tmp && mv tmp docs/indexes/evaluations.json
   ```

## Anti-Patterns

| Pattern | Problem | Fix | Score Impact |
|---------|---------|-----|--------------|
| **Manual boilerplate** | Duplicates stdin parsing, JSON output, no instrumentation | Source `lib/hook-utils.sh`, use `hook_init`/`hook_block`/etc. | D4: -5, D6: -5 |
| **Wrong output format** | Hook doesn't block when it should | Use `hook_block` for PreToolUse, empty output for allow | D1: -15 |
| **No early exit** | Processes every tool, wastes cycles | Use `hook_require_tool` — exits 0 if no match | D1: -5, D4: -5 |
| **Silent failures** | Errors go unnoticed | Log to `~/.claude/hooks-logs/`, handle jq errors | D3: -10 |
| **Hardcoded paths** | Breaks on other machines | Use `$HOME`, `$CLAUDE_PROJECT_DIR`, or relative paths | D4: -10 |
| **No allowlist** | Blocks legitimate work | Add explicit safe-pattern exceptions (e.g., `.env.example`) | D3: -8 |
| **Untestable** | Can't verify behavior | Design for stdin/stdout, document test cases | D2: -15 |
| **Env var bypass** | Defeats the hook's purpose | Remove `ALLOW_*` overrides; user can run commands directly if needed | D3: -5 |
| **Broad matcher** | Hooks fire on unrelated tools | Use specific matcher (`"Bash"`) not `"*"` | D1: -5, D4: -5 |
| **Forks in `match_`** | Defeats dispatcher work-avoidance — the whole point of `match_` is to be free | Move `$(...)`/`jq`/`git` calls into `check_`; keep `match_` to bash pattern matching | D4: -8 |
| **`match_` narrower than `check_` triggers** | False negatives — `match_` returns false, `check_` never runs, guard silently misses cases | Broaden `match_` until it's a strict superset of what `check_` catches. False positives are fine; false negatives are safety bugs | D1: -10, D3: -8 |
| **Missing dual-mode trigger** | Sourced file runs its own `main` during dispatcher load, breaking everything | Add `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` at the bottom | D1: -10 |
| **`$(dirname "$0")` for source path** | When sourced by the dispatcher, `$0` is the dispatcher — the hook sources the wrong file or fails | Use `$(dirname "${BASH_SOURCE[0]}")` instead | D1: -5 |
| **Dual registration** | Hook in both standalone settings.json AND dispatcher's `CHECK_SPECS` — runs twice per call | Pick one: standalone or grouped. Never both | D1: -8 |
| **Inline `hook_block` in `check_`** | `check_` exits before the dispatcher can record the substep outcome; breaks dispatcher contract | Set `_BLOCK_REASON` and `return 1`; let `main`/dispatcher call `hook_block` | D1: -8, D4: -5 |
| **Monolithic Bash PreToolUse hook** | Works standalone but can't be folded into the dispatcher — misses amortization and drift-detection | Refactor into `match_<name>` + `check_<name>` + `main` + dual-mode trigger | D1: -5, D4: -5 |

## Edge Cases

| Hook Type | Scoring Adjustment |
|-----------|-------------------|
| **Logging-only** | D1 lower bar (no blocking logic), D2/D5 still matter |
| **Simple passthrough** | Minimal is fine if purpose is clear |
| **Multi-tool** | Higher D4 bar (must handle all matched tools) |
| **Notification/SessionStart** | `hook_require_tool` not applicable — use `hook_init` only, tool matching done manually or not needed |
| **Non-Bash PreToolUse** (Read, Grep, Write, Edit, EnterPlanMode) | Match/check + dispatcher not required — only Bash is grouped today. Don't penalize D1/D4 for a monolithic shape here. A hook with both Bash and non-Bash branches (e.g., `git-safety` on `EnterPlanMode|Bash`) should still use match/check for the Bash branch and keep the non-Bash branch in `main`. |
| **Match/check hook** | Evaluate `match_` against the cheapness contract (bash patterns only, no forks/jq/git). Evaluate `check_` against the usual D3 guard criteria (allowlists, false-positive handling). Verify dual-mode trigger exists and source path uses `${BASH_SOURCE[0]}`. |

## See Also

- `/evaluate-skill` — Sibling evaluator for skills (knowledge delta rubric).
- `/evaluate-agent` — Sibling evaluator for agents (behavioral effectiveness rubric).
- `/evaluate-docs` — Sibling evaluator for doc files (convention compliance).
- `/evaluate-batch` — Run evaluations across multiple resources of one type.
- `/create-hook` — Hook creation workflow that feeds into this evaluator.
- `.claude/docs/relevant-toolkit-hooks.md` — Match/check pattern + dispatcher contract. Read before scoring any Bash PreToolUse hook.

## Example Evaluations

### Good Hook (78.3%)

**Hook:** `enforce-make-commands.sh` (blocks direct pytest/ruff, suggests make targets)

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Correctness | 22/25 | Right event (PreToolUse), correct output format, early exit for non-Bash |
| D2: Testability | 16/20 | Testable via stdin, but no documented test cases |
| D3: Safety | 15/20 | Handles jq failures, but no allowlist for safe exceptions |
| D4: Maintainability | 17/20 | Clear structure, but patterns are inline rather than configurable |
| D5: Documentation | 10/15 | Purpose clear from comments, no settings.json example |
| D6: Integration | 10/15 | Follows toolkit hook patterns, no conflicts with other hooks |

**Total: 90/115 (78.3%)**

### Before/After: 15.7% → 75.7%

**First attempt** of a secrets-guard hook — blocks commits containing secrets:

```bash
#!/bin/bash
# block secrets
cat | grep -q "password\|secret\|key" && echo "blocked" && exit 1
```

| Dimension | Score | Why |
|-----------|-------|-----|
| D1 | 5/25 | Wrong output format (plain text, exit 1), no tool_name check, matches on ANY tool |
| D2 | 3/20 | No stdin JSON parsing, can't test specific tools |
| D3 | 2/20 | False positives on "key" in variable names, crashes on empty input |
| D4 | 4/20 | Single line, no structure, unmaintainable patterns |
| D5 | 2/15 | One comment, no test cases or config |
| D6 | 2/15 | Ignores toolkit patterns entirely |
| **Total** | **18/115 (15.7%)** | |

**After iteration:**

```bash
#!/bin/bash
# PreToolUse hook: block secrets in Bash commands and Write content
#
# Test cases:
#   echo '{"tool_name":"Bash","tool_input":{"command":"export AWS_SECRET=abc123"}}' | bash secrets-check.sh
#   # Expected: {"decision":"block","reason":"Potential secret detected..."}

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-utils.sh"
hook_init "secrets-check" "PreToolUse"
hook_require_tool "Bash" "Write"

CONTENT=$(hook_get_input '.tool_input.command')
[ -z "$CONTENT" ] && CONTENT=$(hook_get_input '.tool_input.content')

SAFE_PATTERNS=(".env.example" "secret_key_base" "test_secret")
for safe in "${SAFE_PATTERNS[@]}"; do
    CONTENT=$(echo "$CONTENT" | grep -v "$safe")
done

SECRETS_RE='(AWS_SECRET|PRIVATE_KEY|password\s*=\s*["\x27][^"\x27]+)'
if echo "$CONTENT" | grep -qP "$SECRETS_RE"; then
    hook_block "Potential secret detected. Review content before proceeding."
fi
exit 0
```

| Dimension | Score | Why |
|-----------|-------|-----|
| D1 | 20/25 | Correct output via `hook_block`, early exit via `hook_require_tool`, matches Bash+Write |
| D2 | 16/20 | Testable via stdin, test cases documented in header |
| D3 | 14/20 | Allowlist for safe patterns, targeted regex reduces false positives |
| D4 | 17/20 | Sources shared library, patterns in variables, easy to extend arrays |
| D5 | 10/15 | Purpose clear, test cases documented, no settings.json example |
| D6 | 10/15 | Follows toolkit conventions, sources shared library |
| **Total** | **87/115 (75.7%)** | |

**Key fixes:** Sourced shared library, `hook_block` instead of raw output, `hook_require_tool` for early exit, allowlist array, targeted regex instead of broad keyword match.
