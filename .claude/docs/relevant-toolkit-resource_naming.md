# Naming Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Creating or renaming skills, agents, memories, or hooks
- Reviewing resource names during evaluation
- User asks about naming patterns

Guidelines for naming resources in Claude Toolkit.

**See also:** `relevant-toolkit-context` for docs/memories boundary and category conventions

---

## 2. Overview

**Core Principles:**

1. **Pattern per resource type** - Each resource type has one naming pattern
2. **Verb-first for actions** - Skills start with verbs for natural invocation (`/create-agent`)
3. **Role-based for actors** - Agents end with their role (`code-reviewer`)
4. **Alphabetical clustering** - Related resources group together (all `evaluate-*` skills adjacent)
5. **Lowercase kebab-case** - Universal format across all resources

| Resource | Pattern | Example |
|----------|---------|---------|
| Skills | `verb-noun` | `create-agent`, `evaluate-skill` |
| Agents | `context-role` | `code-reviewer`, `goal-verifier` |
| Memories | `descriptive_name` | `professional_profile`, `user` |
| Hooks | `functionality-context-detail` | `enforce-feature-branch` |
| Docs | `{essential\|relevant}-{context}-{name}` | `essential-conventions-code_style`, `relevant-toolkit-artifacts` (full pattern in `relevant-toolkit-context`) |

---

## 3. Skills

**Pattern:** `verb-noun`

### Verb Selection

| Verb | When to use | Examples |
|------|-------------|----------|
| `create-*` | Creating new toolkit resources | `create-agent`, `create-skill`, `create-hook`, `create-docs` |
| `write-*` | Writing artifacts/documents | `write-handoff`, `write-documentation` |
| `evaluate-*` | Assessing quality against criteria | `evaluate-agent`, `evaluate-skill`, `evaluate-hook`, `evaluate-docs` |
| `review-*` | Reviewing work (code, plans, security) | `review-plan`, `review-security` |
| `design-*` | Architecting systems or artifacts | `design-db`, `design-docker`, `design-diagram`, `design-tests` |
| `analyze-*` | Deep investigation or research | `analyze-idea`, `analyze-naming` |
| `read-*` | Reading/querying data sources | `read-json` |
| `setup-*` | Configuring tools or environments | `setup-worktree` |
| `draft-*` | Creating drafts for review | `draft-pr` |
| `list-*` | Enumerating resources | `list-docs` |

### Choosing the Right Verb

- **Creating a toolkit resource?** → `create-*`
- **Writing an artifact/document?** → `write-*`
- **Checking quality?** → `evaluate-*`
- **Looking at existing work?** → `review-*`
- **Planning architecture?** → `design-*`
- **Investigating a topic?** → `analyze-*`

### Noun Selection

- Use the resource/target being acted upon
- Singular when acting on one thing (`create-agent`, not `create-agents`)
- Plural only when the action is inherently about multiple items (`list-docs`)

---

## 4. Agents

**Pattern:** `context-role`

### Components

- **Context:** The domain or target the agent works on (e.g., `code`, `plan`, `goal`, `codebase`, `pattern`)
- **Role:** What the agent does, as a noun (e.g., `reviewer`, `verifier`, `debugger`, `finder`, `mapper`)

### Examples

| Agent | Context | Role |
|-------|---------|------|
| `code-reviewer` | code | reviewer |
| `code-debugger` | code | debugger |
| `plan-reviewer` | plan | reviewer |
| `goal-verifier` | goal | verifier |
| `pattern-finder` | pattern | finder |
| `codebase-mapper` | codebase | mapper |

### Guidelines

- **Context first** - Allows grouping by domain (`code-*` agents together)
- **Role describes function** - Common roles: `-reviewer`, `-verifier`, `-finder`, `-mapper`, `-debugger`, `-builder`
- **Singular context** - `code-reviewer` not `codes-reviewer`

### Adding New Agents

1. Ask: "What does this agent examine?" → context
2. Ask: "What role does it play?" → role
3. Combine: `{context}-{role}`

---

## 5. Memories

**Pattern:** `descriptive_name` (no category prefix)

Memories are organic context — plain named files with underscores. No prefixes, no indexing.

| Type | Format | Example |
|------|--------|---------|
| Regular | `descriptive_name` | `professional_profile`, `user` |
| Branch WIP | `YYYYMMDD-{branch}-{context}` | `20251001-feat_auth-schema_notes` |

**Note:** Memories use `snake_case` for multi-word names, while other resources use `kebab-case` throughout.

---

## 6. Hooks

**Pattern:** `functionality-context-detail`

Detailed conventions to be defined. Current examples follow this loose pattern:

- `git-safety` - functionality: git, context: safety
- `secrets-guard` - functionality: guard, context: secrets
- `track-skill-usage` - functionality: track, context: skill-usage
