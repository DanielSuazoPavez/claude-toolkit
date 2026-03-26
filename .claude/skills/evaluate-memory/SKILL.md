---
name: evaluate-memory
description: Evaluate memory file quality against conventions. Use when reviewing, auditing, or improving memory files.
argument-hint: "[memory-name-or-path]"
allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)
---

# Memory Judge

Evaluate memory quality against memory-specific conventions and best practices.

## When to Use

- Reviewing a memory file before committing
- Auditing existing memories for quality
- After using `/create-memory` to validate output

## Core Philosophy

**What is a Memory?** Persistent context that survives session boundaries.

**The Formula:** `Good Memory = Right Category + Quick Reference + Appropriate Scope`

Memories must load at the right time, contain actionable guidance, and avoid bloat.

**Reference:** See `relevant-toolkit-context.md` (in `.claude/docs/`) for authoritative naming/category conventions and the docs/memories boundary.

## How Memory Loading Works

Memories don't load themselves. Loading is driven by:

1. **Session start hook** - A `SessionStart` hook script reads `essential-*` memories and outputs them as context
2. **User request** - User explicitly asks to load/read a memory (e.g., "read the branch memory")

**Note:** There's no reliable "on-demand" loading. Claude won't spontaneously read memories mid-session. If a memory needs to be loaded, it should either be in `essential-*` (auto-loaded) or the user must request it.

**Implication for D4 scoring:** When evaluating load timing, consider:
- Is this memory included in the session-start hook output? Should it be?
- If not auto-loaded, is the user expected to request it explicitly?
- Would auto-loading this waste context on most sessions?

## Memory vs Skill Distinction

| Aspect | Memory | Skill |
|--------|--------|-------|
| **Purpose** | Persistent context/conventions | Triggered workflows/procedures |
| **Loading** | Session start or user requests | Invoked via `/skill-name` |
| **Content** | Guidelines, patterns, project state | Step-by-step instructions |
| **Lifecycle** | Evolves with project | Stable once written |
| **Examples** | Code style, architecture, branch context | `/commit`, `/review-pr`, `/create-skill` |

## Evaluation Dimensions (115 points)

### D1: Naming & Placement (20 pts) - Most Critical

| Score | Criteria |
|-------|----------|
| 18-20 | Descriptive snake_case name, in correct directory (memories vs docs) |
| 13-17 | Good name, minor clarity issue |
| 7-12 | Vague name or questionable placement |
| 0-6 | Generic name (`notes.md`) or wrong directory (should be a doc) |

**Check:**
- Is this organic context (memory) or prescriptive rules (should be in `.claude/docs/`)?
- Is the filename descriptive enough to identify content without reading?
- Uses `snake_case` with underscores?
- Branch WIP has date prefix (`YYYYMMDD-{branch}-{context}`)?

### D2: Quick Reference Section (25 pts) - Required

| Score | Criteria |
|-------|----------|
| 22-25 | Present as section 1, correct pattern for memory type, clear load timing |
| 16-21 | Present but wrong pattern or unclear timing |
| 8-15 | Exists but buried or incomplete |
| 0-7 | Missing or doesn't guide when to read |

**Required patterns by type:**
- Reference docs: "ONLY READ WHEN" + bullet list
- Orientation: "Purpose/Read at/Not a reference doc"
- Convention: "ONLY READ WHEN" + brief description
- Branch: Must include status and key results

### D3: Content Scope (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Single concern, all content actionable, no duplication with other synced resources |
| 13-17 | Single concern but some content is informational-only (context without guidance) or ≤2 sentences overlap with another synced resource |
| 7-12 | Covers 2+ unrelated concerns, or ≥1 paragraph duplicated from another synced resource |
| 0-6 | No clear focus, or bulk content copy-pasted from other sources |

**Scope of duplication checks:** Only flag duplication between **synced resources** — other memories, skills, and agents. Do NOT flag overlap with toolkit-internal files (indexes, project CLAUDE.md, HOOKS.md) since memories are the portable artifacts that get synced to other projects. A memory may legitimately contain the same information as an index file — the memory is the source of truth.

**Check:**
- Does it overlap with other memories, skills, or agents? (grep key phrases)
- Is each section actionable — does it change behavior, or just inform?
- Would splitting by concern improve clarity?

### D4: Relevance & Freshness (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Content is current, actionable, and clearly useful in the contexts described by Quick Reference |
| 9-12 | Content is mostly current but some sections feel stale or rarely triggered |
| 4-8 | Significant stale content or unclear when this memory would be useful |
| 0-3 | Outdated or no clear use case — should be deleted or merged |

