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

## Evaluation Dimensions (115 points)

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
| 18-20 | Handles errors gracefully, logs failures, false positives are rare or impossible |
| 13-17 | Handles jq/parse failures (won't crash), but no logging. Minor false-positive risk |
| 7-12 | No error handling — bad input causes silent pass-through or crash. No consideration of false positives |
| 0-6 | Crashes on bad input, blocks legitimate work |

**Check:**
- What happens if jq fails or input is malformed?
- Are false positives possible? If so, how are they mitigated?
- For blocking hooks: strictness is a feature, not a bug. Don't penalize for lack of allowlists — guardrails should be strict

### D4: Maintainability (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Clear structure, patterns in arrays/variables, easy to extend |
| 13-17 | Logic is readable and sequential, but patterns are inline rather than in variables. Extending requires editing logic |
| 7-12 | Deeply nested conditionals, mixed concerns, or magic values that require tracing to understand |
| 0-6 | Spaghetti logic, magic values everywhere |

**Check:**
- Uses `$HOME` or env vars instead of hardcoded paths?
- Logic easy to extend with new patterns?
- Patterns in arrays/variables rather than scattered through logic?

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
| 13-15 | Seamless integration — correct references, no conflicts, follows conventions |
| 10-12 | References exist and are correct, minor overlap or missed connections |
| 6-9 | Some conflicts with other hooks, doesn't follow toolkit patterns |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | Conflicts with other hooks, contradicts conventions |

**Check:**
- **Reference accuracy** — points to settings patterns and hook APIs that exist
- **Non-interference** — doesn't conflict with other hooks on same event
- **Ecosystem awareness** — knows what other hooks exist and avoids overlap
- **Convention alignment** — follows toolkit hook patterns (naming, output format)
- **Terminology consistency** — uses same terms as hook documentation

## Grading Scale

| Grade | Score | Description |
|-------|-------|-------------|
| A | 103+ | Production-ready |
| B | 86-102 | Good, minor improvements needed |
| C | 69-85 | Functional but notable gaps |
| D | 46-68 | Significant issues |
| F | <46 | Not safe to deploy |

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "grade": "A/B/C/D/F",
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
8. Update `.claude/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.hooks.resources["<name>"] = $result' .claude/indexes/evaluations.json > tmp && mv tmp .claude/indexes/evaluations.json
   ```

## Anti-Patterns

| Pattern | Problem | Score Impact |
|---------|---------|--------------|
| **Wrong output format** | Hook doesn't block when it should | D1: -15 |
| **No early exit** | Processes every tool, wastes cycles | D1: -5, D4: -5 |
| **Silent failures** | Errors go unnoticed | D3: -10 |
| **Hardcoded paths** | Breaks on other machines | D4: -10 |
| **No allowlist** | Blocks legitimate work | D3: -8 |
| **Untestable** | Can't verify behavior | D2: -15 |
| **Env var bypass** | Defeats the hook's purpose; user can just run the command directly if needed | D3: -5 |

## Edge Cases

| Hook Type | Scoring Adjustment |
|-----------|-------------------|
| **Logging-only** | D1 lower bar (no blocking logic), D2/D5 still matter |
| **Simple passthrough** | Minimal is fine if purpose is clear |
| **Multi-tool** | Higher D4 bar (must handle all matched tools) |

## See Also

- `/evaluate-skill` — Sibling evaluator for skills (knowledge delta rubric).
- `/evaluate-agent` — Sibling evaluator for agents (behavioral effectiveness rubric).
- `/evaluate-memory` — Sibling evaluator for memory files (convention compliance).
- `/evaluate-batch` — Run evaluations across multiple resources of one type.
- `/create-hook` — Hook creation workflow that feeds into this evaluator.

## Example Evaluation

**Hook:** `enforce-make-commands.sh` (blocks direct pytest/ruff, suggests make targets)

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Correctness | 22/25 | Right event (PreToolUse), correct output format, early exit for non-Bash |
| D2: Testability | 16/20 | Testable via stdin, but no documented test cases |
| D3: Safety | 15/20 | Handles jq failures, but no allowlist for safe exceptions |
| D4: Maintainability | 17/20 | Clear structure, but patterns are inline rather than configurable |
| D5: Documentation | 10/15 | Purpose clear from comments, no settings.json example |
| D6: Integration | 10/15 | Follows toolkit hook patterns, no conflicts with other hooks |

**Total: 90/115 - Grade B**

**Top improvements:** Add allowlist for safe exceptions, document test cases, add settings.json example.
