---
name: evaluate-docs
description: Evaluate doc file quality against conventions. Use when reviewing, auditing, or improving docs in .claude/docs/.
argument-hint: "[doc-name-or-path]"
compatibility: jq
allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)
---

# Doc Judge

Evaluate doc quality against doc-specific conventions and best practices.

## When to Use

- Reviewing a doc file before committing
- Auditing existing docs for quality
- After using `/create-docs` to validate output

## Core Philosophy

**What is a Doc?** Prescriptive rules, conventions, or reference documentation that shapes Claude's behavior.

**The Formula:** `Good Doc = Right Category + Quick Reference + Appropriate Scope`

Docs must load at the right time, contain actionable guidance, and avoid bloat.

**Reference:** See `relevant-toolkit-context.md` (in `.claude/docs/`) for authoritative naming/category conventions and the docs/memories boundary.

## How Doc Loading Works

Docs don't load themselves. Loading is driven by:

1. **Session start hook** — `essential-*` docs are auto-loaded at session start
2. **User request** — User explicitly asks to load/read a doc, or `/list-docs` discovers it
3. **Hook injection** — PreToolUse/PostToolUse hooks can surface `relevant-*` docs contextually

**Note:** There's no reliable spontaneous loading. Claude won't read docs mid-session unprompted. If a doc needs to be loaded, it should either be `essential-*` (auto-loaded) or discoverable via `/list-docs`.

**Implication for D4 scoring:** When evaluating load timing, consider:
- Is this doc `essential-*` and auto-loaded? Should it be?
- If `relevant-*`, is it discoverable when needed?
- Would auto-loading this waste context on most sessions?

## Doc vs Skill Distinction

| Aspect | Doc | Skill |
|--------|-----|-------|
| **Purpose** | Persistent rules/conventions/reference | Triggered workflows/procedures |
| **Loading** | Session start (`essential-*`) or on-demand (`relevant-*`) | Invoked via `/skill-name` |
| **Content** | Guidelines, patterns, conventions | Step-by-step instructions |
| **Lifecycle** | Evolves with project | Stable once written |
| **Examples** | Code style, naming conventions, project identity | `/commit`, `/review-pr`, `/create-skill` |

## Doc vs Memory Distinction

| Aspect | Doc (`.claude/docs/`) | Memory (`.claude/memories/`) |
|--------|----------------------|------------------------------|
| **Content** | Prescriptive rules, conventions | Organic context, preferences, ideas |
| **Naming** | `{category}-{context}-{name}` | Plain `descriptive_name.md` |
| **Validation** | Evaluated, indexed | None — just files |
| **Lifecycle** | Stable, rarely changes | Evolves freely |

## Evaluation Dimensions (115 points)

### D1: Naming & Placement (20 pts) - Most Critical