**Guidelines:**
- Memories are loaded on-demand, never at session start
- Quick Reference should accurately describe when to load this memory
- Branch WIP memories should be cleaned up after merge

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
| 6-9 | Some broken cross-references, restates content from other memories |
| 3-5 | Island — mostly ignores the ecosystem |
| 0-2 | No references, duplicates freely, contradicts connected memories |

**Check:**
- **Reference accuracy** — cross-references point to memories, skills, and agents that exist
- **Duplication avoidance** — doesn't restate content from other synced resources (memories, skills, agents). Overlap with toolkit-internal files (indexes, CLAUDE.md) is acceptable
- **Cross-linking** — connects to related memories via See Also or inline references
- **Ecosystem awareness** — knows what other memories cover similar topics
- **Terminology consistency** — uses same terms as connected memories

## Edge Cases

| Situation | Guidance |
|-----------|----------|
| **Should be a doc** | Content is prescriptive rules → move to `.claude/docs/` |
| **Branch WIP after merge** | Clean up or rename to remove date prefix |

## When to Split vs Combine

```
Is the memory > 300 lines?
├─ Yes → Consider splitting by subtopic
└─ No
   ├─ Does it cover 2+ unrelated concerns?
   │  ├─ Yes → Split into focused memories
   │  └─ No → Keep combined
   └─ Is there significant overlap with another memory?
      ├─ Yes → Merge or cross-reference
      └─ No → Keep as-is
```

## Anti-Patterns

| Pattern | Problem | Fix | Score Impact |
|---------|---------|-----|--------------|
| **Missing Quick Reference** | No load guidance | Add as section 1 with "ONLY READ WHEN" bullets | D2: -20 |
| **Should be a doc** | Prescriptive rules in memories | Move to `.claude/docs/` | D1: -15 |
| **Vague filename** | `notes.md` — can't identify content | Use descriptive snake_case name | D1: -10 |
| **Overlaps other resources** | Duplication, drift risk | Delete duplicated content, add cross-reference instead | D3: -10 |
| **Wall of text** | Unscannable | Break prose into tables, lists, or code blocks | D5: -10 |
| **Memory that should be a skill** | Procedures masquerading as context | Extract step-by-step content into a skill | D3: -10 |
| **Stale branch WIP** | Abandoned context after merge | Delete or rename to remove date prefix | D4: -5 |

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

Compute file_hash with: `md5sum <memory-file> | cut -c1-8`

## Invocation

**Launch a subagent** for fresh, unbiased evaluation.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the memory at <path> using the evaluate-memory rubric.
    Read .claude/skills/evaluate-memory/SKILL.md for the full rubric.

    Perform FRESH scoring. Do NOT read evaluations.json or prior scores.

    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from prior evaluations.

## Evaluation Protocol

1. Check filename against category patterns
2. Verify Quick Reference is section 1 with correct pattern
3. Assess content scope and overlap
4. Evaluate load timing vs content criticality
5. Review structure and formatting
6. Score each dimension with evidence
7. Generate report with JSON output including file_hash and top 3 improvements
8. Update `docs/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.memories.resources["<name>"] = $result' docs/indexes/evaluations.json > tmp && mv tmp docs/indexes/evaluations.json
   ```

## Example Evaluation

**Memory:** `relevant-workflow-branch_development.md`

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Category & Naming | 19/20 | Correct relevant- prefix for on-demand content, clear context (workflow) |
| D2: Quick Reference | 24/25 | Section 1, proper "ONLY READ WHEN" bullets, See also cross-refs |
| D3: Content Scope | 19/20 | Single concern (branch workflow), cross-references instead of duplicating |
| D4: Load Timing | 14/15 | On-demand appropriate — not needed every session |
| D5: Structure | 19/20 | Numbered sections, tables, code blocks, no prose walls |
| D6: Integration Quality | 13/15 | References related memories, no duplication, consistent terminology |

**Total: 108/115 (93.9%)**

## See Also

- `/create-memory` — Create memories that this skill evaluates
- `/evaluate-skill` — Sister evaluator for skills (shared calibration philosophy)
- `/evaluate-agent` — Sister evaluator for agents
- `/evaluate-hook` — Sister evaluator for hooks
- `relevant-toolkit-context` — Authoritative naming/category conventions (source of truth for D1/D2, in `.claude/docs/`)
