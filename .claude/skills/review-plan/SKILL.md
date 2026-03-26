---
name: review-plan
description: Review a plan against quality criteria before approving. Use when requests mention "review plan", "check plan", "verify plan", or "approve plan".
argument-hint: Path to plan file (optional, auto-detected from context)
allowed-tools: Read, Glob
---

**See also:** `/brainstorm-idea` (when the plan reveals requirements are still unclear), `/wrap-up` (finalize branch after implementation), `code-reviewer` agent (post-implementation code review), `goal-verifier` agent (verify feature completeness), `implementation-checker` agent (compare implementation to plan)

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

### Project identity lens

If a `relevant-project-identity` memory exists in `.claude/memories/`, read it and use it as an additional evaluation lens. Check whether the plan aligns with the project's stated identity, scope boundaries, and core traits. Flag any steps that drift outside the project's declared boundaries.

## Step 2: Check Structure

### Is the goal clear?

```
Goal statement check:
├─ States the problem being solved? → Good
├─ States the desired end state? → Good
├─ Just says "implement X"? → Needs: why and what success looks like
└─ Missing entirely? → High
```

### Are steps commit-sized?

Each step should be a commit-able unit of work — small enough to verify, large enough to be meaningful. The plan must explicitly state that each step produces a commit.

```
Step granularity check:
├─ Could you commit this step alone and the code still works? → Good
├─ Can be verified in <5 minutes? → Good
├─ Touches >3 files? → Probably split
├─ Contains "and", "also", "then"? → Definitely split
├─ Uses vague verbs (handle, set up, implement)? → Needs specifics
├─ Could fail partially? → Split into success/failure paths
└─ Plan states "commit after each step"? → Required
```

### Does the plan include post-implementation steps?

Every plan must end with closing steps that verify and finalize the work. If missing, **add them to the plan before presenting the review**.

```
Post-implementation steps check:
├─ Implementation check (plans with 5+ steps only)?
│   └─ "Launch implementation-checker agent to compare implementation against the plan"
├─ Goal verification?
│   └─ "Launch goal-verifier agent to confirm the feature works (L1→L2→L3 verification)"
├─ Code review?
│   └─ "Launch code-reviewer agent to review changes on this branch"
└─ Wrap up?
    └─ "Run /wrap-up to update changelog, bump version, and finalize the branch"
```

**If any required post-implementation steps are missing, add them to the plan yourself before generating the review output.** Do not flag them as issues — just fix the plan. Note the additions in the review summary so the user sees what was added.

### Are files listed and valid?

```
File list check:
├─ Explicit list of files to modify? → Good
├─ "Update relevant files"? → Bad - which ones?
├─ New files clearly marked as new? → Good
├─ Deleted files explicitly noted? → Required for refactors
└─ Listed files actually exist? → Verify with Glob — code may have moved since the plan was written
```

### Is verification defined?

```
Verification check:
├─ "Run tests" with specific test file/command? → Good
├─ Just "run tests"? → Acceptable for small changes
├─ Manual verification steps for UI/UX? → Required if applicable
├─ No verification at all? → High for non-trivial plans
└─ For data changes: before/after comparison method? → Required
```

## Step 3: Check for Anti-Patterns

| Anti-Pattern | Signal | Default Severity | Fix |
|--------------|--------|-----------------|-----|
| **The Vague Step** | "Handle", "Set up", "Implement" with no specifics | Medium | List the specific edge cases |
| **Hidden Dependency** | Step N assumes Step M but doesn't say so | High | Reorder or make explicit |
| **The Kitchen Sink** | Step combines 3+ distinct operations | Medium | Split into separate steps |
| **The Wishful Step** | Assumes something works without verification | Medium | Add verification |
| **Wishful Delegation** | Expects the implementing agent to figure out gaps | High | Make implicit knowledge explicit in the plan |
| **Scope Creep** | Steps not traceable to original request | Low | Remove or get explicit approval |
| **Over-Engineering** | Abstractions for single use case | Medium | YAGNI - solve current problem only |
| **Missing Rollback** | No recovery path for risky operations | High | Add rollback step |
| **The Optimistic Plan** | Only happy path, no error handling | Medium | Add: "If API fails..." |

**Wishful Delegation** — Plans are instructions for an agent. Every step must be self-contained. If a step requires context not written in the plan (e.g., "update the tests accordingly", "handle edge cases", "adjust as needed"), the implementing agent will either guess wrong or skip it. The plan should carry the full cognitive load, not the executor.

