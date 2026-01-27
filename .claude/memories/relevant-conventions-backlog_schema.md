# Backlog Schema Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Adding or modifying items in BACKLOG.md
- Reviewing backlog structure
- User explicitly asks about backlog format

Defines the schema for BACKLOG.md: priority sections, entry format, categories, and status values.

---

## 2. Section Hierarchy (by priority)

```markdown
# Project Backlog

## P0 - Critical
## P1 - High
## P2 - Medium
## P3 - Low / Nice-to-Have
## Graveyard
```

---

## 3. Entry Format

```markdown
- **[CATEGORY]** Title
    - **status**: `status-value`
    - **scope**: `Area1, Area2` (areas involved)
    - **branch**: `branch-name` (if exists)
    - **worktree**: `.worktrees/name` (if using git worktree)
    - **plan**: `path/to/plan.md` (if exists)
    - **review**: `path/to/implementation-check.md` (if reviewed)
    - **depends-on**: `branch-name` or description (if blocked)
    - **version**: `x.y.z` (if assigned)
    - Notes or description (free text)
```

**Rules:**
- `**status**` is required on every entry
- `**scope**` recommended for visibility into affected areas
- `**branch**` required for `in-progress`, `ready-for-pr`, `pr-open`, `approved` items
- `**worktree**` optional, for parallel work in separate directories
- `**plan**` required for `planned` items
- `**review**` recommended for `ready-for-pr` and later (link to implementation-check.md)
- `**depends-on**` required for `blocked` items

---

## 4. Category (Work Type)

The category tag describes the **type of work** being done.

| Tag | Meaning |
|-----|---------|
| `DE` | Data Engineering pipeline work |
| `DS` | Data Science / optimization work |
| `UI` | Streamlit interface work |
| `API` | Backend FastAPI work |
| `INFRA` | Infrastructure, deployment, configuration |
| `OPS` | Operations, monitoring, alerts |
| `TOOLING` | data-infra, CLI tools |
| `TESTING` | Tests |
| `DOCS` | Documentation |
| `CHORE` | Maintenance, cleanup |

**Combined categories:** Use `/` for items spanning multiple work types (e.g., `[UI/API]`, `[DS/DOCS]`)

---

## 5. Scope (Areas Involved)

The scope field lists **technical areas/components** that will be touched by the task. Helps identify cross-cutting concerns and indirect impacts.

| Area | Description |
|------|-------------|
| `DE` | Data Engineering pipeline code (`de_pipeline/`) |
| `DS` | Data Science code (`ds_pipeline/`, `SOP_model/`) |
| `Backend` | FastAPI backend (`backend/`) |
| `UI` | Streamlit interface (`ui/`) |
| `Database` | PostgreSQL schemas, migrations, queries |
| `Docker` | Dockerfiles, docker-compose, containers |
| `Airflow` | DAGs, Airflow configuration |
| `S3` | S3 storage, paths, operations |
| `Catalog` | Data catalog configuration (`conf/`) |
| `data_model` | Schema management module (`data_model/`) |
| `DevOps` | CI/CD, deployment scripts, env management |

**Format:** Comma-separated list: `**scope**: DE, DS, Catalog`

---

## 6. Status Values

| Status | Meaning |
|--------|---------|
| `idea` | Not yet scoped |
| `planned` | Scoped, ready to start |
| `in-progress` | Active work, has branch |
| `ready-for-pr` | Code complete, PR not yet created |
| `pr-open` | PR created, awaiting review |
| `approved` | PR approved, awaiting merge |
| `blocked` | Waiting on external (IT, decisions) |

**Typical flow:** `idea` → `planned` → `in-progress` → `ready-for-pr` → `pr-open` → `approved` → merged (remove from backlog)

---

## 7. Priority Guidelines

| Priority | Criteria |
|----------|----------|
| P0 | Blocking production or critical user workflows |
| P1 | High business value, active development |
| P2 | Important but not urgent, has clear scope |
| P3 | Nice-to-have, future improvements |
| Graveyard | Abandoned or superseded items |
