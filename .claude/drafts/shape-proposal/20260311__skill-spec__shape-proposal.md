# Skill Proposal: shape-proposal

## What It Is

A skill that sits between `brainstorm-idea` (design) and plan mode (implementation). Takes a validated design and shapes it into a presentable proposal for a specific audience.

```
brainstorm-idea -> shape-proposal -> plan mode -> implementation
```

## When to Use

- A design or architecture is already validated (brainstorm is done)
- The output needs to be shared with someone: a team, a client, leadership
- The audience, tone, and level of detail matter for how the content lands

## When NOT to Use

- The idea is still fuzzy (use brainstorm-idea instead)
- You're ready to implement (use plan mode instead)
- The document is for yourself / internal notes only

## Inputs

The skill asks one natural question: **"Who is this for and why are you sharing it?"**

From the answer, it infers:

| Parameter | Examples | How it's detected |
|-----------|----------|-------------------|
| **Target audience** | Team that built the MVP, client stakeholder, leadership, internal alignment | Explicit in user's answer |
| **Context / framing** | Feedback request, alternative proposal, pitch, decision request, knowledge transfer | Inferred from audience + purpose |
| **Level of detail** | High-level overview, technical proposal, actionable handoff | Inferred from audience type |
| **Tone calibration** | Confident-direct, confident-respectful, collaborative-exploratory | Inferred from relationship to audience (presenting to peers vs to team whose work you're reviewing) |

If the skill can't confidently infer a parameter, it asks a targeted follow-up — not a form.

**Required input:**
- **Source document**: The validated design (output of brainstorm-idea or equivalent). User provides a path.

## What It Does

### Phase 1: Analyze Source & Select Structure

- Read the source document and the proposal template reference (`proposal-template-reference.md`)
- Identify which **core sections** the source material covers
- Select which **contextual sections** the audience needs (comparison table, non-negotiables, cost estimation, migration path, validation checklist, etc.)
- Determine section ordering based on what the audience cares about most
- Present the proposed structure to the user for confirmation before writing

### Phase 2: Shape the Proposal

- Restructure source content into the selected template sections
- Add the **framing block** (what this is, scope boundaries, purpose)
- Adjust tone for the audience — especially critical when reviewing others' work
- Add audience-specific context the source document doesn't have (e.g., why decisions were made in terms the audience understands)
- Fill structural gaps: if the template calls for a section the source doesn't cover, flag it to the user rather than inventing content

**Key constraint:** The skill reshapes and restructures — it does not rewrite from scratch. The source author's technical substance and voice are preserved. Sections are reordered, framing is added, tone is adjusted, but paragraphs aren't rewritten unless the tone is wrong for the audience.

### Phase 3: Review via `proposal-reviewer` Agent

Spawn a `proposal-reviewer` agent to review the shaped document. The agent checks for:

- **Contradictions** between sections
- **Dismissive language** toward existing work or other teams' decisions
- **Assumptions presented as facts** — things stated with certainty that should be flagged as "to validate"
- **Missing context for the audience** — things the author knows but the reader won't
- **Scope creep** — items that are "too much for this stage" vs "real concerns"
- **Tone consistency** — does the framing block promise one tone but the body deliver another?

Fix issues, re-run the agent if significant changes were made. One pass is usually enough for minor fixes.

### Phase 4: Output

Save the final document to `.claude/output/proposals/`.

Report what was changed from the source: sections added, sections reordered, tone adjustments made, gaps flagged.

## Proposal Template Reference

The skill uses `proposal-template-reference.md` as its structural guide. This defines:

- **8 core sections**: Project Context, Tech Stack, Architecture, Configuration & Validation, Development Standards, Risks & Technical Decisions, Team & Resources, References
- **9 contextual sections**: Comparison Table, Non-Negotiables, Cost Estimation, Security & Compliance, Migration/Coexistence, Validation Checklist, Framework Comparison, Deployment Architecture, Monitoring & Observability
- **Section ordering guidance**: Where contextual sections slot in relative to core sections
- **Status markers**: `[WIP]`, `[TBD]`, `[TO VALIDATE]`, `[MISSING INFO]`, `[ASSUMED]`

Not every proposal uses every section. The skill selects based on source content and audience.

## Key Principles

- **Confident, not apologetic.** Proposals with conviction land better. Frame scope honestly but don't ask for forgiveness.
- **Fair to existing work.** When reviewing/proposing alternatives, acknowledge what works, what you haven't reviewed, and where the existing approach may have advantages you don't fully understand.
- **Separate "what must happen" from "how I'd do it."** Non-negotiable requirements are easier to align on than architectural preferences.
- **Reshape, don't rewrite.** The source document's technical substance is the foundation. The skill changes structure, framing, and tone — not the author's conclusions or technical content.
- **Design vs presentation effort is often 30/70.** The architecture may be straightforward — the real work is making it land well with the audience.
- **Identify audience early.** The same design needs very different framing for different readers.

## Companion: `proposal-reviewer` Agent

A dedicated agent for Phase 3 review. Can also be used standalone to review any proposal or design document.

**Review dimensions:**
- Contradictions and internal inconsistencies
- Tone (dismissive language, unearned certainty, excessive hedging)
- Missing context for the target audience
- Scope appropriateness (proposal-stage vs implementation-stage detail)
- Fairness to existing work / alternative approaches

**Not a general editor** — it doesn't check grammar, formatting, or style. It checks whether the proposal will land well with its intended audience.

## Example Session

See the design iteration files for a real example of this process:

- `20260310_1200__brainstorm-idea__export-doc-extraction.md` - v1: raw brainstorm output
- `20260310_1300__brainstorm-idea__export-doc-extraction-v2.md` - v2: gaps filled after self-review + agent review
- `20260310_1400__brainstorm-idea__export-doc-extraction-v3.md` - v3: reframed as proposal (audience shift happened here)
- `20260311_1500__brainstorm-idea__export-doc-extraction-v4.md` - v4: tone fixes, cost estimation, MVP comparison balanced
- `20260311_1600__brainstorm-idea__export-doc-extraction-v5.md` - v5: final, agent-reviewed, ready to share

The brainstorm converged at v2. Everything after was shaping the proposal for the audience (the team that built the MVP, presented by a senior reviewer).
