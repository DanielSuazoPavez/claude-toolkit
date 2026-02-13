---
name: refactor
description: Structural refactoring analysis. Use when requests mention "refactor", "restructure", "split module", "dependency tangle", "coupling", "cohesion", or "circular imports".
argument-hint: Target file/module/directory, or a specific pain point
---

Analyze structural refactoring decisions. Produces a saved analysis document — not an execution plan.

## When to Use

- Before restructuring modules, splitting files, or reorganizing packages
- When a module feels wrong but you can't articulate why
- When imports are tangled or responsibilities are unclear
- When you suspect dependency direction is inverted

## When NOT to Use

- Mechanical renames or moves — the model handles these fine
- Code style fixes — that's for linters and CLAUDE.md conventions
- Performance optimization — different concern, different analysis
- Trivial changes where the answer is obvious

## Entry Modes

### Triage Mode: `/refactor <target>`

Scans the target (file, module, or directory), classifies severity, recommends whether refactoring is worth it. Full analysis only if warranted.

### Targeted Mode: `/refactor <specific pain point>`

Skips global triage, drills into the stated problem through the four lenses. Use when you already know where it hurts.

**Distinguishing the two:** If `$ARGUMENTS` names a file/module/directory path, use triage mode. If it describes a problem ("circular imports in the auth module", "utils.py does too many things"), use targeted mode.

## Process

### Step 1: Triage

Classify the situation before doing deep analysis.

| Level | Signals | Action |
|-------|---------|--------|
| **Cosmetic** | Naming inconsistencies, minor reorganization | Short summary with suggestions. Stop here — not worth the ceremony. |
| **Structural** | Mixed responsibilities, bloated modules, tangled imports | Full analysis (continue to Step 2) |
| **Architectural** | Wrong abstractions, inverted dependencies, circular deps | Full analysis + flag that `/brainstorm-idea` may be needed first |

In targeted mode, skip to Step 2 — the user already decided it's worth analyzing.

### Step 2: Measure (Light)

Gather concrete data as scaffolding for reasoning. No dogmatic thresholds.

- **Import map**: List who imports whom within the target scope
- **Circular imports**: Flag any (these are concrete bugs, not style opinions)
- **Public exports**: What does the module expose? (e.g., `__init__.py` / `__all__` in Python, `index.ts` barrel exports in TS) — curated or "everything"?
- **File sizes**: As cohesion signals, not hard limits. A 1000-line cohesive module beats 5 fragmented files with tangled imports.

### Step 3: Four-Lens Reasoning (Core)

Apply each lens. Skip what's clean, report only what's relevant. Use `file:line` references.

**1. Coupling** — "Who depends on whom, and should they?"
- High fan-out from one module = possible god module
- Modules importing each other = circular risk
- Many modules importing the same internal detail = fragile coupling

**2. Cohesion** — "Does this module have one job?"
- Can you name the module's responsibility in one phrase?
- Do functions share domain context, or are they grouped by accident?
- Long file + low cohesion = split candidate
- Long file + high cohesion = leave it alone

**3. Dependency Direction** — "Do dependencies point the right way?"
- Core logic importing infra/IO = fine
- Infra/IO importing core logic = fine
- Core module importing another core module's internals = review
- Utility modules importing domain modules = inverted

**4. API Surface** — "Is the interface intentional?"
- Are module entry points curated or re-exporting everything?
- Public functions that are only used internally?
- Could the surface shrink after refactoring?

### Step 4: Write Analysis Document

Save to: `.claude/analysis/{YYYYMMDD}_{HHMM}__refactor__{target}.md`

Use the output format below. For **cosmetic** triage level, output only the Triage section plus a short suggestion list — don't generate a full document.

### Step 5: Present Findings

Show the full analysis to the user. Note the saved file path. Do NOT proceed to implementation — the user decides when and whether to act on the analysis.

**Related resources:**
- **Before**: Use `/analyze-idea` when you need to research feasibility or gather evidence before committing to a refactoring direction. Use the `code-reviewer` agent for complementary pre-refactoring analysis.
- **During triage**: If architectural-level issues surface, escalate to `/brainstorm-idea` to explore the design space before writing the analysis.
- **After**: Use `/review-changes` to verify the refactoring, `/design-tests` if test structure needs updating to match the new module layout.

## Example: Dependency Direction Lens

Given a module `utils/notifications.py` that imports `from models.user import User` and `from services.billing import get_plan`:

```
Dependency Direction issue at utils/notifications.py:3
├─ Utility module imports domain models (User) and services (billing)
├─ This inverts the expected direction: utilities should be imported BY domain code, not import it
├─ Signal: if you change User or billing, a "utility" breaks — that's not utility behavior
└─ This module is misclassified: it's domain logic wearing a utility label
```

**Verdict:** Move to `services/notifications.py` — it's a service, not a utility.

## Example: Cohesion Lens

A 600-line `helpers.py` containing `format_date()`, `send_email()`, `parse_csv()`, `validate_jwt()`, and `resize_image()`:

```
Cohesion issue at helpers.py
├─ Cannot name this module's responsibility in one phrase — "misc stuff" is not a responsibility
├─ Functions share no domain context: dates, email, CSV, auth, and images are unrelated
├─ Each function has different callers — no shared consumer pattern
├─ File size (600 lines) is NOT the problem — lack of cohesion is
└─ A 600-line module doing one thing well would be fine
```

**Verdict:** Split by domain — `formatting.py`, `email.py`, `csv_utils.py`, `auth.py`, `images.py`. Each becomes nameable in one phrase.

## Output Format

```markdown
# Refactor Analysis: {target}

## Triage
- **Target**: {file/module/directory}
- **Level**: Cosmetic | Structural | Architectural
- **Pain point**: {user-stated or detected}
- **Verdict**: {worth refactoring? why/why not}

## Current State
- Dependency map (who imports whom)
- Circular imports (if any)
- Public API surface
- File sizes with cohesion notes

## Problems
{Specific issues through the four lenses, with file:line references}

## Target Structure
- Proposed changes with rationale
- What improves and why (concrete, not "cleaner")

## Suggested Approach
- Brief ordered outline (3-5 lines max)
- Enough to show feasibility and correct ordering
- Actual plan generated at execution time

## Risks
- What could break
- What to watch for during execution
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Refactoring for its own sake** | Triage said cosmetic, you wrote a full report | Respect triage — cosmetic gets a short summary only |
| **Dogmatic rules** | "This file is 800 lines, must split" | File size is a signal, not a rule. Check cohesion first |
| **Abstract complaints** | "This could be cleaner" | Specific problems with file:line references |
| **Execution planning** | Detailed step-by-step implementation plan | Brief outline only — planning happens later |
| **Missing measurement** | Pure opinion without checking imports/exports | Run the light measurements before reasoning |
| **Over-measurement** | Counting metrics that don't change decisions | Import map + circulars + exports + sizes. That's it. |
