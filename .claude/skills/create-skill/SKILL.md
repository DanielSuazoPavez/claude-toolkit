---
name: create-skill
description: Use when adding a new skill, improving an unreliable skill, or extracting a repeatable pattern. Keywords: create skill, new skill, skill template, SKILL.md.
allowed-tools: Read, Write, Glob, Bash(mkdir:*), Skill
---

Create new skills using test-driven documentation. No skill without a failing test first.

## When to Use

- Adding a new skill to `.claude/skills/`
- Improving an existing skill that isn't working reliably
- Extracting a repeatable pattern into a reusable skill

## Process: Red-Green-Refactor for Skills

### Pre-check: Existing Evaluations

When refining an existing skill, first check `docs/indexes/evaluations.json`:
```bash
jq '.skills.resources["<skill-name>"].top_improvements' docs/indexes/evaluations.json
```
Address documented improvements before inventing new ones.

### RED: Document the Failure

Before writing a new skill:
1. Run the scenario without the skill
2. Document what goes wrong (missed steps, wrong approach, etc.)

**For discipline-enforcing skills** (where the failure mode is arguing out of the process, not forgetting it):

3. Document **rationalizations**: what excuses does the agent make for skipping the process?
4. Build a rationalization table — pair each excuse with a concrete counter:

| Rationalization | Counter |
|-----------------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll do it after" | After = never. Do it now or it won't happen. |

Capture verbatim excuses from baseline testing. Every rationalization the agent makes goes in the table. Include the table in the skill itself — it forecloses loopholes before the agent can exploit them.

5. This is your "failing test" - the gap the skill must fill

### GREEN: Write Minimal Skill

Address only the documented failures:
- Don't over-engineer
- Don't add "nice to have" sections
- Keep it focused on the gap

### REFACTOR: Close Loopholes

Test the skill, find edge cases where it fails, tighten the language.

## Skill Structure

```
.claude/skills/<skill-name>/SKILL.md
```

Read `resources/TEMPLATE.md` and use it as the LITERAL STARTING POINT.
Copy the entire template, then modify every section for the new skill.
Do not write from scratch — always start from the template.

### Required Sections

1. **First line**: "Use when..." - triggering conditions only
2. **When to Use**: Symptoms that indicate this skill applies
3. **Process/Instructions**: The actual workflow
4. **Anti-patterns** (optional): Common mistakes

### Template Modifications by Type

