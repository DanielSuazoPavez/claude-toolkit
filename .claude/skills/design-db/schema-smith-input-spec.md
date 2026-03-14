# Input Format Specification

YAML schema definitions that drive all generation. Each project lives in `input/<project>/`.

## Directory Layout

```
input/<project>/
  extensions.yaml          # PostgreSQL extensions (optional, project-level)
  scripts_config.yaml      # Pre/post-processing SQL scripts (optional)
  schemas/
    mixins/
      global.yaml          # Shared mixins (loaded automatically for all schemas)
    <schema_name>.yaml     # One file per schema (or multiple files sharing schema_name)
  sql_scripts/             # Raw SQL files referenced by scripts_config
    preprocessing/
    postprocessing/
```

## Schema File (`.yaml`)

Each YAML file in `schemas/` defines one PostgreSQL schema. The schema name defaults to the filename (without `.yaml`), or can be overridden with `schema_name`.

Multiple files can contribute tables to the same schema by sharing the same `schema_name`. Convention is one file per schema.

**Limitation:** Schema-local mixins (defined under `mixins:` in a schema file) are only visible within that file. If two files share the same `schema_name`, file A's local mixins are not available to file B. Global mixins (`schemas/mixins/global.yaml`) are available everywhere.

```yaml
# Top-level fields
description: "Human-readable schema description"    # optional
schema_name: custom_name                            # optional, overrides filename

# Schema-level index configuration (inherited by all tables)
index_config:                                       # optional
  auto_generate_fk_indexes: true                    # default: true
  fk_index_prefix: "idx_fk_"                        # default: "idx_fk_"

enums:        # optional, dict of enum definitions
mixins:       # optional, dict of schema-local mixin definitions
tables:       # required, dict of table definitions
```

## Enums

Define custom PostgreSQL ENUM types. Enums are registered in the type registry and can be used as column types within the same schema or cross-schema.

```yaml
enums:
  <enum_name>:
    values: [val1, val2, val3]       # required, list of unique strings
    description: "Description"       # optional
```

- Name must match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- Values must be non-empty and unique
- Use as column type: `type: <enum_name>` (same schema) or `type: <schema>.<enum_name>` (cross-schema)

## Mixins

Reusable sets of columns, foreign keys, and triggers. Defined in `schemas/mixins/global.yaml` (shared) or within individual schema files (schema-local).

```yaml
mixins:
  <mixin_name>:
    position: end                    # "start" or "end" (default: "end")
                                     # controls column ordering in table
    columns:                         # optional
      <column_name>:
        # ... column fields (see Column section)
    foreign_keys:                    # optional, list of FK definitions
      - column: <col_name>
        reference:
          schema: <schema>
          table: <table>
          column: <col>              # default: "id"
        on_delete: CASCADE           # optional
        on_update: CASCADE           # optional
    triggers:                        # optional, list of trigger definitions
      - function: <schema>.<function_name>
        timing: BEFORE
        events: [UPDATE]
    metadata:                        # optional, not used by generator
      column_group: "group_name"
      order_priority: 100
```

### Mixin position behavior
- `start`: columns appear before table-specific columns
- `end`: columns appear after table-specific columns
- Table-specific columns always override mixin columns with the same name

### Common mixin patterns (from examples)
- `string_id` — VARCHAR primary key at start
- `auto_id` — BIGSERIAL primary key at start
- `named` — unique VARCHAR `name` column at start
- `audit` — `created_at`/`updated_at` timestamps + trigger at end
- `soft_delete` — `deleted_at`/`is_deleted` columns at end
- FK reference mixins (e.g., `region_id`, `facility_id`) — single column + FK

## Tables

```yaml
tables:
  <table_name>:
    description: "Table description"     # optional, becomes COMMENT ON TABLE
    mixins:                              # optional, list of mixin names
      - mixin_a
      - mixin_b
    columns:                             # optional (tables can be mixin-only)
      <column_name>:
        # ... column fields (see Column section)
    primary_key:                         # optional, for composite PKs
      columns: [col_a, col_b]
    foreign_keys:                        # optional, list of FK definitions
      - # ... FK fields (see Foreign Key section)
    indexes:                             # optional, dict of index definitions
      <index_name>:
        # ... index fields (see Index section)
    checks:                              # optional, dict of CHECK constraints
      <check_name>: "SQL condition"      # string shorthand
      # or:
      <check_name>:
        condition: "SQL condition"       # dict form
    triggers:                            # optional, list of trigger definitions
      - # ... trigger fields (see Trigger section)
    index_config:                        # optional, table-level override
      auto_generate_fk_indexes: false
```

## Columns

```yaml
<column_name>:
  type: varchar              # required — see Supported Types below
  size: 255                  # optional, default: 100 (only for varchar, char)
  required: true             # optional, default: false — adds NOT NULL
  unique: true               # optional, default: false
  primary_key: true          # optional, default: false — single-column PK
  optional: true             # optional, default: false — forces NOT required
  description: "text"        # optional, becomes COMMENT ON COLUMN
  default_value: "expr"      # optional, raw SQL expression (e.g., "CURRENT_TIMESTAMP", "'active'")
  check: "SQL condition"     # optional, column-level CHECK constraint
```

