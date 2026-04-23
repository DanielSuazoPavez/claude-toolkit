# Artifact Output Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Authoring a skill or agent that writes files to `output/claude-toolkit/`
- Reviewing a skill/agent declaration of a `Save to:` / `Write to:` path
- Debugging drift between a declared output path and where files actually land

Standard output path for runtime artifacts produced by skills and agents:

```
output/claude-toolkit/<category>/{YYYYMMDD}_{HHMM}__<source>__<slug>.md
```

**See also:** `relevant-toolkit-resource_naming` for naming of the resources themselves (skills, agents, hooks, docs)

---

## 2. Components

| Part | Rule | Example |
|------|------|---------|
| `<category>` | Lowercase kebab-case; emergent — pick the closest existing directory under `output/claude-toolkit/` before inventing a new one | `analysis`, `reviews`, `sessions`, `plans`, `brainstorm` |
| `{YYYYMMDD}` | 8-digit date, no separators | `20260423` |
| `_` | Single underscore between date and time | — |
| `{HHMM}` | 4-digit 24h time, no separator | `1410` |
| `__` | Double underscore separates timestamp, source, slug | — |
| `<source>` | The skill or agent name that produced the artifact (kebab-case, matches the resource filename) | `analyze-idea`, `code-reviewer` |
| `<slug>` | Short lowercase-kebab descriptor of the specific artifact | `v3-e1-validators-bundle` |
| `.md` | Always markdown | — |

**Full example:**
`output/claude-toolkit/analysis/20260423_1410__analyze-idea__v3-e1-validators-bundle.md`

---

## 3. Why This Format

- **Sortable by time** — `YYYYMMDD_HHMM` sorts lexically in filename order.
- **Greppable by source** — `__<source>__` is a double-underscored island, easy to filter (`ls | grep __analyze-idea__`).
- **No ambiguity at the category boundary** — the double underscore after the timestamp prevents category-name / source-name collision.
- **One line encodes provenance** — given any artifact, you can tell *when*, *what produced it*, and *what it's about* without opening the file.

---

## 4. When It Doesn't Apply

Some resources legitimately write outside `output/claude-toolkit/`:

| Resource | Writes to | Reason |
|----------|-----------|--------|
| `shape-project` | `.claude/docs/relevant-project-identity.md` | Output *is* project config, not a runtime artifact |
| `evaluate-*` skills | `docs/indexes/evaluations.json` | Updates a shared index, not a per-run file |
| `build-communication-style` | `.claude/docs/essential-preferences-communication_style.md` | Updates a session-loaded convention |

These are not exceptions to the format — they're *not artifacts* in the first place. The convention applies only to per-invocation runtime outputs.

---

## 5. Gotchas

- **Don't use `YYYY-MM-DD`.** The hyphenated form has appeared in some older `plans/` artifacts; treat those as pre-convention and don't reproduce the format.
- **Don't use underscores in the source slot.** `review-plan`, not `review_plan` — source must match the skill/agent filename exactly.
- **Timestamp is creation time, not current time at every rewrite.** If the agent rewrites the file mid-session, the filename stays fixed — the artifact is immutable-by-name.
- **Slug goes last, not second.** `{YYYYMMDD}_{HHMM}__<source>__<slug>` — filenames sort by time first, then group visually by source.
