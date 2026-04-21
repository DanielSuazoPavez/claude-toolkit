# v3 Audit — `.claude/skills/` (Design & Architecture subset)

Exhaustive file-level audit of the 4 skills in the Design & Architecture category (per `docs/indexes/SKILLS.md`, expanded to include `design-aws` (scaffold) and `design-docker` (per handoff directive)).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `design-db`, `design-diagram`, `design-aws` (scaffold-only), `design-docker` (including `resources/` subdirectories).

---

## Summary

Four skills, but one of them (`design-aws`) has no SKILL.md — the directory contains only a `resources/aws-reference.md` and is P3 in the backlog (*"idea to deployable AWS architecture"*). That's a deliberate scaffold state, not drift.

The remaining three (`design-db`, `design-diagram`, `design-docker`) are all **knowledge skills** — reference material triggered by keyword, Python/infra-adjacent in scope, inline-output only (no saved artifact). Workshop-shaped by construction.

**Index discrepancy to flag up front:** the handoff said `design-docker` *"appears under both Design & Architecture and Development Tools in SKILLS.md."* Not true — `docs/indexes/SKILLS.md:48` puts it only under Development Tools. This audit covers it here per the handoff directive, but the cross-ref is a ghost; the index is fine. Noting for the index-audit trail.

**Four classes of finding** emerge:

1. **`type:` frontmatter field — 3 instances** (all three with SKILL.md files carry `type: knowledge`). Repo-wide sweep moves them to `metadata: { type: knowledge }` per workflow queue item 7. Full inventory as of this audit: 17 skills still carry `type:` (12 command + 5 knowledge). Sweep target set is nearly the full skills directory.

2. **`design-aws` scaffold state — user-postponed, not blocked.** Skill is P3 backlog, but user confirms the `aws-toolkit` satellite is in good enough shape to build the skill on top of; the delay is user prioritization, not a missing dependency. `resources/aws-reference.md` (246 lines) is already load-bearing content — security checklists, IAM policy evaluation flows, compute cost crossovers, API Gateway v1 vs v2, minimum monthly costs, Terraform gotchas. **User decision: keep scaffold + reference in place**; when the skill gets picked up, it lands on top of already-mature content + ready satellite. No exploration-relegation needed.

3. **`schema-smith` contract duplication in `design-db` — direction decided.** Lines 182-199 route through the `schema-smith` satellite when available; fallback to raw SQL. Satellite integration shape is correct. But `resources/schema-smith-input-spec.md` (304 lines) duplicates a contract owned by the satellite. **User decision:** remove the duplicated spec from the workshop; point the skill at schema-smith's own consumer-facing docs. Direction is locked. Coordination question remaining: does schema-smith already ship consumer-facing input docs in a linkable form, or does the workshop wait for the satellite side to expose them? Cross-project coordination item, not a unilateral workshop action — but the target state is no longer ambiguous.

  Same class as `manage-lessons` direct SQL (workflow queue item 5, resolving via CLI routing). General pattern: workshop should link out to satellite-owned contracts, not carry copies. When the `design-aws` skill ships, the same rule applies for `aws-toolkit` input format.

4. **Non-obvious cross-references are absent.** Zero references to `/brainstorm-idea`, `pattern-finder`, `code-reviewer`, `implementation-checker`, `goal-verifier` across this subset. Skills are self-contained reference material — they don't route to agents or other skills for escalation. Just cross-references to sibling design-* skills and `/refactor`. Clean.

**User resolutions surfaced during review:**
- **`design-aws` is user-postponed, not blocked.** aws-toolkit satellite is ready; delay is prioritization only. Scaffold state stays; skill picks up on top of already-mature reference + ready satellite when scheduled.
- **Schema-smith contract duplication gets removed from the workshop.** Skill will point at schema-smith's consumer docs, not carry a copy. Coordination with the satellite side remaining: confirm it ships consumer-facing input docs in a linkable form. Direction locked; timing depends on satellite readiness.

