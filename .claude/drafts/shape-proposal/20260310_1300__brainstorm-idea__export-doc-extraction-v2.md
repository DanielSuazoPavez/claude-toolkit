# Export Document Extraction & Reconciliation - Design (v2)

## Problem

Extract fields from export transaction documents (5-10 types, many parties/formats), reconcile across documents in a transaction, flag discrepancies. Replaces a deterministic Python approach that broke due to format variance.

## Context

- **Domain**: Exports business - regulatory documents from banks, shippers, clients, customs, etc.
- **Document types**: ~5-10 (bill of lading, commercial invoice, etc.)
- **Parties**: Many, each with different formats for the same document type. Formats change over time even for the same party.
- **Languages**: Documents contain Spanish and English, sometimes mixed in the same document. Other languages possible (open question).
- **Current MVP (phase 2)**: OCR -> embeddings -> vector DB (Qdrant) -> LLM extraction, with a Streamlit UI for manual bounding-box annotation.
- **Phase 1 (deprecated)**: Deterministic Python scripts - too brittle for format variance.
- **Phase 1 transaction model**: Already defines what fields to compare across document types. To be carried over.
- **Current deployment (phase 1)**: PA Desktop + OneDrive + Teams on a Windows machine. Unreliable (crashes), cumbersome.

## Core Architecture

### Data Model First

Versioned, declarative schemas - not buried in code.

```
DocumentType (e.g., "bill_of_lading", "commercial_invoice")
├── required_fields: [{name, type, validation_rules}]
├── optional_fields: [...]
├── version: semver
└── aliases: ["BOL", "B/L", ...]

PartyProfile (e.g., "bank_xyz", "shipper_abc")
├── document_types: [which types they issue]
└── known_formats: [references to examples]

Transaction (shape TBD - phase 1 model exists as baseline)
├── documents: [{doc_type, party, extracted_fields, confidence}]
├── hierarchy: which document is the "source of truth" for each field
└── reconciliation_rules:
    └── [{field_a: "invoice.total", field_b: "bank_doc.amount", comparator: "exact"}]

Document field namespace mapping: TBD
  (how doc_type maps to the field names used in reconciliation rules)
```

Reconciliation rules are declarative: "invoice.total must match bank_doc.amount".
Documents have hierarchy - not all comparisons are symmetric, some documents are the reference for specific fields.

### Decomposed Pipeline

```
0. INGEST  ->  1. CLASSIFY  ->  2. EXTRACT  ->  3. VALIDATE  ->  4. RECONCILE  ->  5. REPORT
```

Each stage independent, each with its own metrics. All non-LLM stages are Python. Orchestrated via **AWS Step Functions** (sequential stages, clear state transitions).

| Stage | Input | Output | LLM? | Can fail independently |
|-------|-------|--------|------|----------------------|
| **Ingest** | Raw file (PDF/Excel/Word) | Extracted text/structured content | No - deterministic Python (text extraction, parsers) | Yes - unsupported format, corrupt file |
| **Classify** | Text content | `{doc_type, party, confidence}` | Yes | Yes - reject if low confidence |
| **Extract** | Text + doc_type schema + examples | `{fields, confidence_per_field}` | Yes | Yes - partial extraction OK |
| **Validate** | Extracted fields + schema | `{valid, errors}` | No - deterministic Python schema validation | Yes - flags missing required fields |
| **Reconcile** | All validated docs in transaction | `{discrepancies}` | No - deterministic Python rule application | Yes - only runs when enough docs present |
| **Report** | Discrepancies | Human-readable output | No - Python | Yes |

#### Ingest Notes

- PDFs are assumed to be text-extractable (not scanned). Text extraction, not OCR.
- Excel structure (multi-sheet, etc.) needs investigation during implementation - format of input data is TBD.
- Multi-document PDFs (e.g., invoice + packing list concatenated in one file) - unknown if this occurs. Flag during implementation if encountered.

#### Processing Flow

The pipeline runs **per document**. A document is identified by file + version (upload timestamp). A document is only processed if it hasn't been processed in its current version.

When a new file is uploaded or an existing file is modified:
1. Pipeline runs for that document (Ingest -> Classify -> Extract -> Validate)
2. Results are stored with full version history
3. If the transaction has enough documents, Reconcile + Report run for the transaction

#### Transaction Grouping

Documents are grouped into transactions **by folder** - all files in one OneDrive folder = one transaction. Users don't rename files, so classification must rely on content, not filenames.

Transactions can be **partially complete** - reconciliation runs with whatever documents are available and flags what's missing.

#### Deduplication

Same document uploaded twice (copied, re-saved) must be detected. Content-hash based - catches duplicates regardless of filename.

#### Low Confidence Handling

When the LLM confidence is below threshold:
1. **First**: Request more examples for that doc_type+party combo (feedback loop)
2. **If still low**: Route to **human review queue** - never silently process uncertain documents. Accuracy is non-negotiable.

#### Error Handling

- **Retry with backoff** for transient failures (LLM API, network)
- **Dead-letter queue** for documents that fail after retries - must be manually reviewed
- **Failure alerting**: When multiple documents fail in a short window, notify the team immediately (likely indicates a systematic issue like a party changing their format)

### LLM Role (scoped, not monolithic)

The LLM does two things, separately:

- **Classify**: "What type of document is this, and from whom?" - near-100% reliable with good prompts
- **Extract**: Given doc type schema + few examples, extract fields
- **Multi-pass extraction** (conceptual): For high-stakes fields, run extraction multiple times or with different prompt strategies and compare. Design details TBD.

