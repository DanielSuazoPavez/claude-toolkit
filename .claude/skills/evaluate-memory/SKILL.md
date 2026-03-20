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

**Reference:** See `essential-conventions-memory.md` for authoritative naming/category conventions.

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

### D1: Category & Naming (20 pts) - Most Critical

| Score | Criteria |
|-------|----------|
| 18-20 | Correct category, follows naming format exactly |
| 13-17 | Right category, minor naming deviation |
| 7-12 | Questionable category choice |
| 0-6 | Wrong category or broken naming |

**Check against categories:**
- `essential-{context}-{name}` - Permanent, core info (auto-loaded at session start)
- `relevant-{context}-{name}` - Long-term, may evolve (on-demand)
- `branch-{YYYYMMDD}-{branch}-{context}` - Temporary, branch-specific (on-demand)
- `idea-{YYYYMMDD}-{context}-{idea}` - Future work, needs permission (on-demand)
- `personal-{context}-{name}` - Private preferences, no eval, no sharing (user on-demand ONLY)
- `experimental-{context}-{name}` - Testing new approaches (user on-demand ONLY)

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
- Ideas: Must include "NOTE: ONLY READ WITH USER EXPLICIT PERMISSION"
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

### D4: Load Timing Appropriateness (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Category prefix matches content criticality — essential content auto-loads, reference content is on-demand, temporary content has dates |
| 9-12 | Category prefix is correct but content criticality is borderline — e.g., relevant- content that arguably should be essential, or essential- content only needed in specific workflows |
| 4-8 | Mismatch — e.g., essential- memory with content only relevant to one workflow, or relevant- memory with session-critical conventions |
| 0-3 | Severe mismatch — always loads but rarely needed, or never loads but critical |

**Guidelines:**
- Session start: Only `essential-` that affect every interaction
- On-demand: `relevant-`, reference docs, detailed guides
- User on-demand ONLY: `personal-`, `experimental-` (user must explicitly request)
- Never auto-load: `idea-` (requires permission)

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
| **Legacy naming** | Suggest update to current conventions, don't block |
| **Spans categories** | Choose dominant purpose; if truly mixed, split |
| **Migrating branch → relevant** | Update prefix, remove date, keep content |

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
| **Missing Quick Reference** | No load guidance | Add as section 1 with correct pattern for memory type | D2: -20 |
| **Wrong category** | essential for temporary info | Match prefix to content lifetime (essential=permanent, branch=temporary) | D1: -15 |
| **No date on branch/idea** | Can't track freshness | Add YYYYMMDD after prefix | D1: -10 |
| **Overlaps other synced resources** | Duplication, drift risk | Delete duplicated content, add cross-reference instead | D3: -10 |
| **Always loads, rarely needed** | Context bloat | Downgrade from essential- to relevant- | D4: -10 |
| **Wall of text** | Unscannable | Break prose into tables, lists, or code blocks | D5: -10 |
| **Memory that should be a skill** | Procedures masquerading as context | Extract step-by-step content into a skill, keep only guidelines in memory | D3: -10 |
| **Stale branch memory** | Abandoned context after merge | Delete after branch merges, or promote to relevant- if still useful | D1: -5 |

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
8. Update `.claude/indexes/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.memories.resources["<name>"] = $result' .claude/indexes/evaluations.json > tmp && mv tmp .claude/indexes/evaluations.json
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
- `essential-conventions-memory` — Authoritative naming/category conventions (source of truth for D1/D2)