Findings below: 3 Rewrite (all three built skills on `type:` sweep; `design-db` additionally on schema-smith spec removal), 1 Defer (design-aws scaffold — user-postponed, not blocked), no independent Keep (every built skill has at least the `type:` drift).

---

## Files

### `design-db/SKILL.md`

- **Tag:** `Rewrite` (frontmatter + schema-smith contract drift)
- **Finding:** Schema design reference skill. 201 lines. Opens with a Defaults table (primary keys, UUID version, FK constraints, money columns, migrations, normalization starting point) — calibrated strict with explicit "Flexible when..." escape hatches. That's the right opinionated-but-overridable shape.

  **Indexing strategy** (line 20-48): composite index column-order rule (*"most selective column first"*), partial indexes, covering indexes, plus a "When NOT to Index" table (low-cardinality, write-heavy, small tables, function-only). Index maintenance costs section calls out unused-index auditing (`pg_stat_user_indexes`) — concrete remediation.

  **Normalize vs denormalize** decision tree (line 54-61) + worked examples table (addresses = normalize, order line items = denormalize for price-at-order-time preservation, cached aggregates = denormalize with staleness). The "denormalize only with measured performance problems" rule (line 70) is exactly the anti-premature-optimization stance.

  **Schema Evolution** (line 72-102): safe vs unsafe column changes with specific guidance (*"Unsafe: NOT NULL without default on large table (locks table). Instead: add nullable → backfill in batches → add constraint"*). Online DDL section covers Postgres (`CONCURRENTLY`), MySQL (`pt-online-schema-change`/`gh-ost`). Upsert patterns for both engines. This is operational knowledge that matters at scale and is hard to infer from docs.

  **Multi-tenancy strategies** (line 104-120) — shared tables with RLS / schema-per-tenant / DB-per-tenant — with concrete Postgres RLS example. Soft Delete pattern with unique-constraint-excluding-soft-deleted rows (subtle but important).

  **Large ERD Strategy** (line 136-156) — three-level approach (index diagram / per-cluster ERDs / dimension catalog) + discovery-first approach for existing DBs. This is the kind of experience-encoded content that makes the difference between a 50-table ERD that nobody reads and a tiered view that does.

  **Anti-patterns table** (line 157-168) — 8 entries covering the classic mistakes (VARCHAR(255) everywhere, FLOAT for money, missing FK constraints, no FK indexes, non-reversible migrations, hard deletes, EAV, indexing everything). Checklist at the end summarizes the operative rules.

  **Schema Smith Integration** (line 182-199) — routes through `schema-smith` CLI when available, falls back to raw DDL. Correct satellite-integration shape. `which schema-smith` feature-detect, explicit fallback, minimal flag surface (`--validate-only`, `--strict`, `--json`).

  **Frontmatter drift:** line 3 has `type: knowledge`. Picked up by repo-wide sweep (workflow queue item 7).

  **Schema-smith contract drift — direction decided:** `resources/schema-smith-input-spec.md` (304 lines) duplicates a contract owned by the satellite. **Remove the workshop copy; link out to satellite-shipped docs.** Schema-smith already ships an `input/CLAUDE.md`-equivalent consumer doc; concrete mechanism is to expose it via the `schema-smith` CLI (e.g., `schema-smith --print-input-spec` or similar) so the workshop skill can instruct the user to run the command and read fresh docs from the satellite rather than a workshop-frozen copy.

  Per identity doc §3 (*"satellites... feed specialist extensions back upstream via `suggestions-box/`"*) and the lessons ecosystem parallel (claude-sessions owns the schema; toolkit consumes), link-out is the canonical shape. Coordinated execution: satellite adds CLI flag (or confirms an existing doc path) → workshop skill updates the integration section to reference the command/path → workshop removes `resources/schema-smith-input-spec.md`. Order matters — don't remove the workshop copy before the satellite-side surface is in place.

  See also references (`/design-diagram`, `/design-tests`, `/refactor`, `/design-docker`) are all current.

  Workshop-shaped: reference content for the consumer's schema design work. No orchestration.

