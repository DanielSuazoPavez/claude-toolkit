---
name: shape-project
description: Use when defining or refining a project's identity, scope, and boundaries. Use before major refactors, reshaping efforts, or to set guardrails on early-stage projects. Keywords: project identity, scope, boundaries, refactor direction, what is this project.
allowed-tools: Read, Write, Glob, AskUserQuestion
---

Define a project's identity and boundaries as a `relevant-project-identity` doc. Produces a declaration of what the project is, its core traits, and what belongs (or doesn't).

## When to Use

- Before a major refactor or cleanup — to align on what stays and what goes
- Early-stage project with enough context — to prevent bloat before it forms
- Project feels unfocused — too many concerns, unclear boundaries

## When NOT to Use

- Project already has a clear `relevant-project-identity` doc (update it instead)
- You just need a README or CLAUDE.md (use `/write-docs`)
- Scope is already obvious from a small, focused codebase

## Process

### Phase 1: Read the Repo

Gather context from what exists. Read in this order, stopping when you have enough:

1. `README.md` — stated purpose, features, usage
2. `CLAUDE.md` — project instructions, structure
3. Package config (`pyproject.toml`, `package.json`, `Cargo.toml`, etc.) — dependencies, scripts
4. Directory structure (top-level `ls`) — what modules/components exist
5. `BACKLOG.md` — current priorities, what's planned vs abandoned

**Goal:** Build a mental model of what the project currently is — not what it aspires to be.

### Phase 2: Ask Targeted Questions

Ask **2-3 questions** about what you can't infer from code. One question per message. Prefer multiple choice.

Focus on:
- **Intent**: What should this project do, in one sentence?
- **Bloat**: What feels like it doesn't belong? What was overengineered?
- **Boundaries**: What should this project explicitly *not* become?

Skip questions where the answer is obvious from Phase 1.

### Phase 3: Draft the Identity

Propose a draft with these sections:

#### Section 1: What This Is
One paragraph. The project's purpose and character — concise, opinionated. Written as a declaration, not a description.

#### Section 2: Core Traits
3-5 principles that guide decisions. Each trait must be:
- **Actionable** — you can point to it when deciding if a change belongs
- **Opinionated** — it excludes something, not just states a preference
- **Grounded** — derived from the project's actual character, not aspirational

Format: `**Trait name** — one-line explanation`

#### Section 3: Scope Boundary
Two lists:
- **In scope**: What belongs in this repo
- **Out of scope**: What doesn't, and where it goes instead (if applicable)

#### Section 4: Decision Filter (include only when relevant)
A short checklist for "does this addition belong?" — useful for toolkits, shared libraries, monorepos, or any project that curates what it includes. Skip for typical application repos.

### Phase 4: Refine

Present the draft. Iterate based on user feedback. The user knows their project — defer to their judgment on tone and emphasis.

### Phase 5: Save

Save as `relevant-project-identity.md` in the project's `.claude/docs/`.

The doc's Quick Reference should use the "ONLY READ WHEN" pattern:
```
**ONLY READ WHEN:**
- Planning major refactors or architectural changes
- Deciding whether to add a new module or dependency
- Project scope feels unclear or is being debated
```

## Output Quality

The identity should feel like a **scalpel, not a manifesto**. Test each section:
- Can you use it to make a concrete keep/cut decision?
- Would removing it leave a gap in decision-making?
- Is it specific to *this* project, or generic advice?

If a section reads like it could apply to any project, it's too vague. Rewrite with specifics.

## Example: Generic vs. Specific Traits

For a CLI tool that generates code from schemas:

| Generic (bad) | Specific (good) |
|---------------|-----------------|
| **Well-tested** — comprehensive test coverage | **Schema in, code out** — no runtime components, no server mode, no watch loops |
| **Clean code** — readable and maintainable | **Single-pass generation** — if it needs two passes, the schema design is wrong |
| **Extensible** — easy to add new features | **Thin core, pluggable outputs** — core parses schemas; language targets are plugins, not core code |

The generic column applies to any project. The specific column makes real keep/cut decisions: "should we add a dev server?" → no, schema in/code out. "Should we add a second-pass optimizer?" → no, single-pass.

## See Also

- `/brainstorm-idea` — use first when the project direction itself is unclear
- `.claude/docs/` — where the output is saved (Phase 5)
- `/refactor` — often follows this skill when cutting scope

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Generic traits** | "Clean code", "well-tested" — applies to everything | Traits must exclude something specific to this project |
| **Aspirational identity** | Describes what the project wants to be, not what it is | Ground in current reality, note aspirations separately |
| **Scope creep in scope** | "In scope" list keeps growing during drafting | If everything's in scope, nothing is — push back |
| **README rehash** | Identity reads like a feature list | Focus on character and boundaries, not capabilities |
