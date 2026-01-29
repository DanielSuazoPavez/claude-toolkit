---
name: design-db
description: Use when requests mention "schema design", "database migration", "data modeling", "table design", "indexing strategy", or "normalize". Designs robust SQL/NoSQL schemas with normalization, indexing, migrations, constraints, and performance optimization.
---

# Database Schema Designer

Design production-ready database schemas with best practices built-in.

## Quick Start

Describe your data model:
```
design a schema for an e-commerce platform with users, products, orders
```

## Process

1. **Analyze**: Identify entities, relationships, access patterns
2. **Design**: Normalize to 3NF, define keys, add constraints
3. **Optimize**: Indexing strategy, consider denormalization
4. **Migrate**: Reversible scripts, backward compatible

## Quick Reference

| Task | Approach |
|------|----------|
| New schema | Normalize to 3NF first |
| SQL vs NoSQL | Access patterns decide |
| Primary keys | INT or UUID (UUID for distributed) |
| Foreign keys | Always constrain, define ON DELETE |
| Indexes | FKs + WHERE columns |
| Migrations | Always reversible |

## SQL vs NoSQL Decision Tree

```
What's your primary access pattern?
├─ Complex queries, joins, transactions → SQL
│   ├─ Need ACID guarantees? → PostgreSQL
│   ├─ High read volume? → MySQL with replicas
│   └─ Embedded/lightweight? → SQLite
│
└─ Simple lookups by key, flexible schema → NoSQL
    ├─ Document storage (nested, variable structure)? → MongoDB
    ├─ Key-value with TTL (caching, sessions)? → Redis
    ├─ Time-series data? → TimescaleDB, InfluxDB
    └─ Graph relationships? → Neo4j
```

### Decision Factors

| Factor | SQL | NoSQL |
|--------|-----|-------|
| Schema | Fixed, migrations | Flexible, schemaless |
| Transactions | ACID guaranteed | Eventually consistent* |
| Joins | Native, optimized | Application-level |
| Scale | Vertical (+ read replicas) | Horizontal sharding |
| Best for | Complex queries, reporting | High write volume, simple reads |

*Some NoSQL (MongoDB, FaunaDB) support transactions

## Data Types

```sql
-- Money: ALWAYS DECIMAL, never FLOAT
price DECIMAL(10, 2)

-- Timestamps
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
updated_at TIMESTAMP ON UPDATE CURRENT_TIMESTAMP

-- IDs
id BIGINT AUTO_INCREMENT PRIMARY KEY  -- Simple
id CHAR(36) DEFAULT (UUID())          -- Distributed
```

## Indexing

```sql
-- Always index foreign keys
CREATE INDEX idx_orders_customer ON orders(customer_id);

-- Composite: most selective first
CREATE INDEX idx_orders_status_date ON orders(status, created_at);

-- Partial indexes: index only relevant rows (PostgreSQL)
CREATE INDEX idx_orders_pending ON orders(created_at)
  WHERE status = 'pending';  -- Much smaller, faster index

-- Partial index for sparse columns (mostly NULL)
CREATE INDEX idx_users_deleted ON users(deleted_at)
  WHERE deleted_at IS NOT NULL;  -- Index only deleted users

-- Covering index: avoid table lookups
CREATE INDEX idx_orders_covering ON orders(customer_id, status, total)
  INCLUDE (created_at);  -- Query satisfied entirely from index
```

## Anti-Patterns

| Avoid | Instead | Why |
|-------|---------|-----|
| VARCHAR(255) everywhere | Size appropriately | Wastes memory in indexes, misleads validation |
| FLOAT for money | DECIMAL(10,2) | FLOAT causes rounding errors: `0.1 + 0.2 != 0.3` |
| Missing FK constraints | Always define FKs | Orphaned records, data corruption over time |
| No indexes on FKs | Index every FK | JOINs become full table scans, cascade deletes slow |
| Dates as strings | DATE, TIMESTAMP types | Can't compare, sort, or do date math correctly |
| Non-reversible migrations | Always write DOWN | Stuck deployments, can't rollback safely |
| Hard deletes | Soft delete with `deleted_at` | Lose audit trail, break foreign key references |
| EAV (Entity-Attribute-Value) | JSON column or separate tables | Impossible to query efficiently, no type safety |