| Skill Type | Modify | Example |
|------------|--------|---------|
| Discipline-enforcing | Add Rationalization table | See [Rationalization Tables](#rationalization-tables-vs-anti-pattern-tables) |
| Reference/lookup | Split to resources/ | See [Progressive Disclosure](#progressive-disclosure-pattern) |
| Knowledge (background) | Add `user-invocable: false` | See [Knowledge Skills](#knowledge-skills) |
| Minimal | Trim to <150 words | Remove anti-patterns, keep process only |

### Description Rules

The first line (description) must:
- Start with "Use when..." or action verb
- List only triggering conditions
- Never summarize the workflow

**Why this matters:** Claude's tool routing uses the description to decide whether to load the skill. If the description contains workflow steps (e.g., "Updates changelog, bumps version"), Claude may execute those steps directly from the description without reading the full SKILL.md body—missing nuances, anti-patterns, and edge cases. Keep descriptions as pure triggers.

### Arguments

If the skill accepts input (file paths, modes, targets):
1. Add `argument-hint` to frontmatter — shown in autocomplete (e.g., `argument-hint: "[file-path] [format]"`)
2. Reference `$ARGUMENTS` in the body where input is needed
3. Handle the empty case — what happens when no args are passed?

Positional access: `$0`, `$1`, `$2` (or `$ARGUMENTS[0]`, `$ARGUMENTS[1]`, etc.)

If `$ARGUMENTS` isn't referenced anywhere in the skill body, Claude Code auto-appends `ARGUMENTS: <value>` at the end.

## Knowledge Skills

Use `user-invocable: false` for skills that provide background knowledge Claude should auto-load, but that users don't invoke directly via `/`.

**When to use:**
- Domain-specific context (API conventions, codebase patterns, compliance rules)
- Skills where the description triggers Claude to load it contextually, not on user command

**Frontmatter:**
```yaml
user-invocable: false
```

The skill's description stays loaded in context (so Claude knows when to read the full body), but it won't appear in the `/` autocomplete menu. No `allowed-tools` needed if the skill is pure knowledge with no tool use.

## Token Efficiency

| Skill Type | Target |
|------------|--------|
| Minimal | <150 words |
| Standard | <500 words |
| Complex reference | Use supporting files |

Techniques:
- Cross-reference other skills instead of repeating
- Move heavy examples to separate files
- Compress: show pattern once, not every variation

## Progressive Disclosure Pattern

### Decision Tree: When to Split

```
Is your skill >400 lines?
├─ No → Keep as single SKILL.md
└─ Yes
   ├─ Is it reference material (API docs, field definitions)?
   │  └─ Yes → Move to resources/*.md, keep process in SKILL.md
   ├─ Is it multiple distinct workflows?
   │  └─ Yes → Consider separate skills instead of splitting
   └─ Is it heavy examples/templates?
      └─ Yes → Move examples to resources/, keep one inline
```

### Structure

When a skill exceeds ~400 lines, split it:

```
skill-name/
  SKILL.md              # <500 lines - overview + navigation
  resources/
    TOPIC.md            # <500 lines per file
```

### Main File (SKILL.md)

Contains:
- Full process overview
- Inline references: `See resources/TOPIC.md for details`
- Decision trees that reference, not replicate, detailed content

### Supporting Files (resources/*.md)

| Requirement | Why |
|-------------|-----|
| <500 lines each | Prevent context bloat |
| Table of contents if >100 lines | Enable navigation |
| One level deep | No nested references |

### Reference Style

**Good:** `See resources/API.md for field definitions`
**Bad:** Copying content into SKILL.md, or bare `See resources/API.md`

### Example

`create-hook` demonstrates this pattern:
- `SKILL.md` (~165 lines): Process + triggers
- `resources/HOOKS_API.md` (400 lines): Complete API reference

## Testing Your Skill

Run the original failing scenario with the skill active:
- Does it address the gap?
- Any new edge cases?
- Is it too verbose? Too terse?

### Quality Gate

Before outputting the skill, evaluate it with `/evaluate-skill`:
- **Target: 85%**
- If below target, iterate on the weakest dimensions
- Common fixes: add anti-patterns table, add decision tree, remove tutorial content
- **D7 (Integration Quality)**: Check that references point to real resources, defer to existing content instead of restating it, and connect to related skills/agents/memories

**See also:** `/create-agent` (when an agent fits better), `/create-hook` (for enforcement patterns), `/create-memory` (for context persistence), `relevant-toolkit-resource_frontmatter` memory (supported frontmatter fields)

## Naming Convention

Use `verb-noun` format: `create-skill`, `review-changes`, `brainstorm-idea`

See `docs/naming-conventions.md` for the full naming guide.

## Iteration Example

**Gap:** Without a skill, Claude writes changelog updates inconsistently — sometimes forgets, no standard format, misses version bumps.

**First attempt:** Skill listed steps but no anti-patterns. Claude followed steps but chose wrong version bump types (patch for new features).

**Fix:** Added anti-patterns table mapping common mistakes to corrections. With table, Claude self-corrects before outputting.

The template in `resources/TEMPLATE.md` shows what a complete skill looks like. Use it as the starting point, then iterate with `/evaluate-skill` to close gaps.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **No Failing Test** | Skill solves imaginary problem | Document the gap BEFORE writing |
| **Kitchen Sink** | 800-line skill covering everything | Focus on one gap, cross-reference others |
| **Workflow in Description** | Claude executes from description, misses nuances in body | Description = triggers only, not steps |
| **Tutorial Content** | Explains what Claude already knows | Only include expert knowledge delta |

## Rationalization Tables vs Anti-Pattern Tables

Anti-pattern tables (3 columns: Pattern | Problem | Fix) capture **structural mistakes** — wrong output format, wrong scope. Rationalization tables (2 columns: Rationalization | Counter) capture **excuses for skipping the process** — correct reasoning, wrong conclusion. Use both when building discipline-enforcing skills.

Example rationalization table (from TDD domain):

| Rationalization | Counter |
|-----------------|---------|
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run. |
| "Test hard = design unclear" | Listen to the test. Hard to test = hard to use. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Existing code has no tests" | You're improving it. Add tests for what you touch. |