- **Action:** at decision point: (1) frontmatter `type: knowledge` → `metadata: { type: knowledge }` as part of repo-wide sweep (queue item 7); (2) schema-smith contract removal: coordinate with the satellite to expose its existing `input/CLAUDE.md`-equivalent consumer doc via CLI (e.g., `schema-smith --print-input-spec`); update skill's Schema Smith Integration section to point at the CLI command; remove `resources/schema-smith-input-spec.md` **after** the satellite surface lands (order matters).
- **Scope:** (1) trivial (sweep-covered). (2) small workshop-side once the satellite-side CLI flag ships; coordinated cross-project work.

### `design-db/resources/schema-smith-input-spec.md`

- **Tag:** `Rewrite` (removal pending satellite-side CLI surface)
- **Finding:** Detailed YAML input-format spec (304 lines) for the `schema-smith` satellite. Covers directory layout, schema files, enums, mixins, tables, column types, FK reference shorthand, auto-indexing behavior, index methods, CHECK constraints, triggers, extensions, scripts config.

  **Content quality is high** — but **ownership belongs at the satellite**, not here. Schema-smith already ships an `input/CLAUDE.md`-equivalent consumer doc. **Direction (user-locked):** remove this workshop copy, link out to satellite-shipped docs via a CLI surface (e.g., `schema-smith --print-input-spec`).

  **Removal ordering:** (1) satellite exposes the doc via CLI, (2) workshop skill updates integration section to reference the CLI command, (3) this file is removed. Steps 1 and 2 before 3 — don't leave the skill pointing at nothing.

- **Action:** remove after satellite-side CLI flag ships. Coordinated with the design-db skill update (Schema Smith Integration section).
- **Scope:** small workshop-side once the satellite-side surface is in place; coordinated cross-project work.

### `design-diagram/SKILL.md`

- **Tag:** `Rewrite` (frontmatter only)
- **Finding:** Diagram-format selection skill. 157 lines. Opens with a "Diagrams are for humans, not agents. Pick the lightest format that communicates" framing — correctly anti-ceremony. Format-selection table (line 14-21) routes by scenario: branching logic → ASCII tree; simple flow → numbered list; ERD → Mermaid; sequence → Mermaid; C4 → Mermaid; cloud/infra → Mermaid `architecture-beta`.

  **"Which Mermaid Diagram Type?" table** (line 29-35) pairs audience to type with explicit rationale (*"Developer (self) → Flowchart, Sequence — Low ceremony, evolves with code"*, *"External stakeholders → C4 Context/Container — Hides implementation detail"*). The rationale columns are what make the table actually guide decisions rather than just classify them.

  **Ambiguous cases table** (line 43-50) — "wrong instinct vs better choice" framing. This is subtle and valuable: *"State machine with side effects → State diagram alone (wrong) → State + Sequence pair (better)"*, *"AWS/cloud topology → C4 Context (wrong) → Architecture (architecture-beta) (better)"*. The wrongness of the obvious choice is the teaching moment.

  **Splitting and Scoping** (line 54-85) — when-to-split table, split-along-bounded-contexts rule (*"Auth flow and payment flow are good splits. Frontend nodes and backend nodes are bad splits — they fragment a single interaction across diagrams"*), evolving requirements (early/stabilizing/production), versioning strategy.

  **Worked Example: E-Commerce Order System** (line 88-128) — three-step decision (type selection, scope check, output). Step 2 *"happy path + failure paths in one diagram → too dense. Split: happy path diagram + payment failure diagram"* shows the splitting rule in action. Good pedagogy.

  **Documentation-vs-working-session concerns table** (line 134-139) — self-contained requirements, complexity budgets, alt-text, format bias. Points at `/write-documentation`. Correct handoff.

  **Anti-patterns table** (line 145-153) — Kitchen Sink, Wrong Abstraction, Missing Legend, Dead Diagram, Over-Detailed, Layer Split, Over-Diagramming. "Dead Diagram" fix (*"Co-locate with code, add `%% Last updated:` for staleness detection"*) is actionable remediation, not just complaint.

  **Resource files (3):**
  - `mermaid-theme-presets.md` (78 lines) — three themes (Documentation, Design Review, Presentation) with both frontmatter and inline-directive syntax. Clean.
  - `mermaid-aws-architecture.md` (105 lines) — `architecture-beta` syntax reference, built-in icon list (*"Only 5 icons render on GitHub"*), AWS service → icon mapping, 3 worked examples (API Gateway → Lambda, EventBridge scheduled cleanup, S3 → OpenSearch with VPC groupings), rendering compatibility table, common mistakes. Pairs with `design-aws/resources/aws-reference.md` — the diagram-side and architecture-side of the same domain.
  - `mermaid-rendering-gotchas.md` (47 lines) — common rendering issues (overlapping arrows, blank-line-before-fence, special-char quoting) + C4 syntax reference + subgraph scoping + `architecture-beta` gotchas. Scannable troubleshooting reference.

  All three resource files are correctly subordinated — main SKILL.md has decision framework; resources have format-specific details.

  **Frontmatter drift:** line 3 has `type: knowledge`. Picked up by repo-wide sweep.

  **Cross-reference absence:** no brainstorm/agent refs; all see-also is to sibling design-* skills + `/refactor` + `/write-documentation`. Workshop-shaped and self-contained.

  Workshop-shaped: reference for the consumer's diagramming work; no orchestration.