Prompts must be **versioned** - tied to extraction results so past results can be reproduced and explained.

Skip the embeddings/vector DB layer. The document types are few, schemas are known. A simple **example store** (annotated JSONs per doc_type+party combo) outperforms a vector DB with less complexity.

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

**Example quality**: Bad corrections can poison future extractions. Consider a review/approval step before corrections become active examples. (Implementation detail - flag during build.)

### UI as Feedback Loop (not prerequisite annotation)

Reframe from "annotate before extraction" to "verify after extraction":
- System extracts fields
- User reviews, corrects mistakes
- Corrections feed back as new examples
- Over time, fewer corrections needed

Current MVP has a Streamlit-based manual flagging UI (bounding box annotation). To be evolved into this feedback loop model. Details TBD.

### Plug-and-Play

Adding a new document type = schema definition + a few examples. No code changes.

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

Run extraction against historical/known-good data on a recurring basis to detect accuracy drift. This is the primary mechanism for ensuring the system stays reliable over time - not LLM confidence scores (which are unreliable), but measured accuracy against verified ground truth.

## Infrastructure

### Glue Layer: Power Automate Cloud (not Desktop)

PA Cloud runs in Microsoft's infrastructure - no machine dependency, no crashes. Keeps the team in familiar territory.

Flow: **PA Cloud watches OneDrive -> triggers AWS pipeline via HTTP -> receives results -> notifies via Teams/email**

### Processing: AWS (Bedrock + Claude)

- Client has existing AWS infrastructure
- **Amazon Bedrock + Claude** for LLM:
  - Haiku for classification (cheaper, faster)
  - Sonnet/Opus for extraction (accuracy matters)
- **AWS Step Functions** for pipeline orchestration
- Local LLM alternative: requires GPU instances (p3/p4/g5) running 24/7, unlikely to be cost-efficient vs Bedrock pay-per-use, and likely lower accuracy
- **Volume is low, accuracy is critical** - errors are extremely costly. This favors using the best available model (Opus) and multi-pass verification over optimizing for speed/cost

### Notifications

- **Teams**: Incoming Webhooks (simplest), or Graph API, or PA Cloud flow as notification layer
- **Email**: Already proven with this client in another project

### Input

- Watch OneDrive folder (PA Cloud built-in trigger) - client users won't change behavior

### Observability

End-to-end tracing across the full chain (OneDrive -> PA Cloud -> AWS Step Functions -> Bedrock -> notification). Every step logged and traceable.

### Security & Compliance

- **Data residency**: Sensitive trade data (pricing, banking details, counterparties) flows through Microsoft and AWS. Region constraints must be specified per client requirements.
- **Access control**: Who can see which transactions, who can make corrections. Model TBD.
- **Audit trail**: Immutable log of all processing events and human interventions (see Tracking & Metrics).
- **Data retention/deletion policy**: Must be defined - trade documents have regulatory retention requirements.
- **Sensitive field handling**: Bank account numbers, LC details, pricing terms flow through the pipeline. Encryption at rest and field-level access control to be considered during implementation.

## Design Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| Data model first | Without versioned schemas and explicit reconciliation rules, the system is a black box |
| Decomposed pipeline | Each stage testable, measurable, and can fail independently |
| Skip embeddings/vector DB | Few document types, known schemas - simple example store is sufficient |
| PA Cloud as glue, not processing | Keeps team in familiar tools, moves heavy lifting to reliable infra |
| Bedrock + Claude | Managed, scalable, cost-effective vs self-hosted LLM |
| Feedback loop UI | Lower barrier than manual annotation, improves over time |
| Python for all deterministic stages | Consistent stack, team knows it, rich library ecosystem for file parsing |
| Step Functions for orchestration | Sequential stages with clear state transitions, built-in retry/error handling |
| Recurring validation against historical data | Accuracy drift detection - more reliable than LLM confidence scores |
| Full audit trail | Regulatory requirement, also needed for debugging and accuracy tracking |

## Open Questions

- Transaction data model details (reconciliation rule format, document hierarchy, how to handle incomplete transactions) - phase 1 model as starting point
- Document field namespace mapping (how doc_type maps to reconciliation rule field names)
- OneDrive -> AWS trigger mechanism (PA Cloud HTTP action vs Graph API webhook)
- Model tier testing results (Haiku vs Sonnet vs Opus accuracy/cost for each stage)
- Level of involvement from original team vs our team
- Ingest tooling: which Python libraries for PDF text extraction, Excel, Word parsing
- Excel input data format (multi-sheet structure?)
- Multi-document PDFs: does this occur in practice?
- Human review queue UX - how does the reviewer interact, where does it live
- 1:1 vs 1:N field relationships in reconciliation (e.g., one invoice total vs multiple partial shipment BOLs)
- Discrepancy severity levels (amount mismatch vs reference number format mismatch)
- Data residency requirements per client
- Data retention/deletion policy
- Access control model
- Deduplication: content-hash based (decided), implementation details during build

## Implementation-Phase Flags

Items acknowledged in design but deferred to implementation for detailed design:

- Example store quality controls (review/approval before corrections become active)
- Multi-pass extraction strategy (same model twice? different models? structured output validation?)
- Sensitive field encryption/masking specifics
- Failure alerting thresholds and notification channels
- Historical validation test suite setup and scheduling
