---
name: analyze-idea
description: Research and exploration tasks. Investigates a topic, gathers evidence, and generates a saved report. Use for feasibility analysis, coverage gaps, codebase audits.
---

Use for research and exploration tasks. Investigates a topic, gathers evidence, and generates a saved report.

## Context

The user provides context after `/analyze-idea` describing what to investigate. Examples:
- `/analyze-idea feasibility of adding real-time alerts`
- `/analyze-idea current test coverage gaps`
- `/analyze-idea over-engineering in the codebase`

## Instructions

1. **Understand the scope**: Parse the user's context to identify what needs analysis.

2. **Explore thoroughly**:
   - Gather concrete evidence (file paths, line counts, patterns found)
   - Use Task tool with Explore agent for broad codebase questions

### Investigation Heuristics

#### Search Strategy (Not Mechanics)

**Start wide, narrow fast:**
- First search: cast a wide net to understand the landscape
- Second search: target specific patterns from initial findings
- Third search: verify edge cases and counterexamples
- Stop when new searches return familiar results

**What reveals truth about code:**
- Tests show intended behavior; absence of tests shows uncertainty
- Error handling reveals what authors feared would go wrong
- Comments often lie; commit messages lie less; code behavior is truth
- Unused code persists longer than you'd expect - verify before assuming "dead"

#### Expert Patterns (by Analysis Type)

**Code Analysis** - Follow the money (data/control flow):
- Who calls this? Who does it call? What state does it touch?
- Where are the exits? (returns, throws, panics, process.exit)
- What must be true for this to work? (preconditions, env, config)
- What's the blast radius of changing this?

**Architecture** - Look for tension:
- Where does code "fight" the architecture? (workarounds, TODOs, hacks)
- What's easy to change vs. what requires touching many files?
- Which components have unstable interfaces? (frequent signature changes)
- Where do abstractions leak? (internal details exposed in public APIs)

**Coverage Gaps** - Test what matters:
- High complexity + low coverage = risk (use cyclomatic complexity as guide)
- Error paths without tests = production surprises waiting to happen
- Mock-heavy tests = integration gaps
- Flaky tests = concurrency or timing issues

**Feasibility** - Find the hard parts first:
- What's the most uncertain assumption? Attack that first
- Prior attempts: check closed PRs, reverted commits, abandoned branches
- Dependencies: unmaintained = you own the bugs
- Can you build a walking skeleton in hours, not days?

### Evidence Triangulation

Cross-validate findings from multiple sources before concluding:

```
┌─────────────────────────────────────────────────────────────┐
│ Source Type        │ Strength │ Watch For                   │
├────────────────────┼──────────┼─────────────────────────────┤
│ Current code       │ Strong   │ May be outdated/dead        │
│ Tests              │ Strong   │ May not reflect prod usage  │
│ Git history        │ Medium   │ Context lost over time      │
│ Comments/docs      │ Weak     │ Often stale                 │
│ Config files       │ Strong   │ Env-specific variations     │
└─────────────────────────────────────────────────────────────┘
```

**Triangulation Rules:**
- 1 source = hypothesis, 2 sources = likely, 3+ sources = confident
- When sources conflict, prefer code > tests > git > docs
- Note contradictions explicitly - they often reveal the real story
- Missing evidence is evidence: no tests often means no confidence

### When to Stop Investigating

```
Should I keep digging?
├─ Have I answered the core question?
│   └─ Yes → Stop, write findings
├─ Are new searches returning the same results?
│   └─ Yes → Diminishing returns, stop
├─ Have I checked 3+ independent sources (code, tests, docs, git history)?
│   └─ Yes → Probably enough evidence
├─ Is this a tangent from the original question?
│   └─ Yes → Note it, don't pursue
└─ Am I confident enough to make a recommendation?
    ├─ Yes → Stop, write report
    └─ No → One more targeted search, then stop anyway
```

**Rule:** Deliver findings with current evidence rather than perfect findings never.

3. **Evaluate objectively**:
   - Assess findings against practical criteria
   - Note trade-offs, not just problems
   - Distinguish facts from opinions
   - Be direct about conclusions

4. **Generate report**: Create a markdown report with:
   - Clear title and date
   - Executive summary (2-3 sentences)
   - Detailed findings with evidence
   - Concrete recommendations (if applicable)
   - Metrics/data where relevant

5. **Save report**:
   - Path: `.claude/analysis/{YYYYMMDD}_{HHMM}__analyze-idea__{topic}.md`
   - Use a slugified version of the topic for filename (lowercase, hyphens)
   - Double underscores (`__`) separate timestamp, source, and context
   - Example: `.claude/analysis/20260121_1430__analyze-idea__test-coverage-gaps.md`

6. **Output to console**:
   - Show the full report content
   - Note the file path where it was saved

## Report Template

```markdown
# [Topic] Analysis Report

**Date**: YYYY-MM-DD HH:MM:SS
**Scope**: [What was analyzed]

---

## Summary

[2-3 sentence executive summary]

---

## Findings

### [Finding 1 Title]

[Description with evidence: file paths, code snippets, metrics]

### [Finding 2 Title]

...

---

## Recommendations

| Priority | Action |
|----------|--------|
| ... | ... |

---

## Metrics (if applicable)

| Metric | Value |
|--------|-------|
| ... | ... |
```

## Notes

- This is exploration and reporting, NOT planning or implementation
- Be factual and evidence-based
- Include file paths and line numbers for traceability
- Keep recommendations actionable but don't implement them

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Analysis Paralysis** | Investigating forever | Set scope, timebox, deliver findings |
| **Confirmation Bias** | Only finding evidence for hypothesis | Actively seek counter-evidence |
| **Shallow Investigation** | Surface-level grep | Trace code paths, check tests, read commits |
| **No Evidence** | "I think X is true" | Include file paths, line numbers, metrics |

## Edge Cases

### Vague or Unbounded Scope
When the user's request is too broad (e.g., "analyze the codebase"):
1. Ask one clarifying question OR pick the most likely interpretation
2. State your scope assumption explicitly in the report
3. Deliver narrow findings rather than shallow broad findings

### Contradictory Evidence
When code says X but docs/tests say Y:
1. Note the contradiction as a finding (this IS valuable information)
2. Prefer code behavior over documentation claims
3. Check git blame/history to understand which is newer
4. Recommend reconciliation in your report

### No Relevant Code Found
When searches return nothing useful:
1. Document what you searched for and where
2. Distinguish "doesn't exist" from "exists but named differently"
3. Check for alternative implementations (vendored, generated, external service)
4. "No evidence of X" is a valid finding - state it confidently

### Security-Sensitive Findings
When investigation reveals potential security issues:
1. Include in report with appropriate severity assessment
2. Be specific about the risk (not vague "this might be bad")
3. Do NOT test exploits or demonstrate vulnerabilities
4. Recommend security review if findings are significant
