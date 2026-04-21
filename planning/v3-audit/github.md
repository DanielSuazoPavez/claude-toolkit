# v3 Audit — `.github/`

Exhaustive file-level audit of the `.github/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`.github/` is the publishing pipeline: PR template, raiz build+push workflow, the `publish.py` that materializes a distribution from a MANIFEST, and the changelog formatter for Telegram notifications. Workshop-shaped — nothing orchestrates downstream projects; `publish-raiz.yml` pushes a *snapshot* into a separate repo (`claude-toolkit-raiz`) via its own deploy key. The relationship is "workshop → published artifact → consumer repo," not "workshop → reach into consumer."

Four files, all `Keep` with one `Investigate` on the workflow's path filter (missing `CHANGELOG.md` trigger). Small finding set.

---

## Files

### `.github/PULL_REQUEST_TEMPLATE.md`

- **Tag:** `Keep`
- **Finding:** Identical to `dist/base/templates/PULL_REQUEST_TEMPLATE.md` (same 12-line scaffold). This is the toolkit's own PR template; the one under `dist/base/templates/` is the template that gets synced *to* consumer projects. Deliberate duplication — one is inbound (toolkit contributors), one is outbound (consumer projects). Not a dedup target.
- **Action:** none.

### `.github/workflows/publish-raiz.yml`

- **Tag:** `Investigate`
- **Finding:** Clean, well-scoped workflow: builds the raiz distribution via `publish.py`, syncs it to the `claude-toolkit-raiz` repo via SSH deploy key, and sends a Telegram notification formatted from the changelog. Two small things to check:

  1. **Path filter omits `CHANGELOG.md`.** Trigger paths (lines 7–15) include `.claude/**`, `dist/**`, and the two `.github/scripts/` files, but **not** `CHANGELOG.md`. The Telegram message is built *from* `CHANGELOG.md` at step "Build Telegram message" (line 76+). This means a pure-changelog fix (e.g., amending wording in a version entry) won't re-fire the workflow — which is sometimes desired (don't re-publish for doc-only tweaks) and sometimes not (re-running for a Telegram-message correction). Worth a deliberate call rather than an accidental omission. If intentional, add a comment; if not, add `CHANGELOG.md` to the path list or move changelog formatting somewhere retriggerable.

  2. **`VERSION` also not in the path filter.** A bare version bump (only `VERSION` changes) wouldn't trigger this workflow either. Currently `VERSION` bumps always ride alongside resource or dist changes, so this doesn't bite in practice — but it's an implicit assumption worth noting. If the workflow is the source of truth for "this version exists as a raiz artifact," then `VERSION` belongs in the filter.

- **Action:** at decision point: decide deliberate-or-oversight on both `CHANGELOG.md` and `VERSION` path triggers; add them or document the omission.
- **Scope:** trivial — up to 2-line YAML tweak, or a 1-line comment.

### `.github/scripts/publish.py`

- **Tag:** `Keep`
- **Finding:** This is the workshop's materialization machinery. Reads a MANIFEST, resolves source paths (`resolve_source_file`/`resolve_source_dir` handle docs-vs-templates routing), copies matching resources, and trims cross-references to excluded resources from markdown (bullet lines + See-also lines + orphaned "## See Also" headers) and settings.template.json (hook filtering + statusLine removal). The trim logic is the crux of "workshop ships curated subsets without dangling refs."

  One observation, not a finding: the `trim_bullet_line` regex is resource-type-aware (`/skill`, `agent`, `doc`), and the tight regexes are a design choice — loose matching would strip unrelated bullets. The tradeoff is that a reference using non-standard phrasing ("the `codebase-explorer` helper" instead of "`codebase-explorer` agent") wouldn't be detected. Current coverage fits current prose conventions; flag if raiz builds start showing dangling refs.

  Confirmed this script is the *only* artifact-production path. No other "publish" entry points exist in `.github/` or elsewhere I can see.

- **Action:** none.

### `.github/scripts/format-raiz-changelog.sh`

- **Tag:** `Keep`
- **Finding:** Extracts a changelog entry for a given version, trims it to raiz-relevant bullets (keyword-matched against MANIFEST-derived resource names), groups by resource type, and outputs either raw markdown or Telegram HTML. Supports `--from X` to range across multiple versions and auto-picks up a hand-written override at `dist/raiz/changelog/<version>.html` when present — which explains why those HTML overrides under `dist/raiz/changelog/` are `Keep` in the dist/ audit: this is the script that reads them.

  Two observations:
  1. **Keyword-matching for relevance is loose by design.** A changelog bullet mentioning any MANIFEST-covered resource name passes. A bullet like "fix bug in `/brainstorm-idea` flow" correctly passes; a bullet like "refactor brainstorm ecosystem" (no exact name) wouldn't. That's acceptable — changelog prose should reference resources by exact name — but couples the formatter's behavior to authoring discipline. Not a finding.
  2. **Handles the "no raiz-relevant changes" case.** Lines 401–413 emit a minimal Telegram message rather than failing, which is why `2.54.0.html` (one of the pre-logged `Keep` artifacts) exists — it's the override message for a release with no raiz-visible changes. The system is self-consistent.

- **Action:** none.

---

## Cross-cutting notes

- **Publishing is one-way.** Workshop builds an artifact (`publish.py`) → pushes to a sibling repo (`publish-raiz.yml`) → notifies via Telegram. The sibling repo is a published artifact, not a live orchestration target. This is the workshop identity at CI level.
- **Two-step trim + override pattern is sound.** `publish.py` trims cross-references (so resources don't dangle refs to things not in the subset); `format-raiz-changelog.sh` trims changelog entries (so users don't see irrelevant release notes). Both use MANIFEST as source of truth. Override file (`dist/raiz/changelog/<version>.html`) provides an escape hatch when auto-generation misses nuance. Clean separation.
- **No orchestration smells.** Nothing here triggers actions on consumer projects; the workshop just produces and hands off.

---

## Decision-point queue (carry forward)

From this directory, the following items need explicit in-or-out calls for v3:

1. `.github/workflows/publish-raiz.yml` **path filter trigger decision** — add `CHANGELOG.md` and `VERSION` to trigger paths, or document the deliberate omission with a comment.
