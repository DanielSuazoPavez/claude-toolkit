---
name: brainstorm-idea
description: Turn fuzzy ideas into clear designs through structured dialogue. Use BEFORE plan mode when requirements are unclear.
---

Turns fuzzy ideas into clear designs through structured dialogue. Use BEFORE plan mode.

## When to Use

- User has an idea but hasn't defined what to build
- Requirements are unclear or open-ended
- Multiple approaches seem viable

## Process

### Phase 1: Understand the Idea

Ask questions **one at a time** to clarify:
- What problem does this solve?
- Who is it for?
- What does success look like?
- What are the constraints (time, tech, scope)?

Prefer **multiple choice** questions when feasible - easier to answer, faster to converge.

### Phase 2: Explore Approaches

Present **2-3 alternatives** with trade-offs before committing:

| Approach | Pros | Cons |
|----------|------|------|
| A: ... | ... | ... |
| B: ... | ... | ... |

Let the user choose direction.

### Phase 3: Incremental Design

Share design in **200-300 word chunks**:
1. Architecture overview
2. Key components
3. Data flow
4. Error handling
5. Testing approach

**Validate after each section** before moving forward. Catch misalignments early.

## Key Principles

- **YAGNI**: Ruthlessly cut features that aren't essential
- **One question per message**: Don't overwhelm
- **Concrete over abstract**: Show examples, not just concepts
- **Revisit assumptions**: If something feels off, go back

## Output

Save validated design to: `docs/plans/YYYY-MM-DD-<topic>-design.md`

Then either:
- Stop here (design only)
- Proceed to implementation planning (use plan mode)

## Handling Disagreement

When user pushes back on your suggestion:

```
User disagrees with approach
├─ Did I miss context? → Ask clarifying question
├─ Is their concern valid? → Acknowledge, adjust approach
├─ Is it a tradeoff? → Present both sides, let them choose
└─ Am I confident I'm right? → Explain reasoning once, then defer to user
```

**Don't:** Immediately cave to seem agreeable
**Don't:** Stubbornly defend your position
**Do:** Explain tradeoffs, respect their choice

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Question Dump** | 5 questions at once overwhelms user | One question per message, prefer multiple choice |
| **Premature Implementation** | Jumping to code before design is clear | Validate each phase before proceeding |
| **YAGNI Violation** | Building for hypothetical future needs | Cut features that aren't essential NOW |
| **Skipping Validation** | "Save time" by not checking alignment | Catch misalignments early, iterate small |

## Example Dialogue

### Phase 1: Understanding
**Claude:** What problem does this feature solve for your users?
- A) Users can't find items quickly
- B) Users want to save items for later
- C) Users need to compare multiple items
- D) Other: [describe]

**User:** A - they can't find items quickly

**Claude:** What's the current search experience like?
- A) Basic text search, often returns irrelevant results
- B) No search at all, just browsing categories
- C) Search exists but is slow
- D) Other: [describe]

### Phase 2: Approaches
**Claude:** Here are two approaches for improving search:

| Approach | Pros | Cons |
|----------|------|------|
| A: Elasticsearch | Fast, fuzzy matching, scalable | Operational complexity, cost |
| B: PostgreSQL full-text | Simple, no new infra | Less fuzzy matching, slower at scale |

Which fits your constraints better?

### Phase 3: Incremental Design
**Claude:** Starting with the search architecture...

[200-300 word chunk explaining the chosen approach]

Does this match your expectations before I continue to data flow?
