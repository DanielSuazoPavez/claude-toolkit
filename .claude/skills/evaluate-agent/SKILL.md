---
name: evaluate-agent
description: Evaluate agent design quality against behavioral effectiveness. Use when reviewing, auditing, or improving agent .md files. Keywords: agent quality, agent review, evaluate agent.
---

# Agent Judge

Evaluate agent design quality against behavioral effectiveness.

## Core Philosophy

**The Formula:** `Good Agent = Specialized Mindset − Claude's Default Approach`

Value = behavioral delta. Agents shift *how* Claude thinks and acts, not just what it knows.

## Skill vs Agent

| Aspect | Skill | Agent |
|--------|-------|-------|
| Core | Knowledge delta | Behavioral delta |
| Loads | On-demand | Persistent during task |
| Value | What to know | How to think/act |

## Evaluation Dimensions (100 points)

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
| 23-25 | Clear role, consistent tone, knows what it isn't |
| 18-22 | Identity clear, voice mostly consistent |
| 13-17 | Role defined but voice drifts or generic |
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

## Grading Scale

| Grade | Score | Description |
|-------|-------|-------------|
| A | 90+ | Exemplary - use as reference |
| A- | 85-89 | Excellent - minor polish |
| B+ | 80-84 | Solid - small improvements |
| B | 75-79 | Good - clear path forward |
| B- | 70-74 | Functional - needs attention |
| C | 60-69 | Needs work - notable gaps |
| D | 50-59 | Significant issues |
| F | <50 | Needs redesign |

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

## Edge Cases

| Agent Type | Evaluation Adjustment |
|------------|----------------------|
| **Single-purpose runner** | D1 should be near-perfect; penalize any scope creep |
| **Multi-step orchestrator** | Allow broader scope in D1 if stages are clearly defined |
| **Read-only analyzer** | D4: no Edit/Write tools; penalize if present |
| **Interactive agent** | D2: output may be conversational, not templated |

## Evaluation Protocol

**Use a subagent** to run evaluations - avoids self-evaluation bias when reviewing your own work.

1. Read completely, noting scope boundaries and output format
2. Check frontmatter: name, description, tools
3. Score each dimension with evidence
4. Calculate total, assign grade
5. Generate report with top improvements

## Example Evaluation

**Before (D - 52/100):**
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

**After (A- - 88/100):**
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

## The Meta-Question

> "Does this agent make Claude behave differently than it would by default?"

If yes → genuine value. If no → it's just a system prompt with extra words.