## Step 4: Rate Issues and Determine Verdict

### Issue Severity Definitions

| Severity | Criteria | Examples |
|----------|----------|----------|
| **High** | Would cause incorrect implementation, data loss, or security risk if not fixed before execution | Missing rollback for migration; hidden dependency between steps; wishful delegation of critical logic |
| **Medium** | Would degrade plan quality or increase implementation risk, but unlikely to cause outright failure | Vague step that could be misinterpreted; kitchen sink step; missing verification for non-trivial change |
| **Low** | Cosmetic or minor improvement; implementation would likely succeed without fixing | Scope creep on a low-risk addition; step ordering preference; minor naming clarity |

**Severity calibration rule:** Consider the implementing agent's perspective. If an issue would force the agent to make assumptions or decisions not covered by the plan, raise severity by one level. The plan is the *only* context the executor has.

### Verdict Rules

The verdict is derived from the issue list. Issues set a **floor** — the approach assessment can raise the verdict (make it stricter) but never lower it below what the issues demand.

```
Verdict floor (from issues):
│
├─ Any High severity issue? → Floor is REVISE
│   └─ 3+ High severity issues? → Floor is RETHINK
│
├─ 2+ Medium severity issues? → Floor is REVISE
│   └─ Only 1 Medium, rest Low? → Floor is APPROVE
│
└─ Only Low severity issues? → Floor is APPROVE
```

```
Approach assessment (can only raise, never lower):
│
├─ Wrong abstraction level? → Raise to RETHINK
├─ Solving wrong problem? → Raise to RETHINK
├─ Missing critical consideration (security, data loss)? → Raise to RETHINK
└─ Over-engineered for the task? → Raise to RETHINK
```

**Self-check before finalizing verdict:** Re-read each issue. Does its severity match the definitions above? A verdict of APPROVE with any High issue, or RETHINK with only Low issues, signals a calibration error — fix the severities or the verdict.

| Verdict | Criteria | Action |
|---------|----------|--------|
| **APPROVE** | Only Low issues (or 1 Medium). Approach is sound. | Proceed with implementation |
| **REVISE** | High issues or multiple Medium issues, but approach is correct | List exact changes needed in the plan |
| **RETHINK** | 3+ High issues, or fundamental approach problems | Explain what's wrong and suggest alternative approach |

## Output Format

Use color and visual emphasis to make the review scannable at a glance:
- Verdicts: `APPROVE` in **bold green** (wrap in a blockquote with >), `REVISE` in **bold yellow**, `RETHINK` in **bold red**
- Severity labels: **High** in bold red, **Medium** in bold yellow, Low in regular text
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
- [ ] Steps are commit-sized — *step 3 combines multiple changes* → **Medium**
- [x] Files listed
- [ ] Verification defined — *missing: no test plan* → **Medium**

### Clarity
- [x] Requirements are specific
- [x] Order is logical
- [ ] Scope boundaries clear — *unclear: does this include error handling?* → **Medium**

### Pragmatism
- [x] No over-engineering
- [ ] Scope matches request — *creep: step 5 adds logging not requested* → Low
- [x] No premature optimization

---

## Issues

### **#1: [Issue title]**
**Severity:** **High** | **Location:** Step X | **Anti-pattern:** Hidden Dependency

[Description of what's wrong and why it matters. From the implementing agent's perspective: what would go wrong if they followed this plan as-is?]

> **Suggestion:** [Specific change to the plan — not "consider adding", but "add step 3a: ..."]

---

## Issue Summary

| Severity | Count |
|----------|-------|
| **High** | 0 |
| **Medium** | 3 |
| Low | 1 |

**Verdict floor from issues:** REVISE (2+ Medium)

---

## Verdict

> **REVISE** — [1-2 sentences. Reference the issue count that drove this verdict.]
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

## Before Presenting the Review

Before outputting the review to the user, ensure the plan has been updated:

1. **Commit cadence** — if the plan doesn't state "commit after each step", add it to the plan's preamble or first step.
2. **Post-implementation steps** — if any required closing steps are missing (see "Does the plan include post-implementation steps?" above), add them to the plan.

These are not suggestions — they are structural requirements. Fix the plan first, then present the review of the fixed version. Note any additions you made in the review summary.
