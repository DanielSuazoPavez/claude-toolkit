---
name: review-plan
description: Review a plan against quality criteria before approving. Use when requests mention "review plan", "check plan", "verify plan", or "approve plan".
argument-hint: Path to plan file (optional, auto-detected from context)
---

## Your Task

Review the plan and provide structured feedback before the user decides to approve or request changes.

## Finding the Plan

1. If `$ARGUMENTS` contains a path, read that file
2. Otherwise, look for the plan path in recent conversation context (usually mentioned when exiting plan mode)
3. If still not found, check `~/.claude/plans/` for the most recently modified `.md` file

## Step 1: Identify Plan Type and Calibrate

First, determine what kind of plan this is:

| Plan Type | Strictness | Primary Focus |
|-----------|------------|---------------|
| Bug fix | Low | Root cause identified? Regression test? |
| New feature | Medium | Scope boundaries? Integration points? |
| Refactor | High | Behavior preservation? Incremental steps? |
| Data migration | Very High | Backup strategy? Verification? Rollback? |
| Security fix | Very High | Attack surface? Timing? Disclosure? |
| Infrastructure | High | Rollback? Monitoring? Blast radius? |

**Calibration rule:** Match review depth to plan risk. A 3-step bug fix doesn't need the same scrutiny as a database migration.

## Step 2: Check Structure

### Is the goal clear?

```
Goal statement check:
├─ States the problem being solved? → Good
├─ States the desired end state? → Good
├─ Just says "implement X"? → Needs: why and what success looks like
└─ Missing entirely? → Major issue
```

### Are steps atomic enough?

```
Atomicity check for each step:
├─ Can be verified in <5 minutes? → Atomic
├─ Touches >3 files? → Probably split
├─ Contains "and", "also", "then"? → Definitely split
├─ Uses vague verbs (handle, set up, implement)? → Needs specifics
└─ Could fail partially? → Split into success/failure paths
```

### Are files listed?

```
File list check:
├─ Explicit list of files to modify? → Good
├─ "Update relevant files"? → Bad - which ones?
├─ New files clearly marked as new? → Good
└─ Deleted files explicitly noted? → Required for refactors
```

### Is verification defined?

```
Verification check:
├─ "Run tests" with specific test file/command? → Good
├─ Just "run tests"? → Acceptable for small changes
├─ Manual verification steps for UI/UX? → Required if applicable
├─ No verification at all? → Major issue for non-trivial plans
└─ For data changes: before/after comparison method? → Required
```

## Step 3: Check for Anti-Patterns

| Anti-Pattern | Signal | Example | Fix |
|--------------|--------|---------|-----|
| **The Vague Step** | "Handle", "Set up", "Implement" with no specifics | "Handle edge cases" | List the specific edge cases |
| **Hidden Dependency** | Step N assumes Step M but doesn't say so | "Update config" listed after "Deploy" | Reorder or make explicit |
| **The Kitchen Sink** | Step combines 3+ distinct operations | "Refactor auth, add logging, update tests" | Split into separate steps |
| **The Wishful Step** | Assumes something works without verification | "This should just work" | Add verification |
| **Scope Creep** | Steps not traceable to original request | "While we're here, let's also..." | Remove or get explicit approval |
| **Over-Engineering** | Abstractions for single use case | "Create generic handler for future..." | YAGNI - solve current problem only |
| **Missing Rollback** | No recovery path for risky operations | Database schema change with no down migration | Add rollback step |
| **The Optimistic Plan** | Only happy path, no error handling | "Call API and process response" | Add: "If API fails..." |

## Step 4: Determine Verdict

```
Verdict decision tree:
│
├─ Are there fundamental approach problems?
│   ├─ Wrong abstraction level? → RETHINK
│   ├─ Solving wrong problem? → RETHINK
│   ├─ Missing critical consideration (security, data loss)? → RETHINK
│   └─ Over-engineered for the task? → RETHINK
│
├─ Are there specific fixable issues?
│   ├─ Vague steps that need specifics? → REVISE
│   ├─ Missing verification? → REVISE
│   ├─ Order/dependency problems? → REVISE
│   └─ Scope creep that should be removed? → REVISE
│
└─ Is intent clear and approach sound?
    ├─ Minor gaps but implementation path is obvious? → APPROVE
    └─ No issues found? → APPROVE
```

| Verdict | Criteria | Action |
|---------|----------|--------|
| **APPROVE** | Sound approach, intent clear, any gaps are minor | Proceed with implementation |
| **REVISE** | Good approach but specific issues need fixing | List exact changes needed |
| **RETHINK** | Fundamental problems with approach | Explain what's wrong and why |

## Output Format

Use color and visual emphasis to make the review scannable at a glance:
- Verdicts: `APPROVE` in **bold green** (wrap in a blockquote with >), `REVISE` in **bold yellow**, `RETHINK` in **bold red**
- Severity labels: **Major** in bold, Minor in regular text
- Use horizontal rules (`---`) to separate major sections
- Use blockquotes (`>`) for the summary and verdict sections to make them stand out

```markdown
# Plan Review

**Plan type:** Bug fix | **Calibrated strictness:** Low

---

> **Summary:** [1-2 sentences: Is this plan ready to execute?]

---

## Checklist

### Structure
- [x] Clear goal stated
- [ ] Steps are atomic — *step 3 combines multiple changes*
- [x] Files listed
- [ ] Verification defined — *missing: no test plan*

### Clarity
- [x] Requirements are specific
- [x] Order is logical
- [ ] Scope boundaries clear — *unclear: does this include error handling?*

### Pragmatism
- [x] No over-engineering
- [ ] Scope matches request — *creep: step 5 adds logging not requested*
- [x] No premature optimization

---

## Issues

### **#1: [Issue title]**
**Severity:** **Major** | **Location:** Step X | **Anti-pattern:** The Kitchen Sink

[Description of what's wrong and why it matters]

> **Suggestion:** [How to fix it]

---

## Verdict

> **APPROVE** — [1-2 sentences on recommended action]
```

## Calibration Guidance

**Be stricter when:**
- Plan involves data loss risk (migrations, deletions)
- Plan touches security-sensitive code
- Plan affects production systems
- Plan has no rollback path

**Be more lenient when:**
- Plan is for a quick bug fix with obvious solution
- Plan is exploratory/prototype work
- User has indicated time pressure
- Changes are easily reversible

**Always flag regardless of strictness:**
- Missing verification for non-trivial changes
- Hidden dependencies between steps
- Security implications not addressed
