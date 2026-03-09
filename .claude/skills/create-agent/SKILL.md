---
name: create-agent
description: Create new agents for specialized tasks. Use when adding behavioral specialists to `.claude/agents/`. Keywords: agent creation, new agent, behavioral specialist, subagent, Task tool, spawned agent.
---

Use when adding a new agent to `.claude/agents/`.

## Contents

1. [When to Use](#when-to-use) - Triggers for agent creation
2. [Agent vs Skill Decision](#agent-vs-skill-decision) - Decision tree
3. [Process](#process) - Define, write, evaluate
4. [Structure Template](#structure-template) - Template reference and persona calibration
5. [Template Modifications by Type](#template-modifications-by-type) - Type-specific adjustments
6. [Tool Selection Guide](#tool-selection-guide) - Tools by purpose
7. [First-Attempt Checklist](#first-attempt-checklist) - Pre-evaluation gate
8. [Edge Cases](#edge-cases) - Overlap, personas, reviewers, abandonment
9. [Anti-Patterns](#anti-patterns) - Named failures
10. [Iteration Reference](#iteration-reference) - Narrowing scope and fixing evaluations

**See also:** `/evaluate-agent` (quality gate), `/create-skill` (when a skill fits better), `/create-hook` (for enforcement patterns), `/create-memory` (for context persistence)

## When to Use

- Adding a specialized agent for a recurring task type
- Existing agent isn't focused enough (scope creep)
- Need persistent behavioral shift, not just knowledge

## Agent vs Skill Decision

```
Does this need to CHANGE how Claude behaves?
├─ Yes → Does it need to persist across multiple turns?
│   ├─ Yes → Agent
│   └─ No → Skill (one-shot workflow)
└─ No → Does it add expert knowledge?
    ├─ Yes → Skill
    └─ No → Probably not needed
```

## Process

### 1. Define the Behavioral Delta

What does this agent do that default Claude doesn't?
- Different perspective (skeptic, advocate, librarian)
- Stricter constraints (read-only, single-focus)
- Specialized output format

### 2. Write the Agent

Location: `.claude/agents/<agent-name>.md`

Use `context-role` format for agent names. See `docs/naming-conventions.md`.

**Required frontmatter:**
```yaml
---
name: agent-name
description: One-line purpose. Use when [trigger].
tools: Read, Grep, Glob  # minimal set
---
```

**Required sections:**
1. Persona statement: "You are a X who Y"
2. Focus: What this agent does
3. What I Don't Do: Explicit boundaries
4. Output Format: Template or structure

### 3. Apply Quality Gate

Run `/evaluate-agent` on the result:
- **Target: 85%**
- If below target, iterate on the weakest dimensions

## Structure Template

Read `resources/TEMPLATE.md` and use it as the LITERAL STARTING POINT.
Copy the entire template, then modify every section for the new agent.
Do not write from scratch — always start from the template.

### Persona Calibration

| Agent Type | Weak Persona | Strong Persona |
|------------|--------------|----------------|
| Reviewer | "You review code" | "You are a skeptical reviewer who assumes bugs exist until proven otherwise" |
| Finder | "You find patterns" | "You are a pattern librarian who catalogs without judgment" |
| Verifier | "You check work" | "You are a QA auditor who verifies claims against evidence" |

The persona should create a **behavioral constraint** that default Claude doesn't have.

## Template Modifications by Type

| Agent Type | Modify | Details |
|------------|--------|---------|
| Reviewer/Verifier | Add Verdict + Automatic Fails | See [Edge Cases: Reviewer/Verifier Agents](#reviewerverifier-agents) |
| Read-only cataloger | Remove Output Path, add Rules | Pattern: `pattern-finder.md` |
| Code modifier | Expand tools, add safety constraints | Pattern: `code-debugger.md` |

## Tool Selection Guide

| Agent Purpose | Recommended Tools |
|---------------|-------------------|
| Read-only analysis | Read, Grep, Glob |
| Verification/testing | Read, Bash, Grep, Glob |
| Code modification | Read, Write, Edit, Bash, Grep, Glob |
| Documentation | Read, Write, Grep, Glob |

## First-Attempt Checklist

Before running `/evaluate-agent`, verify:

- [ ] Persona is specific? (not "helpful assistant")
- [ ] "What I Don't Do" section exists?
- [ ] Output Format has a template?
- [ ] Tool set is minimal for the task?
- [ ] Description includes "Use when [trigger]"?
- [ ] If reviewer/verifier: explicit rejection criteria defined? (when to say NO)

## Edge Cases

### Scope Overlap with Existing Agent

When the new agent overlaps with an existing one:

| Situation | Resolution |
|-----------|------------|
| 80%+ overlap | Extend existing agent instead of creating new |
| Different perspective, same domain | Create new agent with explicit boundary ("I focus on X, not Y") |
| Subset of existing agent | Consider if skill is better fit (one-shot vs persistent) |

**Red flag:** If you're adding "What I Don't Do" items that another agent handles, the agents may conflict.

### Persona Red Flags

These weak personas signal an unfocused agent:

| Red Flag | Problem | Better Alternative |
|----------|---------|-------------------|
| "helpful assistant" | No behavioral constraint | Specific role with perspective |
| "expert in X" | Expertise isn't behavior | "skeptical reviewer who..." |
| "handles all aspects" | Generalist, no focus | Pick ONE aspect |
| "assists with" | Passive, no ownership | "verifies", "catalogs", "enforces" |
| No "who [constraint]" | Missing perspective | Add behavioral modifier |

### Reviewer/Verifier Agents

Agents that evaluate, check, or validate work need explicit rejection criteria to prevent rubber-stamping.

**Required for reviewer-type agents:**
- Default stance (skeptical until proven otherwise)
- Explicit pass/fail/partial output states
- Automatic fail triggers (conditions that always result in rejection)

**Example (hypothetical migration-reviewer):**
```
## Verdict

- **SAFE**: All checks pass, rollback verified
- **UNSAFE**: Any automatic fail trigger hit
- **CONDITIONAL**: Minor issues, safe with noted changes

## Automatic Fails
- Missing rollback step
- Unguarded DROP/TRUNCATE on populated table
- No-lock strategy for index on large table
```

**Reference agents:** goal-verifier (PASS/FAIL/PARTIAL), code-reviewer (PASS/BLOCKERS/RISKS), implementation-checker (GREEN/YELLOW/RED)

### When to Abandon an Agent Idea

Stop and reconsider if:
- Can't articulate a single "What I Don't Do" boundary
- Persona keeps drifting to "helpful" or "general"
- Existing skill covers 80%+ of the need
- Output format is "whatever's useful" (no structure)

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Generalist** | "Handles all aspects of..." | Pick ONE focus, add "What I Don't Do" |
| **The Commentator** | Produces analysis, not action | Add Output Format template |
| **Tool Hoarder** | Every tool listed | Match tools to actual needs |
| **No Persona** | "You are a helpful assistant" | Specific role with perspective |
| **Missing Boundaries** | No "What I Don't Do" | Always include explicit limits |
| **Overlapping Scope** | Conflicts with existing agent | Check `.claude/indexes/AGENTS.md` first |

## Iteration Reference

### Narrowing Scope

**Request:** "Create an agent that helps with database work"

Too broad. Refinement questions:
1. What specific database task recurs? → "Reviewing migrations for safety"
2. What perspective is needed? → "Skeptical — assume migrations break production"
3. What does it NOT do? → "Doesn't write migrations, just reviews them"

Result: `migration-reviewer` — focused agent with clear boundaries.

### Fixing Evaluation Failures

**`deploy-checker` first attempt:** D (62/115)
- D1: 8/30 — "checks deployments" too broad → narrowed to "validates deployment checklists"
- D2: 12/30 — no output format → added Verdict (READY/NOT READY/CONDITIONAL) + Automatic Fails
- D3: 7/25 — "helpful assistant" → "cautious release engineer who blocks deploys until every item has evidence"
- D4: 5/15 — every tool listed → trimmed to Read, Grep, Glob

**After iteration:** B+ (95/115). Fix weakest dimensions first, one at a time.

## Reference

See existing agents for patterns:
- `code-reviewer.md` — Proportional review with calibration questions
- `pattern-finder.md` — Read-only cataloging, no critique
- `goal-verifier.md` — Verification levels (L1/L2/L3)
