# Export Document Extraction & Reconciliation — Technical Proposal

> **What this is:** An alternative architecture proposal for export document extraction, based on a review of the current MVP (phase 2). This analysis focuses on the extraction pipeline, annotation UI, and general architecture — the MVP's reconciliation module was not reviewed in depth and is not being compared here. Other aspects of the current system (operational procedures, team workflows, edge cases the team has already solved) were not evaluated in depth and likely have strengths not reflected here. The purpose is to present an architectural direction for discussion — not to prescribe a replacement.

## The Core Insight

**Reconciliation is the product, extraction is the tool.** The business value is finding discrepancies across documents in a transaction — the output (flagged problems + notifications) is what matters. Extraction accuracy matters because it serves reconciliation, not as an end in itself. Architecture decisions should flow from this.

---

## 1. Project Context

### Challenge

Export transactions involve 5–10 document types (bills of lading, commercial invoices, bank documents, customs declarations, etc.) issued by multiple parties, each with their own formats — formats that change over time, even for the same party. Documents mix Spanish and English, sometimes within the same page. Volume is low. Accuracy is what matters — errors are extremely costly.

The phase 1 approach used deterministic Python scripts for field extraction — parsing variable layouts with rigid rules. This broke under format variance because the extraction itself was deterministic: when a party changed their invoice format, the parser broke. The current MVP (phase 2) addressed this by introducing OCR, embeddings, a vector database (Qdrant), and LLM extraction with a Streamlit UI for manual bounding-box annotation. The current deployment runs on Power Automate (PA) Desktop + OneDrive + Teams on a Windows machine, which has proven unreliable (crashes, manual overhead).

This proposal also uses deterministic Python — but only for stages where the input is already structured (schema validation on extracted fields, rule-based reconciliation across documents). The variable-format extraction that broke phase 1 is handled entirely by the LLM. This is the key architectural distinction: deterministic code operates on LLM-extracted structured data, not on raw document formats.

### Objectives

1. **Reliable extraction** across document types and party formats, tolerant to format changes over time
2. **Automated reconciliation** with clear discrepancy reporting
3. **Self-improving system** — user corrections feed back as examples, reducing manual effort over time
4. **Full audit trail** — every extraction, correction, and reconciliation event tracked and reproducible
5. **Stable deployment** — no dependency on a single desktop machine

---

## 2. Comparison: Current MVP vs Proposed Approach

Note: This comparison covers the areas we reviewed. The MVP's reconciliation module was not reviewed in depth and is not being compared here. The MVP's approach may have strengths or handle edge cases we haven't identified yet — this table reflects our current understanding and is open to correction.

| Area | Current MVP (Phase 2) | Proposed | Tradeoff |
|------|----------------------|----------|----------|
| **Preprocessing** | Text extraction → embeddings → vector DB (Qdrant) | Direct text extraction, no embeddings (PDFs assumed text-based, to be validated) | Proposed has fewer moving parts. The vector DB may serve purposes beyond schema lookup (e.g., fuzzy matching across format variants) that we haven't fully explored |
| **Knowledge base** | Vector DB with embedded document fragments | Simple example store (JSONs per doc_type + party) | Less infrastructure, easier to debug, human-readable examples. Tradeoff: may not scale if example volume grows significantly |
| **Annotation** | Manual bounding-box flagging before extraction (Streamlit UI) | Feedback loop: extract first, user verifies/corrects after. MVP's annotation approach would still be used for initial seeding of new doc_type+party combos | Lower ongoing barrier, but requires acceptable initial extraction quality to be useful |
| **LLM usage** | Single extraction pass with embedded context | Scoped: Classify (identify doc) then Extract (get fields), separately | Each step can be tested, measured, and optimized independently. Tradeoff: two LLM calls instead of one |
| **Reconciliation** | Present in MVP (not reviewed in depth yet) | Deterministic Python rules against structured extracted data | To be compared once we review the MVP's reconciliation implementation. Both approaches are deterministic. |
| **Deployment** | PA Desktop on Windows machine | PA Cloud (glue) + AWS (processing) | Reliable, no desktop dependency, team stays in familiar tools |
| **Accuracy tracking** | Not identified in initial review | Recurring validation against historical data + full audit trail | Non-negotiable for this domain |