- **Action:** frontmatter `type: knowledge` → `metadata: { type: knowledge }` as part of repo-wide sweep (queue item 7). No other action.
- **Scope:** trivial (sweep-covered).

### `design-aws/` (scaffold — no SKILL.md)

- **Tag:** `Defer` (user-postponed, not blocked — aws-toolkit is ready)
- **Finding:** Directory state: `resources/aws-reference.md` only (246 lines). No `SKILL.md`. Not in `docs/indexes/SKILLS.md`. P3 in backlog as *"idea to deployable AWS architecture"* — explicit phased workflow (understand idea → design architecture → generate diagram via `/design-diagram` → translate to aws-toolkit input configs → security-first review). **User confirmed: deferral is prioritization, not a dependency gap. The `aws-toolkit` satellite is in good shape — when the user picks this up, the skill shell can land directly on top of ready infrastructure.**

  **The reference content is load-bearing despite no skill body.** `aws-reference.md` has two layers:
  - **Layer 1: Checklists** — Security Review (IAM scope, encryption, public exposure, secrets) / Detection (CloudTrail/VPC Flow Logs/audit logs) / Data in Transit / Incident Prep / Monitoring Review (per-service metric/alarm-when/why table) / Quota & Limits Review / Backup Review. Concrete and actionable.
  - **Layer 2: Precision** — IAM Policy Evaluation Flow (same-account vs cross-account with ALLOW/DENY logic), Compute Cost Crossover (Lambda/Fargate/EC2 comparison at 1K-10M req/day), API Gateway REST vs HTTP feature matrix, Minimum Monthly Costs, IAM activation notes (Lambda ARN semantics, MFA condition key absent-key handling, KMS permission mapping per service), service selection (SQS FIFO throughput, Aurora Serverless v2 costs, Lambda cold start benchmarks, DAX vs ElastiCache), security (SQS vs SNS encryption defaults, Lambda function URL auth, API Gateway throttling defaults and WAF availability), Terraform gotchas (`prevent_destroy` edge case, `apply_immediately`, `manage_master_user_password`, security group default egress behavior, `default_tags` perpetual diff, API Gateway deployment triggers).

  This is the kind of content that takes months to accumulate and is hard to find assembled elsewhere. It would be wasteful to defer it just because the skill shell isn't built.

  **Scaffold-with-reference stays as-is.** User-locked: no move to exploration, no shell-first rush. Reference is load-bearing and ready; shell lands when the user picks up the backlog item.

  **Cross-satellite dependency:** the skill will consume `aws-toolkit` satellite (input format = YAML) for deterministic generation. When the skill lands, the satellite-contract rule applies the same way as schema-smith: link out to aws-toolkit's own consumer docs, don't duplicate its input format in the workshop. Given aws-toolkit is already "in good shape" per user, that link-out surface may already exist or can be added during skill construction.

  **Frontmatter:** n/a — no SKILL.md yet. When built, follow the `metadata: { type: command }` convention established by the sweep.

