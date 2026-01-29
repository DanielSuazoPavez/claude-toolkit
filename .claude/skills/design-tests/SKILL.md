---
name: design-tests
description: Use when writing or reviewing tests. Use when requests mention "pytest", "fixtures", "mocking", "conftest", "parametrize", or "test organization".
---

# Test Design Guide

Consistent pytest patterns for reliable, maintainable tests.

## Table of Contents

1. [Test Priority Framework](#test-priority-framework)
2. [Fixtures](#fixtures)
3. [Mocking](#mocking)
4. [Organization](#organization)
5. [Marks](#marks)
6. [Make Targets](#make-targets)
7. [Concrete Examples](#concrete-examples)
8. [Anti-Patterns](#anti-patterns)

---

## Test Priority Framework

What to test depends on what you're building:

```
What type of code is this?
├─ Business logic (calculations, rules, transformations)
│   → Unit tests (high coverage)
│   → Edge cases, boundary conditions
│
├─ I/O operations (API, database, file system)
│   → Integration tests at boundaries
│   → Mock external services, test real DB when feasible
│
├─ Orchestration (glue code, routing, composition)
│   → Light integration tests
│   → Don't over-test wiring
│
└─ UI/CLI (user-facing interfaces)
    → Smoke tests for critical paths
    → Don't test framework behavior
```

### How Much Testing?

| Code Type | Coverage Target | Focus |
|-----------|-----------------|-------|
| Business logic | 80-90% | All branches, edge cases |
| I/O boundaries | Key paths | Happy path + error handling |
| Orchestration | 50-60% | Integration points |
| UI/CLI | Critical paths | Smoke tests only |

**Rule:** Test behavior, not implementation. If refactoring breaks tests but not behavior, tests are too coupled.

---

## Fixtures

### Which Scope?

```
What kind of fixture is this?
├─ Creates/modifies state each test needs fresh? → function (default)
├─ Expensive setup (>100ms)?
│   ├─ Read-only or shared across tests? → module or session
│   └─ Each test modifies it? → function (pay the cost)
├─ External service connection?
│   ├─ Stateless (HTTP client)? → session
│   └─ Stateful (DB transaction)? → function with rollback
└─ Utility/helper with no state? → module
```

| Scope | Use When | Example |
|-------|----------|---------|
| `function` (default) | Isolated per test | Most fixtures |
| `class` | Shared across test class | Stateless helpers |
| `module` | Expensive setup, read-only | DB schema |
| `session` | Very expensive, immutable | External service connection |

```python
@pytest.fixture(scope="module")
def db_connection():
    """Expensive setup, shared across module."""
    conn = create_connection()
    yield conn
    conn.close()
```

### Factory Pattern

Use factories when tests need variations of the same object:

```python
@pytest.fixture
def make_user():
    """Factory for creating test users with defaults."""
    def _make_user(name="test", email=None, active=True):
        return User(
            name=name,
            email=email or f"{name}@test.com",
            active=active,
        )
    return _make_user


def test_inactive_user(make_user):
    user = make_user(active=False)
    assert not user.can_login()
```

### conftest.py Organization

```
tests/
├── conftest.py          # Shared fixtures (db, factories)
├── unit/
│   ├── conftest.py      # Unit-specific fixtures
│   └── test_*.py
└── integration/
    ├── conftest.py      # Integration-specific fixtures
    └── test_*.py
```

**Rule:** Put fixtures in the narrowest scope where they're needed.

---

## Mocking

### When to Mock

```
Should I mock this?
├─ External service (API, DB, filesystem)? → Yes, at boundary
├─ Slow operation (network, disk)? → Yes
├─ Non-deterministic (time, random)? → Yes
├─ Internal function in same module? → Usually no
└─ Third-party library internals? → No, mock at your boundary
```

### Patch vs Dependency Injection

| Approach | Use When | Example |
|----------|----------|---------|
| `@patch` | Legacy code, no DI available | Patching `requests.get` |
| DI (fixture) | New code, testable design | Passing client as parameter |

**Prefer DI** - it makes dependencies explicit and tests clearer.

```python
# Dependency Injection (preferred)
def fetch_data(client):  # Client passed in
    return client.get("/data")

def test_fetch_data(mock_client):
    mock_client.get.return_value = {"key": "value"}
    result = fetch_data(mock_client)
    assert result == {"key": "value"}


# Patch (when DI not possible)
@patch("myapp.api.requests.get")
def test_fetch_legacy(mock_get):
    mock_get.return_value.json.return_value = {"key": "value"}
    result = fetch_data_legacy()
    assert result == {"key": "value"}
```

### Mock Boundaries

```python
# Bad: Mocking internal implementation
@patch("myapp.service._calculate_tax")  # Internal detail
def test_order_total(mock_tax):
    ...

# Good: Mocking external boundary
@patch("myapp.service.tax_api.get_rate")  # External service
def test_order_total(mock_api):
    ...
```

---

## Organization

### File Structure

```
tests/
├── conftest.py
├── unit/
│   └── test_<module>.py      # Mirror src/ structure
├── integration/
│   └── test_<feature>.py     # Test feature workflows
└── fixtures/
    └── data/                 # Test data files
```

### Parametrize vs Separate Tests

```
Should I parametrize this?
├─ Same assertion logic, different inputs? → Parametrize
├─ Different setup/teardown per case? → Separate tests
├─ Different assertions per case? → Separate tests
├─ Failure in one case helps debug others? → Parametrize
└─ Cases represent different behaviors? → Separate tests
```

```python
# GOOD: Same logic, different inputs → Parametrize
@pytest.mark.parametrize("input,expected", [
    ("", False),
    ("valid@email.com", True),
    ("no-at-sign", False),
])
def test_email_validation(input, expected):
    assert is_valid_email(input) == expected

# GOOD: Different behaviors → Separate tests
def test_valid_user_can_login():
    user = make_user(active=True)
    assert user.login() == "success"

def test_inactive_user_sees_reactivation_prompt():
    user = make_user(active=False)
    result = user.login()
    assert result == "inactive"
    assert "reactivate" in user.last_message
```

---

## Marks

### Standard Marks

```python
# tests/conftest.py
import pytest

# Register custom marks
def pytest_configure(config):
    config.addinivalue_line("markers", "slow: marks tests as slow")
    config.addinivalue_line("markers", "integration: marks integration tests")
    config.addinivalue_line("markers", "external: requires external services")
```

| Mark | Use When | Example |
|------|----------|---------|
| `@pytest.mark.slow` | Test takes >1s | Large data processing |
| `@pytest.mark.integration` | Tests real integrations | Database, filesystem |
| `@pytest.mark.external` | Requires external service | Third-party APIs |
| `@pytest.mark.skip` | Temporarily disabled | `@pytest.mark.skip(reason="...")` |
| `@pytest.mark.xfail` | Known failure | `@pytest.mark.xfail(reason="...")` |

```python
@pytest.mark.slow
@pytest.mark.integration
def test_full_data_pipeline():
    ...
```

---

## Make Targets

```makefile
# Standard test targets
.PHONY: test test-fast test-cov test-integration

test:                    ## Run all tests
	uv run pytest

test-fast:               ## Run fast tests only (skip slow/integration)
	uv run pytest -m "not slow and not integration"

test-cov:                ## Run tests with coverage report
	uv run pytest --cov=src --cov-report=term-missing

test-integration:        ## Run integration tests only
	uv run pytest -m integration

test-watch:              ## Run tests in watch mode (requires pytest-watch)
	uv run ptw
```

Register markers in `pyproject.toml` under `[tool.pytest.ini_options].markers` to avoid warnings. See `resources/EXAMPLES.md` for full configuration.

---

## Concrete Examples

See `resources/EXAMPLES.md` for full implementations of:

- **conftest.py structure** - Root and module-specific organization
- **Health checks** - Graceful skipping when services unavailable
- **Real vs mock fixtures** - Dual fixture pattern for unit/integration
- **Factory fixtures** - Creating test data with defaults
- **Makefile targets** - Complete test workflow commands
- **pyproject.toml** - Full pytest configuration

**Key patterns to note:**
- Health checks (`is_service_available()`) skip tests gracefully when services are down
- Session-scoped real fixtures alongside function-scoped mocks
- Marker-based separation enables fast CI feedback (`test-unit` vs `test-integration`)

---

## Anti-Patterns

| Pattern | Why It Fails | Fix |
|---------|--------------|-----|
| **Testing implementation** | Tests break on refactor even when behavior unchanged | Assert on outputs, not internal calls |
| **Mocking internals** | Every internal change breaks tests | Mock at system boundaries only |
| **Giant fixtures** | Hidden dependencies, can't tell what matters | Factory pattern with explicit variations |
| **No marks on slow tests** | CI blocks, devs skip tests locally | Mark and run fast subset by default |
| **Parametrize different logic** | Cryptic names, painful debugging | Separate tests for different behaviors |
| **100% coverage goal** | Diminishing returns past 80% | Cover critical paths and edge cases |

See `resources/EXAMPLES.md#anti-pattern-code-examples` for before/after code examples of the top 3 anti-patterns.
