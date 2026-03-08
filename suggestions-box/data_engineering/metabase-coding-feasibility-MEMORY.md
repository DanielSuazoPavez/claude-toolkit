# Metabase via Code: Feasibility Summary

## Context

Evaluated Metabase (open-source, Docker-based) as a fully programmable dashboard/visualization platform — companion to the Power BI feasibility study.

## The Short Answer

**The entire stack is API-driven**, including visualizations. No GUI required at any point. Metabase doesn't do data modeling (it queries your DB directly), but everything from database connections to dashboard layout can be created via code.

## What's Fully Doable via API (Free/OSS Tier)

### Database Connections
- Add/validate/update/delete data sources via `/api/database`
- Trigger schema sync and field value rescans
- Supports: Postgres, MySQL, SQLite, SQL Server, BigQuery, Snowflake, Redshift, ClickHouse, DuckDB, MongoDB, and many more

### Questions/Cards (Charts)
- Create questions with SQL or MBQL (Metabase's structured query language)
- Set chart type: line, bar, area, pie, table, pivot, gauge, funnel, scatter, map, waterfall, Sankey, etc.
- Configure visualization settings (axis labels, colors, series, goal lines) via JSON
- Execute ad-hoc queries via `/api/dataset`

### Dashboards
- Create dashboards via `/api/dashboard`
- Add cards with explicit grid positioning (`row`, `col`, `size_x`, `size_y`)
- Configure filter parameters (date, category, ID, text, number, location)
- Wire filters to cards via `parameter_mappings`

### Users & Permissions
- Create/manage users and groups
- Configure group-based data access permissions

### Embedding
- Static/signed embedding (JWT-signed iframe URLs) — free, with "Powered by Metabase" watermark
- Parameters can be locked, editable, or disabled per embed

### Configuration
- Environment variables for all core settings (`MB_DB_*`, `MB_SITE_*`, `MB_EMBEDDING_*`, etc.)
- Docker secrets via `_FILE` suffix

## Docker Setup

Single command for testing:
```bash
docker run -d -p 3000:3000 --name metabase metabase/metabase
```

Production with Postgres backend:
```yaml
services:
  metabase:
    image: metabase/metabase:latest
    ports:
      - "3000:3000"
    environment:
      MB_DB_TYPE: postgres
      MB_DB_DBNAME: metabase
      MB_DB_HOST: postgres
      MB_DB_PORT: 5432
      MB_DB_USER: metabase
      MB_DB_PASS: secret
    depends_on:
      - postgres
  postgres:
    image: postgres:16
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: metabase
      POSTGRES_USER: metabase
      POSTGRES_PASSWORD: secret
volumes:
  pgdata:
```

## MCP Servers (Community)

No official MCP, but several community options:

| Project | Tools | Notes |
|---|---|---|
| enessari/metabase-ai-assistant | 134 tools | NL-to-SQL, dashboard templates, query optimization |
| CognitionAI/metabase-mcp-server | 82 tools | Dashboard (23), card (21), DB (13), table (16) |
| CW-Codewalnut/metabase-mcp-server | — | Business-user focused, NL analytics |

These wrap the REST API and let Claude Code create dashboards, run queries, and manage everything via natural language.

## Practical Workflow

1. Spin up Metabase + data DB via docker-compose
2. Connect data source via API
3. Build one chart in the UI, inspect the API request in browser dev tools
4. Use that JSON structure as a template to create variations via API/MCP
5. Assemble dashboards with cards and filters via API

The "inspect and template" pattern works because viz settings JSON is complex and undocumented — but consistent once captured.

## Free Tier Limitations

| Feature | Free | Pro/Enterprise |
|---|---|---|
| REST API (full CRUD) | Yes | Yes |
| Serialization (YAML export/import of dashboards, questions, settings) | No | Yes |
| Config file (`config.yml` declarative setup) | No | Yes |
| React embedding SDK | No | Yes |
| Embed watermark removal | No | Yes |
| SSO (SAML/JWT) | No | Yes |
| Data sandboxing (row/column-level) | No | Yes |
| Audit logs | No | Yes |

## API Caveats

- **Unversioned API** — endpoints rarely change but no backward-compat guarantees
- **MBQL not stable** — treated as opaque format, can change between releases
- **No bulk operations** — 50 dashboards = 50 API calls
- **Viz settings undocumented** — must reverse-engineer from UI-created objects
- **No auto-layout** — card grid positions must be calculated manually

## Comparison: Metabase vs Power BI for Code-First Dashboards

| Aspect | Power BI | Metabase (OSS) |
|---|---|---|
| Data modeling via code | Full (TMDL, MCP) | N/A (queries DB directly) |
| Dashboards via code | Needs GUI | Full API |
| Charts/visuals via code | Needs GUI | Full API |
| Filters via code | Needs GUI | Full API |
| Docker deployment | No | One command |
| Self-hosted | No (SaaS/on-prem server) | Yes |
| MCP servers | Official (Microsoft) | Community (multiple) |
| Free embedding | No (needs capacity) | Yes (with watermark) |
| Data engine | Vertipaq (in-memory) | Queries source DB |

**Bottom line**: If Power BI's strength is the semantic model layer, Metabase's strength is that the visualization layer is fully programmable. Different tools for different layers — potentially complementary.

## Key Sources

- [Metabase API Docs](https://www.metabase.com/docs/latest/api)
- [Working with the Metabase API](https://www.metabase.com/learn/metabase-basics/administration/administration-and-operation/metabase-api)
- [Running Metabase on Docker](https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker)
- [Embedding Overview](https://www.metabase.com/docs/latest/embedding/start)
- [Serialization Docs](https://www.metabase.com/docs/latest/installation-and-operation/serialization)
- [Environment Variables](https://www.metabase.com/docs/latest/configuring-metabase/environment-variables)
- [metabase-api Python package](https://pypi.org/project/metabase-api/)
