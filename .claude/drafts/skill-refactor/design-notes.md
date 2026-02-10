# skill-refactor — Design Notes

## Core Insight

The skill's value is **consistency, not capability**. The model can reason about refactoring at a deep level when prompted — the skill ensures it does so *every time*, systematically.

This is not about mechanical operations (move, rename, fix imports). It's about refactoring as a **design activity** with structured decision-making and measurable outcomes.

## Decision Guidance (Metrics to Drive Decisions)

### Coupling
- Cross-module import count before/after
- Fan-in / fan-out per module — are dependencies concentrated or scattered?
- Are modules importing each other (circular risk)?

### Cohesion
- Do functions in a module share data types, concepts, or domain context?
- Could you name the module's single responsibility in one phrase?
- If you can't — that's a split signal

### Dependency Direction
- Are dependencies pointing toward stable abstractions or toward volatile details?
- Inward dependencies (toward core) = good, outward (toward IO/infra) = review

### Public API Surface
- Did the refactor reduce or grow the public interface?
- Are `__init__.py` re-exports intentional or just legacy?

## Structured Process

### 1. Analyze Current State
- Measure concrete metrics (coupling, cohesion signals, API surface)
- Map the dependency graph — who imports whom
- Identify the pain points: what's actually wrong, not just "messy"

### 2. Define Target Structure
- Propose the target with **rationale** — not "feels better", but "reduces coupling from X to Y" or "groups by domain concept instead of by accident"
- Explicit goals: what metrics should improve

### 3. Plan Step Ordering
- Rename before restructure, restructure before rewrite
- Small, verifiable steps — each one should pass tests and type checks
- Order by dependency: move leaf modules first, work inward

### 4. Execute with Verification
- Validate each step against the defined metrics, not just "tests pass"
- Check for regressions: did we accidentally increase coupling elsewhere?
- Run type checker between moves (mypy as safety net)

### 5. Evaluate Outcome
- Compare before/after metrics
- Did we hit the goals defined in step 2?
- Document what changed and why (commit messages, not comments)

## What This Skill Is NOT

- Not a "how to update imports" guide — the model handles mechanics fine
- Not a code style enforcer — that's for linters and CLAUDE.md conventions
- Not a general "clean code" checklist — focused on structural refactoring decisions

## Open Questions

- Which Python tools (if any) should the skill recommend for dependency analysis? (e.g., `pydeps`, `import-linter`, `grimp`)
- Should it include a lightweight template for the before/after analysis report?
- Scope: Python-only or language-agnostic principles with Python examples?