## Migration Template

```sql
-- UP
BEGIN;
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
CREATE INDEX idx_users_phone ON users(phone);
COMMIT;

-- DOWN
BEGIN;
DROP INDEX idx_users_phone ON users;
ALTER TABLE users DROP COLUMN phone;
COMMIT;
```

## Schema Evolution Patterns

### Adding Columns Safely
```sql
-- Safe: nullable column with default
ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}';

-- Unsafe: NOT NULL without default on large table (locks table)
-- Instead: add nullable, backfill, then add constraint
ALTER TABLE users ADD COLUMN tenant_id BIGINT;
UPDATE users SET tenant_id = 1 WHERE tenant_id IS NULL;  -- Batch this!
ALTER TABLE users ALTER COLUMN tenant_id SET NOT NULL;
```

### Online DDL for Large Tables
```sql
-- PostgreSQL: CREATE INDEX CONCURRENTLY (no lock)
CREATE INDEX CONCURRENTLY idx_orders_customer ON orders(customer_id);

-- MySQL: pt-online-schema-change or gh-ost for large tables
-- Avoid: ALTER TABLE on multi-million row tables during traffic
```

### Constraint Violation Handling
```sql
-- Upsert pattern (PostgreSQL)
INSERT INTO users (email, name) VALUES ('a@b.com', 'Alice')
ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;

-- Upsert pattern (MySQL)
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

## Soft Delete Patterns

```sql
-- Standard soft delete
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;
CREATE INDEX idx_users_active ON users(id) WHERE deleted_at IS NULL;

-- Queries must filter: WHERE deleted_at IS NULL
-- Consider: view for active records
CREATE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;

-- Unique constraints with soft delete (PostgreSQL)
CREATE UNIQUE INDEX idx_users_email_active ON users(email)
  WHERE deleted_at IS NULL;  -- Allows reuse of deleted emails
```

## Normalize vs Denormalize

```
Should I normalize this data?
├─ Is it reference data (rarely changes)? → Normalize (separate table)
├─ Is it frequently queried together? → Consider denormalizing
├─ Does duplication risk inconsistency? → Normalize
├─ Is read performance critical? → Denormalize with care
└─ Is write performance critical? → Normalize (fewer updates)
```

| Scenario | Decision | Example |
|----------|----------|---------|
| User addresses | Normalize | `addresses` table with FK |
| Order snapshot | Denormalize | Store price at time of order |
| Product categories | Normalize | Categories change rarely |
| Cached aggregates | Denormalize | Store `order_count` on user |

**Rule of thumb:** Start normalized, denormalize only when you have measured performance problems.

## Edge Cases

### Large Table Migrations
- **Never** run `ALTER TABLE` on million+ row tables during peak traffic
- Use `pt-online-schema-change` (MySQL) or `CREATE INDEX CONCURRENTLY` (PostgreSQL)
- Backfill data in batches: `UPDATE ... WHERE id BETWEEN x AND y LIMIT 1000`
- Add columns as nullable first, backfill, then add NOT NULL constraint

### Handling Constraint Violations
- Use `ON CONFLICT` / `ON DUPLICATE KEY` for upserts
- Wrap bulk inserts in transactions with `SAVEPOINT` for partial success
- Log violations for debugging rather than silently ignoring

### Partial Indexes for Sparse Data
- Index only non-NULL values: `WHERE column IS NOT NULL`
- Index only active records: `WHERE status = 'active'`
- Index hot data: `WHERE created_at > NOW() - INTERVAL '30 days'`

### UUID vs Integer Keys
- UUIDs: no sequence bottleneck, safe for distributed systems, but larger indexes
- Use UUIDv7 (time-ordered) for better index locality than UUIDv4
- Consider `BIGINT` for internal tables, `UUID` for public-facing IDs

## Checklist

- [ ] Every table has a primary key
- [ ] All relationships have FK constraints
- [ ] ON DELETE strategy defined for each FK
- [ ] Indexes on all FKs and frequently queried columns
- [ ] DECIMAL for money, proper types everywhere
- [ ] NOT NULL on required fields
- [ ] created_at and updated_at timestamps
- [ ] Migrations are reversible
