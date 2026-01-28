# Agentic Coding Conventions

## 1. Quick Reference

**Read at:** Session start (via hook) AND when implementing new code

Core coding philosophy: pragmatism, simplicity, and leveraging existing systems. Follow these conventions for maintainable code.

**See also:** `essential-workflow-task_completion` for task completion steps, `relevant-philosophy-reducing_entropy` for deeper guidance on code minimalism

---

## 2. Core Philosophy

Deliver the simplest, most direct solution. Avoid over-engineering and unnecessary complexity.

---

## 3. Design Principles

**Leverage Existing Systems First**
- Check for existing patterns, functions, or library capabilities before writing new code
- Example: Use Polars' built-in S3 support (`scan_parquet("s3://...")`) instead of custom readers

**Prefer Functions Over Classes**
- Use simple, stateless functions for operations
- Only create classes when state management is required
- Avoid wrapper classes that don't add value

**Use Environment Variables for Configuration**
- Let libraries auto-discover credentials via env vars
- Avoid custom credential management classes

**Keep Interfaces Minimal**
- Add only essential parameters to functions

---

## 4. Implementation Guidelines

**Follow Existing Style**
- Adhere to formatting/naming patterns in the codebase (PEP 8 baseline)
- Look at similar existing code for patterns

**Ensure Type Safety**
- Use type hints for all function signatures
- Verify with static analysis

**Write Focused Code**
- Keep functions small, single-responsibility
- Handle exceptions gracefully

**Document with Purpose**
- Clear docstrings for public APIs
- Concise comments for complex logic only

**Be Idiomatic**
- Use Python built-ins and comprehensions before custom implementations
- Use Polars expressions over Python loops for dataframe operations
