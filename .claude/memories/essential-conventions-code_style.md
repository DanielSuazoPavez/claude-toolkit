# Code Style Conventions

## 1. Quick Reference

**MANDATORY:** Read at session start - affects all code written.

Core philosophy: pragmatism, simplicity, leverage existing systems.

**See also:** `relevant-workflow-task_completion` for completion checklist, `relevant-philosophy-reducing_entropy` for code minimalism

---

## 2. Core Philosophy

Deliver the simplest, most direct solution. Avoid over-engineering and unnecessary complexity.

---

## 3. Design Principles

**Leverage Existing Systems First**
- Check for existing patterns, functions, or library capabilities before writing new code
- Use built-in library features over custom implementations

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
- Adhere to formatting/naming patterns in the codebase
- Look at similar existing code for patterns

**Ensure Type Safety**
- Use type hints for all function signatures
- Verify with static analysis tools

**Write Focused Code**
- Keep functions small, single-responsibility
- Handle exceptions gracefully

**Document with Purpose**
- Clear docstrings for public APIs
- Concise comments for complex logic only

**Be Idiomatic**
- Use language built-ins and standard patterns before custom implementations
- Prefer library-native operations over manual loops