---

## 3. Non-Negotiables

These should apply regardless of which architecture is chosen:

1. **Data model comes first.** Document type schemas, reconciliation rules, and party profiles must be declarative and versioned, not buried in code. Without this, the system is a black box that can't be audited or extended without developer intervention.

2. **Full audit trail.** Every extraction, user correction, and reconciliation event must be immutably logged — who, when, what, which model, which prompt version. This is both a regulatory requirement (trade documents) and essential for debugging.

3. **Accuracy validation against ground truth.** System accuracy must be measured against verified historical data on a recurring basis. This is the real accuracy metric, not LLM confidence scores (which are unreliable as a sole measure).

4. **Human review for low confidence.** Documents where extraction confidence is below threshold must route to a human review queue. Never silently process uncertain documents — errors in trade document reconciliation are extremely costly.

5. **Metrics on every stage.** Execution time, accuracy (vs user corrections), volume — per stage, not just end-to-end.

6. **Reliable deployment.** The current PA Desktop setup on a Windows machine has stability issues. Production deployment needs to be on managed infrastructure.

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
| **Classify** | Text content | `{doc_type, party, confidence}` | Yes | Reject if low confidence |
| **Extract** | Text + doc_type schema + examples | `{fields, confidence_per_field}` | Yes | Partial extraction OK |
| **Validate** | Extracted fields + schema | `{valid, errors}` | No — schema validation | Flags missing required fields |
| **Reconcile** | All validated docs in transaction | `{discrepancies}` | No — declarative rule application | Only runs when enough docs present |
| **Report** | Discrepancies | Annotated PDFs with flagged problems + notifications | No — Python | Always succeeds |

Stages 0, 3, 4, 5 are pure Python — no LLM involved. The LLM is scoped to classification and extraction only.

#### Ingest Notes

- PDFs are assumed to be text-extractable (not scanned). To be validated with the client.
- Excel structure (multi-sheet, etc.) needs investigation during implementation — format of input data is TBD.
- Multi-document PDFs (e.g., invoice + packing list concatenated in one file) — unknown if this occurs. Flag during implementation if encountered.

### Data Model

Versioned, declarative schemas — not buried in code.

```
DocumentType (e.g., "bill_of_lading", "commercial_invoice")
├── required_fields: [{name, type, validation_rules}]
├── optional_fields: [...]
├── version: semver
└── aliases: ["BOL", "B/L", ...]

PartyProfile (e.g., "bank_xyz", "shipper_abc")
├── document_types: [which types they issue]
└── known_formats: [references to examples]

Transaction (shape TBD — phase 1 model exists as baseline)
├── documents: [{doc_type, party, extracted_fields, confidence}]
├── hierarchy: which document is the "source of truth" for each field
└── reconciliation_rules:
    └── [{field_a: "invoice.total", field_b: "bank_doc.amount", comparator: "exact"}]

Document field namespace mapping: TBD
  (how doc_type maps to the field names used in reconciliation rules)
```

Reconciliation is a deterministic operation — rules are declarative and testable: "invoice.total must match bank_doc.amount." The mapping details (which fields map where, when to trigger reconciliation) are TBD, but the approach is clear.

Documents have hierarchy — not all comparisons are symmetric. Some documents are the reference for specific fields.

### Processing Flow

The pipeline runs **per document**. A document is identified by file + content hash. A document is only re-processed if its content has changed (new hash).

When a new file is uploaded or an existing file is modified:
1. Pipeline runs for that document (Ingest → Classify → Extract → Validate)
2. Results are stored with full version history
3. If the transaction has enough documents, Reconcile + Report run for the transaction

#### Transaction Grouping

Documents are grouped into transactions **by folder** — all files in one OneDrive folder = one transaction. Users don't rename files, so classification must rely on content, not filenames.

Transactions can be **partially complete** — reconciliation runs with whatever documents are available and flags what's missing.

#### Deduplication