| Score | Criteria |
|-------|----------|
| 18-20 | Correct `{category}-{context}-{name}` format, in `.claude/docs/` |
| 13-17 | Good name, minor clarity issue |
| 7-12 | Vague name or questionable placement |
| 0-6 | Generic name or wrong directory (should be a memory or doesn't belong) |

**Check:**
- Is this prescriptive rules/conventions (doc) or organic context (should be in `.claude/memories/`)?
- Follows `{category}-{context}-{name}` format?
- Uses correct category prefix (`essential-` or `relevant-`)?
- Context segment is descriptive?

### D2: Quick Reference Section (25 pts) - Required

| Score | Criteria |
|-------|----------|
| 22-25 | Present as section 1, correct pattern for doc type, clear load timing |
| 16-21 | Present but wrong pattern or unclear timing |
| 8-15 | Exists but buried or incomplete |
| 0-7 | Missing or doesn't guide when to read |

**Required patterns by type:**
- Essential docs: `**MANDATORY:** Read at session start - affects all [scope]`
- Relevant docs: `**ONLY READ WHEN:**` + bullet list of triggering contexts
- Both: `**See also:**` cross-references

### D3: Content Scope (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Single concern, all content actionable, no duplication with other synced resources |
| 13-17 | Single concern but some content is informational-only or ≤2 sentences overlap |
| 7-12 | Covers 2+ unrelated concerns, or ≥1 paragraph duplicated from another synced resource |
| 0-6 | No clear focus, or bulk content copy-pasted from other sources |

**Scope of duplication checks:** Only flag duplication between **synced resources** — other docs, skills, and agents. Do NOT flag overlap with toolkit-internal files (indexes, project CLAUDE.md) since docs are the portable artifacts that get synced to other projects. A doc may legitimately contain the same information as an index file — the doc is the source of truth.

**Check:**
- Does it overlap with other docs, skills, or agents? (grep key phrases)
- Is each section actionable — does it change behavior, or just inform?
- Would splitting by concern improve clarity?

### D4: Relevance & Freshness (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Content is current, actionable, and clearly useful in the contexts described by Quick Reference |
| 9-12 | Content is mostly current but some sections feel stale or rarely triggered |
| 4-8 | Significant stale content or unclear when this doc would be useful |
| 0-3 | Outdated or no clear use case — should be deleted or merged |

**Guidelines:**
- Essential docs are auto-loaded — they must justify the context cost every session
- Relevant docs are on-demand — Quick Reference should accurately describe when to load
- Review whether the doc's conventions still match current project practices

### D5: Structure & Formatting (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Numbered sections, tables for comparisons, no prose paragraph >4 lines without a list/table/code block break |
| 13-17 | Sections exist but ≥1 prose block >4 lines that should be a table/list, or inconsistent heading levels |
| 7-12 | Minimal structure — mostly prose paragraphs, few or no tables/lists |
| 0-6 | No sections, wall of text, or inconsistent formatting throughout |

### D6: Integration Quality (15 pts)
Does it work well within the resource ecosystem?

| Score | Criteria |
|-------|----------|
| 13-15 | Seamless integration — correct cross-references, no duplication, clean connections |
| 10-12 | References exist and are correct, minor duplication or missed connections |
| 6-9 | Some broken cross-references, restates content from other docs |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | No references, duplicates freely, contradicts connected docs |

**Check:**
- **Reference accuracy** — cross-references point to docs, skills, and agents that exist
- **Duplication avoidance** — doesn't restate content from other synced resources (docs, skills, agents). Overlap with toolkit-internal files (indexes, CLAUDE.md) is acceptable
- **Cross-linking** — connects to related docs via See Also or inline references
- **Ecosystem awareness** — knows what other docs cover similar topics
- **Terminology consistency** — uses same terms as connected docs

## Edge Cases

| Situation | Guidance |
|-----------|----------|
| **Should be a memory** | Content is organic context/preferences → move to `.claude/memories/` |
| **Should be a skill** | Content is step-by-step procedures → extract to a skill |

## When to Split vs Combine

```
Is the doc > 300 lines?
├─ Yes → Consider splitting by subtopic
└─ No
   ├─ Does it cover 2+ unrelated concerns?
   │  ├─ Yes → Split into focused docs
   │  └─ No → Keep combined
   └─ Is there significant overlap with another doc?
      ├─ Yes → Merge or cross-reference
      └─ No → Keep as-is
```

## Anti-Patterns

| Pattern | Problem | Fix | Score Impact |
|---------|---------|-----|--------------|
| **Missing Quick Reference** | No load guidance | Add as section 1 with appropriate pattern | D2: -20 |
| **Should be a memory** | Organic context in docs | Move to `.claude/memories/` | D1: -15 |
| **Vague filename** | Missing category or context | Use `{category}-{context}-{name}` format | D1: -10 |
| **Overlaps other resources** | Duplication, drift risk | Delete duplicated content, add cross-reference instead | D3: -10 |
| **Wall of text** | Unscannable | Break prose into tables, lists, or code blocks | D5: -10 |
| **Doc that should be a skill** | Procedures masquerading as reference | Extract step-by-step content into a skill | D3: -10 |
| **Essential doc rarely needed** | Wastes context every session | Demote to `relevant-` | D4: -5 |

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "score": <total>,
  "max": 115,
  "percentage": <score/max * 100>,
  "dimensions": {
    "D1": <score>, "D2": <score>, "D3": <score>, "D4": <score>, "D5": <score>, "D6": <score>
  },
  "top_improvements": ["...", "...", "..."]
}
```

Compute file_hash with: `md5sum <doc-file> | cut -c1-8`

## Invocation

**Launch a subagent** for fresh, unbiased evaluation.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the doc at <path> using the evaluate-docs rubric.
    Read .claude/skills/evaluate-docs/SKILL.md for the full rubric.

    Perform FRESH scoring. Do NOT read evaluations.json or prior scores.

    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from prior evaluations.

## Evaluation Protocol

1. Check filename against `{category}-{context}-{name}` pattern
2. Verify Quick Reference is section 1 with correct pattern
3. Assess content scope and overlap
4. Evaluate load timing vs content criticality
5. Review structure and formatting
6. Score each dimension with evidence
7. Generate report with JSON output including file_hash and top 3 improvements
8. Update `docs/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.docs.resources["<name>"] = $result' docs/indexes/evaluations.json > tmp && mv tmp docs/indexes/evaluations.json
   ```

## Example Evaluation

**Doc:** `relevant-workflow-branch_development.md`

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Naming & Placement | 19/20 | Correct `relevant-` prefix, clear context (workflow), in `.claude/docs/` |
| D2: Quick Reference | 24/25 | Section 1, proper "ONLY READ WHEN" bullets, See also cross-refs |
| D3: Content Scope | 19/20 | Single concern (branch workflow), cross-references instead of duplicating |
| D4: Relevance & Freshness | 14/15 | On-demand appropriate — not needed every session |
| D5: Structure | 19/20 | Numbered sections, tables, code blocks, no prose walls |
| D6: Integration Quality | 13/15 | References related docs, no duplication, consistent terminology |

**Total: 108/115 (93.9%)**

## See Also

- `/create-docs` — Create docs that this skill evaluates
- `/evaluate-skill` — Sister evaluator for skills (shared calibration philosophy)
- `/evaluate-agent` — Sister evaluator for agents
- `/evaluate-hook` — Sister evaluator for hooks
- `relevant-toolkit-context` — Authoritative naming/category conventions (source of truth for D1/D2, in `.claude/docs/`)
