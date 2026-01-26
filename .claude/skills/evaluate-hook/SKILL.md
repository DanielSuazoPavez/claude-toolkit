---
name: evaluate-hook
description: Evaluate Claude Code hook quality. Use when reviewing, auditing, or improving hooks before deployment.
---

# Hook Judge

Evaluate hook quality against hook-specific best practices.

## When to Use

- Reviewing a hook before deployment
- Auditing existing hooks for quality
- Improving a hook that's causing issues

## Core Philosophy

**What is a Hook?** A safety/automation gate, not application logic.

**The Formula:** `Good Hook = Correct Behavior + Testable + Maintainable`

Hooks must be reliable (they guard critical operations), testable (stdin/stdout), and fail gracefully.

## Evaluation Dimensions (100 points)

### D1: Correctness (25 pts) - Most Critical

| Score | Criteria |
|-------|----------|
| 22-25 | Correct event, matcher, output format; handles edge cases |
| 17-21 | Mostly correct, minor edge case gaps |
| 10-16 | Works for happy path, misses important cases |
| 0-9 | Wrong event type, broken output format, or logic errors |

**Check:**
- Right hook event? (PreToolUse for blocking, PostToolUse for reactions)
- Output format correct? (`{"decision":"block","reason":"..."}` or empty)
- Early exit for non-matching tools?

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
| 18-20 | Handles errors gracefully, logs failures, has allowlist |
| 13-17 | Basic error handling, some edge cases covered |
| 7-12 | Fails silently on errors, no allowlist |
| 0-6 | Crashes on bad input, blocks legitimate work |

**Check:**
- What happens if jq fails or input is malformed?
- Does it have an allowlist for safe exceptions?
- Is it overly strict (blocks legitimate operations)?

### D4: Maintainability (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Clear structure, configurable (safety levels), no hardcoded paths |
| 13-17 | Readable but some hardcoding |
| 7-12 | Works but hard to modify |
| 0-6 | Spaghetti logic, magic values everywhere |

**Check:**
- Uses `$HOME` or env vars instead of hardcoded paths?
- Safety level configurable via single constant?
- Logic easy to extend with new patterns?

### D5: Documentation (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Purpose clear, test commands documented, settings.json example |
| 9-12 | Purpose clear, minimal docs |
| 4-8 | Unclear what it does or how to configure |
| 0-3 | No documentation |

## Grading Scale

| Grade | Score | Description |
|-------|-------|-------------|
| A | 90+ | Production-ready |
| B | 75-89 | Good, minor improvements needed |
| C | 60-74 | Functional but notable gaps |
| D | 40-59 | Significant issues |
| F | <40 | Not safe to deploy |

## Evaluation Protocol

1. Identify hook event and matcher
2. Verify output format matches spec
3. Check for early exit on non-matching tools
4. Look for error handling and allowlists
5. Verify testability via stdin/stdout
6. Score each dimension with evidence
7. Generate report with grade and top 3 improvements

## Anti-Patterns

| Pattern | Problem | Score Impact |
|---------|---------|--------------|
| **Wrong output format** | Hook doesn't block when it should | D1: -15 |
| **No early exit** | Processes every tool, wastes cycles | D1: -5, D4: -5 |
| **Silent failures** | Errors go unnoticed | D3: -10 |
| **Hardcoded paths** | Breaks on other machines | D4: -10 |
| **No allowlist** | Blocks legitimate work | D3: -8 |
| **Untestable** | Can't verify behavior | D2: -15 |

## Edge Cases

| Hook Type | Scoring Adjustment |
|-----------|-------------------|
| **Logging-only** | D1 lower bar (no blocking logic), D2/D5 still matter |
| **Simple passthrough** | Minimal is fine if purpose is clear |
| **Multi-tool** | Higher D4 bar (must handle all matched tools) |

## Example Evaluation

**Hook:** `enforce-make-commands.sh` (blocks direct pytest/ruff, suggests make targets)

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Correctness | 22/25 | Right event (PreToolUse), correct output format, early exit for non-Bash |
| D2: Testability | 16/20 | Testable via stdin, but no documented test cases |
| D3: Safety | 15/20 | No error handling if jq fails, no allowlist |
| D4: Maintainability | 17/20 | Clear structure, but patterns could be configurable |
| D5: Documentation | 10/15 | Purpose clear from comments, no settings.json example |

**Total: 80/100 - Grade B**

**Top improvements:** Add jq error handling, document test cases, add settings.json example.