Same document uploaded twice (copied, re-saved) must be detected. Content-hash based — catches duplicates regardless of filename.

#### Low Confidence Handling

Confidence-based routing is a safety net, not the accuracy mechanism. The real accuracy measure is recurring validation against historical data (see Tracking & Metrics). The routing works as follows:

1. **First**: Request more examples for that doc_type+party combo (feedback loop)
2. **If still low**: Route to **human review queue** — never silently process uncertain documents.

#### Error Handling

- **Retry with backoff** for transient failures (LLM API, network)
- **Dead-letter queue** for documents that fail after retries — requires manual review
- **Failure alerting**: Multiple document failures in a short window trigger team notification (likely indicates a systematic issue like a party changing their format)

### LLM Role (Scoped)

The LLM is used for:

- **Classify**: "What type of document is this, and from whom?" — expected to be highly reliable with good prompts
- **Extract**: Given doc type schema + few examples, extract fields
- **Multi-pass extraction** (conceptual): For high-stakes fields, run extraction multiple times or with different prompt strategies and compare. Design details TBD.

Prompts should be **versioned** — tied to extraction results so past results can be reproduced and explained.

We'd propose replacing the embeddings/vector DB layer with a simpler **example store** (annotated JSONs per doc_type+party combo) — less complexity, easier to debug. The vector DB may have advantages we haven't fully explored, so this is a point for discussion.

Example selection: if the number of examples per doc_type+party is small (expected), use all related examples. Revisit if example volume grows significantly.

### Example & Feedback Storage

Examples and user corrections live in S3 (or equivalent cloud storage), structured by doc_type and party:

```
examples/{doc_type}/{party_id}/
├── example_001.json   # annotated extraction
├── example_002.json
└── ...
```

Lightweight DB (DynamoDB or equivalent) for indexing and metadata. Corrections from the feedback loop UI are saved here and become new examples automatically.

**Example quality**: Bad corrections can poison future extractions. Consider a review/approval step before corrections become active examples. (Implementation detail — flag during build.)

### UI as Feedback Loop

Reframe from "annotate before extraction" to "verify after extraction":
- System extracts fields
- User reviews, corrects mistakes
- Corrections feed back as new examples
- Over time, fewer corrections needed

**Cold start**: For new doc_type+party combos with no examples, initial extraction quality will be lower. The first few documents will need more manual correction. The MVP's manual annotation approach can serve as the seeding mechanism for initial examples before the feedback loop takes over.

Current MVP has a Streamlit-based manual flagging UI (bounding box annotation). To be evolved into this feedback loop model. Details TBD.

### Config-Driven Document Types

The system is **config-driven**: document type schemas define what fields to extract and how to validate them. Adding a new document type means adding a schema definition and a few examples — the extraction and validation code is generic and operates on whatever schema it's given. This is a design goal, not a guarantee — edge cases in field structure may require adjustments.

### Tracking & Metrics

**Full audit trail is mandatory.** Every processing event is tracked:
- What was extracted, when, which prompt version, which model
- User corrections: who corrected what, when, old value vs new value
- Reconciliation results per transaction over time

Per-stage metrics:
- Execution time
- Accuracy (vs user corrections)
- Volume / throughput

#### Validation Testing with Historical Data

Run extraction against historical/known-good data on a recurring basis to detect accuracy drift. This is the primary mechanism for ensuring the system stays reliable over time — not LLM confidence scores (which are unreliable), but measured accuracy against verified ground truth.

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

### Design Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| Data model first | Without versioned schemas and explicit reconciliation rules, the system is a black box |
| Decomposed pipeline | Each stage testable, measurable, and can fail independently |
| Simple example store over vector DB | Few document types, known schemas — open to discussion if the vector DB serves additional purposes |
| PA Cloud as glue, not processing | Keeps team in familiar tools, moves heavy lifting to reliable infra |
| Bedrock + Claude | Managed, pay-per-use, no fixed infrastructure cost at low volume |
| Feedback loop UI | Lower barrier than manual annotation, improves over time |
| Python for all deterministic stages | Consistent stack, team knows it, rich library ecosystem for file parsing |
| Step Functions for orchestration | Sequential stages with clear state transitions, built-in retry/error handling |
| Recurring validation against historical data | Accuracy drift detection — more reliable than LLM confidence scores |
| Full audit trail | Regulatory requirement, also needed for debugging and accuracy tracking |
| Config-driven document types | New document types without code changes, schema defines behavior |

