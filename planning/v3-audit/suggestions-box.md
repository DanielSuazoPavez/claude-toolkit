# v3 Audit — `suggestions-box/`

Exhaustive file-level audit of the `suggestions-box/` directory. Every file gets a finding.

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`

**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

---

## Summary

`suggestions-box/` is the **upstream feedback channel** — the mechanism that makes the workshop–satellite relationship two-way. Downstream projects (consumer or satellite) drop resources or issues here via `claude-toolkit send`; the workshop triages them into real resources or backlog items. This is *exactly* the pattern the v3 canon calls for ("satellites … feed specialist extensions back upstream via `suggestions-box/`"). Directory shape is correct; contents are tiny.

Two files, both `Keep` with minor polish notes. No structural findings. This directory is one of the clearest examples in the repo of workshop identity done right.

---

## Files

### `suggestions-box/.gitkeep`

- **Tag:** `Keep`
- **Finding:** Empty file keeping the directory tracked when it has no pending items. Standard practice.
- **Action:** none.

### `suggestions-box/CLAUDE.md`

- **Tag:** `Keep`
- **Finding:** Describes the inbound workflow: list → classify (new vs modification) → evaluate with the right `/evaluate-*` skill → scope-check (project-specific vs toolkit-worthy) → recommend. This is canonically workshop-shaped:
  - **Entry point matches canon.** Opening line names the channel correctly ("upstream feedback channel for the workshop") and calls out both consumer and satellite as valid senders.
  - **Scope gate is the right gate.** Step 4 ("Is this project-specific or toolkit-worthy?") is the exact question from `relevant-project-identity.md` §5 ("Does this belong?"). Without it, every satellite nudge would bloat the workshop.
  - **Two flow types handled.** Resources (evaluated via the matching skill) and issues (triaged into BACKLOG). Clean split.
  - **`claude-toolkit send` is real** — verified it's wired in `bin/claude-toolkit` (commands `send` at line 755, `cmd_send` at line 72). Not a dangling reference.

  Two small polish items (not blockers, queueable for decision point):
  1. **Resource file naming.** Line 22 says files arrive as `<name>-<TYPE>.md` (e.g., `draft-pr-SKILL.md`). Check whether `cmd_send` actually produces that shape — name drift between doc and code is exactly the kind of thing that breaks triage skills silently. One-line verification.
  2. **No "Satellites feed back extensions" example.** Doc correctly says "consumer or satellite" can send, but the examples (draft-pr-SKILL.md, `timestamp_issue.txt`) both feel consumer-shaped. An example of a satellite contributing a specialist extension (e.g., claude-sessions contributing a lessons-management tool) would make the satellite pathway concrete. Not urgent.

- **Action:** at decision point: (1) verify `cmd_send` output naming matches the doc, (2) consider adding a satellite-feed-back example.
- **Scope:** both trivial — doc tweaks only.

---

## Cross-cutting notes

- **This directory is the v3 canon's two-way arrow made concrete.** The workshop→consumer direction happens via `claude-toolkit sync` (pull). The consumer/satellite→workshop direction happens via `claude-toolkit send` + `suggestions-box/` triage. Together they form the whole relationship.
- **No orchestration smells whatsoever.** The workshop doesn't reach out to pull suggestions; senders push. The workshop reviews when asked ("check suggestions"), then accepts/rejects. Inert until invited.
- **Separate doc + code coverage.** The inbound doc lives here; the outbound CLI command lives in `bin/claude-toolkit` and will be audited in the top-level slot. Scope matches what's under `suggestions-box/` — small.

---

## Decision-point queue (carry forward)

From this directory, the following items need explicit in-or-out calls for v3:

1. `suggestions-box/CLAUDE.md` **verify `cmd_send` output naming** matches the `<name>-<TYPE>.md` convention documented on line 22.
2. `suggestions-box/CLAUDE.md` **add a satellite-feed-back example** (optional polish) to make the satellite pathway concrete, not just implicit.
