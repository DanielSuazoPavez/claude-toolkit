# Raiz Sidecar

On every version bump, write `dist/raiz/changelog/<version>.json` describing what a raiz consumer sees. The publish-raiz workflow reads it to build the Telegram notification.

## Skip check

Two-step: first filter by file paths, then judge whether a raiz consumer actually notices.

**Step 1 — does the diff touch anything raiz ships?**

```bash
git diff --name-only main...HEAD \
  | grep -Ff <(grep -v '^#\|^$' dist/raiz/MANIFEST) \
  ; git diff --name-only main...HEAD | grep -E '^dist/(raiz|base)/templates/'
```

Both empty → `skip: true`, `sections: []`. Done.

The `dist/*/templates/` grep covers `.claude/templates/` overrides — they ship to consumers but don't appear in MANIFEST (paths rewrite at sync time).

**Step 2 — if files matched, does the behavior change reach the raiz consumer?**

A file in MANIFEST can still be a `skip:true` if the edited path is gated on a feature raiz doesn't have. Examples:

- Lessons system isn't in raiz. A `session-start.sh` change that only affects lesson-surfacing rendering → `skip: true` (this is the 2.68.3 case).
- A skill in MANIFEST gets a docstring tweak with no behavioral change → `skip: true`.

When in doubt, `skip: false` and write a one-bullet section. A muted bullet is cheaper than a missed announcement.

## Decision table

| Question | Answer |
|---|---|
| No MANIFEST or templates path touched? | `skip: true` |
| Touched file but change is gated on a feature raiz doesn't ship? | `skip: true` |
| Touched file with consumer-visible behavior change? | `skip: false`, one section per `kind` |
| Cross-cutting change (e.g. new hook + doc index)? | `skip: false`, one section per `kind`, ordered by impact |

## `kind` selection

Mirrors the directory the file lives in:

| Path | `kind` |
|---|---|
| `.claude/skills/` | `skills` |
| `.claude/agents/` | `agents` |
| `.claude/hooks/` | `hooks` |
| `.claude/docs/`, `docs/` (synced) | `docs` |
| `.claude/scripts/` (incl. `lib/`) | `scripts` |
| `.claude/templates/`, `dist/*/templates/` | `templates` |
| anything else synced | `other` |

Cross-cutting commits split into one section per kind (see 2.65.0 example below).

## HTML override

`dist/raiz/changelog/<version>.html` takes precedence over the JSON in `--html` mode. Use it only for:

- Historical backfills where the sidecar schema can't reconstruct what shipped.
- Hand-crafted announcements where the rendered output needs structure JSON can't express.

Default is JSON. If the JSON copy needs polish, edit the JSON — don't reach for the override.

## Worked examples

**Skip-only** (2.68.3): `session-start.sh` was edited, but only the lesson-surfacing block changed — and lessons aren't in raiz. Step 1 matches; step 2 says skip.

```json
{ "version": "2.68.3", "date": "2026-04-26",
  "headline": "session-start narrowed to branch lessons + nudge (workshop-internal)",
  "skip": true, "sections": [] }
```

**Cross-cutting** (2.65.0): new hook + doc index refresh — two sections, hook first (primary impact).

```json
{ "version": "2.65.0", "date": "2026-04-25",
  "headline": "block-credential-exfiltration hook",
  "skip": false,
  "sections": [
    { "kind": "hooks", "bullets": ["..."] },
    { "kind": "docs",  "bullets": ["..."] }
  ] }
```

## Preview before commit

```bash
python .github/scripts/format-raiz-changelog.py <version> [--from <prev>]
```

Reads the JSON (or HTML override) and prints the Telegram message. Iterate on the sidecar copy until the preview reads well.
