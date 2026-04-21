# v3 Audit — `dist/`

Exhaustive file-level audit of the `dist/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Note:** this doc was opened during stage 1 to capture a single early finding (the stale gitignore entry). Findings logged here are **not resolved** — they are queued for stage 2, where the full `dist/` audit happens and actions are applied. Stage 1 is prose-only; code/config edits wait.

---

## Early Findings (captured during stage 1)

### `dist/base/templates/gitignore.claude-toolkit`

- **Tag:** `Rewrite`
- **Finding:** Lines 16–18 gitignore `lessons.db`, `session-index.db`, and `hooks.db`. Two issues:
  1. `session-index.db` was renamed to `sessions.db` at some point — the entry is stale.
  2. `hooks.db` was at `~/.claude/` at some point but is no longer expected in project roots.
- **Action:** remove both `session-index.db` and `hooks.db` entries. Keep `lessons.db`.
- **Scope:** trivial — 2-line removal in the gitignore template.

---

## Stage 2 TODO (not yet filled in)

The remaining files in `dist/` get findings in stage 2. Placeholder list:

- [ ] `dist/CLAUDE.md`
- [ ] `dist/base/EXCLUDE`
- [ ] `dist/base/templates/BACKLOG-minimal.md`
- [ ] `dist/base/templates/BACKLOG-standard.md`
- [ ] `dist/base/templates/CLAUDE.md.template`
- [ ] `dist/base/templates/Makefile.claude-toolkit`
- [ ] `dist/base/templates/PULL_REQUEST_TEMPLATE.md`
- [ ] `dist/base/templates/claude-powerline.json`
- [ ] `dist/base/templates/claude-toolkit-ignore.template`
- [ ] `dist/base/templates/gitignore.claude-toolkit` (finding pre-logged above; action still pending)
- [ ] `dist/base/templates/mcp.template.json`
- [ ] `dist/base/templates/settings.template.json`
- [ ] `dist/raiz/MANIFEST`
- [ ] `dist/raiz/templates/CLAUDE.md.template`
- [ ] `dist/raiz/templates/settings.template.json`
- [ ] (any other files under `dist/raiz/changelog/` or elsewhere — confirm at stage 2 start)
