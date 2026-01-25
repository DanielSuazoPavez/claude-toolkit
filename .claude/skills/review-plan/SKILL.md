---
name: review-plan
description: Review a plan against quality criteria before approving. Use when presented with a plan in plan mode.
argument-hint: Path to plan file (optional, auto-detected from context)
---

## Your Task

Review the plan and provide structured feedback before the user decides to approve or request changes.

## Finding the Plan

1. If `$ARGUMENTS` contains a path, read that file
2. Otherwise, look for the plan path in recent conversation context (usually mentioned when exiting plan mode)
3. If still not found, check `~/.claude/plans/` for the most recently modified `.md` file

## Quality Criteria

Evaluate the plan against these criteria:

### Structure (must have)

| Element | Check |
|---------|-------|
| **Clear goal** | Is the objective stated upfront? |
| **Atomic steps** | Are steps small and independently verifiable? |
| **File list** | Are affected files explicitly listed? |
| **Verification** | Is there a way to confirm success? |

### Clarity (should have)

| Element | Check |
|---------|-------|
| **No ambiguity** | Are requirements specific enough to implement without guessing? |
| **Order/dependencies** | Is the sequence logical? Are dependencies clear? |
| **Scope boundaries** | Is it clear what's NOT included? |

### Pragmatism (watch for)

| Anti-pattern | Description |
|--------------|-------------|
| **Over-engineering** | Adding unnecessary abstractions, config, or flexibility |
| **Scope creep** | Steps that go beyond the original request |
| **Premature optimization** | Performance concerns before correctness |
| **Missing error paths** | Only happy path considered |

## Output Format

```markdown
# Plan Review

## Summary
[1-2 sentences: Is this plan ready to execute?]

## Checklist

### Structure
- [x] Clear goal stated
- [ ] Steps are atomic - *[issue: step 3 combines multiple changes]*
- [x] Files listed
- [ ] Verification defined - *[missing: no test plan]*

### Clarity
- [x] Requirements are specific
- [x] Order is logical
- [ ] Scope boundaries clear - *[unclear: does this include error handling?]*

### Pragmatism
- [x] No over-engineering
- [ ] Scope matches request - *[creep: step 5 adds logging not requested]*
- [x] No premature optimization

## Issues

### #1: [Issue title]
**Severity:** Major | Minor
**Location:** Step X / Section Y

[Description of what's wrong and why it matters]

**Suggestion:** [How to fix it]

## Verdict

**APPROVE** | **REVISE** | **RETHINK**

[1-2 sentences on recommended action]
```

## Verdicts

```
What's the state of this plan?
├─ Ready to implement as-is?
│   └─ APPROVE
├─ Good approach, but has specific fixable issues?
│   └─ REVISE (list the specific changes needed)
└─ Fundamental problems with the approach?
    └─ RETHINK (explain what's wrong and why)
```

| Verdict | When to Use | Examples |
|---------|-------------|----------|
| **APPROVE** | No blocking issues | Minor gaps OK if intent is clear |
| **REVISE** | Fixable issues | Missing error handling, unclear step |
| **RETHINK** | Wrong approach | Over-engineered, wrong abstraction level |

## Important

- Be pragmatic, not pedantic. Minor gaps are fine if the intent is clear.
- Flag only issues that would cause real problems during implementation.
- If the plan is good, say so briefly and approve.
