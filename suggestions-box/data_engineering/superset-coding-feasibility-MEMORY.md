# Apache Superset via Code: Feasibility Summary

## Context

Evaluated Apache Superset as a self-hosted, fully programmable dashboard/visualization platform. Chosen over Metabase due to Apache 2.0 license (no features behind paywall), official MCP support, and stronger API surface.

## The Short Answer

**Everything is API-driven** — database connections, datasets, charts, dashboards, filters, embedding. No GUI required. Apache 2.0 license means all features are available in the open-source edition.

## Docker Setup (Minimal)

Start simple: Superset + Postgres + Redis. No Celery workers initially.

```yaml
services:
  superset:
    image: apache/superset:latest
    ports:
      - "8088:8088"
    environment:
      SUPERSET_SECRET_KEY: your-secret-key
      # Point at Postgres for metadata
      SQLALCHEMY_DATABASE_URI: postgresql+psycopg2://superset:superset@postgres:5432/superset
    depends_on:
      - postgres
      - redis
  postgres:
    image: postgres:16
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: superset
      POSTGRES_USER: superset
      POSTGRES_PASSWORD: superset
  redis:
    image: redis:7
    volumes:
      - redisdata:/data
volumes:
  pgdata:
  redisdata:
```

**Future improvement**: Add Celery workers for async queries, scheduled reports, cache warmup, and thumbnail generation. Core dashboard/chart/API functionality works without it.

**Note**: The official docker-compose includes Celery by default. For production, Superset recommends Kubernetes (Helm chart available). Docker-compose is fine for personal/team use.

## What's Fully Doable via API

### Workflow: Code → Dashboard

1. **Authenticate** → get JWT + CSRF token
2. **POST `/api/v1/database/`** → connect a data source
3. **POST `/api/v1/dataset/`** → define a dataset (table or SQL query)
4. **POST `/api/v1/chart/`** → create a chart with `viz_type`, `datasource`, `params`, `query_context`
5. **POST `/api/v1/dashboard/`** → create a dashboard
6. **PUT `/api/v1/dashboard/{id}`** → add charts with `position_json` (grid layout)

### API Surface

| Resource | Endpoints | Capabilities |
|---|---|---|
| Databases | ~18 | Connect, validate, test, sync, delete |
| Datasets | ~18 | Create from tables or SQL, manage columns/metrics |
| Charts | ~20 | Create, update, clone, delete, get data, cache warmup |
| Dashboards | ~26 | Create, update, delete, export/import, add filters, embed |
| Queries | — | Execute SQL, get results, saved queries |
| Security | — | Roles, permissions, row-level security |
| Settings | — | Read/update instance config |

OpenAPI docs available at `/api/docs` on every running instance.

### Chart Types (viz_type values)

Line, bar, area, pie, table, pivot_table, big_number, big_number_total, gauge, funnel, scatter, bubble, heatmap, histogram, box_plot, waterfall, sunburst, treemap, sankey, world_map, country_map, deck_* (map layers), and more.

### Interactivity

- **Native filter bar** — date ranges, dropdowns, text search, numeric ranges
- **Cross-filtering** — click a chart element to filter the whole dashboard
- **Drill-down** — configurable per chart
- All configurable via the dashboard JSON metadata

### Export/Import (Version Control)

- `GET /api/v1/dashboard/export/` → ZIP file with YAML + JSON definitions
- `POST /api/v1/dashboard/import/` → import from ZIP
- Git-friendly: export, commit, review diffs, import to another instance

## MCP Server

The [aptro/superset-mcp](https://github.com/aptro/superset-mcp) server works with Claude Code.

Install:
```bash
npx -y @smithery/cli install @aptro/superset-mcp --client claude
```

Superset's core team has been [actively improving MCP support](https://preset.io/blog/apache-superset-community-update-february-2026/) (Feb 2026): response size guards, dataset validation, safety improvements.

Capabilities: create/manage databases, datasets, charts, dashboards, run SQL queries, explore data — all via natural language through Claude Code.

## Configuration (superset_config.py)

Superset is configured via a Python file — maximum flexibility:

- Authentication backends (OAuth, LDAP, DB)
- Feature flags (cross-filtering, dashboard embedding, etc.)
- Caching (Redis)
- Theming / branding
- Security settings
- Database driver registration
- Custom middleware

## Embedding

- **Guest Token flow** — server generates a token, client loads dashboard in iframe
- **Embedded SDK** — `@superset-ui/embedded-sdk` npm package
- **No watermark** on the open-source edition
- CSP headers configurable for cross-domain embedding

## Practical Approach

1. Spin up Superset + Postgres + Redis via docker-compose
2. Connect your data source via API
3. Build one chart in the UI to understand the JSON structure
4. Use that JSON as a template — replicate and vary via API or MCP
5. Assemble dashboards with charts, filters, and layout via API
6. Export dashboard definitions to Git for version control

The "inspect and template" pattern is key — chart config JSON is complex but consistent once captured.

## Why Superset Over Alternatives

| Factor | Superset | Metabase | Grafana |
|---|---|---|---|
| License | Apache 2.0 | AGPL | AGPL |
| All features free | Yes | No (serialization, config file, SDK locked) | Yes (but AGPL limits embedding) |
| Dashboard API | Full (26 endpoints) | Full | Best-in-class |
| Chart creation API | Full (20 endpoints) | Full | Full |
| MCP server | Official support | Community only | Official |
| Embedding | Free, no watermark | Free, with watermark | AGPL complications |
| Best for | Business BI | Simple BI | Monitoring/time-series |
| Setup complexity | Medium (3 containers) | Low (2 containers) | Low (1 container) |

## Limitations & Gotchas

- **Chart config JSON is complex** — no standalone schema docs, must reverse-engineer from UI
- **API is not versioned** — endpoints rarely change but no backward-compat guarantee
- **Docker-compose not recommended for production** — K8s preferred for HA
- **Database drivers not included by default** — need to build custom image for non-Postgres sources
- **No bulk operations** — creating many charts means many API calls
- **Learning curve** — more complex than Metabase for initial setup

## Adoption Stats (as of 2025-2026)

| Metric | Superset | Metabase | Grafana |
|---|---|---|---|
| GitHub stars | ~71k | ~46k | ~68k |
| Users | 500k+ worldwide | ~6k tracked companies | 25M+ |
| Revenue (commercial arm) | Preset (undisclosed) | $13.4M | $400M+ ARR |
| Monthly contributors | ~42, ~266 PRs/month | Smaller (122-person company) | 2,000+ total contributors |
| Growth | ~40% annual adoption increase | Steady | Dominant in observability |
| Backing | Apache Foundation + Preset | VC-funded startup | Grafana Labs (enterprise) |

Superset is the most adopted open-source tool for business BI specifically. Grafana is larger overall but monitoring-focused. Metabase is smaller but known for simplicity.

## Key Sources

- [Superset API Reference](https://superset.apache.org/docs/api/)
- [Superset Docker Compose](https://superset.apache.org/docs/installation/docker-compose/)
- [Superset MCP Integration](https://superset.apache.org/developer_portal/extensions/mcp/)
- [aptro/superset-mcp GitHub](https://github.com/aptro/superset-mcp)
- [Superset Community Update Feb 2026](https://preset.io/blog/apache-superset-community-update-february-2026/)
- [Creating charts via API](https://github.com/apache/superset/discussions/26191)
- [Dashboard creation via API](https://github.com/apache/superset/discussions/32970)
- [Superset Embedded SDK](https://github.com/apache/superset/tree/master/superset-embedded-sdk)
- [Superset Configuration](https://superset.apache.org/docs/configuration/configuring-superset/)
