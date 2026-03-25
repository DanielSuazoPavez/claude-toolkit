# Naming Conventions

Guidelines for naming resources in Claude Toolkit.

## Overview

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
| Memories | `category-context-name` | `essential-workflow-task_completion` |
| Hooks | `functionality-context-detail` | `enforce-feature-branch` |

---

## Skills

**Pattern:** `verb-noun`

### Verb Selection

| Verb | When to use | Examples |
|------|-------------|----------|
| `create-*` | Creating new toolkit resources | `create-agent`, `create-skill`, `create-hook`, `create-memory` |
| `write-*` | Writing artifacts/documents | `write-handoff`, `write-docs` |
| `evaluate-*` | Assessing quality against criteria | `evaluate-agent`, `evaluate-skill`, `evaluate-hook`, `evaluate-memory` |
| `review-*` | Reviewing work (code, plans, security) | `review-plan`, `review-security` |
| `design-*` | Architecting systems or artifacts | `design-db`, `design-docker`, `design-diagram`, `design-qa` |
| `analyze-*` | Deep investigation or research | `analyze-idea`, `analyze-naming` |
| `read-*` | Reading/querying data sources | `read-json` |
| `setup-*` | Configuring tools or environments | `setup-worktree` |
| `draft-*` | Creating drafts for review | `draft-pr` |
| `list-*` | Enumerating resources | `list-memories` |

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
- Plural only when the action is inherently about multiple items (`list-memories`)

---

## Agents

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

## Memories

**Pattern:** `category-context-name`

See `essential-conventions-memory.md` for full documentation.

| Category | Lifespan | Format | Example |
|----------|----------|--------|---------|
| `essential` | Permanent | `essential-{context}-{name}` | `essential-workflow-task_completion` |
| `relevant` | Long-term | `relevant-{context}-{name}` | `relevant-data_model-migration_context` |
| `branch` | Temporary | `branch-{YYYYMMDD}-{branch}-{context}` | `branch-20251001-feat_auth-schema_notes` |
| `idea` | Temporary | `idea-{YYYYMMDD}-{context}-{name}` | `idea-20251001-logging-monitoring` |

**Note:** Memories use `snake_case` for multi-word segments within the name (e.g., `code_style`, `task_completion`), while other resources use `kebab-case` throughout.

---

## Hooks

**Pattern:** `functionality-context-detail`

Detailed conventions to be defined. Current examples follow this loose pattern:

- `git-safety` - functionality: git, context: safety
- `secrets-guard` - functionality: guard, context: secrets
- `track-skill-usage` - functionality: track, context: skill-usage
