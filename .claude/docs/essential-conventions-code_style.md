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
- Ruff for linting and formatting (not black/isort separately); `ty` for type checking
- Formatting lives in pre-commit, not in `make check` (see §4 Verification)
- `pathlib` over `os.path`

**Code Habits**
- Follow existing formatting/naming patterns in the codebase
- Type hints for all function signatures
- Use language built-ins and standard patterns before custom implementations
- No `sys.path.insert` hacks — use proper package imports (e.g., `uv` workspace, `pyproject.toml` package install)
- Zero warnings: treat lint/type warnings as errors — fix or explicitly suppress with justification

---

## 4. Verification

**Post-implementation verification is `make check`, invoked bare.**

Do not pipe through `head`/`tail`/`grep` or other filters — the full output is what you need. If it fails, read the complete output before re-running.

### Target Layout

| Target | Purpose | Mutates files? |
|--------|---------|----------------|
| `make lint` | `ruff check` (no `--fix`) + `ty` | No |
| `make test` | pytest, concise output (`--tb=short -q`) | No |
| `make check` | `make lint && make test` | No |

`make check` is **read-only**. It never reformats, never auto-fixes. If it fails, the failure is real.

### Formatting

Formatting runs via **pre-commit** at `git commit` time — not from `make check`.
- `ruff format`, trailing-whitespace, end-of-file-fixer, etc. live in `.pre-commit-config.yaml`.
- If a pre-commit hook reformats files and exits non-zero, that is a **commit-time event** ("files reformatted, re-stage and commit"), not a verification failure.
- No `make format` target — if you need to format mid-implementation, invoke ruff directly or just commit.

### Rationale

Separating formatting (mutating, at commit) from verification (read-only, on demand) removes a recurring confusion: a reformat-on-exit-1 followed by a passing re-run looks identical to a "flaky test that magically fixed itself." Keeping `make check` read-only makes every failure honest.

### Test Scope (when tests get slow)

Defer until `make test` exceeds ~10s or you notice yourself avoiding it:
- Mark tests with `@pytest.mark.unit`, `@pytest.mark.integration`, `@pytest.mark.slow`.
- `make test` = unit only (fast default for `make check`).
- `make test-all` = everything.

Not needed for small suites.