### Top Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **LLM accuracy on edge cases** — unusual formats, mixed-language fields, handwritten annotations | High | Multi-pass extraction for high-stakes fields, human review queue for low confidence, recurring validation against ground truth |
| **Example quality poisoning** — bad user corrections degrade future extractions | Medium | Review/approval step before corrections become active examples [TBD — implementation detail] |
| **Format drift** — parties change document formats without notice | Medium | Failure alerting when multiple documents from the same party fail, feedback loop accelerates adaptation |
| **Excel input complexity** — multi-sheet structures, merged cells, non-standard layouts | Medium | Investigate during implementation — format of input data is [TBD] |
| **OneDrive → AWS trigger reliability** — PA Cloud HTTP action vs Graph API webhook | Low | Both approaches are proven; test during implementation to determine latency and reliability |

---

## 10. Migration & Coexistence

This proposal does not assume throwing away the current MVP. Possible paths forward:

- **Incremental replacement**: Keep the MVP running, build the proposed pipeline alongside it, migrate stage by stage as each is validated
- **MVP as reference**: Use the MVP's extraction results as a benchmark to validate the proposed approach against
- **Shared components**: The MVP's annotation UI and any operational learnings can be carried forward

The right path depends on the team's assessment of what's working well in the MVP and what isn't. This should be a collaborative decision.

The phase 1 transaction model (reconciliation rules, field definitions) carries over regardless of approach — it represents domain knowledge that doesn't depend on the processing architecture.

---

## 11. To Validate with the Client

These need client input before implementation can proceed:

- [ ] **Data residency**: Are there restrictions on where trade documents can be processed/stored? (Affects AWS region choice and Bedrock availability)
- [ ] **Data retention/deletion**: How long must documents and extraction results be kept? Any mandatory destruction timelines?
- [ ] **Access control needs**: Who should see what? Different roles for different transaction types?
- [ ] **Document formats**: Are PDFs always text-based (not scanned)? Do they ever concatenate multiple documents in one file?
- [ ] **Excel input**: What does the Excel data look like? Multi-sheet? What structure?
- [ ] **Languages**: Beyond Spanish and English, are other languages present?
- [ ] **Transaction completeness**: Is there a point where a transaction is "closed"? Or does it stay open indefinitely for new documents?
- [ ] **Reconciliation tolerance**: Are there fields where near-matches are acceptable (rounding, formatting differences)? Or is it strictly exact match = OK, anything else = costly fee to pay?
- [ ] **Sample documents**: We need access to representative samples from different parties for each document type to validate the approach.

## 12. Open Questions (Internal)

- Transaction data model details (reconciliation rule format, document hierarchy, how to handle incomplete transactions) — phase 1 model as starting point
- Document field namespace mapping (how doc_type maps to reconciliation rule field names)
- OneDrive → AWS trigger mechanism (PA Cloud HTTP action vs Graph API webhook)
- Model tier testing results (Haiku vs Sonnet vs Opus accuracy/cost for each stage)
- Level of involvement from original team vs our team
- Ingest tooling: which Python libraries for PDF text extraction, Excel, Word parsing
- Human review queue UX — how does the reviewer interact, where does it live
- 1:1 vs 1:N field relationships in reconciliation (e.g., one invoice total vs multiple partial shipment BOLs)
- Discrepancy severity levels (amount mismatch vs reference number format mismatch)
- Review of MVP reconciliation module (pending)

## Implementation-Phase Flags

Items acknowledged in design but deferred to implementation for detailed design:

- Example store quality controls (review/approval before corrections become active)
- Multi-pass extraction strategy (same model twice? different models? structured output validation?)
- Sensitive field encryption/masking specifics
- Failure alerting thresholds and notification channels
- Historical validation test suite setup and scheduling
