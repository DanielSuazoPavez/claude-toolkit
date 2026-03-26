# Context Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Creating or evaluating memories or docs
- Understanding the docs/memories boundary
- User asks about context file conventions

Defines the two context systems (docs and memories), their categories, naming conventions, and the auto-memory integration.

**See also:** `/create-memory` skill, `/evaluate-memory` for quality audits, `relevant-project-identity` for resource roles

---

## 2. Docs vs Memories

The toolkit uses two directories for persistent context:

| Directory | Purpose | Contains |
|-----------|---------|----------|
| `.claude/docs/` | Prescriptive rules, reference documentation, toolkit config | Stable, rarely-changing files that shape behavior |
| `.claude/memories/` | Organic context, user/project identity, preferences, ideas | Evolving, contextual files that inform decisions |

**Decision guide:** If it tells Claude *how to behave* or *what the rules are* → doc. If it tells Claude *who you are* or *what's happening* → memory.

### Examples

| File | Where | Why |
|------|-------|-----|
| Code style conventions | `.claude/docs/` | Prescriptive rules applied to all code |
| Communication preferences | `.claude/docs/` | Prescriptive behavior shaping |
| Project identity | `.claude/memories/` | Organic context about what the project is |
| Professional profile | `.claude/memories/` | User context, evolves over time |
| Branch WIP notes | `.claude/memories/` | Temporary, contextual |

---

## 3. Categories

### Docs categories

| Category | Lifetime | Load Pattern | Format |
|----------|----------|-------------|--------|
| `essential-` | Permanent | Auto-loaded at session start | `essential-{context}-{name}` |
| `relevant-` | Long-term | On-demand | `relevant-{context}-{name}` |

All docs are indexed in `docs/indexes/DOCS.md`.

### Memory categories

| Category | Lifetime | Load Pattern | Format |
|----------|----------|-------------|--------|
| `relevant-` | Long-term | On-demand | `relevant-{context}-{name}` |
| `branch-` | Temporary | On-demand (branch work) | `branch-{YYYYMMDD}-{branch}-{context}` |
| `idea-` | Temporary | User permission required | `idea-{YYYYMMDD}-{context}-{idea}` |
| `personal-` | Private | User on-demand ONLY | `personal-{context}-{name}` |
| `experimental-` | Testing | User on-demand ONLY | `experimental-{context}-{name}` |
Indexed memories (`relevant-`) go in `docs/indexes/MEMORIES.md`. Ephemeral categories (`idea-`, `personal-`, `experimental-`) are excluded from indexing and validation.

### Auto-memory (`auto/` subdirectory)

Claude Code's built-in auto-memory lives in `.claude/memories/auto/` via symlink. This is Claude Code's territory — no naming conventions, no validation, no indexing. The directory is gitignored.

---

## 4. Quick Reference Section Guidelines

All docs and memories MUST include a "Quick Reference" section as section 1.

### For reference docs (rules, conventions)

```markdown
## 1. Quick Reference

**MANDATORY:** Read at session start - affects all [scope].

Brief description.

**See also:** [Related resources]
```

### For on-demand docs/memories

```markdown
## 1. Quick Reference

**ONLY READ WHEN:**
- [Specific triggering context]
- User explicitly asks about [topic]

Brief description.
```

### For special cases

- **`idea-` memories**: Always add `**NOTE**: ONLY READ WITH USER EXPLICIT PERMISSION`
- **`branch-` memories**: Include status and key results in Quick Reference
- **`essential-` docs**: Add `**MANDATORY:**` prefix to indicate session-start loading

---

## 5. Naming Best Practices

- Keep names concise but descriptive
- Use underscores (`_`) to separate words: `relevant-opensearch-query_patterns.md`
- Use `YYYYMMDD` date format for branch and idea memories
- Follow the format patterns defined in section 3 for each category

---

## 6. Auto-Memory Symlink

To unify Claude Code's auto-memory with the toolkit's memory directory:

```bash
mkdir -p .claude/memories/auto
rm -rf ~/.claude/projects/<project-hash>/memory/
ln -s /path/to/project/.claude/memories/auto ~/.claude/projects/<project-hash>/memory
```

The `auto/` directory is gitignored via `.claude/memories/.gitignore`.
