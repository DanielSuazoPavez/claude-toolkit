---
name: create-docs
description: Create a new doc file following project conventions. Use when user asks to create a doc for rules, conventions, or reference documentation. Keywords: create doc, new doc, write doc, add convention, add reference.
allowed-tools: Read, Write, Glob
---

# Create Doc Skill

## When to Use

Activate when user says:
- "create a doc about..."
- "write a doc for..."
- "add a convention for..."
- "save this as a doc..."

## Decision: Doc or Something Else?

```
Is this prescriptive rules, conventions, or reference documentation?
├─ Yes → `.claude/docs/` (this skill)
│
└─ No → Is this organic context (who you are, what's happening, preferences)?
    ├─ Yes → Memory in `.claude/memories/` (just create the file directly, no skill needed)
    └─ No → Consider if persistence is needed at all
```

For procedures (step-by-step workflows), use `/create-skill` instead.

**See also:** `/evaluate-docs` (quality gate), `/list-docs` (check for duplicates), `/create-skill` (for procedures), `/create-hook` (for enforcement), `/create-agent` (for behavioral specialists), `relevant-conventions-naming`

## Instructions

1. **Check for duplicates**: List `.claude/docs/` to see existing docs
2. **Choose a name**: Follow `{category}-{context}-{name}` format
   - `essential-` prefix: auto-loaded at session start (use sparingly)
   - `relevant-` prefix: loaded on-demand when needed
3. **Include Quick Reference** as section 1
4. **Write content** based on what user wants to capture

## File Format

```markdown
# Title

## 1. Quick Reference

**ONLY READ WHEN:**
- [Specific triggering context]
- User explicitly asks about [topic]

Brief description.

**See also:** [Related resources]

---

## 2. Main Content

[Detailed content here]
```

For essential docs (auto-loaded), use `**MANDATORY:**` instead of `**ONLY READ WHEN:**`:

```markdown
## 1. Quick Reference

**MANDATORY:** Read at session start - affects all [scope].

Brief description.
```

## Notes

- Use `{category}-{context}-{name}` format: `relevant-workflow-branch_development.md`
- Categories: `essential-` (auto-loaded) or `relevant-` (on-demand)
- Context describes the topic area: `toolkit`, `conventions`, `workflow`, `philosophy`, etc.

## Reference Examples

For format and structure examples, see existing docs:
- `.claude/docs/relevant-toolkit-context.md` - naming conventions, docs/memories boundary
- `.claude/docs/essential-conventions-code_style.md` - example of well-structured essential doc

## When to Merge vs Split Docs

**Merge when:**
- Topics are always referenced together
- Combined content stays under 200 lines
- Single mental model covers both topics

**Split when:**
- Content exceeds 300 lines
- Topics have different update frequencies
- Different triggering contexts (Quick Reference would have unrelated bullets)

## Pre-Save Validation Checklist

Before writing the doc file, verify:

- [ ] **Not a memory?** Organic context → `.claude/memories/`, not docs
- [ ] **Quick Reference exists?** Has appropriate pattern for doc type
- [ ] **Correct naming?** Follows `{category}-{context}-{name}` format
- [ ] **No duplicate?** List `.claude/docs/` to check
- [ ] **Under 300 lines?** Split if larger

### Quality Gate

Run `/evaluate-docs` on the result:
- **Target: 85%**
- If below target, iterate on the weakest dimensions

## Common Mistakes: Worked Example

**Bad request:** "Create a doc for our API endpoints"

**Problem:** Too vague — is this conventions for designing APIs, or a reference list of endpoints?

**Good correction:** "Create a doc for our API design conventions, including naming patterns, error response format, and pagination approach"

**Result:** `relevant-conventions-api_design.md` with:
- Quick Reference: "ONLY READ WHEN: Designing new API endpoints, reviewing API PRs"
- Content: Naming conventions, error format, pagination pattern

---

**Bad request:** "Create a doc about what I'm working on this sprint"

**Problem:** Ephemeral context — this is a memory, not a doc.

**Good correction:** Use a memory in `.claude/memories/` for organic context, or `/write-handoff` for session continuation.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Organic Context as Doc** | User preferences, branch WIP in docs | Use `.claude/memories/` instead |
| **Duplicate Doc** | Topic already has a doc | Update existing doc instead |
| **No Quick Reference** | Full file must be loaded to assess relevance | Always add Quick Reference section |
| **Giant Doc** | 500+ lines, mixes concerns | Split into focused docs |
| **Vague Filename** | `notes.md` — impossible to identify | Use `{category}-{context}-{name}` format |
| **Wrong Category** | Essential doc that's rarely needed | Use `relevant-` for on-demand content |