- **Action:** at decision point: (1) mark the P3 backlog item as "reference + satellite ready; user-postponed" for clarity (no dependency blockers); (2) when the skill ships, audit both halves (SKILL.md + reference) in a follow-up pass and enforce the satellite-contract rule (link out to aws-toolkit docs, no duplicated spec).
- **Scope:** (1) 1-line backlog edit. (2) future audit work, not v3-blocking.

### `design-aws/resources/aws-reference.md`

- **Tag:** `Keep` (conditional on Defer above)
- **Finding:** Two-layer AWS reference (246 lines). Content detail covered in the parent `design-aws/` finding. Holds up as standalone reference material even without a skill shell.

  **Freshness:** compute cost crossover (line 128) explicitly dated *"us-east-1, x86, March 2026"* — good practice for cost data, which ages quickly. Aurora Serverless v2 notes (line 215) — *"does NOT scale to zero — that was v1, now deprecated"* — up-to-date.

  **Depth calibration:** Layer 1 (checklists) is suitable for a reviewer walking through a design; Layer 2 (precision) is what an expert would look up for a specific edge case. The split matches how the content will be consumed.

  **Cross-ref to `design-diagram/resources/mermaid-aws-architecture.md`:** that file covers the diagramming-side of AWS; this file covers the architecture-side. The two pair cleanly when the `/design-aws` skill lands and routes through `/design-diagram`.

- **Action:** none (until skill ships, then audit both halves together).

### `design-docker/SKILL.md`

- **Tag:** `Rewrite` (frontmatter only)
- **Finding:** Docker/compose patterns skill. 334 lines — the largest in this subset. Note: appears only in `docs/indexes/SKILLS.md` Development Tools section (line 48), **not** Design & Architecture. The handoff's "appears in both subsets" assertion is incorrect; the index is fine, this audit just covers it here per handoff directive.

  **Entry-point routing** (line 9-16) — three modes (Generate / Review / Refine) by request pattern. Explicit request-pattern → mode mapping is clearer than most triage framings.

  **Generate Mode** (line 19-128):
  - Project analysis checklist (framework, dependencies, entry point, multi-service detection).
  - Base image selection — two defaults (`python:3.12-slim` / `python:3.12-alpine`) + minimal-base decision tree (slim / scratch / distroless by use case).
  - **Dockerfile pattern (uv)** (line 49-64) — multi-stage (base → deps → runtime), non-root user (`appuser`), uv cache mount, `COPY --from=ghcr.io/astral-sh/uv:latest`. This is the current-best-practice pattern for Python containerization with uv. Workshop is Python + uv, so this is the correct default.
  - .dockerignore + docker-compose patterns (YAML anchors with `x-app-common: &app-common`, health-dependency conditions, init-service pattern with `service_completed_successfully`, profiles for selective startup, user UID mapping, resource limits).

  **Health Checks by Service table** (line 132-142) — 8 services (FastAPI, Streamlit, Airflow webserver/scheduler, Dagster gRPC, Postgres, OpenSearch, OpenSearch Dashboards) with health check command and `start_period`. Concrete, not generic.

  **Review Mode** (line 156-194) — four checklists (Security / Efficiency / Reliability / Compose). Output format structured (Critical / Improvements / Good). That's the right shape for a review artifact.

  **Refine Mode** (line 199-208) — goal-oriented decision tree (smaller image / faster builds / security / CI-CD / production).

  **Dagster Multi-Container Pattern** (line 212-277) — three-service architecture (webserver / daemon / user-code) with ASCII diagram + compose pattern. Dagster-specific, which is narrow — but this is current workshop usage (Dagster is in the actual health-check list). Not speculative.

  **Makefile Targets** (line 281-302) — up / down / build / reset / infra / infra-down. Uses compose profiles (`--profile full` / `--profile infra`) — matches the profile-based selective-startup pattern from the compose section.

  **Edge Cases table** (line 308-313) — monorepo (per-service Dockerfiles), no pyproject.toml, existing partial Dockerfile (route to review mode), package builder pattern.

  **Anti-patterns table** (line 319-328) — 8 entries including two infra-specific ones: *"No pinned subnets"* (Docker auto-assigning from RFC1918 ranges colliding with corporate LANs) and *"Stale networks after reconfig"* (run `docker network prune`). Those are non-obvious gotchas that matter in enterprise environments.

  **Frontmatter drift:** line 3 has `type: knowledge`. Picked up by repo-wide sweep.

  **No resource files** — everything inline. At 334 lines this is borderline but still scannable; pulling Dagster pattern + Health Checks table into a resource would thin the main doc by ~100 lines if needed. Not a current drift.

  **Cross-references:** no agent / brainstorm refs; See also is to sibling design-* skills only. Clean.

  **Python-centric (like `design-tests`).** All code samples are Python + uv; the health-check service list is Python-framework-heavy (FastAPI, Streamlit, Dagster, Airflow). Correct scoping for current workshop usage — same posture as `design-tests`. If a non-Python consumer shows up, a parallel skill is cleaner than expansion.

  Workshop-shaped: reference for consumer's Docker work. No orchestration.

