---
name: brainstorm-idea
description: Turn fuzzy ideas into clear designs through structured dialogue. Use BEFORE plan mode when requirements are unclear. Keywords: fuzzy, unclear, ideation, requirements, vague, explore, figure out.
---

Turns fuzzy ideas into clear designs through structured dialogue. Use BEFORE plan mode.

## When to Use

- User has an idea but hasn't defined what to build
- Requirements are unclear or open-ended
- Multiple approaches seem viable

## When NOT to Use

Skip this skill and go directly to plan mode when:

- **Clear requirements exist**: User provides specific, unambiguous specs
- **Single obvious approach**: No meaningful alternatives to explore
- **Small, well-defined task**: Bug fix, minor feature, or routine implementation
- **User explicitly says "just build it"**: They've already done the thinking
- **Time pressure**: User needs something fast and is okay with your default choices

Signs you should skip brainstorming:
- User provides wireframes, specs, or detailed descriptions
- Request matches a common pattern with an obvious solution
- User has made this type of feature before

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
| **Premature Design Save** | Committing design before full validation | Run the Phase 3 decision point checklist first |
| **Over-Brainstorming** | Using this skill when requirements are already clear | Check "When NOT to Use" - skip to plan mode |

## When is Brainstorming Complete?

Expert heuristics for recognizing completion vs needing more iteration:

### Ready to Proceed (3+ signals present)
- **Crisp problem statement**: User can explain the problem in one sentence
- **Clear scope boundary**: User knows what's in AND what's explicitly out
- **Chosen approach**: One direction selected with understood tradeoffs
- **Success criteria**: Measurable definition of "done"
- **No open questions**: User isn't saying "I'm not sure about..."

### Needs More Iteration (any signal present)
- **Hedging language**: "Maybe we could...", "I'm thinking possibly..."
- **Scope creep**: New features keep getting added mid-discussion
- **Circular returns**: Same topic comes up multiple times
- **Conflicting constraints**: Requirements contradict each other
- **Vague success**: "It should just work better"

### Decision Point
After Phase 3, explicitly check:
```
"Before we save this design, let me verify:
1. Problem: [one sentence] - correct?
2. Scope: [in/out list] - anything missing?
3. Approach: [chosen option] - still confident?
4. Success: [criteria] - measurable?"
```

If user hesitates on any point, return to that phase.

## Handling Stuck or Circular Conversations

When progress stalls:

### Detecting Stuck States
- Same question asked 3+ times with no resolution
- User responds with "I don't know" repeatedly
- Conversation loops back to already-decided topics
- 5+ messages without concrete progress

### Recovery Strategies

**For "I don't know" responses:**
```
User: "I don't know what tech stack to use"
├─ Offer concrete defaults → "For a web app like this, I'd default to X. Sound reasonable?"
├─ Narrow the choice → "Let's just pick between A or B. Which feels closer?"
└─ Defer the decision → "Let's skip this for now and decide after we see the data flow"
```

**For circular conversations:**
```
Same topic returning
├─ Name it → "We've discussed auth three times now. What's making it hard to decide?"
├─ Timebox → "Let's spend 2 more messages on this, then pick something"
└─ Make it reversible → "Let's go with X for now. We can change it later if needed"
```

**For analysis paralysis:**
```
Too many options
├─ Cut options → "Let me reduce this to just 2 choices"
├─ Add constraints → "Given your timeline, only A is realistic"
└─ Propose default → "If you have no strong preference, I'd go with X because..."
```

**Escalation**: If stuck for 10+ messages, suggest:
- "We might need more information. What could we research or prototype to unblock this?"
- "This decision might not matter much. Want to just pick one and move on?"

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

## Quick Completion Checklist

Before saving the design and exiting this skill:

- [ ] **Problem defined**: One-sentence problem statement validated by user
- [ ] **Scope bounded**: Clear in/out list with no ambiguity
- [ ] **Approach chosen**: Single direction selected with tradeoffs understood
- [ ] **Success criteria set**: Measurable definition of "done"
- [ ] **No hedging**: User speaks confidently, not "maybe" or "possibly"
- [ ] **Decision point passed**: Phase 3 verification questions answered affirmatively

If any box is unchecked, return to the relevant phase before proceeding.
