# Export Document Extraction & Reconciliation — Technical Proposal

> **What this is:** An alternative architecture proposal for export document extraction, based on a review of the current MVP (phase 2). This analysis focuses on the extraction pipeline, reconciliation model, and infrastructure — it does not cover UI/UX design or business process changes beyond document processing. The existing MVP's Streamlit annotation approach and vector DB layer were reviewed at a high level; other aspects of the current system (operational procedures, team workflows, edge cases the team has already solved) were not evaluated in depth and likely have strengths not reflected here. The purpose is to present an architectural direction for discussion — not to prescribe a replacement.

---

## 1. Project Context

### Challenge

Export transactions involve 5–10 document types (bills of lading, commercial invoices, bank documents, customs declarations, etc.) issued by multiple parties, each with their own formats — formats that change over time, even for the same party. Documents mix Spanish and English, sometimes within the same page.

The phase 1 approach used deterministic Python scripts for field extraction — parsing variable layouts with rigid rules. This broke under format variance because the extraction itself was deterministic: when a party changed their invoice format, the parser broke. The current MVP (phase 2) addressed this by introducing OCR, embeddings, a vector database (Qdrant), and LLM extraction with a Streamlit UI for manual bounding-box annotation. The current deployment runs on Power Automate (PA) Desktop + OneDrive + Teams on a Windows machine, which has proven unreliable (crashes, manual overhead).

This proposal also uses deterministic Python — but only for stages where the input is already structured (schema validation on extracted fields, rule-based reconciliation across documents). The variable-format extraction that broke phase 1 is handled entirely by the LLM. This is the key architectural distinction: deterministic code operates on LLM-extracted structured data, not on raw document formats.

The core problem remains: **extracting structured fields from variable-format documents, then reconciling those fields across documents in a transaction to flag discrepancies** — reliably, with minimal manual intervention, and with full auditability.

### Objectives

1. **Reliable extraction** across document types and party formats, tolerant to format changes over time
2. **Automated reconciliation** with clear discrepancy reporting
3. **Self-improving system** — user corrections feed back as examples, reducing manual effort over time
4. **Full audit trail** — every extraction, correction, and reconciliation event tracked and reproducible
5. **Stable deployment** — no dependency on a single desktop machine

---

## 2. Comparison: Current MVP vs Proposed Approach

