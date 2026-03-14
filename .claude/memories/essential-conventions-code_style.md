# Code Style Conventions

## 1. Quick Reference

**MANDATORY:** Read at session start - affects all code written.

- Functions over classes (classes only when state is needed)
- Leverage existing systems before writing new code
- Env vars for config, not custom credential classes
- Minimal interfaces — only essential parameters

**See also:** `relevant-philosophy-reducing_entropy` for code minimalism

---

## 2. Design Principles

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

## 3. Project Conventions

**Python Tooling**
- `uv` for dependency management, not pip
- `make` targets over raw tool invocations (`make test`, not `pytest`)
- Ruff for linting and formatting (not black/isort separately)
- `pathlib` over `os.path`

**Code Habits**
- Follow existing formatting/naming patterns in the codebase
- Type hints for all function signatures
- Use language built-ins and standard patterns before custom implementations
