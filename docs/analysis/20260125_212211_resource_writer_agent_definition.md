# Resource Writer Agent Definition Analysis

**Date**: 2026-01-25 21:22:11
**Scope**: Feasibility analysis of a unified "resource writer" agent for skills, agents, hooks, and memories

---

## Summary

A resource-writer agent that routes to appropriate write/judge skills is feasible but raises design questions about scope, value-add over direct skill invocation, and the missing `write-agent` skill. The core idea is sound—a single entry point that dispatches to specialized tools—but implementation requires careful scoping to avoid becoming a generic coordinator that adds no behavioral value.

---

## Findings

### Finding 1: Current Write/Judge Skill Pairs

The toolkit has write and judge skill pairs for 3 of 4 resource types:

| Resource | Write Skill | Judge Skill | Status |
|----------|-------------|-------------|--------|
| Skill | `write-skill` | `skill-judge` | Complete |
| Hook | `write-hook` | `hook-judge` | Complete |
| Memory | `write-memory` | `memory-judge` | Complete |
| Agent | **Missing** | `agent-judge` | Incomplete |

**Evidence**: `.claude/skills/` contains write-skill, write-hook, write-memory, skill-judge, hook-judge, memory-judge, agent-judge but no write-agent.

**Gap**: `write-agent` is already in BACKLOG.md (line 32) but not implemented.

### Finding 2: Pattern Analysis of Write Skills

Common patterns in write-* skills:

| Aspect | write-skill | write-hook | write-memory |
|--------|-------------|------------|--------------|
| Decision tree | When to use | Hook event selection | Category selection |
| Structure template | SKILL.md format | Bash script + JSON | Quick Reference pattern |
| Anti-patterns | 4 named patterns | 6 named patterns | 5 named patterns |
| Quality gate | "Run skill-judge, target B+" | Test with bash | Check conventions |
| Line count | ~150 | ~100 | ~100 |

Key insight: Each write skill follows `Decision Tree → Structure → Anti-Patterns → Quality Gate` formula.

### Finding 3: Agent Definition Requirements

Based on `agent-judge` evaluation criteria (SKILL.md lines 22-82):

| Dimension | Points | Agent Requirement |
|-----------|--------|-------------------|
| D1: Right-sized Focus | 30 | ONE thing at right intensity |
| D2: Output Quality | 30 | Actionable, clear handoff |
| D3: Coherent Persona | 25 | Consistent identity and voice |
| D4: Tool Selection | 15 | Minimal, justified tools |

A resource-writer agent scoring well would need:
- Laser focus on routing/dispatching, not content creation
- Clear output: either finished resource or handoff to user
- Strong "dispatcher" identity, not "generic helper"
- Tools: Read (to check existing resources), Write (to create), Skill (to invoke specialists)

### Finding 4: Three Design Approaches

**Approach A: Dispatcher Agent**
- Role: Routes to write-skill, write-hook, write-memory, write-agent based on user intent
- Tools: Read, Skill
- Value: Single entry point, reduces user cognitive load
- Risk: Thin wrapper, may not provide behavioral delta

**Approach B: Resource Factory Agent**
- Role: Creates resources directly, using judge skills as internal quality gates
- Tools: Read, Write, Grep, Glob
- Value: End-to-end resource creation with validation
- Risk: Duplicates write-* skill logic, scope creep

**Approach C: Write-Resource Skill (not agent)**
- Role: Skill that dispatches to other skills
- Invocation: `/write-resource` → asks what type → invokes specific `/write-*`
- Value: Consistent with skill invocation pattern
- Risk: Meta-skill complexity, one extra step vs direct invocation

### Finding 5: Value Proposition Analysis

**Question**: Does a resource-writer agent provide behavioral delta?

| Scenario | Without Agent | With Agent |
|----------|--------------|------------|
| User says "create a skill for X" | Claude may miss quality gate | Agent ensures judge runs |
| User says "I need a hook for Y" | Direct `/write-hook` works | Extra routing step |
| User says "write some documentation" | Unclear which resource type | Agent can clarify and route |
| User creates 3+ resources in session | Manual skill invocations | Agent maintains context |

**Finding**: Primary value is in:
1. Ambiguous cases where resource type is unclear
2. Quality enforcement (always running judge)
3. Multi-resource creation sessions

### Finding 6: Missing Piece: write-agent

Before building a resource-writer agent, `write-agent` skill needs to exist. Based on `agent-judge` dimensions, a write-agent skill should:

1. Decision tree: When to create an agent vs skill
2. Structure template: Frontmatter + persona + scope + output format
3. Anti-patterns from agent-judge: The Generalist, The Commentator, The Chameleon, The Hoarder, The Overkill
4. Quality gate: Target B (75+) on agent-judge

---

## Recommendations

| Priority | Action |
|----------|--------|
| 1 | Create `write-agent` skill first (completes the write/judge pairs) |
| 2 | Evaluate if dispatcher adds value via real-world usage patterns |
| 3 | If proceeding, use **Approach A: Dispatcher Agent** with Skill tool access |
| 4 | Consider **Approach C** instead if agent doesn't provide behavioral delta |

---

## Proposed Agent Definition (if proceeding)

```yaml
---
name: resource-writer
description: Routes resource creation to appropriate write/judge skills. Use when creating skills, agents, hooks, or memories.
tools: Read, Skill
color: green
---
```

**Persona**: You are a resource routing coordinator that identifies the correct write skill and ensures quality validation.

**Focus**:
- Identify resource type from user intent
- Route to: write-skill, write-agent, write-hook, or write-memory
- Ensure quality gate (invoke corresponding judge skill)

**What I Don't Do**:
- Write resource content directly (that's the write-* skills)
- Make decisions about resource design (that's the user + write skill)
- Review existing resources (that's the judge skills)

**Decision Tree**:
```
User wants to create a reusable pattern
├─ Behavior shift (how Claude acts) → write-agent
├─ Knowledge delta (what Claude knows) → write-skill
├─ Automation/safety gate → write-hook
└─ Persistent context → write-memory
```

---

## Metrics

| Metric | Value |
|--------|-------|
| Write skills present | 3/4 (75%) |
| Judge skills present | 4/4 (100%) |
| Resources without write skill | agent |
| Estimated write-agent effort | ~100 lines (similar to other write skills) |
| Backlog item exists | Yes (BACKLOG.md:32) |

---

## Open Questions

1. Is a dispatcher agent worth the complexity, or should users invoke `/write-skill` etc. directly?
2. Should the dispatcher be a skill (`/write-resource`) instead of an agent?
3. What's the frequency of "ambiguous resource type" scenarios in practice?
4. Should the agent enforce judge quality gates or leave that optional?
