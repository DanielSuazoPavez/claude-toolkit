---
name: evaluate-skill
description: Evaluate Agent Skill design quality against specifications and best practices. Use when reviewing, auditing, or improving SKILL.md files. Provides multi-dimensional scoring and actionable improvements.
---

# Skill Judge

Evaluate skill design quality against best practices.

## Core Philosophy

**What is a Skill?** A knowledge externalization mechanism, not a tutorial.

**The Formula:** `Good Skill = Expert-only Knowledge − What Claude Already Knows`

Value = knowledge delta. Skills should contain decision trees, trade-offs, edge cases, domain frameworks—not basics Claude already understands.

## Three Knowledge Types

| Type | Action | Example |
|------|--------|---------|
| **Expert** | Keep | Non-obvious decision trees, trade-offs |
| **Activation** | Keep sparingly | Brief reminders of known concepts |
| **Redundant** | Delete | Basic concepts Claude knows |

## Evaluation Dimensions (120 points)

### D1: Knowledge Delta (20 pts) - Most Critical
Does it add genuine expert knowledge?
- Red flags: "What is X" sections, generic best practices
- Green flags: Non-obvious decisions, expert trade-offs

### D2: Mindset + Procedures (15 pts)
Does it transfer expert thinking AND domain-specific workflows?

### D3: Anti-Pattern Quality (15 pts)
Are anti-patterns specific with reasoning, not vague warnings?

### D4: Specification Compliance (15 pts)
Is the description clear about WHAT, WHEN, and KEYWORDS for triggering?

### D5: Progressive Disclosure (15 pts)
- Metadata: Always in memory
- Body: Loaded when triggered
- References: On-demand
- Target: Under 500 lines

#### Supporting Files Checklist

When skill has companion files, also check:

| Issue | Deduction |
|-------|-----------|
| Supporting file >500 lines | -3 per file |
| No TOC when >100 lines | -2 per file |
| Nested references (refs within refs) | -3 |
| Bare reference (no context) | -1 each |
| Orphaned file (never referenced) | -2 per file |

### D6: Freedom Calibration (15 pts)
- Creative tasks → High freedom (principles)
- Fragile operations → Low freedom (exact scripts)

### D7: Pattern Recognition (10 pts)
Does it follow established patterns?
- Mindset (~50 lines)
- Navigation (~30 lines)
- Philosophy (~150 lines)
- Process (~200 lines)
- Tool (~300 lines)

### D8: Practical Usability (15 pts)
Decision trees, working examples, error handling, edge cases?

## Scoring Calibration

### D1 (Knowledge Delta) - 20 pts

| Score | Criteria |
|-------|----------|
| 18-20 | Expert says "yes, this took years to learn" |
| 14-17 | Useful but partially derivable from first principles |
| 10-13 | Mostly activation knowledge, some expert bits |
| 5-9 | Tutorial territory - explains basics |
| 0-4 | Pure redundancy - Claude already knows this |

### D3 (Anti-Pattern Quality) - 15 pts

| Score | Criteria |
|-------|----------|
| 13-15 | Specific anti-patterns with reasoning AND fixes |
| 10-12 | Named anti-patterns with some reasoning |
| 6-9 | Vague warnings ("avoid bad practices") |
| 0-5 | No anti-patterns section |

## Edge Cases

| Skill Type | Evaluation Adjustment |
|------------|----------------------|
| **Reset/Calibration** | D1 judged on "resets behavior effectively" not "adds knowledge" |
| **Meta-skills** | Self-reference is fine if genuinely useful |
| **Navigation** | Minimal is correct; penalize bloat, not brevity |
| **Wrapper/Utility** | Lower D1 bar if procedural value is clear |

## Grading Scale

| Grade | Score | Description |
|-------|-------|-------------|
| A | 108+ (90%) | Exemplary - reference quality |
| A- | 102-107 (85-89%) | Excellent - minimal polish needed |
| B+ | 96-101 (80-84%) | Solid - minor improvements |
| B | 90-95 (75-79%) | Good - clear path forward |
| B- | 84-89 (70-74%) | Functional - needs attention |
| C+ | 78-83 (65-69%) | Adequate - notable gaps |
| C | 72-77 (60-64%) | Needs work |
| D | 60-71 (50-59%) | Significant issues |
| F | <60 (<50%) | Needs redesign |

## Common Failures

| Failure | How to Recognize | How to Fix |
|---------|------------------|------------|
| **The Tutorial** | "What is X" sections, explains basics | Delete basics, keep only expert delta |
| **The Dump** | 800+ lines, everything included | Split into skill + references |
| **The Invisible Skill** | Great content, vague description | Add WHEN and KEYWORDS to description |
| **The Freedom Mismatch** | Rigid for creative, vague for fragile | Match freedom to task risk |

## Evaluation Protocol

**Use a subagent** to run evaluations - avoids self-evaluation bias when reviewing your own work.

1. Read completely, mark sections as [E]xpert, [A]ctivation, [R]edundant
2. Analyze structure: frontmatter, line count, pattern
3. Score each dimension with evidence
4. Calculate total, assign grade
5. Generate report with critical issues and top 3 improvements

## Example Evaluation

**Before (D - 62/120):**
```markdown
# Git Workflow
Use branches for features. Commit often. Write good messages.
```
- D1: 6/20 - Claude knows this
- D3: 0/15 - No anti-patterns
- D8: 4/15 - No decision trees

**After (A - 112/120):**
```markdown
# Git Workflow
## Branch Naming Decision Tree
[specific tree based on team conventions]

## Commit Sizing
| Change Type | Commit Strategy |
[expert guidance on atomic commits]

## Anti-Patterns
| Pattern | Why Bad | Fix |
| Mega-commit | Unreviewable | [specific split strategy]
```
- D1: 18/20 - Team-specific expert knowledge
- D3: 14/15 - Specific anti-patterns with fixes
- D8: 14/15 - Decision trees, examples

## The Meta-Question

> "Would an expert say this captures knowledge requiring years to learn?"

If yes → genuine value. If no → it's compressing what Claude already knows.
