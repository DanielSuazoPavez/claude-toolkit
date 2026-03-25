# Testing Conventions

## 1. Quick Reference

**ONLY READ WHEN:**
- Adding or modifying tests
- Creating new testable resources (hooks, CLI commands, skills)
- Running `make test` or `make check` and need to understand what's being tested

Tests are bash scripts in `tests/` plus pytest for Python modules. Run via Makefile targets.

**See also:** `essential-conventions-code_style` for make-target conventions, `/design-tests` for test design methodology

---

## 2. Test Runner

**Entry point:** `make check` (runs tests + validations)

| Target | What it runs | Speed |
|--------|-------------|-------|
| `make test` | hooks + cli + backlog + raiz + eval tests | Fast |
| `make test-hooks` | Hook behavior tests | Fast |
| `make test-cli` | CLI (sync/send) tests | Fast |
| `make test-backlog` | backlog-query.sh tests | Fast |
| `make test-triggers` | Skill trigger eval (uses `claude -p`) | Slow |
| `make validate` | Resource index + dependency validation | Fast |
| `make check` | `test` + `validate` | Fast |

`test-triggers` is excluded from `make test` because it's slow (calls Claude API).

---

## 3. Test Structure

### Bash tests

- **Location:** `tests/test-*.sh`
- **Shell options:** `set -uo pipefail` (no `set -e` — tests check failure cases)
- **Args:** `-v` for verbose, optional filter arg for specific test group
- **Exit codes:** 0 = all pass, 1 = failures

### Python tests (pytest)

- **Location:** `tests/test_*.py`
- **Config:** `pyproject.toml` — `testpaths`, `pythonpath = ["."]` for `from scripts.x import ...`
- **Dev dep:** `pytest>=8.0` in `[dependency-groups] dev`
- **Install:** `make install` (`uv sync --dev`)
- **Pattern:** synthetic JSONL fixtures via `tmp_path`/`tmp_path_factory`, module-scoped where read-only

### Common helpers (defined per test file, not shared):

- `expect_success` / `expect_failure` — assert exit codes
- `expect_output` — assert output contains string
- `expect_file_exists` / `expect_file_content` — assert filesystem state
- `expect_block` / `expect_allow` — hook-specific (check JSON decision field)
- `expect_contains` — assert output contains pattern

### Test lifecycle:

- `setup_test_env` / `teardown_test_env` — create/destroy temp dirs with mock structures
- Each test function calls setup, runs assertions, calls teardown
- Counters: `TESTS_RUN`, `TESTS_PASSED`, `TESTS_FAILED` (manual increment)

---

## 4. Hook Tests (`test-hooks.sh`)

Tests each hook script by piping JSON input (simulating Claude Code's hook protocol) and checking for `"decision": "block"` or empty/allow output.

- Test both block cases (dangerous input) and allow cases (safe input)
- For hooks needing git context (e.g., enforce-feature-branch), create temp git repos
- Filter by hook name: `bash tests/test-hooks.sh secrets` (fuzzy match)

---

## 5. CLI Tests (`test-cli.sh`)

Tests `bin/claude-toolkit` sync and send commands using mock toolkit/project directories.

- Uses `TOOLKIT_DIR` env override to point at mock structure
- Filter by command group: `bash tests/test-cli.sh sync` or `send`
- Also tests validation scripts (validate-resources-indexed, verify-resource-deps) in MANIFEST mode

---

## 6. Skill Trigger Tests (`test-skill-triggers.sh`)

Tests whether natural language prompts correctly trigger skills via `claude -p`.

- Requires `claude` CLI authenticated and `jq`
- Each skill has an `eval-triggers.json` with queries and expected trigger behavior
- Engine: `.claude/scripts/test-trigger.sh` — streams Claude output, detects Skill tool invocations
- Slow: each query runs a full Claude API call with timeout

---

## 7. Validation Scripts (not tests, but run by `make check`)

- `.claude/scripts/validate-all.sh` — orchestrates all validations
- `.claude/scripts/validate-resources-indexed.sh` — checks resources appear in index files
- `.claude/scripts/verify-resource-deps.sh` — checks cross-references between resources
- `.claude/scripts/validate-settings-template.sh` — validates settings.json template

---

## 8. When Adding New Resources

- **New hook:** Add test cases to `tests/test-hooks.sh` (block + allow cases)
- **New CLI command:** Add test group to `tests/test-cli.sh`
- **New skill:** Create `eval-triggers.json` with should/shouldn't trigger queries
- **New validation:** Add to `validate-all.sh` and ensure it follows exit code conventions

**See also:** `essential-conventions-code_style` (make-target conventions), `/design-tests` skill (test design methodology)
