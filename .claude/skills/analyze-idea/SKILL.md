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
   - Use Glob, Grep, Read to investigate relevant code/docs
   - Use Task tool with Explore agent for broad codebase questions
   - Gather concrete evidence (file paths, line counts, patterns found)

### Investigation Techniques

#### For Code Analysis
```bash
# Find all implementations of a pattern
grep -rn "pattern" src/ --include="*.py"

# Trace dependencies
grep -rn "from module import" . --include="*.py"

# Find test coverage for a module
grep -rn "test_modulename" tests/

# Check git history for context
git log --oneline -20 -- path/to/file.py
git blame path/to/file.py | head -50
```

#### For Architecture Questions
1. Start with entry points (main.py, __init__.py, routes/)
2. Follow imports to trace data flow
3. Check tests for expected behavior
4. Look for existing docs (README, docstrings, comments)

#### For Coverage/Gap Analysis
```bash
# Count lines per module
find src/ -name "*.py" -exec wc -l {} + | sort -n

# Find untested modules
diff <(ls src/*.py | xargs -n1 basename | sed 's/.py//') \
     <(ls tests/test_*.py | xargs -n1 basename | sed 's/test_//' | sed 's/.py//')

# Check for TODO/FIXME
grep -rn "TODO\|FIXME\|HACK" src/
```

#### For Feasibility Analysis
1. Identify dependencies (external libs, APIs, infrastructure)
2. Check for similar implementations in codebase
3. Estimate scope by counting affected files
4. Look for blockers (tech debt, missing abstractions)

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
   - Path: `docs/analysis/<YYYYMMDD_HHMMSS>_<topic>.md`
   - Use a slugified version of the topic for filename
   - Example: `docs/analysis/20260121_143022_test_coverage_gaps.md`

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
