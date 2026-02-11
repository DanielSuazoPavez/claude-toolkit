---
name: write-skill
description: Use when adding a new skill, improving an unreliable skill, or extracting a repeatable pattern. Keywords: create skill, new skill, skill template, SKILL.md.
---

Create new skills using test-driven documentation. No skill without a failing test first.

## When to Use

- Adding a new skill to `.claude/skills/`
- Improving an existing skill that isn't working reliably
- Extracting a repeatable pattern into a reusable skill

## Process: Red-Green-Refactor for Skills

### Pre-check: Existing Evaluations

When refining an existing skill, first check `.claude/evaluations.json`:
```bash
jq '.skills.resources["<skill-name>"].top_improvements' .claude/evaluations.json
```
Address documented improvements before inventing new ones.

### RED: Document the Failure

Before writing a new skill:
1. Run the scenario without the skill
2. Document what goes wrong (missed steps, wrong approach, etc.)
3. This is your "failing test" - the gap the skill must fill

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

### Required Sections

1. **First line**: "Use when..." - triggering conditions only
2. **When to Use**: Symptoms that indicate this skill applies
3. **Process/Instructions**: The actual workflow
4. **Anti-patterns** (optional): Common mistakes

### Description Rules

The first line (description) must:
- Start with "Use when..." or action verb
- List only triggering conditions
- Never summarize the workflow

**Why this matters:** Claude's tool routing uses the description to decide whether to load the skill. If the description contains workflow steps (e.g., "Updates changelog, bumps version"), Claude may execute those steps directly from the description without reading the full SKILL.md body—missing nuances, anti-patterns, and edge cases. Keep descriptions as pure triggers.

## Token Efficiency

| Skill Type | Target |
|------------|--------|
| Getting-started | <150 words |
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

`write-hook` demonstrates this pattern:
- `SKILL.md` (100 lines): Process + triggers
- `HOOKS_API.md` (400 lines): Complete API reference

## Testing Your Skill

Run the original failing scenario with the skill active:
- Does it address the gap?
- Any new edge cases?
- Is it too verbose? Too terse?

### Quality Gate

Before outputting the skill, evaluate it with `/evaluate-skill`:
- **Target: B (90+) or better**
- If score is below B, iterate on the weakest dimensions
- Common fixes: add anti-patterns table, add decision tree, remove tutorial content
- **D7 (Integration Quality)**: Check that references point to real resources, defer to existing content instead of restating it, and connect to related skills/agents/memories

## Naming Convention

Use `verb-noun` format: `write-skill`, `review-changes`, `brainstorm-idea`

See `docs/naming-conventions.md` for the full naming guide.

## Complete Example

### Before (The Gap)
Without a skill, Claude writes changelog updates inconsistently:
- Sometimes updates, sometimes forgets
- No standard format
- Misses version bumps

### The Skill: `wrap-up`

```yaml
---
name: wrap-up
description: Use when finishing work on a feature branch. Keywords: finish feature, complete branch, ready to merge, finalize branch, wrap up.
---
```

```markdown
Use when finishing a feature branch.

## Instructions

### 1. Analyze the branch
Review commits since branching from main.

### 2. Determine version bump
- **Major**: Breaking changes
- **Minor**: New features
- **Patch**: Bug fixes only

### 3. Update CHANGELOG.md
Add entry with date, version, changes.

### 4. Update pyproject.toml
Bump the version field.

### 5. Commit changes
`git commit -m "docs: update changelog, version X.Y.Z"`

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Wrong Bump** | Patch for new feature | Match bump to change type |
| **Empty Entry** | "Updated stuff" | Describe what and why |
```

### After (The Fix)
With skill active, Claude consistently:
- Updates changelog with proper format
- Bumps version appropriately
- Commits with standard message

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **No Failing Test** | Skill solves imaginary problem | Document the gap BEFORE writing |
| **Kitchen Sink** | 800-line skill covering everything | Focus on one gap, cross-reference others |
| **Workflow in Description** | Claude executes from description, misses nuances in body | Description = triggers only, not steps |
| **Tutorial Content** | Explains what Claude already knows | Only include expert knowledge delta |
