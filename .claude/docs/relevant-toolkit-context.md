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
| Project identity | `.claude/docs/` | Prescriptive identity and scope boundaries |
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

### Memories

Memories are plain `.md` files in `.claude/memories/` — no category prefixes, no indexing, no validation. Just descriptive names with underscores: `professional_profile.md`, `user.md`.

For branch-specific WIP context, use a date prefix: `YYYYMMDD-{branch}-{context}.md` (e.g., `20260320-feat_auth-schema_notes.md`).

Ideas and explorations go in `output/claude-toolkit/drafts/`, not memories.

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

- **`essential-` docs**: Add `**MANDATORY:**` prefix to indicate session-start loading

---

## 5. Naming Best Practices

- Keep names concise but descriptive
- Docs: follow `{category}-{context}-{name}` format with `essential-` or `relevant-` prefix
- Memories: plain `descriptive_name.md` with underscores (no prefixes)
- Use `YYYYMMDD` date prefix for branch WIP memories

---

## 6. Auto-Memory Symlink

To unify Claude Code's auto-memory with the toolkit's memory directory:

```bash
mkdir -p .claude/memories/auto
rm -rf ~/.claude/projects/<project-hash>/memory/
ln -s /path/to/project/.claude/memories/auto ~/.claude/projects/<project-hash>/memory
```

The `auto/` directory is gitignored via `.claude/memories/.gitignore`.