### Primary key rules
- **Single-column PK**: use `primary_key: true` on the column
- **Composite PK**: use table-level `primary_key.columns: [col_a, col_b]`
- Cannot use both on the same table
- Cannot have multiple columns with `primary_key: true` in the same table (including across mixins)

### Default values
- String literals must be wrapped in single quotes inside double quotes: `default_value: "'active'"`
- SQL expressions are bare: `default_value: "CURRENT_TIMESTAMP"`, `default_value: "TRUE"`

## Supported Column Types

| Category | Types |
|----------|-------|
| Numeric | `smallint`, `integer`, `bigint`, `serial`, `bigserial`, `decimal`, `numeric`, `real`, `double precision`, `money` |
| Character | `varchar` (accepts size), `char` (accepts size), `text` |
| Boolean | `boolean` |
| Date/Time | `date`, `timestamp`, `timestamptz`, `time`, `timetz`, `interval` |
| Binary | `bytea` |
| UUID | `uuid` |
| JSON | `json`, `jsonb` |
| Network | `inet`, `cidr`, `macaddr` |
| Full-text | `tsvector`, `tsquery` |
| XML | `xml` |
| Array | Any type + `[]` suffix (e.g., `integer[]`, `varchar[]`) |
| Enum | User-defined enum name or `schema.enum_name` |

Notes:
- `serial`/`bigserial` automatically skip NOT NULL (handled by PostgreSQL)
- `varchar`/`char` accept `size` parameter (default 100)

## Foreign Keys

```yaml
foreign_keys:
  - column: local_column_name        # required
    reference:                       # required (string or dict)
      schema: target_schema          # optional (defaults to current schema in table FKs,
                                     #   consuming table's schema for mixin FKs)
      table: target_table            # required
      column: target_column          # optional, default: "id"
    on_delete: CASCADE               # optional, valid: CASCADE, RESTRICT, NO ACTION, SET NULL, SET DEFAULT
    on_update: CASCADE               # optional, same valid values
    auto_index: true                 # optional, default: true — auto-generate index for this FK
    index_name: custom_idx_name      # optional, override auto-generated index name
```

### Reference shorthand
```yaml
# Dict form (full):
reference:
  schema: core
  table: users
  column: id

# String form (table name only, defaults column to "id"):
reference: users
```

### Auto-indexing behavior
- By default, indexes are auto-generated for FK columns
- Disable per-FK: `auto_index: false`
- Disable per-table: `index_config.auto_generate_fk_indexes: false`
- If a manual index already exists on the FK column, a validation warning is emitted

## Indexes

```yaml
indexes:
  <index_name>:                      # base name for the index
    columns:                         # required, list of column names
      - column_a
      - column_b
    unique: true                     # optional, default: false
    method: gin                      # optional, valid: btree, hash, gin, gist, spgist, brin
    conditions:                      # optional, list of WHERE conditions (makes it a partial index)
      - "is_available = true AND is_deleted = false"
```

Index names exceeding PostgreSQL's 63-char limit are automatically truncated with a hash suffix.

## CHECK Constraints

```yaml
# String shorthand (most common):
checks:
  positive_value: "value > 0"

# Dict form:
checks:
  positive_value:
    condition: "value > 0"

# Column-level (inline):
columns:
  month:
    type: integer
    check: "month BETWEEN 1 AND 12"
```

Constraint names are auto-generated as `chk_<table>_<check_name>` (or `chk_<table>_<column>` for column-level).

## Triggers

```yaml
triggers:
  - function: public.trigger_set_timestamp    # required, schema.function_name format
                                               # bare name defaults to public schema
    timing: BEFORE                             # optional, default: BEFORE
                                               # valid: BEFORE, AFTER, INSTEAD OF
    events: [UPDATE]                           # optional, default: [UPDATE]
                                               # valid: INSERT, UPDATE, DELETE, TRUNCATE
                                               # supports multiple events
    for_each: ROW                              # optional, default: ROW
                                               # valid: ROW, STATEMENT
```

Trigger names are auto-generated as `trg_<function_name>_<table_name>`.
Triggers defined in mixins are inherited by all tables using that mixin.

## Extensions (`extensions.yaml`)

```yaml
extensions:
  # String form (name only):
  - uuid-ossp
  - hstore

  # Dict form (with metadata):
  - name: pgcrypto
    schema: public                   # optional, install schema
    version: "1.3"                   # optional
    description: "Cryptographic functions"  # optional
```

- Extension names must match `^[a-zA-Z_][a-zA-Z0-9_-]*$`
- No duplicate names allowed
- Generates `CREATE EXTENSION IF NOT EXISTS` statements

## Scripts Config (`scripts_config.yaml`)

```yaml
preprocessing_scripts:
  - name: create_trigger_function
    description: "Create trigger function for updated_at columns"
    file: sql_scripts/preprocessing/updated_at_trigger.sql
    order: 1                         # execution order
    enabled: true                    # set false to skip
postprocessing_scripts:
  - name: populate_time
    description: "Populate time dimension"
    file: sql_scripts/postprocessing/populate_time.sql
    order: 1
    enabled: true
```

- `file` paths are relative to the project's `input/<project>/` directory
- Preprocessing scripts run before schema creation (e.g., trigger functions)
- Postprocessing scripts run after schema creation (e.g., data population)
- Scripts are ordered by `order` field, then concatenated into `00_preprocessing.sql` / `99_postprocessing.sql`
