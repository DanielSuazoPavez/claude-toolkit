---
name: write-agent
description: Create new agents for specialized tasks. Use when adding behavioral specialists to `.claude/agents/`. Keywords: agent creation, new agent, behavioral specialist, subagent.
---

Use when adding a new agent to `.claude/agents/`.

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

Run `agent-judge` on the result:
- **Target: B (75+)**
- Key dimensions: D1 (Focus), D2 (Output), D3 (Persona)

## Structure Template

```markdown
---
name: [name]
description: [One line]. Use when [trigger].
tools: [minimal set]
---

You are a [role] who [perspective/constraint].

## Focus

[What this agent does - 2-3 bullets max]
```

### Persona Examples

| Agent Type | Weak Persona | Strong Persona |
|------------|--------------|----------------|
| Reviewer | "You review code" | "You are a skeptical reviewer who assumes bugs exist until proven otherwise" |
| Finder | "You find patterns" | "You are a pattern librarian who catalogs without judgment" |
| Verifier | "You check work" | "You are a QA auditor who verifies claims against evidence" |

The persona should create a **behavioral constraint** that default Claude doesn't have.

```markdown

## What I Don't Do

- [Explicit boundary 1]
- [Explicit boundary 2]
- [Hand off to: other-agent or skill]

## Output Format

\```markdown
# [Title]: [Scope]

## [Section 1]
...
\```
```

## Tool Selection Guide

| Agent Purpose | Recommended Tools |
|---------------|-------------------|
| Read-only analysis | Read, Grep, Glob |
| Verification/testing | Read, Bash, Grep, Glob |
| Code modification | Read, Write, Edit, Bash, Grep, Glob |
| Documentation | Read, Write, Grep, Glob |

## First-Attempt Checklist

Before running `agent-judge`, verify:

- [ ] Persona is specific? (not "helpful assistant")
- [ ] "What I Don't Do" section exists?
- [ ] Output Format has a template?
- [ ] Tool set is minimal for the task?
- [ ] Description includes "Use when [trigger]"?

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **The Generalist** | "Handles all aspects of..." | Pick ONE focus, add "What I Don't Do" |
| **The Commentator** | Produces analysis, not action | Add Output Format template |
| **Tool Hoarder** | Every tool listed | Match tools to actual needs |
| **No Persona** | "You are a helpful assistant" | Specific role with perspective |
| **Missing Boundaries** | No "What I Don't Do" | Always include explicit limits |

## Reference

See existing agents for patterns:
- `code-reviewer.md` - Proportional review with calibration questions
- `pattern-finder.md` - Read-only cataloging, no critique
- `goal-verifier.md` - Verification levels (L1/L2/L3)
