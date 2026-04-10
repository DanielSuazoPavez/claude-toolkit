---
name: brainstorm
description: General-purpose brainstorm facilitation through structured dialogue. Use when exploring ideas, clarifying problems, or weighing tradeoffs — not building software. Do NOT use for software design/requirements (use /brainstorm-idea) or research/evidence-gathering (use /analyze-idea). Keywords: brainstorm, think through, ideas, explore, tradeoffs, weigh options.
argument-hint: "[topic]"
allowed-tools: Read, Write, AskUserQuestion
---

Structured brainstorm facilitation that converges on **clarity**, not a design document.

**See also:** `/brainstorm-idea` (when the goal is a software design document), `/analyze-idea` (for research/evidence gathering)

## When to Use

- User wants to think through a problem, not build something
- Creative ideation — generating and filtering ideas
- Weighing tradeoffs between non-technical (or loosely technical) options
- Exploring a fuzzy topic to gain understanding

## When NOT to Use

- **Goal is a software design** → `/brainstorm-idea`
- **User needs research/evidence** → `/analyze-idea`
- **Requirements are already clear** → skip to plan mode or just do it

## Process

### Phase 1: Frame

"What are we actually thinking about?"

Ask questions **one at a time** to clarify:
- What's the topic or problem?
- What's the goal of this brainstorm?
- What constraints exist?

Prefer **multiple choice** questions when feasible — easier to answer, faster to converge.

**Exit when:** the user can state what they're brainstorming in one sentence.

### Phase 2: Explore

"Generate and evaluate"

Start by diverging — generate ideas, perspectives, angles. Then converge — compare, weigh, filter. But stay **fluid**: interleave generating and evaluating as the conversation flows rather than enforcing rigid sub-steps.

- Tables for comparisons when multiple options exist
- Free-form riffing when the conversation calls for it
- Can loop: generate → evaluate → generate more

### Phase 3: Land

"Crystallize takeaways"

1. Summarize: what did we figure out? What's still open?
2. Ask the user what output format they want (default: summary of core ideas discussed)
3. Save the artifact

**Escape hatch:** If the brainstorm has clearly become "what should I build", suggest switching to `/brainstorm-idea`.

## Key Principles

- **One question per message**: Don't overwhelm
- **Concrete over abstract**: Show examples, not just concepts
- **Follow the energy**: If the user lights up on a topic, explore it
- **Revisit assumptions**: If something feels off, go back

## Output

Save to: `output/{project}/design/{YYYYMMDD}_{HHMM}__brainstorm__{topic}.md`

Format adapts to what the session was about. Default structure:

```markdown
# Brainstorm: {topic}

## Context
[What we set out to think about]

## Key Ideas
[Core ideas that emerged]

## Open Questions
[What's still unresolved]
```

Ask the user before saving — they may want a different structure or no artifact at all.

## Handling Disagreement

```
User disagrees with your framing
├─ Did I miss context? → Ask clarifying question
├─ Is their concern valid? → Acknowledge, adjust
├─ Is it a tradeoff? → Present both sides, let them choose
└─ Am I confident I'm right? → Explain reasoning once, then defer
```

## Completion Heuristics

### Ready to Land (3+ signals)
- **Clear framing**: User can state the topic in one sentence
- **Ideas explored**: Multiple angles considered, not just the first one
- **Direction emerged**: User has a sense of where they stand
- **Energy fading**: Natural conversation wind-down
- **No circling**: Topics aren't repeating

### Needs More Exploration
- **Hedging language**: "Maybe...", "I'm not sure..."
- **New threads**: Fresh ideas still surfacing
- **Circling back**: Same topic returning unresolved
- **User asking more questions**: They're still seeking, not landing

## Handling Stuck Conversations

**"I don't know" responses:**
- Offer a concrete starting point: "What if we assume X? Does that feel right?"
- Narrow the space: "Between A and B, which is closer?"
- Defer: "Let's skip this and come back after we explore other angles"

**Circular conversations:**
- Name it: "We've come back to this three times — what's making it hard to resolve?"
- Timebox: "Two more messages on this, then we pick something"
- Make it low-stakes: "This doesn't have to be final — let's go with X for now"

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Question Dump** | 5 questions at once overwhelms | One question per message, prefer multiple choice |
| **Premature Landing** | Saving before ideas are explored | Stay in Explore until energy naturally fades |
| **Forcing Software Output** | Steering toward architecture/design docs | This skill converges on clarity, not design — suggest `/brainstorm-idea` if it fits |
| **Over-Structuring** | Rigid phases kill creative flow | Phases are a guide, not a cage — follow the conversation |
| **Ignoring Energy** | Sticking to the plan when user is excited about a tangent | Follow what's alive in the conversation |
