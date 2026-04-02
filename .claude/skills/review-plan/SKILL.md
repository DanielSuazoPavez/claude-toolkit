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

If a `relevant-project-identity` doc exists in `.claude/docs/`, read it and use it as an additional evaluation lens. Check whether the plan aligns with the project's stated identity, scope boundaries, and core traits. Flag any steps that drift outside the project's declared boundaries.

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

### Does the plan include final steps?

The last steps of every plan should include review and finalization. These are the **last numbered steps** in the plan — not a separate "post-implementation" phase.

Which final steps are needed depends on plan complexity:

```
Final steps (tiered by complexity):
│
├─ Always required:
│   ├─ "Launch code-reviewer agent to review changes on this branch"
│   └─ "Run /wrap-up to update changelog, bump version, and finalize the branch"
│
├─ Medium+ complexity plans (multi-step features, refactors, integrations):
│   └─ "Launch goal-verifier agent to confirm the feature works (L1→L2→L3 verification)"
│
└─ Detailed plans with strict step-by-step requirements (migrations, infrastructure):
    └─ "Launch implementation-checker agent to compare implementation against the plan"
```

**Token budget context:** implementation-checker and goal-verifier are expensive agents. Don't require them for simple plans where code-reviewer covers the risk. Reserve implementation-checker for plans where step ordering and completeness genuinely matter.

If final steps are missing, flag it as an issue in the review — do not silently fix the plan.

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
| **The Vague Step** | "Handle", "Set up", "Implement" with no specifics | **Medium–High** | List the specific actions, files, and edge cases |
| **Hidden Dependency** | Step N assumes Step M but doesn't say so | High | Reorder or make explicit |
| **The Kitchen Sink** | Step combines 3+ distinct operations | Medium | Split into separate steps |
| **The Wishful Step** | Assumes something works without verification | Medium | Add verification |
| **Wishful Delegation** | Expects the implementing agent to figure out gaps | High | Make implicit knowledge explicit in the plan |
| **Scope Creep** | Steps not traceable to original request | Low | Remove or get explicit approval |
| **Over-Engineering** | Abstractions for single use case | Medium | YAGNI - solve current problem only |
| **Missing Rollback** | No recovery path for risky operations | High | Add rollback step |
| **The Optimistic Plan** | Only happy path, no error handling | Medium | Add: "If API fails..." |

**Wishful Delegation** — Plans are instructions for an agent. Every step must be self-contained. If a step requires context not written in the plan (e.g., "update the tests accordingly", "handle edge cases", "adjust as needed"), the implementing agent will either guess wrong or skip it. The plan should carry the full cognitive load, not the executor.

**How to spot delegation gaps:** For each step, ask: "If I handed this step to someone with no context beyond this plan, would they know exactly what to do?" If the answer is "they'd figure it out" — that's a gap. The implementing agent doesn't "figure things out"; it follows instructions or guesses. Common tells:
- Pronouns without referents ("update it", "fix the issue")
- Implied knowledge ("handle the edge cases" — which ones?)
- Deferred decisions ("choose an appropriate approach")
- Vague scope ("and any related files")

## Step 4: Rate Issues and Determine Verdict

### Issue Severity Definitions

| Severity | Criteria | Examples |
|----------|----------|----------|
| **High** | Would cause incorrect implementation, data loss, or security risk if not fixed before execution | Missing rollback for migration; hidden dependency between steps; wishful delegation of critical logic |
| **Medium** | Would degrade plan quality or increase implementation risk, but unlikely to cause outright failure | Vague step that could be misinterpreted; kitchen sink step; missing verification for non-trivial change |
| **Low** | Cosmetic or minor improvement; implementation would likely succeed without fixing | Scope creep on a low-risk addition; step ordering preference; minor naming clarity |

**Severity calibration rule:** Consider the implementing agent's perspective. If a step would force the agent to make assumptions or decisions not covered by the plan, that is **Medium at minimum** — never Low. The implementing agent has no context beyond the plan text. "The agent will figure it out" is not a valid assumption; agents that guess tend to either do the wrong thing or spin in circles. When in doubt, raise severity — a false Medium is cheap, but a false Low causes real implementation pain.

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

**Do not edit the plan.** Review it as-is. If something is missing, flag it as an issue in the review output — don't silently fix it. The user needs to see the gaps to decide whether to address them or accept the risk.

Specifically, check for these structural requirements and flag as issues if missing:

1. **Commit cadence** — plan should state "commit after each step". If missing, flag as **Medium**.
2. **Final steps** — plan should include appropriate review/finalization steps (see "Does the plan include final steps?" above). If missing, flag as **Medium** and specify which steps are needed based on plan complexity.
