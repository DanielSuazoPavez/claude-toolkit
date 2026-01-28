---
name: evaluate-memory
description: Evaluate memory file quality against conventions. Use when reviewing, auditing, or improving memory files.
---

# Memory Judge

Evaluate memory quality against memory-specific conventions and best practices.

## When to Use

- Reviewing a memory file before committing
- Auditing existing memories for quality
- After using `/write-memory` to validate output

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
| **Examples** | Code style, architecture, branch context | `/commit`, `/review-pr`, `/write-skill` |

## Evaluation Dimensions (100 points)

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
| 18-20 | Focused, actionable, no redundancy with other memories |
| 13-17 | Mostly focused, minor overlap |
| 7-12 | Too broad or duplicates existing content |
| 0-6 | Kitchen sink or pure duplication |

**Check:**
- Does it overlap with CLAUDE.md or other memories?
- Is content actionable or just informational?
- Would splitting improve clarity?

### D4: Load Timing Appropriateness (15 pts)

| Score | Criteria |
|-------|----------|
| 13-15 | Load timing matches content criticality |
| 9-12 | Could be more selective about when to load |
| 4-8 | Loads at wrong time (too early/late) |
| 0-3 | Always loads but rarely needed, or never loads but critical |

**Guidelines:**
- Session start: Only `essential-` that affect every interaction
- On-demand: `relevant-`, reference docs, detailed guides
- User on-demand ONLY: `experimental-` (user must explicitly request)
- Never auto-load: `idea-` (requires permission)

### D5: Structure & Formatting (20 pts)

| Score | Criteria |
|-------|----------|
| 18-20 | Clear sections, tables for comparisons, scannable |
| 13-17 | Readable but could be more scannable |
| 7-12 | Wall of text or poor organization |
| 0-6 | Unreadable or inconsistent formatting |

## Grading Scale

| Grade | Score | Description |
|-------|-------|-------------|
| A | 90+ | Exemplary - use as template |
| B | 75-89 | Good - minor improvements needed |
| C | 60-74 | Functional but notable gaps |
| D | 40-59 | Significant issues |
| F | <40 | Needs rewrite |

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

| Pattern | Problem | Score Impact |
|---------|---------|--------------|
| **Missing Quick Reference** | No load guidance | D2: -20 |
| **Wrong category** | essential for temporary info | D1: -15 |
| **No date on branch/idea** | Can't track freshness | D1: -10 |
| **Overlaps CLAUDE.md** | Duplication, drift risk | D3: -10 |
| **Always loads, rarely needed** | Context bloat | D4: -10 |
| **Wall of text** | Unscannable | D5: -10 |

## JSON Output Format

```json
{
  "file_hash": "<first 8 chars of MD5>",
  "date": "YYYY-MM-DD",
  "grade": "A/B/C/D/F",
  "score": <total>,
  "max": 100,
  "percentage": <score/max * 100>,
  "dimensions": {
    "D1": <score>, "D2": <score>, "D3": <score>, "D4": <score>, "D5": <score>
  },
  "top_improvements": ["...", "...", "..."]
}
```

Compute file_hash with: `md5sum <memory-file> | cut -c1-8`

## Invocation

**Launch a subagent** to run evaluations - avoids self-evaluation bias when reviewing your own work.

```
Task tool with:
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    Evaluate the memory at <path> using the evaluate-memory rubric.
    Read .claude/skills/evaluate-memory/SKILL.md for the full rubric.
    Follow the Evaluation Protocol and output JSON matching the JSON Output Format.
```

Using a separate agent ensures objective assessment without influence from the current conversation context.

## Evaluation Protocol

1. Check filename against category patterns
2. Verify Quick Reference is section 1 with correct pattern
3. Assess content scope and overlap
4. Evaluate load timing vs content criticality
5. Review structure and formatting
6. Score each dimension with evidence
7. Generate report with JSON output including file_hash and top 3 improvements
8. Update `.claude/evaluations.json` using jq:
   ```bash
   jq --argjson result '<JSON>' '.memories.resources["<name>"] = $result' .claude/evaluations.json > tmp && mv tmp .claude/evaluations.json
   ```

## Example Evaluation

**Memory:** `essential-workflow-branch_development.md`

| Dimension | Score | Evidence |
|-----------|-------|----------|
| D1: Category & Naming | 19/20 | Correct essential- prefix, clear context (workflow), descriptive name |
| D2: Quick Reference | 23/25 | Present as section 1, "Read at" pattern, clear timing |
| D3: Content Scope | 17/20 | Focused on branch workflow, links to related skill |
| D4: Load Timing | 14/15 | Session start appropriate for workflow guidance |
| D5: Structure | 18/20 | Good tables, clear sections, scannable |

**Total: 91/100 - Grade A**
