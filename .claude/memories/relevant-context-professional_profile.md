---
name: relevant-context-professional_profile
description: Professional context — data engineering role, stack, tools, and current trajectory for tailoring technical collaboration
type: user
---

## 1. Quick Reference

**ONLY READ WHEN:**
- Working on data engineering tasks or pipeline-related discussions
- User asks about their stack or professional context
- Deciding how to frame technical suggestions (what tools/patterns they know well vs learning)

**See also:** `personal-context-user` for non-work context, `essential-preferences-communication_style` for interaction style

---

## 2. Role & Domain

Data engineer. Batch analytical pipelines — "run the pipeline" model, not streaming/ETL ops. Optimization model pipelines: ingestion, preprocessing, validation, model execution, report generation. Reports feed Power BI via SQL tables (deploy) or parquet (local).

---

## 3. Stack

| Layer | Tool | Notes |
|-------|------|-------|
| Transforms | Polars (strongly preferred) | Pandas only when strictly needed |
| Orchestration | Airflow (current), Dagster (learning/migrating) | |
| Pipeline framework | Custom Kedro-inspired framework | Config-driven, YAML catalogs, DAG resolution, node-based |
| Validation | Custom config-driven framework | YAML configs, registry pattern, check + action, DQ reporting |
| Config validation | Pydantic | Used across projects for YAML schema validation |
| Schema definition | schema-smith (own tool) | YAML → PostgreSQL DDL |
| Dashboards | opensearch-dashboard (own tool) | YAML → OpenSearch dashboard elements |
| Reporting output | Parquet (local), SQL tables (deploy) | Excel for user-facing files |
| No Spark | Scale doesn't warrant it | |

---

## 4. Current Trajectory

- **Building a personal data engineering tool ecosystem** — first experience designing standalone tools for cross-project reuse (not publishing publicly)
- Three tools: schema-smith (exists), schema/type bridge (new), validation framework (extraction)
- Philosophy: Linux-style "one tool, one purpose," connected via YAML artifacts
- Strong "config-driven" orientation — if it can be config-driven, it should be
- Getting into pandera — understanding where it fits as structural validation gate
- Dagster training repo in early stages — establishing personal patterns
- Polars + pydantic + pandera intersection is an active area of interest
- Consistent personal design language across tools: **config-driven, YAML-defined, single-purpose generators** (schema-smith, opensearch dashboard definitions, schema bridge, validation framework)
