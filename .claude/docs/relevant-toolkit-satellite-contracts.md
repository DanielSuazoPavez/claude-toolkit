# Satellite CLI Contract Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Building a satellite CLI that pairs with a workshop skill (`schema-smith` ↔ `/design-db`, `aws-toolkit` ↔ `/design-aws`, etc.)
- Adding a new input/output surface to an existing satellite that a workshop skill will consume
- Reviewing whether a workshop skill's duplicated spec file should be replaced by a CLI call

**Audience:** satellite maintainers. Satellites are peers of the workshop, not children — this doc describes what works well, not what you must do.

**Core idea:** a satellite CLI that pairs with a workshop skill should expose its agent-facing contracts as a **base command** on the CLI itself, so the workshop skill can fetch them at runtime instead of carrying a copy that drifts.

**See also:** `relevant-project-identity` for the workshop/satellite relationship, `relevant-toolkit-resource_naming` for workshop-side skill naming

---

## 2. Why This Exists

Workshop skills that pair with a satellite CLI need to know the satellite's contract — the YAML input shape, the JSON output schema, the database schema, whatever the skill's Claude instance has to produce or consume. Historically the workshop has solved this by **copying the spec** into the skill (e.g., a 300-line YAML spec lived at `.claude/skills/design-db/resources/schema-smith-input-spec.md`).

That approach breaks down quietly:
- The satellite adds a field; the copy doesn't know.
- The workshop copy is well-written but stale; nothing fails loudly.
- Two sources of truth for the same contract.

The fix is to move the contract into the satellite's own CLI as a **documentation command** — stable, machine-addressable, owned by the satellite. Workshop skills then call it at runtime.

This is advisory. Satellites that don't want the coupling (or don't have a paired skill yet) don't need it.

---

## 3. The Shape That Works

### 3.1 Command form

Prefer a `docs` base command with per-contract subcommands:

```bash
<satellite> docs                      # list available contracts
<satellite> docs <contract-name>      # emit one contract to stdout
```

Examples:
```bash
schema-smith docs                     # lists: input-spec, output-schema
schema-smith docs input-spec          # emits the YAML input-spec markdown
claude-sessions docs lessons-schema   # emits the lessons.db schema reference
aws-toolkit docs infra-input-spec     # emits the infra.yaml shape
```

Why a base command, not a flag:
- Scales naturally when a satellite has multiple contracts — `docs input-spec`, `docs output-schema`, `docs events`.
- Doesn't compete with flags on other subcommands (a `--print-input-spec` attached to `generate` is awkward; a top-level `--print-*` is the same thing by another name).
- Bare `<satellite> docs` gives discovery: a Claude instance can list what's available before choosing one.

A flag form (`--print-input-spec`) is acceptable for a satellite with exactly one contract that will never grow. If there's any chance of adding a second contract, start with `docs`.

### 3.2 Wire contract

This part benefits from being consistent so workshop skills can rely on it:

| Aspect | Convention | Reason |
|---|---|---|
| Output destination | `stdout` | Skill captures with `$(...)`; no temp files |
| Output format | Markdown | Human- and agent-readable; renders in terminals and contexts |
| Exit code | `0` on success | Standard |
| Side effects | None (read-only) | Safe to call mid-session from any skill |
| Encoding | UTF-8, no BOM | Avoids silent breakage in agent context |
| Missing contract | Exit non-zero, print available names to stderr | Discoverability on typos |

### 3.3 Content shape (advisory)

What makes a contract doc usable to an agent consumer — from experience with `schema-smith-input-spec`:

- **Self-contained** — understandable without the satellite's README. No "see other doc for details."
- **Scoped to one contract** — input spec ≠ tutorial ≠ architecture. Split, don't bundle.
- **Include the satellite's version in a header line** — lets skills detect skew if they care.
- **One compact end-to-end example per major shape** — agents anchor on examples faster than on prose alone.
- **Stable field names over prose** — "`schema_name: str` (optional, defaults to filename)" beats a paragraph explaining it.
- **No marketing, no install instructions, no "why we built this"** — that's README territory.

Rule of thumb: if the doc would change because your landing page copy changed, it's not a contract doc.

### 3.4 Versioning

The contract command's output shape is part of the satellite's public interface. Breaking changes to the shape (removing fields, renaming structure) warrant the same treatment as breaking changes to any other CLI surface — a major version bump, mentioned in the changelog.

The content of the doc changes freely (adding a field, documenting a new default) — those are non-breaking.

Workshop skills will typically note the minimum satellite version they expect; runtime checks aren't required (user pain surfaces fast enough).

---

## 4. Fallback Behavior in Workshop Skills

Workshop skills that call `<satellite> docs <contract>` also need a graceful path when the satellite isn't installed. The existing pattern from `/design-db`:

```
If <satellite> is available (which <satellite>), use it: run `<satellite> docs <contract>`
and follow that spec. Otherwise fall back to <plain approach> (e.g., raw SQL DDL).
```

This is the skill's job, not the satellite's. But it's worth knowing as a satellite maintainer: consumers won't hard-require you. Your contract command is a preferred path, not a load-bearing dependency.

---

## 5. When Not To Adopt This

Skip this convention if:

- The satellite has no paired workshop skill and isn't likely to get one.
- The contract in question is a language-level type (Python class, pydantic model) — language tooling already documents it.
- The consumer isn't a Claude instance (another CLI calling yours via pipes has different needs — stable JSON output matters more than agent-readable markdown).

It's fine to expose `docs` for some contracts and not others. Not every internal shape deserves to be a public contract.

---

## 6. Current State (2026-04-24)

Reference snapshot for satellite maintainers; will drift — check the satellite's `--help` for current truth.

| Satellite | Has `docs` command? | Duplicated contract in workshop? |
|---|---|---|
| claude-toolkit | Yes — `claude-toolkit docs satellite-contracts` emits this doc | n/a (workshop) |
| schema-smith | Yes | No — workshop calls `schema-smith docs input-spec` at runtime (≥ v1.6.0) |
| claude-sessions | No | No (preventative adoption) |
| aws-toolkit | No | No (skill `/design-aws` not yet built) |

The motivating case is schema-smith → `/design-db`. claude-sessions and aws-toolkit benefit from adopting early because the duplication hasn't happened yet. The workshop dogfoods the convention by exposing this doc itself — `claude-toolkit docs satellite-contracts` is how a satellite maintainer (or their Claude instance) fetches the current version at runtime.
