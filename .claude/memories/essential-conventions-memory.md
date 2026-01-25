# Memory Naming Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Creating a new memory file
- Unsure about memory naming or categorization
- User explicitly asks about memory organization

Guidelines for naming and structuring memory files, including categories, formats, and Quick Reference patterns.

---

## 2. Memory Categories

### `essential` (Permanent)
- **Principle:** For core, stable project information that is fundamental to development, such as architecture, style guides, or key workflows.
- **Format:** `essential-{context}-{descriptive_name}`
- **Example:** `essential-conventions-code_style`

### `relevant` (Long-term)
- **Principle:** For important, general context that may evolve or become outdated over time, such as architectural decisions or specific analyses.
- **Format:** `relevant-{context}-{descriptive_name}`
- **Example:** `relevant-data_model-migration_context`

### `branch` (Temporary)
- **Principle:** For work-in-progress context specific to a feature branch. These memories should be deleted after the branch is merged or abandoned.
- **Format:** `branch-{YYYYMMDD}-{branch_name}-{context}`
- **Example:** `branch-20251001-feat_update_data_model-updating_schema_definitions`

### `idea` (Temporary)
- **Principle:** For future implementation ideas that might appear during development of features. To be reviewed and prioritized with the team, then moved by the user to an appropriate location.
- **Format:** `idea-{YYYYMMDD}-{context}-{plan_idea}`
- **Example:** `idea-20251001-logging-simple_monitoring`

---

## 3. Quick Reference Section Guidelines

All memories MUST include a "Quick Reference" section as section 1.

### For Detailed Reference Memories (structure, architecture docs)

Use the **"ONLY READ WHEN"** pattern to guide appropriate usage:

```markdown
## 1. Quick Reference

**ONLY READ WHEN:**
- Actively working on [specific module/component]
- [Specific task or context]
- User explicitly asks about [topic]
- Otherwise, use [orientation memory] for high-level overview

Brief description of what this memory contains.

**See also:** [Related memories]
```

### For Orientation/Overview Memories (codebase map, quick refs)

Use the **Purpose/Read at** pattern:

```markdown
## 1. Quick Reference

**Purpose:** [What this memory is for]
**Read at:** [When to read - e.g., session start, when navigating unfamiliar areas]
**Not a reference doc:** [Clarification if needed]

Brief description and key context.
```

### For Convention/Process Memories

Use simple guidance:

```markdown
## 1. Quick Reference

**ONLY READ WHEN:**
- [Specific triggering context]
- User explicitly asks about [topic]

Brief description of what this memory defines.
```

### For Special Cases

- **`idea` memories**: Always add `**NOTE**: ONLY READ WITH USER EXPLICIT PERMISSION`
- **`branch` memories**: Include status and key results in Quick Reference
- **Conversational pattern memories**: Add `**MANDATORY: If not already read, read this memory immediately at the start of each session.**` if they should be read at session start

---

## 4. Naming Best Practices

- Keep names concise but descriptive
- Use underscores (`_`) to separate words in the name
- Use the `YYYYMMDD` date format for branch and idea memories
- Follow the format patterns defined in section 2 for each category
