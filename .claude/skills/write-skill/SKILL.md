---
name: write-skill
description: Create new skills using test-driven documentation. Use when adding, improving, or extracting skills.
---

Create new skills using test-driven documentation. No skill without a failing test first.

## When to Use

- Adding a new skill to `.claude/skills/`
- Improving an existing skill that isn't working reliably
- Extracting a repeatable pattern into a reusable skill

## Process: Red-Green-Refactor for Skills

### RED: Document the Failure

Before writing the skill:
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

Why? If description summarizes workflow, Claude may follow description instead of reading full content.

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

Before outputting the skill, evaluate it with `skill-judge`:
- **Target: B (90+) or better**
- If score is below B, iterate on the weakest dimensions
- Common fixes: add anti-patterns table, add decision tree, remove tutorial content

## Naming Convention

Two words, hyphenated: `write-skill`, `quick-review`, `brainstorm-idea`

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
description: Use when finishing work on a feature branch. Updates changelog, bumps version, commits changes.
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
| **Workflow in Description** | Claude follows description, skips body | Description = triggers only, not steps |
| **Tutorial Content** | Explains what Claude already knows | Only include expert knowledge delta |
