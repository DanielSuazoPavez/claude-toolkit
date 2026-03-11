---
name: evaluate-agent
description: Evaluate agent design quality against behavioral effectiveness. Use when reviewing, auditing, or improving agent .md files. Keywords: agent quality, agent review, evaluate agent.
---

# Agent Judge

Evaluate agent design quality against behavioral effectiveness.

## Contents

1. [Core Philosophy](#core-philosophy) - Behavioral delta formula
2. [Evaluation Dimensions](#evaluation-dimensions-115-points) - 5 dimensions
3. [Common Failures](#common-failures) - Named failure patterns
5. [Anti-Pattern Detection](#anti-pattern-detection) - Textual signals
6. [Edge Cases](#edge-cases) - Type-specific adjustments
7. [JSON Output Format](#json-output-format) - Result schema
8. [Invocation](#invocation) - How to run evaluations
9. [Example Evaluation](#example-evaluation) - Before/After

## Core Philosophy

**The Formula:** `Good Agent = Specialized Mindset − Claude's Default Approach`

Value = behavioral delta. Agents shift *how* Claude thinks and acts, not just what it knows.

## Skill vs Agent

| Aspect | Skill | Agent |
|--------|-------|-------|
| Core | Knowledge delta | Behavioral delta |
| Loads | On-demand | Persistent during task |
| Value | What to know | How to think/act |

## Evaluation Dimensions (115 points)

### D1: Right-sized Focus (30 pts) - Most Critical
Does the agent do ONE thing at the right intensity?

| Score | Criteria |
|-------|----------|
| 27-30 | Laser-focused scope, calibrated to task context |
| 21-26 | Clear scope, mostly appropriate intensity |
| 15-20 | Scope defined but too broad or intensity mismatched |
| 8-14 | Tries to do multiple things, inconsistent intensity |
| 0-7 | Kitchen sink agent or wildly miscalibrated |

Red flags: "handles all aspects of...", reviewing scripts like production systems
Green flags: Clear boundaries, explicit "what I don't do"

### D2: Output Quality (30 pts)
Does the agent produce usable, actionable results?

| Score | Criteria |
|-------|----------|
| 27-30 | Output format specified, immediately actionable, clear handoff |
| 21-26 | Good output structure, mostly actionable |
| 15-20 | Output described but vague on format/handoff |
| 8-14 | Commentary over action, unclear what to do next |
| 0-7 | No output guidance, just vibes |

Red flags: "provide feedback on...", no output format section
Green flags: Template/checklist provided, explicit next steps

### D3: Coherent Persona (25 pts)
Does the agent have a consistent identity and voice?

| Score | Criteria |
|-------|----------|
| 23-25 | Clear role with explicit anti-behaviors, voice directives ("be X, not Y"), and "What I Don't Do" section |
| 18-22 | Role stated and tone present, but no anti-behaviors or persona doesn't constrain default Claude behavior |
| 13-17 | Role is a job title only ("You are a code reviewer") — no behavioral specifics that change how Claude acts |
| 7-12 | Vague identity, could be any agent |
| 0-6 | No discernible persona |

Red flags: Generic "you are a helpful assistant", tone shifts mid-doc
Green flags: "You are a X who Y", explicit anti-behaviors

### D4: Tool Selection (15 pts)
Is the tool set an exact fit for the stated purpose?

| Score | Criteria |
|-------|----------|
| 14-15 | Each tool is justified by the agent's purpose; no extras, no gaps |
| 11-13 | Reasonable tools, one questionable inclusion or omission |
| 7-10 | Tools listed but mismatch with stated purpose |
| 3-6 | Over-provisioned or under-provisioned |
| 0-2 | No tools specified or completely wrong set |

**Scoring rule**: If the agent's purpose explicitly requires a tool (e.g., "writes a report" → Write), award full credit. Don't penalize for tools the agent explicitly says it won't use anyway.

Red flags: Edit tools on read-only reviewer, no Bash on a test runner
Green flags: Tools match stated purpose, no unnecessary capabilities

### D5: Integration Quality (15 pts)
Does it work well within the resource ecosystem?

| Score | Criteria |
|-------|----------|
| 13-15 | Seamless integration — correct references, no duplication, clean handoffs |
| 10-12 | References exist and are correct, minor duplication or missed connections |
| 6-9 | Some broken/outdated references, restates content from other resources |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | No references, duplicates freely, contradicts connected resources |

**Check:**
- **Reference accuracy** — points to skills, memories, and agents that exist
- **Duplication avoidance** — defers to existing skills/agents instead of reimplementing
- **Handoff clarity** — clean boundaries with skills that invoke it or agents it complements
- **Ecosystem awareness** — knows what tools and resources are available
- **Terminology consistency** — uses same terms as connected resources

## Common Failures

| Failure | How to Recognize | How to Fix |
|---------|------------------|------------|
| **The Generalist** | "Handles all aspects of...", no boundaries | Pick ONE thing, add "What I Don't Do" |
| **The Commentator** | Produces analysis, not action | Add output template, specify next steps |
| **The Chameleon** | Generic voice, could be any agent | Add persona statement, anti-behaviors |
| **The Hoarder** | Requests every tool available | Match tools to actual needs |
| **The Overkill** | Reviews scripts like distributed systems | Add calibration questions |

## Anti-Pattern Detection

| In Agent | Suggests |
|----------|----------|
| "comprehensive", "thorough", "all aspects" | Scope creep (D1) |
| No output format section | Unclear handoff (D2) |
| "You are an assistant that..." | Weak persona (D3) |
| Tools: Read, Write, Edit, Bash, Grep, Glob | Tool hoarding (D4) |
| Reviewer with no rejection criteria | Rubber-stamp risk (D2) |

## Edge Cases

| Agent Type | Evaluation Adjustment |
|------------|----------------------|
| **Single-purpose runner** | D1 should be near-perfect; penalize any scope creep |
| **Multi-step orchestrator** | Allow broader scope in D1 if stages are clearly defined |
| **Read-only analyzer** | D4: no Edit/Write tools; penalize if present |
| **Interactive agent** | D2: output may be conversational, not templated |
| **Reviewer/verifier** | D2: must define explicit rejection criteria (when to say NO, automatic fail triggers); penalize if pass/fail logic is absent |

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "score": <total>,
  "max": 115,
  "percentage": <score/max * 100>,
  "dimensions": {
    "D1": <score>, "D2": <score>, "D3": <score>, "D4": <score>, "D5": <score>
  },
  "top_improvements": ["...", "...", "..."]
}
```

Compute file_hash with: `md5sum <agent-file> | cut -c1-8`

## Invocation

**Launch a subagent** for fresh, unbiased evaluation.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the agent at <path> using the evaluate-agent rubric.
    Read .claude/skills/evaluate-agent/SKILL.md for the full rubric.

    Perform FRESH scoring. Do NOT read evaluations.json or prior scores.

    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from prior evaluations.

## Evaluation Protocol

1. Read completely, noting scope boundaries and output format
2. Check frontmatter: name, description, tools
3. Score each dimension with evidence
4. Calculate total and percentage
5. Generate report with JSON output including file_hash and top improvements
6. Update `.claude/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.agents.resources["<name>"] = $result' .claude/indexes/evaluations.json > tmp && mv tmp .claude/indexes/evaluations.json
   ```

## Example Evaluation

**Before (45% - 52/115):**
```markdown
---
name: code-helper
description: Helps with code
tools: Read, Write, Edit, Bash, Grep, Glob
---
You are a helpful assistant that assists with coding tasks.
Provide thorough and comprehensive feedback.
```
- D1: 8/30 - No scope, "comprehensive" = everything
- D2: 10/30 - No output format, just "feedback"
- D3: 7/25 - Generic assistant, no persona
- D4: 5/15 - Every tool, no justification
- D5: 3/15 - No references, island agent

**After (85% - 98/115):**
```markdown
---
name: test-coverage-analyzer
description: Identifies untested code paths. Use before marking feature complete.
tools: Read, Grep, Glob
---
You are a test coverage skeptic who assumes code is untested until proven otherwise.

## Focus
Find code paths without test coverage. Don't review test quality or suggest implementations.

## What I Don't Do
- Review test quality (that's test-reviewer)
- Write tests (that's the developer)
- Check code style (that's linters)

## Output Format
\```markdown
# Coverage Gaps: [Feature]

## Untested Paths
| File:Line | Code Path | Risk |
|-----------|-----------|------|
| ... | ... | High/Med/Low |

## Recommended Test Cases
1. [Specific test to add]
\```
```
- D1: 28/30 - Laser focus, explicit boundaries
- D2: 27/30 - Clear template, actionable gaps
- D3: 20/25 - Good persona, could strengthen voice
- D4: 13/15 - Appropriate read-only tools
- D5: 10/15 - References test-reviewer, could connect more

## See Also

- `/evaluate-skill` — Sibling evaluator for skills (knowledge delta rubric).
- `/evaluate-hook` — Sibling evaluator for hooks (testability and safety rubric).
- `/evaluate-memory` — Sibling evaluator for memory files (convention compliance).
- `/evaluate-batch` — Run evaluations across multiple resources of one type.
- `/create-agent` — Agent creation workflow that feeds into this evaluator.
- `relevant-toolkit-resource_frontmatter` memory — Supported frontmatter fields for agents and skills.

## The Meta-Question

> "Does this agent make Claude behave differently than it would by default?"

If yes → genuine value. If no → it's just a system prompt with extra words.
