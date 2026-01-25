# Task Completion Workflow

## 1. Quick Reference

**ONLY READ WHEN:**
- About to complete a task
- Running final checks before marking work as done
- User asks about task completion workflow

Mandatory steps to ensure code quality before considering a task complete.

---

## 2. Code Quality Checks (Mandatory)

All code changes must pass linting:

```bash
make lint
# or
pre-commit run
```

### Handling PLR09XX Errors (Complexity)

For PLR09XX ruff errors (too many branches/statements), add `# noqa: PLR09XX` to the line and document:

```
**Brief list of PLR09XX noqa instances applied:**

1. **`method_name` (line X)**:
   - `PLR0912`: Too many branches (X > 12) - Brief reason
   - `PLR0915`: Too many statements (X > 50) - Brief reason
```

---

## 3. Testing

Run the test suite:

```bash
make test
# or
uv run pytest
```

- Verify tests related to changed functionality pass
- No breaking changes to existing interfaces

---

## 4. Documentation Updates

**When to update:**
- Changed API/function signatures -> Update docstrings
- Modified configuration -> Update config examples in CLAUDE.md
- Architectural changes -> Propose new memory or update existing

**What NOT to do:**
- Don't create README or .md files proactively
- Don't add documentation for unchanged code

---

## 5. Final Checklist

- `make lint` / `pre-commit run` passes
- Tests pass
- Code follows project conventions (see `essential-conventions-code_style`)
- No breaking changes introduced
- Documentation updated (if applicable per section 4)

---

## 6. Bug Fix Guidelines

When fixing bugs in code you wrote:
- Directly replace buggy code with correct implementation
- Do NOT add backward compatibility layers for the broken version
- Do NOT treat the fix as an alternative approach