- **Action:** frontmatter `type: knowledge` → `metadata: { type: knowledge }` as part of repo-wide sweep (queue item 7). No other action.
- **Scope:** trivial (sweep-covered).

---

## Cross-cutting notes

- **`type:` frontmatter drift is the dominant issue across the full skills directory, not just this subset.** Inventory from this pass: 17 skills carry `type:` (12 command, 5 knowledge). Subset-by-subset coverage:
  - Workflow: 4 (analyze-idea, write-handoff, wrap-up, list-docs)
  - Code quality: 1 (design-tests)
  - Design & arch (this subset): 3 (design-db, design-diagram, design-docker)
  - Remaining (dev tools + toolkit dev + personalization): 9 — to be audited in remaining subsets, but the count gives a sense of sweep scope.

  The repo-wide sweep (workflow queue item 7) now has a clearer target size. One coordinated commit moves all 17 to `metadata: { type: ... }` + updates `evaluate-skill` / `evaluate-batch` to read the new path.

- **Satellite-contract duplication is a pattern, not a one-off.** `design-db` duplicates `schema-smith`'s input spec; `design-aws` (when built) will duplicate `aws-toolkit`'s input format. Both are specific instances of the same shape: workshop skill needs to know the satellite's contract, workshop copies the contract in, satellite evolves independently, copy rots.

  Same category as `manage-lessons` direct SQL (workflow queue item 5, which is resolving via CLI-mediated access). The parallel resolution for design-* skills would be: satellite ships a machine-readable spec (perhaps `schema-smith --print-input-spec`); workshop skill links to it at runtime rather than carrying a copy. That's satellite-side work though — can't be solved unilaterally in the workshop.

  Worth flagging as a recurring ecosystem pattern for the identity doc / canon to address. One paragraph in `relevant-project-identity.md` on "when to copy satellite contracts vs link out" would make this a repeatable decision, not a per-case judgment.

- **Inline-output vs saved-artifact shape (continuing the Code Quality subset observation).** All three built skills here are inline-output: reference material, no file saved. Matches review-security / design-tests shape from the prior subset. The output-shape convention doc (code-quality queue item 5) would pick this up — knowledge skills are inline; workflow/analysis skills save artifacts.

- **Cross-reference cleanliness.** No `/brainstorm-idea`, `pattern-finder`, `code-reviewer`, `implementation-checker`, `goal-verifier` references anywhere in this subset. Skills are self-contained reference material and only cross-reference siblings + `/refactor` / `/write-documentation`. No cascading impact from the agents audit or the brainstorm rename.

