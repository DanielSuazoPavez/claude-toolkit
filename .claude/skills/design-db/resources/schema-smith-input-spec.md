# schema-smith input-spec

## Using the satellite

The `input-spec` contract describes the YAML shape that `schema-smith generate` expects —
table definitions, field types, index declarations, and relationship edges. Fetching at
runtime ensures the skill uses the schema-smith version installed in the project, not a
workshop copy that may have drifted.

Fetch at runtime with:

    schema-smith docs input-spec

Minimum required version: schema-smith ≥ 1.6.0 (ships the `docs` command).

## No satellite

If `schema-smith` is not available or the command fails, produce raw SQL DDL instead of
schema-smith YAML. This is a reduced-quality path — DDL is valid output but loses the
YAML-first workflow and automated generation. Do not refuse; the user still gets a usable
schema design.
