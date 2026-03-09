---
name: evaluate-skill
description: Use when reviewing, auditing, or scoring a SKILL.md file. Keywords: skill evaluation, skill audit, skill quality, evaluate skill, score skill, review skill.
---

# Skill Judge

Evaluate skill design quality against best practices.

## Contents

1. [Core Philosophy](#core-philosophy) - Knowledge delta formula
2. [Skill Types](#skill-types) - Knowledge vs command classification
3. [Evaluation Dimensions](#evaluation-dimensions-120-points) - 8 dimensions (D4 revised, D7 replaced)
4. [Scoring Calibration](#scoring-calibration) - Score-to-criteria mapping
5. [Grading Scale](#grading-scale) - Grade thresholds
6. [JSON Output Format](#json-output-format) - Result schema
7. [Invocation](#invocation) - How to run evaluations
8. [Example Evaluation](#example-evaluation) - Complete worked example

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

## Skill Types

Skills declare a `type` in frontmatter: `knowledge` (default) or `command`.

| Type | Value Proposition | Examples |
|------|-------------------|----------|
| **knowledge** | Expert knowledge transfer — decision trees, trade-offs, domain frameworks | design-db, design-tests, refactor |
| **command** | Expert curation + consistent execution — checklists, sequences, resets | wrap-up, write-handoff, snap-back |

**How to classify:** If the skill's primary value is "knowing *which* things to check and *in what order*" rather than "explaining *how* to think about a domain," it's a command.

### Dimension Adjustments for Command-Type Skills

Command skills use the same 8 dimensions and 120-point scale, but D1, D2, and D8 are interpreted differently:

| Dimension | Knowledge Interpretation | Command Interpretation |
|-----------|--------------------------|------------------------|
| **D1** (20 pts) | Does it add genuine expert knowledge? | Is the checklist expert-curated? Would removing any item leave a gap? Are items non-obvious in combination? |
| **D2** (15 pts) | Does it transfer expert thinking? | Does it encode expert sequencing? Does the order matter and is it correct? |
| **D8** (15 pts) | Decision trees, examples, edge cases? | Is the execution sequence clear and complete? Are edge cases handled (partial completion, errors)? |

D3–D7 apply identically to both types.

### D1 Scoring Calibration for Command Type

| Score | Criteria |
|-------|----------|
| 18-20 | Checklist captures non-obvious items; removing any creates a real gap; ordering reflects expert judgment |
| 14-17 | Good coverage but some items are obvious or ordering is arbitrary |
| 10-13 | Mostly obvious items with a few expert picks |
| 5-9 | Generic checklist anyone could write |
| 0-4 | Trivial — no curation value |

## Evaluation Dimensions (120 points)

### D1: Knowledge Delta (20 pts) - Most Critical
Does it add genuine expert knowledge?
- Red flags: "What is X" sections, generic best practices
- Green flags: Non-obvious decisions, expert trade-offs
- **Command type:** See [Dimension Adjustments](#dimension-adjustments-for-command-type-skills) for reinterpretation

### D2: Mindset + Procedures (15 pts)
Does it transfer expert thinking AND domain-specific workflows?
- **Command type:** Does it encode expert sequencing? Does the order matter and is it correct?

### D3: Anti-Pattern Quality (15 pts)
Are anti-patterns specific with reasoning, not vague warnings?

### D4: Specification Compliance (10 pts)
Is the description clear about WHAT and WHEN? Keywords should be precise — penalize over-broad trigger lists that cause false-positive routing.

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

### D7: Integration Quality (15 pts)
Does it work well within the resource ecosystem?
- **Reference accuracy** — points to resources that exist and are current
- **Duplication avoidance** — defers to other resources instead of restating their content
- **Handoff clarity** — clean boundaries when delegating to agents, skills, or memories
- **Ecosystem awareness** — knows what's available and connects to it
- **Terminology consistency** — uses same terms as connected resources

### D8: Practical Usability (15 pts)
Decision trees, working examples, error handling, edge cases?
- **Command type:** Is the execution sequence clear and complete? Are edge cases handled (partial completion, errors)?

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

### D7 (Integration Quality) - 15 pts

| Score | Criteria |
|-------|----------|
| 13-15 | Seamless integration — correct references, no duplication, clean handoffs, full ecosystem awareness |
| 10-12 | References exist and are correct, minor duplication or missed connections |
| 6-9 | Some broken/outdated references, restates content from other resources |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | No references, duplicates freely, contradicts connected resources |

## Edge Cases

| Skill Type | Classification | Evaluation Adjustment |
|------------|---------------|----------------------|
| **Reset/Calibration** | `command` | D1 judged on curation: does the reset target the right behaviors? |
| **Meta-skills** | `knowledge` | Self-reference is fine if genuinely useful |
| **Navigation** | `knowledge` | Minimal is correct; penalize bloat, not brevity |
| **Wrapper/Utility** | `command` | D1 judged on curation: does it cover the right steps? |

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

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "type": "knowledge|command",
  "grade": "A/A-/B+/B/B-/C+/C/D/F",
  "score": <total>,
  "max": 120,
  "percentage": <score/max * 100>,
  "dimensions": {
    "D1": <score>, "D2": <score>, "D3": <score>, "D4": <score>,
    "D5": <score>, "D6": <score>, "D7": <score>, "D8": <score>
  },
  "top_improvements": ["[high] ...", "[low] ...", "[low] ..."]
}
```

Compute file_hash with: `md5sum <skill-file> | cut -c1-8`

## Invocation

**Launch a subagent** for fresh, unbiased evaluation.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the skill at <path> using the evaluate-skill rubric.
    Read .claude/skills/evaluate-skill/SKILL.md for the full rubric.

    Perform FRESH scoring. Do NOT read evaluations.json or prior scores.

    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from prior evaluations.

## Evaluation Protocol

1. Read completely, mark sections as [E]xpert, [A]ctivation, [R]edundant
2. Determine type from frontmatter (`type: knowledge|command`, default: `knowledge`). Apply dimension adjustments from [Skill Types](#skill-types) accordingly.
3. Analyze structure: frontmatter, line count, pattern
4. Score each dimension with evidence
5. Calculate total, assign grade
6. Generate report with JSON output including file_hash, type, and top 3 improvements (tag each with `[high]` or `[low]` priority)
7. Update `.claude/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.skills.resources["<name>"] = $result' .claude/indexes/evaluations.json > tmp && mv tmp .claude/indexes/evaluations.json
   ```

## Example Evaluation

**Skill:** `git-workflow` (hypothetical)

**Before (F - 45/120):**
```markdown
# Git Workflow
Use branches for features. Commit often. Write good messages.
```

| Dim | Score | Evidence |
|-----|-------|----------|
| D1 | 6/20 | Pure basics - Claude knows branching and commits |
| D2 | 5/15 | No mindset transfer, just commands |
| D3 | 0/15 | No anti-patterns section |
| D4 | 5/10 | Vague description, no keywords |
| D5 | 12/15 | Short (good), but too sparse |
| D6 | 10/15 | Neither rigid nor principled - just vague |
| D7 | 3/15 | No references to other resources, island skill |
| D8 | 4/15 | No decision trees, no examples |

**After (A- - 109/120):**
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

| Dim | Score | Evidence |
|-----|-------|----------|
| D1 | 18/20 | Team-specific naming conventions, sizing heuristics |
| D2 | 14/15 | Transfers "think in atomic units" mindset |
| D3 | 14/15 | Specific anti-patterns with reasoning and fixes |
| D4 | 9/10 | Clear triggers, precise keywords |
| D5 | 14/15 | ~150 lines, well-structured |
| D6 | 13/15 | Appropriate freedom for git (medium risk) |
| D7 | 13/15 | References commit conventions memory, defers to branch workflow |
| D8 | 14/15 | Decision tree, tables, concrete examples |

## The Meta-Question

> "Would an expert say this captures knowledge requiring years to learn?"

If yes → genuine value. If no → it's compressing what Claude already knows.
