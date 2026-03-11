# Proposal Template Reference

Reference structure for the `shape-proposal` skill. Not a rigid template — the skill selects and adapts sections based on audience, context, and source material.

## How This Works

The source document (brainstorm output, design doc, etc.) contains the technical substance. This template defines how to **structure and present** that substance as a proposal. Sections are included or excluded based on what the source material covers and what the audience needs.

---

## Framing Block

Every proposal starts with a framing block that sets expectations for the reader.

**Always include:**
- What this document is (and isn't)
- What was reviewed / what's in scope
- The purpose: feedback request, decision request, alignment, pitch, etc.

**When proposing alternatives to existing work, also include:**
- What you reviewed and what you didn't
- Explicit acknowledgment that the existing approach may have strengths not fully explored

**Guidance:**
- Confident but honest about scope boundaries
- One paragraph, not a wall of disclaimers

---

## Core Sections

These 8 sections form the backbone. All are included by default — the skill drops or merges sections only when the source material genuinely doesn't cover that area.

### 1. Project Context

**What it covers:** Problem statement, current state, objectives.

**Subsections:**
- **Challenge / Problem**: Current process, pain points, business impact. Quantify when possible (hours, error rates, cost).
- **Solution Objective**: 3-5 measurable outcomes the proposal aims to achieve.

**Guidance:**
- Use the audience's language, not yours
- Connect technical goals to business value
- If the audience already knows the problem, keep this brief — don't over-explain what they live with daily

### 2. Tech Stack

**What it covers:** Technology choices and justifications.

**Format:** Table with Component | Technology | Justification.

**Categories to consider:**
- Backend / Frontend frameworks
- Data processing / pipeline tools
- Databases / storage
- LLM / AI services (if applicable)
- Infrastructure / orchestration
- Testing / code quality
- Security tooling

**Guidance:**
- Every choice needs a justification — "we know it" is valid but say it explicitly
- Flag decisions pending input with status markers
- If comparing against existing work, acknowledge what the current stack does well

### 3. Architecture

**What it covers:** System design, components, data flow.

**Structure:**
- Component overview (numbered list with brief input → output description)
- Per-component detail: purpose, responsibilities, outputs, tech stack
- Data flow between components

**Guidance:**
- Lead with the decomposition, then detail each part
- Make each component's boundaries clear — what it does, what it doesn't
- If stages can fail independently, say so — it demonstrates maturity

### 4. Configuration & Validation

**What it covers:** How the system is configured and how data quality is ensured.

**Include when:** The system has configurable behavior, multiple environments, or data validation requirements.

**Topics:**
- Configuration management approach (files, env vars, hierarchy)
- Validation strategy (schema validation, data quality, API validation)
- What's config-driven vs hard-coded

**Guidance:**
- Skip this section if it's a straightforward application with no meaningful config surface
- For data pipelines, this section carries significant weight

### 5. Development Standards

**What it covers:** Code quality, testing, and development practices.

**Topics:**
- Code quality tooling (linting, formatting, type checking)
- Testing strategy and coverage targets
- CI/CD approach (if in scope)
- Documentation standards

**Guidance:**
- Keep proportional to the proposal scope — a 2-person project doesn't need a page on standards
- Focus on what differs from "obvious best practices" — the audience doesn't need to be told to use version control

### 6. Risks & Technical Decisions

**What it covers:** Known risks, mitigation strategies, and decisions deferred to later phases.

**Structure:**
- Top 3-5 risks with severity and mitigation
- Deferred decisions with criteria for resolution
- Assumptions made and their basis

**Guidance:**
- Risks should be real, not performative. "The API might change" is a real risk. "The project might fail" is not useful.
- Deferred decisions should have a clear resolution mechanism (phase 1 PoC, client input, testing)

### 7. Team & Resources

**What it covers:** Team structure, roles, and why this composition.

**Include when:** The proposal involves staffing decisions, resource allocation, or role definitions.

**Structure:**
- Team structure table: Role | Responsibilities | Key Skills | Critical Phases
- Justification for team size and composition
- Collaboration model with existing team (if applicable)
- QA distribution (if no dedicated QA role)

**Guidance:**
- Skip this section for internal proposals where the team is already defined
- When proposing to a team that built the existing system, be explicit about collaboration model — this isn't a replacement, it's augmentation

### 8. References

**What it covers:** Proven patterns, past projects, and source documentation.

**Include when:** There are relevant precedents, external docs, or established patterns backing the proposal.

**Topics:**
- Architectural patterns from past projects
- Client/external documentation referenced
- Industry standards or best practices applied

**Guidance:**
- Don't pad this section — only include references that genuinely inform the proposal
- Skip entirely if there are no meaningful references to cite

---

## Contextual Sections

Added based on audience needs and proposal context. The skill evaluates which apply.

### A. Comparison Table

**When to include:** Proposing an alternative to existing work, or comparing multiple approaches.

**Format:** Table with Area | Current/Option A | Proposed/Option B | Tradeoff.

**Guidance:**
- Lead with this section when the audience built or owns the thing being compared
- The "Tradeoff" column is critical — "Why" sounds like you've already decided; "Tradeoff" invites discussion
- Acknowledge where the existing approach may have advantages you haven't fully explored
- Keep rows to areas where there's a meaningful difference

### B. Requirements / Non-Negotiables

**When to include:** Proposing to an audience that may choose a different architecture. Separates "what must happen" from "how we'd do it."

**Guidance:**
- Frame as "regardless of which approach is chosen"
- These should be hard to disagree with — data model, audit trail, accuracy validation, not "use our preferred framework"
- Usually 4-6 items

### C. Cost Estimation

**When to include:** Budget matters to the audience, or the proposal involves infrastructure choices with cost implications.

**Format:** Table with Component | Cost Driver | Estimate.

**Guidance:**
- Always include a "bottom line" summary
- Compare with alternatives when relevant (managed service vs self-hosted)
- Flag estimates as rough and specify what would refine them
- Separate one-time setup costs from recurring operational costs

### D. Security & Compliance

**When to include:** Sensitive data, regulatory requirements, or the audience cares about data handling.

**Topics:** Data residency, access control, audit trail, data retention, sensitive field handling.

**Guidance:**
- Frame as questions to validate with stakeholders where requirements are unknown
- Don't overspecify — "encryption at rest" is enough at proposal stage, not cipher suite details

### E. Migration / Coexistence

**When to include:** The proposal replaces or modifies something that already exists and is running.

**Guidance:**
- Present multiple paths (incremental replacement, parallel operation, staged migration)
- Signal collaboration, not replacement — "the right path depends on the team's assessment"
- Acknowledge operational risk of migration

### F. Validation Checklist

**When to include:** Decisions require stakeholder input before implementation can proceed.

**Format:** Checklist of items needing input, grouped by urgency.

**Guidance:**
- Each item should be a clear question, not a vague topic
- Include why the answer matters (affects region choice, blocks implementation, etc.)

### G. Framework / Technology Comparison

**When to include:** A critical technology decision has 2-3 viable options requiring evaluation.

**Format:** Comparison table with evaluation criteria, recommendation or deferral to discovery phase.

**Guidance:**
- Different from section A (Comparison Table) — this is about internal tech choices, not current-vs-proposed

### H. Deployment Architecture

**When to include:** Multi-service deployment, containerization, or infrastructure choices are in scope.

### I. Monitoring & Observability

**When to include:** Production system requiring operational visibility.

---

## Status Markers

For in-progress proposals, use status markers to track what needs attention:

| Marker | Meaning |
|--------|---------|
| `[WIP]` | Section is incomplete |
| `[TBD]` | Decision not yet made |
| `[TO VALIDATE]` | Needs stakeholder confirmation |
| `[MISSING INFO]` | Information not yet available |
| `[ASSUMED]` | Reasonable assumption made, to be validated |

Remove all markers before final version.

---

## Section Ordering

Default order follows the numbered core sections, with contextual sections inserted where they have the most impact:

- **Comparison Table (A)**: After Project Context, before Architecture — when the audience needs to see the delta first
- **Non-Negotiables (B)**: After Project Context — establishes common ground before diverging into architecture
- **Cost Estimation (C)**: After Infrastructure / Architecture sections
- **Security (D)**: After Architecture or as part of Infrastructure
- **Migration (E)**: Near the end, after the full proposal is laid out
- **Validation Checklist (F)**: Last — the natural "what's next" after reading everything
- **Tech Comparison (G)**: After Tech Stack
- **Deployment (H)**: After Architecture
- **Monitoring (I)**: After Deployment or Infrastructure
