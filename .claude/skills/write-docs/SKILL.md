---
name: write-docs
description: Use when writing or updating project documentation. Keywords: docs, documentation, README, docstrings, API docs, write docs, update docs, document.
---

Write or update project documentation based on actual code. Gap analysis first, then write.

## Mindset

**Audit before you write.** Documentation is a claim about code. Every claim must be verifiable. If you can't trace a statement back to source, don't write it.

**Code is truth.** When docs and code disagree, the code is right. Update the docs, never the other way around. Comments lie, commit messages lie less, code behavior is truth.

**Document the contract, not the mechanism.** Users need to know what a function does, what it accepts, and what it returns. They don't need to know how it works internally — unless the how affects their usage (performance, side effects, ordering constraints).

## When to Use

- User asks to write, update, or improve documentation
- Docs have drifted from code and need syncing
- New code lacks documentation
- README is missing, incomplete, or outdated

## Modes

Ask the user which mode (or detect from context):

| Mode | What it produces | Scope |
|------|-----------------|-------|
| **user-docs** | README, guides, API reference (markdown files) | Project-level or module-level |
| **docstrings** | Function/class/module docstrings in source files | File-level or module-level |

If unclear, default to **user-docs**.

## Process

### 1. Check for Codebase Explorer Report

Look for `.claude/reviews/codebase/` (ARCHITECTURE.md, STACK.md, STRUCTURE.md).

```
Report exists?
├─ Yes → Use as your map. Skip broad exploration.
└─ No → Ask user:
   ├─ "Run codebase-explorer first?" (recommended for large/unfamiliar projects)
   └─ "Proceed with lighter exploration?" (fine for small projects or targeted docs)
```

### 2. Gap Analysis

**Inventory existing docs** — what exists, where, what it covers.

**Audit against code** — for each doc:
- Does it match current code behavior?
- Are examples runnable?
- Are referenced files/functions still present?
- Is the structure/API description accurate?

**Identify gaps:**
- Undocumented modules or features
- Outdated sections (code changed, docs didn't)
- Missing sections (install, usage, API reference, etc.)

Present the gap analysis to the user before writing:

```markdown
## Gap Analysis: [project/module]

### Existing Docs
- `README.md` — covers install, missing API reference
- `docs/guide.md` — outdated (references removed function X)

### Gaps Found
1. [GAP] No API reference for `src/services/`
2. [OUTDATED] README install steps reference old dependency
3. [MISSING] No usage examples for CLI commands

### Recommended Actions
- [ ] Update README install section
- [ ] Add API reference for services module
- [ ] Fix guide.md references

Proceed with these? (user confirms/adjusts)
```

### 3. Style Detection

Before writing, detect the project's doc voice:

- **Tone**: Formal ("This module provides...") vs casual ("Here's how to...")
- **Structure**: Headings depth, bullet vs prose, code example frequency
- **Conventions**: Badge usage, table of contents, API doc format

Match what exists. If no docs exist, ask the user's preference or default to concise and direct.

### 4. Write Documentation

**Scope decisions — what to document and how deep:**

```
Who reads this?
├─ End users (README, guides) → What it does, how to use it, examples
├─ API consumers (reference) → Signatures, parameters, return values, errors
├─ Contributors (docstrings) → Contract + non-obvious constraints
└─ No clear audience → Ask the user before writing
```

```
How deep?
├─ Public API → Full documentation (params, returns, errors, examples)
├─ Internal modules used across files → Brief docstrings (purpose + contract)
├─ Private helpers → Skip unless complex or non-obvious
└─ Trivial code (getters, wrappers, delegates) → Skip
```

**For user-docs mode:**
- Write/update markdown files in place
- Every claim must be verifiable against current code
- Include working code examples (test them if possible)
- Cross-reference related docs where they exist

**For docstrings mode:**
- Follow the language's docstring convention (Python: Google/NumPy style, JS: JSDoc, etc.)
- Match existing docstring style in the project
- Cover: purpose, parameters, return values, exceptions
- Skip trivial functions (getters, simple wrappers) unless user asks

### 5. Verify

After writing, spot-check:
- Do code examples actually work?
- Do file paths referenced in docs exist?
- Do function signatures in docs match source?

## Quality Rules

| Rule | Why |
|------|-----|
| **Never fabricate** | If unsure about behavior, read the code first or mark as `[VERIFY]` |
| **Accuracy > completeness** | Better to skip than document wrong |
| **Code is truth** | When docs and code disagree, update docs to match code |
| **Working examples** | Dead examples are worse than no examples |
| **No filler** | Skip boilerplate ("This project is a...") unless it adds real context |

## Edge Cases

| Situation | Response |
|-----------|----------|
| **Code too complex to document accurately** | Mark with `[VERIFY]` tag, explain what you understood, flag for user review. Don't guess. |
| **Existing docs are severely wrong** | Flag in gap analysis as `[REWRITE]`. Don't patch — rewrite the section from code. |
| **Gap analysis reveals more work than scoped** | Present full gap list, ask user to prioritize. Do the top items, note the rest as future work. |
| **No code comments or tests to guide understanding** | Rely on function signatures, call sites, and variable names. Document the contract you can verify, mark uncertainty. |
| **Conflicting docs** (README says X, guide says Y) | Check code for truth. Update both to match code. Note the conflict in gap analysis. |

## Examples

See `resources/EXAMPLES.md` for good and bad examples of both modes (user-docs and docstrings).

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Write-first** | Docs based on assumptions, not code | Always run gap analysis first |
| **Copy-paste syndrome** | Duplicating the same info across files | Cross-reference instead |
| **Aspirational docs** | Documenting planned features as if they exist | Document current state only |
| **Over-documenting internals** | Exposing implementation details in user docs | User docs = what/how-to-use, not how-it-works |
| **Ignoring existing voice** | Generic tone clashing with project style | Detect and match existing style |
| **Skipping verification** | "Looks right" without checking code | Spot-check examples, paths, signatures |
