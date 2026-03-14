---
name: design-db
type: knowledge
description: Use when requests mention "schema design", "database migration", "data modeling", "table design", "indexing strategy", or "normalize".
---

# Database Schema Designer

## Defaults (strict unless project overrides)

| Decision | Default | Flexible when... |
|----------|---------|-------------------|
| Primary keys | BIGINT internal, UUID public-facing | Project already uses a different convention |
| UUID version | UUIDv7 (time-ordered index locality) | UUIDv4 acceptable if no range queries on PK |
| Foreign keys | Always constrain, define ON DELETE | Never skip — no flexibility here |
| Money columns | DECIMAL, never FLOAT | Never skip |
| Migrations | Always reversible (UP + DOWN) | One-way acceptable for data-only backfills |
| Starting point | Normalize to 3NF first | Denormalize only with measured perf data |

## Indexing Strategy

```sql
-- Composite: most selective column first
CREATE INDEX idx_orders_status_date ON orders(status, created_at);

-- Partial indexes: index only relevant rows (PostgreSQL)
CREATE INDEX idx_orders_pending ON orders(created_at)
  WHERE status = 'pending';  -- Much smaller, faster index

-- Covering index: avoid table lookups entirely
CREATE INDEX idx_orders_covering ON orders(customer_id, status, total)
  INCLUDE (created_at);  -- Query satisfied from index alone
```

### When NOT to Index

| Scenario | Why Skip |
|----------|----------|
| Low-cardinality columns alone (boolean, status with 3 values) | Full scan often faster than index scan |
| Write-heavy tables with rarely-queried columns | Index maintenance slows every INSERT/UPDATE |
| Small tables (<1000 rows) | Sequential scan is fast enough |
| Columns used only with functions | Index won't be used unless it's a functional index |

### Index Maintenance Costs

- Each index adds overhead to every INSERT, UPDATE, DELETE
- Unused indexes waste disk and slow writes — audit with `pg_stat_user_indexes` or `sys.dm_db_index_usage_stats`
- Duplicate/overlapping indexes (e.g., `(a)` + `(a, b)`) — the composite covers single-column queries

## Normalize vs Denormalize

For complex schemas, use `/design-diagram` to visualize entity relationships before normalizing.

```
Should I normalize this data?
├─ Is it reference data (rarely changes)? → Normalize (separate table)
├─ Is it frequently queried together? → Consider denormalizing
├─ Does duplication risk inconsistency? → Normalize
├─ Is read performance critical? → Denormalize with care
└─ Is write performance critical? → Normalize (fewer updates)
```

| Scenario | Decision | Reasoning |
|----------|----------|-----------|
| User addresses | Normalize | `addresses` table with FK |
| Order line items | Denormalize | Store price/name at time of order — source data changes |
| Product categories | Normalize | Categories change rarely, many products reference same |
| Cached aggregates | Denormalize | Store `order_count` on user — accept staleness |

**Rule of thumb:** Start normalized, denormalize only when you have measured performance problems.

## Schema Evolution

### Safe Column Changes
```sql
-- Safe: nullable column with default
ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}';

-- Unsafe: NOT NULL without default on large table (locks table)
-- Instead: add nullable → backfill in batches → add constraint
ALTER TABLE users ADD COLUMN tenant_id BIGINT;
-- Backfill in batches to avoid long locks:
UPDATE users SET tenant_id = 1 WHERE tenant_id IS NULL AND id BETWEEN 1 AND 10000;
ALTER TABLE users ALTER COLUMN tenant_id SET NOT NULL;
```

### Online DDL for Large Tables
- **PostgreSQL**: `CREATE INDEX CONCURRENTLY` (no lock)
- **MySQL**: `pt-online-schema-change` or `gh-ost`
- **Never** `ALTER TABLE` on million+ row tables during peak traffic
- Backfill in batches: `UPDATE ... WHERE id BETWEEN x AND y LIMIT 1000`

### Upsert Patterns
```sql
-- PostgreSQL
INSERT INTO users (email, name) VALUES ('a@b.com', 'Alice')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- MySQL
INSERT INTO users (email, name) VALUES ('a@b.com', 'Alice')
ON DUPLICATE KEY UPDATE name = VALUES(name);
```

## Multi-Tenancy Strategies

| Strategy | Implementation | Trade-offs |
|----------|---------------|------------|
| **Shared tables** | `tenant_id` column + RLS | Simple, but noisy neighbor risk |
| **Schema per tenant** | `tenant_123.users` | Good isolation, harder migrations |
| **Database per tenant** | Separate DB connections | Full isolation, operational complexity |

```sql
-- Row-Level Security (PostgreSQL)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::bigint);

-- Always filter by tenant_id first (index it!)
CREATE INDEX idx_orders_tenant ON orders(tenant_id, created_at);
```

## Soft Delete Pattern

```sql
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;
CREATE INDEX idx_users_active ON users(id) WHERE deleted_at IS NULL;

-- View for active records (avoids forgetting the filter)
CREATE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;

-- Unique constraints with soft delete (PostgreSQL)
CREATE UNIQUE INDEX idx_users_email_active ON users(email)
  WHERE deleted_at IS NULL;  -- Allows reuse of deleted emails
```

## Anti-Patterns

| Avoid | Instead | Why |
|-------|---------|-----|
| VARCHAR(255) everywhere | Size appropriately | Wastes memory in indexes, misleads validation |
| FLOAT for money | DECIMAL(10,2) | Rounding errors: `0.1 + 0.2 != 0.3` |
| Missing FK constraints | Always define FKs | Orphaned records, data corruption over time |
| No indexes on FKs | Index every FK | JOINs become full table scans, cascade deletes slow |
| Non-reversible migrations | Always write DOWN | Stuck deployments, can't rollback safely |
| Hard deletes | Soft delete with `deleted_at` | Lose audit trail, break FK references |
| EAV (Entity-Attribute-Value) | JSON column or separate tables | Impossible to query efficiently, no type safety |
| Indexing everything | Index what queries need | Write overhead, wasted disk, maintenance burden |

## Checklist

- [ ] Every table has a primary key
- [ ] All relationships have FK constraints with ON DELETE defined
- [ ] Indexes on all FKs and frequently queried columns
- [ ] DECIMAL for money, proper types everywhere
- [ ] NOT NULL on required fields
- [ ] created_at and updated_at timestamps
- [ ] Migrations are reversible (UP + DOWN)
- [ ] No unnecessary indexes on low-cardinality or write-heavy columns

## Schema Smith Integration

If `schema-smith` is available (`which schema-smith`), generate schemas as YAML instead of raw DDL.

1. **Read the input spec** at `schema-smith-input-spec.md` (in this skill's directory) before writing any YAML
2. **Design first** — use the knowledge sections above to make schema decisions (normalization, indexing, types)
3. **Output as schema-smith YAML** — structure the design as YAML files following the input spec
4. **Generate DDL** — run schema-smith to produce the SQL:

```bash
schema-smith generate <project> --input-dir <path>/input --output-dir <path>/output --json
```

Useful flags:
- `--validate-only` — check YAML without generating files
- `--strict` — treat warnings as errors
- `--json` — structured output for programmatic use

If `schema-smith` is not available, fall back to raw SQL as usual.

**See also:** `/design-diagram` (ER diagrams and relationship visualization), `/design-tests` (test database fixtures and factory patterns), `/refactor` (restructuring data access layers), `/design-docker` (database containers for local dev)