- **Python-centricity is consistent across the toolkit.** `design-tests` (pytest), `design-db` (Postgres-biased SQL, Python/uv examples in schema-smith integration), `design-docker` (Python + uv Dockerfile, Python-framework health-check list). `design-diagram` is the only language-agnostic one in the subset. This is correct — the workshop itself is Python + shell, so the tooling tracks that — but document the scope assumption somewhere explicit. Not a drift; clarity polish.

- **No orchestration-shaped leakage.** Every skill assumes a consumer session, reference content or review findings to the user, no cross-project coordination. Correct workshop identity.

- **Scaffold-with-resources-but-no-SKILL is a new shape.** `design-aws` is the only instance in this subset. The state is deliberate (P3 backlog) but the invocation-reachability question is real: without SKILL.md, Claude can't auto-load the skill from keyword triggers, even though the reference is valuable. That's a feature (keeps unfinished work out of the invocation surface) not a bug, but worth recognizing as an ecosystem shape. If other skills end up in scaffold state in the future, the convention "resources/ alone is OK while skill is P2+" should be documented.

- **Index discrepancy.** The handoff said `design-docker` appears in both Design & Architecture and Development Tools in the index. Not true — only Dev Tools (line 48). The Design & Architecture index section has only `design-db` and `design-diagram`. Audit covered `design-docker` here per handoff directive; index is correct; no action needed on the index. Flagging to avoid carrying the ghost cross-ref forward.

---

## Decision-point queue (carry forward)

Every item below is a real work item. None are blocked behind the v3 reshape — they're just audit-surfaced issues that get scheduled like any backlog work.

**Resolved during review (pending execution — coordinated cross-project work):**

1. **Schema-smith contract removal** (direction locked). Remove `design-db/resources/schema-smith-input-spec.md` after schema-smith satellite exposes its existing `input/CLAUDE.md`-equivalent consumer doc via a CLI surface (e.g., `schema-smith --print-input-spec`). Order: (1) satellite ships CLI flag, (2) design-db Schema Smith Integration section updated to point at the CLI command, (3) workshop spec file removed. Coordinated with schema-smith satellite team.

2. **Scaffold backlog annotation.** Mark the `design-aws` P3 backlog item as "reference + satellite ready; user-postponed" — no dependency blockers; deferral is prioritization only. 1-line backlog edit.

**Resolved during review (pending execution — trivial scope):**

3. `design-aws/` scaffold state — **keep as-is** (user-locked). Reference stays co-located with the future skill shell. No exploration-relegation. No action.

**Coordinated with other audit directories:**

4. **`type:` frontmatter sweep — full inventory 17 skills.** Picked up by workflow queue item 7 (move to `metadata: { type: ... }` + update `evaluate-skill` / `evaluate-batch`). This audit contributes 3 instances (design-db, design-diagram, design-docker).

5. **Output-shape convention doc** (code-quality queue item 5) — three more inline-output skills documented here (design-db, design-diagram, design-docker, plus design-aws when built). Convention doc should explicitly name knowledge-skill inline-output as the default shape.

6. **Satellite-contract rule** — generalizable from the schema-smith resolution. When the design-aws skill ships, enforce the same rule for aws-toolkit: link out to satellite's consumer docs, don't duplicate. Worth a one-paragraph addition to `relevant-project-identity.md` on "when workshop skills interact with satellite contracts" so this becomes a repeatable convention, not a per-case judgment.

**Still open / low-priority:**

7. **Scaffold convention doc** — `design-aws` is the only skill in resources-only scaffold state. If the pattern recurs, a one-paragraph note in `relevant-toolkit-context.md` on "when a skill directory can exist without SKILL.md" would make the shape learnable.

8. **Index ghost cross-ref (handoff-only).** `design-docker` does NOT appear in Design & Architecture in `docs/indexes/SKILLS.md` — only Dev Tools. Handoff assumed otherwise; no index change needed. Flagging so the assumption doesn't propagate forward.
