# Satellite Consumer Conventions

## 1. Quick Reference

**READ WHEN:**
- Building a workshop skill that calls a satellite CLI contract (e.g., `/design-db` calling `schema-smith docs input-spec`)
- Adding satellite integration to an existing skill
- Reviewing whether inlined spec copies in a skill should be replaced by a runtime CLI call
- Debugging why a satellite contract fetch failed and what the skill should do instead

**Audience:** workshop skill authors. This doc defines how skills on the workshop side discover, invoke, and handle failures from satellite contracts. Pairs with `relevant-toolkit-satellite-contracts` (the satellite maintainer's view).

**Core idea:** Skills that use satellite contracts should fetch them at runtime via a stable CLI convention, rather than carrying a copy that drifts. When the satellite is unavailable, the skill has an explicit fallback path — either a reduced-quality output or a refusal, the skill author decides.

**See also:** `relevant-toolkit-satellite-contracts` for the satellite maintainer's side, `relevant-project-identity` for the workshop/satellite relationship

---

## 2. Why This Exists

Workshop skills that pair with a satellite CLI need to know the satellite's agent-facing contract — the YAML input shape, the JSON output schema, the infrastructure template shape, whatever the skill's Claude instance has to produce or consume. Historically the workshop solves this by **copying the spec** into the skill (a 300-line YAML spec in `.claude/skills/design-db/resources/schema-smith-input-spec.md`).

Copied specs break down quietly:
- The satellite adds a field; the copy doesn't know.
- The workshop copy is well-written but stale; nothing fails loudly.
- Two sources of truth for the same contract.

The fix is to move the contract into the satellite's own CLI as a **documentation command** — stable, machine-addressable, owned by the satellite. Workshop skills then call it at runtime. When the satellite is unavailable, the skill follows an explicit fallback ladder: check for the binary, invoke the command, validate output, and either proceed or fall back gracefully.

---

## 3. The Pointer File

When a skill integrates with a satellite contract, create a **pointer file** in the skill's `resources/` directory. It externalizes the invocation logic and makes the fallback path explicit.

### 3.1 Location and Naming

```
.claude/skills/<skill>/resources/<contract-name>.md
```

File name matches the satellite contract name exactly (e.g., `schema-smith-input-spec.md` for `schema-smith docs input-spec`).

### 3.2 Two Mandatory Sections

#### Section 1: Using the Satellite

```markdown
## Using the satellite

<1–2 sentence explanation of what this contract is used for>

Fetch at runtime with:

    <satellite> docs <contract-name>

Minimum required version: <satellite> ≥ <version> (ships the `docs` command).
```

Example from `design-db`:

```markdown
## Using the satellite

The `input-spec` contract describes the YAML shape that `schema-smith generate` expects —
table definitions, field types, index declarations, and relationship edges.

Fetch at runtime with:

    schema-smith docs input-spec

Minimum required version: schema-smith ≥ 1.6.0 (ships the `docs` command).
```

#### Section 2: No Satellite

```markdown
## No satellite

<Explicit fallback: either a reduced-quality path OR refusal>
```

The skill author chooses. Examples:

- **Reduced-quality path** — produce raw SQL DDL instead of schema-smith YAML. Valid output, but loses the YAML-first workflow.
- **Refusal** — don't attempt the request without the satellite. The user is told the satellite is required.
- **Hybrid** — try the satellite, fall back to a simplified version if it fails.

Example from `design-db`:

```markdown
## No satellite

If `schema-smith` is not available or the command fails, produce raw SQL DDL instead of
schema-smith YAML. This is a reduced-quality path — DDL is valid output but loses the
YAML-first workflow and automated generation. Do not refuse; the user still gets a usable
schema design.
```

---

## 4. Invocation Pattern at Runtime

When a skill fetches a satellite contract, follow this 4-step ladder:

1. **Check for the binary** — `which <satellite>` → exit code non-zero or empty output = satellite missing, proceed to fallback silently.
2. **Invoke the docs command** — `<satellite> docs <contract-name>` → non-zero exit or error output = command failed, proceed to fallback silently.
3. **Validate output** — Zero exit, but empty or unparseable output → warn the user ("fetched <satellite> docs <contract-name> but output was empty/invalid"), proceed to fallback.
4. **Success** — Zero exit and valid output → proceed with the fetched spec.

**Pseudocode:**

```bash
if ! which "$satellite" > /dev/null 2>&1; then
  # Satellite missing: silent fallback (handled by skill's "no satellite" path)
  proceed_with_fallback
elif ! output=$(${satellite} docs ${contract} 2>&1); then
  # Command failed: silent fallback
  proceed_with_fallback
elif [[ -z "$output" ]]; then
  # Output empty: warn user
  echo "Warning: fetched ${satellite} docs ${contract} but output was empty" >&2
  proceed_with_fallback
else
  # Success: use the fetched spec
  process_output "$output"
fi
```

---

## 5. Failure Ladder — Decision Table

What happens when the satellite is missing, broken, or returns invalid output:

| Condition | User sees | Skill does |
|-----------|-----------|-----------|
| Satellite binary not found (`which` fails) | Nothing (silent) | Fall back to "no satellite" path from pointer file |
| Command exits non-zero (`<satellite> docs <contract>` fails) | Nothing (silent) | Fall back to "no satellite" path from pointer file |
| Command succeeds but output is empty | Warning: "fetched <satellite> docs <contract> but output was empty — falling back to <fallback-mode>" | Fall back to "no satellite" path from pointer file |
| Command succeeds, output is valid | Nothing (spec is used internally) | Proceed with fetched spec |

**Rationale:** Silent fallback for missing/broken satellite preserves backward compatibility — the skill was working before the satellite existed, and it continues to work if the satellite is uninstalled or breaks. User-visible warnings only when the satellite *partially* succeeds (command exits 0 but produces garbage), so the user knows something went wrong and has a hint.

---

## 6. Failure Ladder — Future Extensibility

These are **not yet implemented** but worth knowing as you design a pointer file:

- **Persisting satellite errors for review** — if a command fails, should the skill save stderr to `output/<skill>/satellite-errors/<timestamp>.txt` for the user to inspect? Deferred — no evidence of need yet. Decide if a pattern emerges across multiple skills.
- **Strict mode** — could a skill define a mode where missing/broken satellite is an error, not a fallback? Deferred — most skills should be usable offline.

---

## 7. Updating Skill Documentation

When a skill integrates with a satellite, update the skill's `SKILL.md` to:

1. **Reference the pointer file** — "See `resources/<contract-name>.md` for the invocation pattern and fallback path" (1–2 lines).
2. **Explain usage, not invocation** — what the contract *is used for* in the skill's workflow (keep this in SKILL.md).
3. **Remove inlined specs and invocation logic** — that's what the pointer file is for.

Example refactor from `design-db`:

**Old (inlined):**

```markdown
## Schema Smith Integration

If `schema-smith` is available, generate schemas as YAML instead of raw DDL.
Requires schema-smith ≥ 1.6.0 (which ships `docs` and `version` commands).

1. **Fetch the current input spec** by running `schema-smith docs input-spec` — this emits
   the YAML shape as markdown to stdout. If the command fails for any reason, fall back to raw SQL.
2. **Design first** — use the knowledge sections above to make schema decisions...
3. ...
```

**New (pointer-based):**

```markdown
## Schema Smith Integration

If `schema-smith` is available, generate schemas as YAML instead of raw DDL. Follow the
satellite consumer convention (`relevant-toolkit-satellite-consumers`): read
`resources/schema-smith-input-spec.md` for the invocation pattern and fallback path.

1. **Fetch the current input spec** — as described in `resources/schema-smith-input-spec.md`
2. **Design first** — use the knowledge sections above to make schema decisions...
3. **Output as schema-smith YAML** — structure the design as YAML files following the fetched spec
...
```

---

## 8. Adding a New Satellite Integration (Checklist)

When adding a new satellite contract to a skill:

- [ ] **Confirm satellite has the `docs` command** — check the satellite's `<satellite> docs --help` or `<satellite> --help` output
- [ ] **Create the pointer file** — `.claude/skills/<skill>/resources/<contract-name>.md` with "Using the satellite" and "No satellite" sections
- [ ] **Update `SKILL.md`** — replace inlined specs with a reference to the pointer file
- [ ] **Test the failure ladder** — uninstall/break the satellite and verify the skill's fallback path works
- [ ] **Update this doc** — add a row to the "Current State" table below (if the skill/satellite pairing is significant)

---

## 9. Current State (2026-04-24)

Reference snapshot for workshop maintainers; will drift — check individual skills and satellites for current truth.

| Skill | Satellite | Contract | Pointer file | Status |
|---|---|---|---|---|
| `/design-db` | `schema-smith` | `input-spec` | `resources/schema-smith-input-spec.md` | Live |
| `/design-aws` | `aws-toolkit` | `infra-input-spec` | (skill not yet built) | Planned |

---

## 10. See Also

- `relevant-toolkit-satellite-contracts` — the satellite maintainer's view (how to expose contracts via CLI)
- `relevant-project-identity` — workshop/satellite ecosystem overview
- `/design-db` skill — first concrete implementation of this convention
- `schema-smith` CLI — example satellite with `docs` command