| Area | Current MVP (Phase 2) | Proposed | Tradeoff |
|------|----------------------|----------|----------|
| **Document processing** | OCR → embeddings → vector DB (Qdrant) → LLM | Text extraction → LLM classification → LLM extraction | Proposed has fewer moving parts. Current approach handles scanned/image-based documents — if documents are sometimes scanned rather than text-based PDFs, this is a real advantage the proposed approach doesn't address [TO VALIDATE] |
| **Example management** | Vector DB similarity search for relevant examples | Flat example store (S3), structured by doc_type + party | At current scale (~5–10 doc types), a flat store is likely sufficient and easier to debug. The vector DB approach may handle edge cases better (e.g., unusual formats that don't match a known doc_type+party combo exactly) — this wasn't fully evaluated [ASSUMED: flat store sufficient at current scale] |
| **User interaction** | Pre-extraction annotation (bounding boxes in Streamlit) | Post-extraction verification (review + correct) | Pre-extraction annotation produces higher-quality training data with explicit field locations. Post-extraction verification has lower per-document user effort but depends on extraction being good enough to correct rather than start from scratch [ASSUMED: extraction quality sufficient for verify-and-correct workflow] |
| **Data model** | [TO VALIDATE] — unclear how schemas are currently managed | Versioned declarative schemas (doc types, reconciliation rules, party profiles) | Declarative schemas make the system configurable without Python changes (though schema/rule changes still require careful validation). The current approach may already have equivalent mechanisms not reviewed here |
| **Pipeline architecture** | [TO VALIDATE] — unclear if processing is monolithic or staged | 6-stage decomposed pipeline (Ingest → Classify → Extract → Validate → Reconcile → Report) | Decomposed stages are independently testable and measurable. A more integrated approach can be simpler to deploy and debug end-to-end |
| **Deployment** | Power Automate Desktop on Windows machine | Power Automate Cloud (glue) + AWS (processing) | PA Cloud eliminates single-machine dependency. PA Desktop gives the team direct control and visibility on the machine — operational familiarity has real value |
| **Reconciliation** | [TO VALIDATE] — unclear how current MVP handles cross-document reconciliation | Declarative rules with document hierarchy (which doc is source of truth per field) | — |
| **Prompt management** | [TO VALIDATE] — unclear if prompts are versioned | Versioned prompts tied to extraction results for reproducibility | — |

---

## 3. Non-Negotiables

Regardless of which architectural approach is chosen, these should hold:

1. **Versioned data model** — Document type schemas, reconciliation rules, and party profiles must be declarative and versioned, not buried in code. Without this, the system is a black box that can't be audited or extended without developer intervention.

2. **Full audit trail** — Every extraction, user correction, and reconciliation event must be immutably logged with timestamps, model versions, and prompt versions. This is both a regulatory requirement (trade documents) and essential for debugging.

3. **Accuracy validation against ground truth** — System accuracy must be measured against verified historical data on a recurring basis. LLM confidence scores are unreliable as a sole accuracy metric — measured accuracy against known-good extractions is the primary mechanism for detecting drift.

4. **Human review for low confidence** — Documents where extraction confidence is below threshold must route to a human review queue. Never silently process uncertain documents — errors in trade document reconciliation are extremely costly.

5. **Plug-and-play document types** — Adding a new document type should require a schema definition and a few examples, not Python code changes. Note: adding a document type that participates in reconciliation also requires updating cross-document reconciliation rules — this is configuration, not code, but still requires careful validation since incorrect rules can produce false discrepancies or miss real ones.

---

## 4. Architecture

### Pipeline Overview

```
0. INGEST  →  1. CLASSIFY  →  2. EXTRACT  →  3. VALIDATE  →  4. RECONCILE  →  5. REPORT
```

Each stage is independent, individually testable, and can fail without taking down the pipeline. All non-LLM stages are deterministic Python. Orchestrated via AWS Step Functions.

### Stage Detail

| Stage | Input | Output | LLM? | Failure mode |
|-------|-------|--------|------|--------------|
| **Ingest** | Raw file (PDF/Excel/Word) | Extracted text/structured content | No — Python text extraction | Unsupported format, corrupt file |
| **Classify** | Text content | `{doc_type, party, confidence}` | Yes (Haiku — fast, cheap) | Reject if low confidence |
| **Extract** | Text + doc_type schema + examples | `{fields, confidence_per_field}` | Yes (Sonnet/Opus — accuracy) | Partial extraction OK |
| **Validate** | Extracted fields + schema | `{valid, errors}` | No — schema validation | Flags missing required fields |
| **Reconcile** | All validated docs in transaction | `{discrepancies}` | No — declarative rule application | Only runs when enough docs present |
| **Report** | Discrepancies + extraction results | Human-readable output | No — Python | Always succeeds |

### Data Model

```
DocumentType (e.g., "bill_of_lading", "commercial_invoice")
├── required_fields: [{name, type, validation_rules}]
├── optional_fields: [...]
├── version: semver
└── aliases: ["BOL", "B/L", ...]

PartyProfile (e.g., "bank_xyz", "shipper_abc")
├── document_types: [which types they issue]
└── known_formats: [references to examples]

Transaction
├── documents: [{doc_type, party, extracted_fields, confidence}]
├── hierarchy: which document is source of truth for each field
└── reconciliation_rules:
    └── [{field_a: "invoice.total", field_b: "bank_doc.amount", comparator: "exact"}]
```

Reconciliation rules are declarative — "invoice.total must match bank_doc.amount." Documents have hierarchy: not all comparisons are symmetric. Some documents are the reference for specific fields.

### Processing Flow

The pipeline runs **per document**. A document is identified by file + version (upload timestamp). Documents are only reprocessed when modified.

- Documents are grouped into transactions **by folder** — all files in one OneDrive folder = one transaction [ASSUMED — based on current workflow observation, to be confirmed with the team]
- Classification relies on content, not filenames [ASSUMED — based on the understanding that users don't consistently rename files, to be validated]
- Content-hash based deduplication catches duplicates regardless of filename
- Transactions can be partially complete — reconciliation runs with available documents and flags what's missing

### LLM Role (Scoped)

The LLM does exactly two things:

1. **Classify**: "What type of document is this, and from whom?" — high reliability with well-structured prompts
2. **Extract**: Given the document type schema + few-shot examples, extract fields with per-field confidence

At current scale (~5–10 document types, known schemas), this proposal uses a flat **example store** (annotated JSONs per doc_type + party combo) instead of embeddings and a vector DB. The hypothesis is that with few document types, direct example lookup by doc_type + party is sufficient and easier to debug. If example volume or document type count grows significantly, or if edge cases require fuzzy matching across formats, similarity search may prove more valuable [ASSUMED: flat store sufficient at current scale].

Prompts are **versioned** — tied to extraction results so past results can be reproduced and explained.

### Example & Feedback Loop

This proposal shifts the user interaction model from "annotate before extraction" to "verify after extraction":

1. System extracts fields automatically
2. User reviews results, corrects mistakes
3. Corrections are saved as new examples (S3, structured by doc_type/party)
4. Over time, fewer corrections needed

```
examples/{doc_type}/{party_id}/
├── example_001.json
├── example_002.json
└── ...
```

Lightweight DB (DynamoDB or equivalent) for indexing and metadata.

### Error Handling

- **Retry with backoff** for transient failures (LLM API, network)
- **Dead-letter queue** for documents that fail after retries — requires manual review
- **Failure alerting**: Multiple document failures in a short window trigger team notification (likely indicates a systematic issue like a party changing their format)

### Low Confidence Path

1. Request more examples for that doc_type + party combo (feedback loop)
2. If still low → route to human review queue. Never silently process uncertain documents.

---

## 5. Tech Stack

| Component | Technology | Justification |
|-----------|------------|---------------|
| Pipeline orchestration | AWS Step Functions | Sequential stages with clear state transitions, built-in retry/error handling |
| LLM — Classification | Amazon Bedrock + Claude Haiku | Cheaper, faster — classification is a simpler task |
| LLM — Extraction | Amazon Bedrock + Claude Sonnet/Opus | Accuracy-critical task, best available model justified by low volume + high error cost |
| Deterministic stages | Python | Consistent stack, team familiarity, rich library ecosystem for file parsing |
| Example storage | S3 | Simple, durable, structured by doc_type/party |
| Metadata / indexing | DynamoDB | Lightweight, serverless, sufficient for example metadata and processing state |
| Glue layer | Power Automate Cloud | Watches OneDrive, triggers AWS pipeline via HTTP, sends notifications. Team familiarity, no machine dependency |
| Notifications | Teams (Incoming Webhooks) + Email | Proven channels with this client |
| Input trigger | OneDrive folder watch (PA Cloud) | Client users won't change behavior — meet them where they are |

---

## 6. Cost Estimation: Bedrock vs Self-Hosted GPU

### Amazon Bedrock (Claude API — Pay-per-Use)

Based on current Bedrock pricing (via Anthropic's published rates, March 2026):

| Model | Input | Output | Use case |
|-------|-------|--------|----------|
| Claude Haiku 4.5 | $1.00 / MTok | $5.00 / MTok | Classification |
| Claude Sonnet 4.5+ | $3.00 / MTok | $15.00 / MTok | Extraction (standard) |
| Claude Opus 4.5+ | $5.00 / MTok | $25.00 / MTok | Extraction (high-stakes) |

**Estimated monthly cost** (rough, based on low volume — ~100–500 documents/month):

| Task | Model | Tokens/doc (est.) | Docs/month | Monthly cost |
|------|-------|--------------------|------------|-------------|
| Classification | Haiku | ~2K in + ~500 out | 500 | ~$3.50 |
| Extraction | Sonnet | ~5K in + ~2K out | 500 | ~$22.50 |
| Multi-pass extraction [TBD] | Sonnet/Opus | ~10K in + ~4K out | 100 (high-stakes only) | ~$13.00 |
| **Total** | | | | **~$39/month** |

Even at 5x volume (2,500 docs/month), Bedrock costs stay under **~$200/month**. Batch API (50% discount) could reduce this further for non-time-sensitive processing.

### Self-Hosted GPU (EC2)

Running a local open-source LLM (e.g., Llama 3, Mixtral) requires GPU instances:

| Instance | GPU | GPU Memory | On-Demand $/hr | Monthly (24/7) |
|----------|-----|------------|-----------------|----------------|
| g5.xlarge | 1x A10G | 24 GB | ~$1.01 | ~$727 |
| g5.4xlarge | 1x A10G | 24 GB | ~$1.62 | ~$1,167 |
| g5.12xlarge | 4x A10G | 96 GB | ~$5.67 | ~$4,082 |
| p4d.24xlarge | 8x A100 | 320 GB | ~$32.77 | ~$23,594 |

For a model capable of matching Claude's extraction accuracy on multilingual trade documents, you'd likely need at minimum a g5.12xlarge (4x A10G, 96 GB) to run a 70B+ parameter model at reasonable speed. Smaller instances could run smaller models, but with significant accuracy tradeoffs on this domain.

### Comparison

| Factor | Bedrock (Claude) | Self-Hosted GPU |
|--------|-----------------|-----------------|
| **Monthly cost** | ~$39–200 (scales with usage) | ~$727–4,082 (fixed, 24/7) |
| **Accuracy** | State-of-the-art on multilingual document extraction | Open-source models lag on domain-specific, multilingual tasks — [TO VALIDATE] with benchmarks |
| **Maintenance** | Zero — managed service | Model updates, instance management, monitoring |
| **Scaling** | Automatic | Manual instance scaling |
| **Latency** | API call (~1–5s) | Local inference (~1–10s depending on model/hardware) |
| **Data residency** | Bedrock supports region selection | Full control — data never leaves your VPC |

**Bottom line**: At current volume (~100–500 docs/month), Bedrock is **~20–100x cheaper** than maintaining a self-hosted GPU instance. Self-hosted becomes economically viable at very high volumes (tens of thousands of documents/month), but only if an open-source model can match Claude's accuracy on this specific task — which would need to be validated with benchmarks on actual export documents [TO VALIDATE].

Self-hosted has a clear advantage on **data residency** — if regulations prohibit sending trade document data to a third-party LLM service, self-hosting keeps everything within the client's VPC. Bedrock's region selection may address this depending on the specific regulatory requirements [TO VALIDATE with client].

---

## 7. Configuration & Validation

### Schema-Driven Extraction

Document type schemas are the central configuration mechanism:

- **Required fields** with types and validation rules (e.g., "amount must be numeric", "date must parse to ISO format")
- **Optional fields** with confidence thresholds for inclusion
- **Aliases** for document type matching during classification
- **Version history** — schema changes are tracked, extraction results reference the schema version used

Adding a new document type = define the schema + provide a few annotated examples. No Python code changes required — though reconciliation rules must also be updated if the new type participates in cross-document validation.

### Validation Strategy

- **Schema validation** (deterministic Python) runs after extraction — catches type mismatches, missing required fields, format violations
- **Cross-document validation** happens at the reconciliation stage — declarative rules compare fields across documents
- **Accuracy validation** runs on a recurring basis against historical ground truth — the primary drift detection mechanism

---

## 8. Security & Compliance

These items need stakeholder input — framed as questions, not decisions:

| Area | Question | Impact |
|------|----------|--------|
| **Data residency** | Which AWS regions are acceptable for processing trade documents containing pricing, banking details, and counterparty information? | Determines Bedrock region configuration and whether self-hosted is required |
| **Access control** | Who can view which transactions? Who can make corrections? Is role-based access sufficient, or is per-transaction/per-client access needed? | Shapes the access control model — simple roles vs fine-grained permissions |
| **Data retention** | What are the regulatory retention requirements for processed trade documents and extraction results? | Determines storage lifecycle policies and archival strategy |
| **Sensitive field handling** | Do bank account numbers, LC details, and pricing terms require field-level encryption beyond at-rest encryption? | Affects data model design and access patterns |
| **Audit compliance** | Are there specific audit formats or reporting requirements for document processing systems in this regulatory context? | Shapes the audit trail implementation |

The proposed architecture includes an immutable audit trail by design (every processing event logged with timestamps, model versions, prompt versions, and user corrections). This covers the technical foundation — regulatory specifics need client input.

---

## 9. Risks & Technical Decisions

### Top Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **LLM accuracy on edge cases** — unusual formats, mixed-language fields, handwritten annotations | High | Multi-pass extraction for high-stakes fields, human review queue for low confidence, recurring validation against ground truth |
| **Example quality poisoning** — bad user corrections degrade future extractions | Medium | Review/approval step before corrections become active examples [TBD — implementation detail] |
| **Format drift** — parties change document formats without notice | Medium | Failure alerting when multiple documents from the same party fail, feedback loop accelerates adaptation |
| **Excel input complexity** — multi-sheet structures, merged cells, non-standard layouts | Medium | Investigate during implementation — format of input data is [TBD] |
| **OneDrive → AWS trigger reliability** — PA Cloud HTTP action vs Graph API webhook | Low | Both approaches are proven; test during implementation to determine latency and reliability |

### Open Questions

These require input before or during implementation:

- **Transaction data model details** — reconciliation rule format, document hierarchy, handling of incomplete transactions. Phase 1 model exists as a starting point.
- **Document field namespace mapping** — how doc_type maps to the field names used in reconciliation rules
- **1:1 vs 1:N field relationships** — e.g., one invoice total vs multiple partial shipment BOLs. Affects reconciliation rule design.
- **Discrepancy severity levels** — is an amount mismatch the same severity as a reference number format mismatch?
- **Multi-document PDFs** — does this occur in practice (e.g., invoice + packing list concatenated in one file)?
- **Human review queue UX** — how does the reviewer interact, where does this interface live?
- **Level of involvement from original team** — collaboration model, knowledge transfer, handoff

### Deferred to Implementation

- Multi-pass extraction strategy details
- Example store quality controls (review/approval workflow)
- Sensitive field encryption specifics
- Failure alerting thresholds
- Historical validation test suite setup and scheduling

---

## 10. Migration & Coexistence

The current MVP (phase 2) is running and the team has operational experience with it. Any transition should be staged, not a hard cutover:

**Possible paths** (the right one depends on the team's assessment):

1. **Parallel operation** — Run the proposed pipeline alongside the current MVP on the same documents, compare results. Lowest risk, highest effort.
2. **Incremental replacement** — Replace one pipeline stage at a time (e.g., start with classification, then extraction), keeping the rest of the current system running. Moderate risk, allows validation at each step.
3. **New-document-types-first** — Use the proposed architecture only for document types not yet supported by the current MVP. No disruption to existing workflows. Builds confidence before migrating existing types.

The phase 1 transaction model (reconciliation rules, field definitions) carries over regardless of approach — it represents domain knowledge that doesn't depend on the processing architecture.

---

## 11. Validation Checklist

Items requiring stakeholder input before implementation can proceed, grouped by urgency:

### Blocks Architecture Decisions

- [ ] Data residency requirements — which AWS regions are acceptable? (determines Bedrock vs self-hosted)
- [ ] Access control model — role-based vs per-transaction permissions? (shapes data model)
- [ ] Collaboration model with original team — who owns what, knowledge transfer plan

### Blocks Implementation Start

- [ ] Excel input format — multi-sheet structure, sample files needed for ingest stage design
- [ ] Multi-document PDFs — does this occur? Affects ingest stage complexity
- [ ] Phase 1 transaction model review — confirm reconciliation rules and field mappings carry over as-is or need adaptation

### Needed During Implementation

- [ ] Discrepancy severity levels — amount mismatch vs format mismatch priority
- [ ] 1:1 vs 1:N field relationships in reconciliation
- [ ] Human review queue UX requirements
- [ ] Data retention / deletion policy
- [ ] Sensitive field encryption requirements
- [ ] Historical validation data — access to verified ground truth for accuracy testing
