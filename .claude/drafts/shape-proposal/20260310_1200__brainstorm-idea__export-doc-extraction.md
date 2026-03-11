# Export Document Extraction & Reconciliation - Design

## Problem

Extract fields from export transaction documents (5-10 types, many parties/formats), reconcile across documents in a transaction, flag discrepancies. Replaces a deterministic Python approach that broke due to format variance.

## Context

- **Domain**: Exports business - regulatory documents from banks, shippers, clients, customs, etc.
- **Document types**: ~5-10 (bill of lading, commercial invoice, etc.)
- **Parties**: Many, each with different formats for the same document type. Formats change over time even for the same party.
- **Current MVP (phase 2)**: OCR -> embeddings -> vector DB (Qdrant) -> LLM extraction, with a Streamlit UI for manual bounding-box annotation.
- **Phase 1 (deprecated)**: Deterministic Python scripts - too brittle for format variance.
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

Transaction (shape TBD)
├── documents: [{doc_type, party, extracted_fields, confidence}]
└── reconciliation_rules:
    └── [{field_a: "invoice.total", field_b: "bank_doc.amount", comparator: "exact"}]
```

Reconciliation rules are declarative: "invoice.total must match bank_doc.amount".

### Decomposed Pipeline

```
0. INGEST  ->  1. CLASSIFY  ->  2. EXTRACT  ->  3. VALIDATE  ->  4. RECONCILE  ->  5. REPORT
```

Each stage independent, each with its own metrics. All non-LLM stages are Python.

| Stage | Input | Output | LLM? | Can fail independently |
|-------|-------|--------|------|----------------------|
| **Ingest** | Raw file (PDF/Excel/Word) | Extracted text/structured content | No - deterministic Python (OCR, parsers) | Yes - unsupported format, corrupt file |
| **Classify** | Text content | `{doc_type, party, confidence}` | Yes | Yes - reject if low confidence |
| **Extract** | Text + doc_type schema + examples | `{fields, confidence_per_field}` | Yes | Yes - partial extraction OK |
| **Validate** | Extracted fields + schema | `{valid, errors}` | No - deterministic Python schema validation | Yes - flags missing required fields |
| **Reconcile** | All validated docs in transaction | `{discrepancies}` | No - deterministic Python rule application | Yes - only runs when enough docs present |
| **Report** | Discrepancies | Human-readable output | No - Python | Always succeeds |

#### Transaction Grouping

Documents are grouped into transactions **by folder** - all files in one OneDrive folder = one transaction. Users don't rename files, so classification must rely on content, not filenames.

#### Low Confidence Handling

When the LLM confidence is below threshold:
1. **First**: Request more examples for that doc_type+party combo (feedback loop)
2. **If still low**: Route to **human review queue** - never silently process uncertain documents. Accuracy is non-negotiable.

### LLM Role (scoped, not monolithic)

The LLM does two things, separately:

- **Classify**: "What type of document is this, and from whom?" - near-100% reliable with good prompts
- **Extract**: Given doc type schema + few examples, extract fields

Skip the embeddings/vector DB layer. The document types are few, schemas are known. A simple **example store** (annotated JSONs per doc_type+party combo) outperforms a vector DB with less complexity.

### Example & Feedback Storage

Examples and user corrections live in S3 (or equivalent cloud storage), structured by doc_type and party:

```
examples/{doc_type}/{party_id}/
├── example_001.json   # annotated extraction
├── example_002.json
└── ...
```

Lightweight DB (DynamoDB or equivalent) for indexing and metadata. Corrections from the feedback loop UI are saved here and become new examples automatically.

### UI as Feedback Loop (not prerequisite annotation)

Reframe from "annotate before extraction" to "verify after extraction":
- System extracts fields
- User reviews, corrects mistakes
- Corrections feed back as new examples
- Over time, fewer corrections needed

### Plug-and-Play

Adding a new document type = schema definition + a few examples. No code changes.

### Metrics

Track everything per stage:
- Execution time
- Confidence scores
- Accuracy (vs user corrections)
- Volume / throughput

## Infrastructure

### Glue Layer: Power Automate Cloud (not Desktop)

PA Cloud runs in Microsoft's infrastructure - no machine dependency, no crashes. Keeps the team in familiar territory.

Flow: **PA Cloud watches OneDrive -> triggers AWS pipeline via HTTP -> receives results -> notifies via Teams/email**

### Processing: AWS (Bedrock + Claude)

- Client has existing AWS infrastructure
- **Amazon Bedrock + Claude** for LLM:
  - Haiku for classification (cheaper, faster)
  - Sonnet/Opus for extraction (accuracy matters)
- Containerized pipeline (ECS, Lambda, or Step Functions - TBD)
- Local LLM alternative: requires GPU instances (p3/p4/g5) running 24/7, unlikely to be cost-efficient vs Bedrock pay-per-use, and likely lower accuracy
- **Volume is low, accuracy is critical** - errors are extremely costly. This favors using the best available model (Opus) and multi-pass verification over optimizing for speed/cost

### Notifications

- **Teams**: Incoming Webhooks (simplest), or Graph API, or PA Cloud flow as notification layer
- **Email**: Already proven with this client in another project

### Input

- Watch OneDrive folder (PA Cloud built-in trigger) - client users won't change behavior

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

## Open Questions

- Transaction data model details (reconciliation rule format, how to handle incomplete transactions)
- Exact AWS setup (Lambda vs ECS vs Step Functions)
- OneDrive -> AWS trigger mechanism (PA Cloud HTTP action vs Graph API webhook)
- Model tier testing results (Haiku vs Sonnet vs Opus accuracy/cost for each stage)
- Level of involvement from original team vs our team
- Ingest tooling: which Python libraries for PDF (OCR vs text-based), Excel, Word parsing
- Human review queue UX - how does the reviewer interact, where does it live
