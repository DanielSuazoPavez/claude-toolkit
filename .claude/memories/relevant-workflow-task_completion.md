# Task Completion Workflow

## 1. Quick Reference

**ONLY READ WHEN:**
- About to complete a coding task
- Running final checks before marking work done
- User asks about task completion workflow

Checklist for code quality before completing a task.

**See also:** `essential-conventions-code_style` for coding standards

---

## 2. Pre-Completion Checklist

| Check | Command | Notes |
|-------|---------|-------|
| Lint passes | `make lint` or `pre-commit run` | Fix all errors before proceeding |
| Tests pass | `make test` or `uv run pytest` | Related tests must pass |
| No breaking changes | Manual review | Check interfaces remain compatible |
| Docs updated | If API/config changed | Docstrings, CLAUDE.md examples |

---

## 3. Handling Linter Exceptions

For PLR09XX ruff errors (complexity), add `# noqa: PLR09XX` and document:

```
**PLR09XX exceptions:**
1. `method_name` (line X): PLR0912 - [brief justification]
```

Only suppress when refactoring would reduce clarity.

---

## 4. Documentation Rules

**Update when:**
- API/function signatures change → docstrings
- Configuration changes → CLAUDE.md examples
- Architecture changes → propose new memory

**Don't:**
- Create README/.md files proactively
- Document unchanged code

---

## 5. Bug Fix Approach

When fixing bugs in your own code:
- Replace buggy code directly with correct implementation
- Don't add backward compatibility for broken versions
- Don't treat fixes as "alternative approaches"
