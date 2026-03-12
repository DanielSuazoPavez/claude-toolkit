---
name: shape-proposal
description: Shape a validated design into a presentable proposal for a specific audience. Use AFTER brainstorm-idea when the design is solid but needs to be shared with a team, client, or stakeholder. Keywords: proposal, present, audience, share, reframe, pitch, stakeholder, client.
---

Shape a validated design into a presentable proposal. Use AFTER `brainstorm-idea`, BEFORE plan mode.

```
brainstorm-idea -> shape-proposal -> plan mode -> implementation
```

**See also:** `/brainstorm-idea` (if the design isn't solid yet), `/review-plan` (after proposal is accepted and you're planning implementation)

## When to Use

- Design or architecture is already validated (brainstorm is done)
- Output needs to be shared with someone: a team, a client, leadership
- Audience, tone, and level of detail matter for how the content lands

## When NOT to Use

- Idea is still fuzzy → use `/brainstorm-idea`
- Ready to implement → use plan mode
- Document is for yourself / internal notes only
- Source material is too thin (<1 page) → needs more design work first, not presentation work

## Process

### Phase 1: Gather Context

Ask the user for the **source document path** (brainstorm output, design doc, etc.).

Then ask one question: **"Who is this for and why are you sharing it?"**

From the answer, infer:

| Parameter | Infer from |
|-----------|------------|
| **Target audience** | Explicit in answer (team, client, leadership, etc.) |
| **Context / framing** | Audience + purpose → feedback request, alternative proposal, pitch, decision request, knowledge transfer |
| **Level of detail** | Audience type → high-level overview, technical proposal, actionable handoff |
| **Tone** | Relationship to audience → confident-direct (peers), confident-respectful (reviewing others' work), collaborative-exploratory (alignment) |

If any parameter is ambiguous, ask **one** targeted follow-up. Not a form.

### Phase 2: Analyze Source & Select Structure

Read the source document and `resources/PROPOSAL_TEMPLATE.md`.

1. **Map source content** to the template's 8 core sections — identify what's covered and what's missing
2. **Select contextual sections** based on audience and context:
   - Proposing alternatives to existing work → Comparison Table (lead section), Non-Negotiables, Migration/Coexistence
   - Budget matters → Cost Estimation
   - Sensitive data or compliance → Security & Compliance
   - Stakeholder input needed → Validation Checklist
     - When the audience mediates between you and stakeholders, suggest splitting the checklist: client/stakeholder questions vs internal/team questions
   - Technology decisions open → Framework Comparison
3. **Determine section order** — what the audience cares about most goes first
4. **Present proposed structure to the user** for confirmation before writing

### Phase 3: Shape the Proposal

Restructure source content into the confirmed structure:

- Add **framing block**: what this document is, scope boundaries, what was/wasn't reviewed, purpose
- **Look for the core insight** — the one sentence that reframes the problem in a way that makes the architecture feel inevitable. If the source has one, surface it prominently (before Project Context). If it doesn't emerge naturally, don't force it — not every proposal has one.
- **Reshape, don't rewrite**: reorder sections, adjust framing and tone, add audience context — but preserve the source author's technical substance and voice
  - **Source is already a proposal** → reshape structure and tone, preserve text
  - **Source is a design doc / brainstorm output** → content needs restructuring into proposal form. The constraint becomes: preserve technical conclusions and the author's reasoning, even when the words change significantly
- Flag structural gaps to the user rather than inventing content
- Apply status markers for incomplete items: `[TBD]`, `[TO VALIDATE]`, `[MISSING INFO]`, `[ASSUMED]`

#### Tone Calibration

| Audience relationship | Tone adjustments |
|----------------------|------------------|
| Presenting to team that built existing work | Soften comparisons ("tradeoff" not "why"), acknowledge unreviewed areas, add "may have strengths we haven't explored" where honest |
| Presenting to client/stakeholder | Lead with business value, quantify impact, separate requirements from recommendations |
| Internal alignment | Be direct, skip disclaimers, focus on decision points |
| Leadership / non-technical | High-level first, details in appendix, emphasize outcomes over architecture |

### Phase 4: Review via `proposal-reviewer` Agent

Spawn a `proposal-reviewer` agent with the shaped document and the target audience context. The agent reviews for:

- Contradictions between sections
- Dismissive language toward existing work
- Assumptions presented as facts (should be `[TO VALIDATE]`)
- Missing context the audience needs but the author takes for granted
- Scope creep (implementation detail in a proposal-stage document)
- Tone inconsistency (framing block promises one tone, body delivers another)

Fix issues flagged by the agent. Re-run only if changes were significant.

After fixing reviewer issues, do a **source fidelity check**: scan the source document for technical substance (specific claims, caveats, design rationale, edge case handling) that didn't make it into the shaped output. Flag any dropped content to the user — they can decide whether it was intentionally omitted or accidentally lost.

### Phase 5: Output

Save to `.claude/output/proposals/{YYYYMMDD}_{HHMM}__shape-proposal__{topic}.md`

Report to user:
- Sections added vs source
- Sections reordered
- Tone adjustments made
- Gaps flagged (sections the template expected but source didn't cover)

## Key Principles

- **Confident, not apologetic.** Frame scope honestly but don't ask for forgiveness. Proposals with conviction land better than hedged ones.
- **Fair to existing work.** Acknowledge what works, what you haven't reviewed, and where the existing approach may have advantages you don't fully understand.
- **Separate "what must happen" from "how I'd do it."** Non-negotiable requirements are easier to align on than architectural preferences. When the audience is technical and the purpose is architectural alignment, implementation detail can ground the discussion. When the audience is deciding *whether* to proceed, it's premature. If including implementation specifics, acknowledge it in the framing block.
- **Reshape, don't rewrite.** Structure, framing, and tone change. Technical conclusions and the author's voice don't.
- **30/70 rule.** Design may be 30% of the effort. Making it land with the audience is the other 70%.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Full Rewrite** | Rewrites source from scratch, loses author's voice and precision | Reshape structure and tone, preserve technical substance |
| **Missing Framing Block** | Jumps into architecture without setting expectations | Always start with what this is, scope, and purpose |
| **One-Sided Comparison** | "Why" column instead of "Tradeoff" column when comparing | Acknowledge strengths of alternatives, use balanced framing. **Tradeoff column test**: read only the Tradeoff column top-to-bottom — if every row lands the same side, the table is one-sided regardless of the words used |
| **Kitchen Sink Sections** | Includes all 17 possible sections regardless of audience | Select sections based on what this audience needs, not what's available |
| **Inventing Content** | Fills template gaps with fabricated details | Flag gaps to user, use status markers, ask don't assume |
| **Skipping Structure Confirmation** | Writes full proposal before user confirms section selection | Phase 2 ends with user confirmation — don't skip it |
