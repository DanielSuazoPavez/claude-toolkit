# Worked Example: Shaping Techniques

Annotated excerpts showing how the `shape-proposal` skill makes structural and presentational decisions. Each excerpt demonstrates a shaping technique with a `<!-- WHY -->` annotation explaining the principle at work.

**Source**: A design doc (brainstorm output) shaped into a proposal for the team that built an existing MVP.

---

## 1. Framing Block

```markdown
> **What this is**: An architectural proposal based on reviewing the current MVP
> (phase 2) and phase 1 deployment. Covers the extraction pipeline, annotation UI,
> and general architecture. The reconciliation module was not reviewed in depth yet.
```

<!-- WHY: Sets scope boundaries up front. "not reviewed in depth yet" is honest about
what the author doesn't know — critical when presenting to the team that built it.
No apologies, no excessive disclaimers, just one paragraph of expectation-setting.
Principle: "Confident, not apologetic." -->

---

## 2. Core Insight Placement

```markdown
## The Core Insight

**Reconciliation is the product, extraction is the tool.** The business value is
finding discrepancies across documents in a transaction — the current output
(annotated PDFs with flagged problems + notifications) is what matters. Extraction
accuracy matters because it serves reconciliation, not as an end in itself.
Architecture decisions should flow from this.
```

<!-- WHY: Placed before Problem/Context — reframes everything that follows. The reader
now evaluates every architectural decision through this lens. Not every proposal has
a core insight, but when the source material has one, it belongs at the top.
Principle: "Look for the core insight." -->

---

## 3. Balanced Comparison Table

```markdown
Note: This comparison covers the areas we reviewed. The MVP's reconciliation module
was not reviewed in depth and is not being compared here. The MVP's approach may have
strengths or handle edge cases we haven't identified yet — this table reflects our
current understanding and is open to correction.

| Area | Current MVP (phase 2) | This proposal | Tradeoff |
|------|----------------------|---------------|----------|
| **Preprocessing** | Text extraction -> embeddings -> vector DB | Direct text extraction, no embeddings | Simpler, but the vector DB may serve purposes beyond schema lookup that we haven't fully explored |
| **Annotation** | Manual bounding-box flagging before extraction | Feedback loop: extract first, user verifies/corrects after | Lower ongoing barrier, but requires acceptable initial extraction quality |
| **Reconciliation** | Present in MVP (not reviewed in depth yet) | Deterministic Python rules against structured data | To be compared once we review the MVP's implementation |
```

<!-- WHY: Tradeoff column test passes — rows genuinely land both ways. "Simpler, but
the vector DB may serve purposes..." acknowledges a real unknown. The reconciliation
row explicitly defers comparison. Preamble scopes what's being compared and invites
correction.
Principle: "Fair to existing work" + tradeoff column self-test. -->

---

## 4. Validation Checklist Split

```markdown
## To Validate with the Client

- [ ] **Data residency**: Are there restrictions on where trade documents can be
  processed/stored?
- [ ] **Document formats**: Are PDFs always text-based (not scanned)?
- [ ] **Sample documents**: We need representative samples from different parties.

## Open Questions (Internal)

- Transaction data model details — phase 1 model as starting point
- OneDrive -> AWS trigger mechanism (PA Cloud HTTP action vs Graph API webhook)
- Level of involvement from original team vs our team
```

<!-- WHY: Split by who answers. Client questions need escalation by the audience;
internal questions the team resolves themselves. A single flat checklist forces the
reader to mentally triage — this does it for them.
Principle: Audience-based validation checklist splitting. -->

---

## 5. Implementation Detail in Framing

The framing block says: *"The reconciliation module was not reviewed in depth yet"* — scoping what's included. Then at the end:

```markdown
## Implementation-Phase Flags

Items acknowledged in design but deferred to implementation for detailed design:

- Example store quality controls (review/approval before corrections become active)
- Multi-pass extraction strategy (same model twice? different models?)
- Sensitive field encryption/masking specifics
```

<!-- WHY: Implementation detail is present but explicitly deferred — "acknowledged in
design but deferred to implementation." The framing block scopes the document as a
proposal; this section makes clear the detail isn't smuggled in as decided.
Principle: "If including implementation specifics, acknowledge it in the framing block." -->

---

## 6. Status Markers

```markdown
Transaction (shape TBD - phase 1 model exists as baseline)
├── documents: [{doc_type, party, extracted_fields, confidence}]
├── hierarchy: which document is the "source of truth" for each field
└── reconciliation_rules: [...]

Document field namespace mapping: TBD
  (how doc_type maps to the field names used in reconciliation rules)
```

```markdown
Current MVP has a Streamlit-based manual flagging UI. To be evolved into this
feedback loop model. Details TBD.
```

<!-- WHY: TBD markers appear in context — inside data model definitions and UI plans,
not in a separate "open items" list. The reader sees exactly what's decided and what
isn't, right where it matters. Honest about what's not decided without undermining
confidence in what is.
Principle: Status markers for incomplete items. -->

---

## 7. Section Ordering

The v5 uses this structure:

1. **Core Insight** — reframes everything
2. **Problem** — shared understanding
3. **Context** — domain specifics
4. **Comparison Table** — what changes and why (led early for a team that built the MVP)
5. **Non-Negotiables** — common ground before diverging
6. **Architecture** — the proposal itself
7. **Infrastructure** — grounding decisions
8. **Cost / Migration / Design Decisions** — supporting detail
9. **Validation Checklists** — what's next

<!-- WHY: Audience is the team that built the MVP. Comparison comes early so they see
how this relates to their work before diving into new architecture. Non-negotiables
before architecture establishes common ground — "regardless of approach, these must be
true." Validation checklists last because they're the natural "what do we do next?"
Principle: "What the audience cares about most goes first." -->
