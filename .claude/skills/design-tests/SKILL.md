---
name: design-tests
description: Use when writing or reviewing tests. Use when requests mention "pytest", "fixtures", "mocking", "conftest", "parametrize", "test organization", "test gaps", "test audit", or "coverage audit".
---

# Test Design Guide

Consistent pytest patterns for reliable, maintainable tests.

## Mindset: Tests Are Specifications

Tests are not verification — they are **executable specifications** of behavior contracts. A well-written test suite is the most accurate documentation of what your code promises to do.

This changes how you write them:
- **Name tests for the behavior**, not the function: `test_expired_token_returns_401` not `test_validate_token`
- **A broken test means the contract changed** — decide if the contract or the code is wrong before touching either
- **Missing test = undocumented behavior** — if it's not tested, it's not promised

## Table of Contents

1. [Test Priority Framework](#test-priority-framework)
2. [Audit Mode — Gap Analysis](#audit-mode--gap-analysis)
3. [Fixtures](#fixtures)
4. [Mocking](#mocking)
5. [Async Testing](#async-testing)
6. [High-Risk Scenarios](#high-risk-scenarios)
7. [Troubleshooting](#troubleshooting)
8. [Concrete Examples](#concrete-examples)
9. [Anti-Patterns](#anti-patterns)

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

## Audit Mode — Gap Analysis

Use when asked to audit, review, or find gaps in existing test coverage.

### Process

#### 1. Map Source to Tests

Build a mapping of every source module to its test file(s):

```
src/auth/login.py        → tests/unit/test_login.py ✓
src/auth/permissions.py  → tests/unit/test_permissions.py ✓
src/payments/checkout.py → (no test file) ✗
src/payments/refund.py   → tests/unit/test_refund.py ✓
src/utils/helpers.py     → (no test file, orchestration — OK)
```

Classify each unmapped file using the Priority Framework:
- Business logic with no tests → **GAP (high priority)**
- I/O boundary with no tests → **GAP (medium priority)**
- Orchestration/glue with no tests → **Acceptable** (note it, don't flag)

#### 2. Audit Existing Tests for Missing Cases

For each test file that exists, check:

```
Does this test file cover...?
├─ Happy path                    → Basic functionality works
├─ Error/exception paths         → What happens when things fail
├─ Boundary conditions           → Empty input, max values, off-by-one
├─ State transitions             → Before/after for stateful operations
└─ Concurrency (if applicable)   → Race conditions, deadlocks
```

Flag specific missing cases, not vague "needs more tests":
- "test_checkout.py: no test for expired payment method"
- "test_login.py: no test for concurrent session limit"

#### 3. Output Format

```markdown
## Test Coverage Audit — <project>

### Summary
- Source files: X
- Test files: Y
- Coverage gaps: Z (N high priority)

### Missing Test Files (High Priority)
| Source File | Code Type | Why It Matters |
|-------------|-----------|----------------|
| src/payments/checkout.py | Business logic | Core revenue path, untested |

### Missing Test Cases in Existing Files
| Test File | Missing Case | Priority |
|-----------|-------------|----------|
| test_login.py | Expired session token | High — security boundary |
| test_refund.py | Partial refund rounding | Medium — edge case |

### Acceptable Gaps
- src/utils/helpers.py — orchestration only, no business logic
- src/config.py — read-only config loading

### Recommended Next Steps
1. (highest impact first)
2. ...
```

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

### Factory Pattern

Use factories when tests need variations of the same object:

```python
@pytest.fixture
def make_user():
    """Factory for creating test users with defaults."""
    def _make_user(name="test", email=None, active=True):
        return User(name=name, email=email or f"{name}@test.com", active=active)
    return _make_user
```

**Rule:** Put fixtures in the narrowest conftest.py scope where they're needed.

See `resources/EXAMPLES.md` for conftest.py structure, health checks, dual real/mock fixtures, and factory patterns.

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

**Prefer dependency injection** over `@patch` — it makes dependencies explicit and tests clearer. Use `@patch` only for legacy code without DI.

```python
# Mock at your boundary, not theirs
@patch("myapp.service.tax_api.get_rate")  # Good: external boundary
def test_order_total(mock_api): ...

@patch("myapp.service._calculate_tax")  # Bad: internal detail
def test_order_total(mock_tax): ...
```

---

## Async Testing

Use `asyncio_mode = "auto"` in `pyproject.toml` to avoid decorating every test with `@pytest.mark.asyncio`.

```python
# Async factory with proper cleanup — fixture must be async for await in teardown
@pytest.fixture
async def make_async_client():
    clients = []
    def _make(**kwargs):
        client = AsyncClient(**kwargs)
        clients.append(client)
        return client
    yield _make
    for client in clients:
        await client.aclose()
```

### Gotchas

| Gotcha | Fix |
|--------|-----|
| Mixing sync/async fixtures | Async fixture can use sync fixtures, not vice versa |
| Sync factory with async cleanup | Make the factory fixture itself `async` (see above) |
| Event loop scope mismatch | Match `loop_scope` to fixture scope in `pytest.ini` |
| `asyncio_mode = "strict"` | Requires `@pytest.mark.asyncio` on every test — prefer `"auto"` |

---

## High-Risk Scenarios

Prescriptive patterns for code where under-testing causes real damage.

### Database Transactions

```python
@pytest.fixture
async def db_session(async_engine):
    """Each test runs in a rolled-back transaction — no data leaks."""
    async with async_engine.connect() as conn:
        trans = await conn.begin()
        session = AsyncSession(bind=conn)
        yield session
        await trans.rollback()  # Always rollback, even if test passes

# Test MUST verify both commit and rollback paths
async def test_transfer_funds(db_session, make_account):
    sender = make_account(balance=100)
    receiver = make_account(balance=0)

    await transfer(db_session, sender.id, receiver.id, amount=50)

    assert (await get_balance(db_session, sender.id)) == 50
    assert (await get_balance(db_session, receiver.id)) == 50

async def test_transfer_insufficient_funds_rolls_back(db_session, make_account):
    sender = make_account(balance=30)
    receiver = make_account(balance=0)

    with pytest.raises(InsufficientFunds):
        await transfer(db_session, sender.id, receiver.id, amount=50)

    # Verify no partial state change
    assert (await get_balance(db_session, sender.id)) == 30
    assert (await get_balance(db_session, receiver.id)) == 0
```

**Rule:** For any write operation, test both the success path AND the failure-rollback path. Partial state is the bug you won't catch otherwise.

### Authentication & Authorization

Always test:
- Valid credentials → access granted
- Invalid credentials → access denied (not just "error")
- Expired token → specific error, not generic 500
- Missing permissions → 403, not 404 (don't leak resource existence)
- Privilege escalation → user A can't access user B's resources

```python
def test_user_cannot_access_other_users_data(auth_client, make_user):
    user_a = make_user()
    user_b = make_user()
    client = auth_client(as_user=user_a)

    response = client.get(f"/users/{user_b.id}/settings")
    assert response.status_code == 403  # Not 404
```

### External API Calls

Test these failure modes — they will happen in production:

```python
@pytest.mark.parametrize("error,expected", [
    (httpx.TimeoutException("timeout"), "Service temporarily unavailable"),
    (httpx.HTTPStatusError("", request=mock_req, response=mock_429), "Rate limited"),
    (httpx.ConnectError("refused"), "Service temporarily unavailable"),
])
def test_api_failure_modes(mock_client, error, expected):
    mock_client.get.side_effect = error
    result = fetch_with_fallback(mock_client, "/data")
    assert result.error_message == expected
```

---

## Troubleshooting

Common pytest failures that waste debugging time.

### Fixture Not Found

```
E fixture 'my_fixture' not found
```

```
Is conftest.py in the right directory?
├─ Same directory as test file? → Should work
├─ Parent directory? → Should work (pytest walks up)
├─ Sibling directory? → Won't work — fixtures don't cross branches
└─ Is conftest.py actually named conftest.py? → Check spelling, no prefix
```

**Key rule:** `conftest.py` fixtures are available to tests in the same directory and all subdirectories, never sideways.

### Import Errors at Collection

```
E ModuleNotFoundError: No module named 'myapp'
```

| Cause | Fix |
|-------|-----|
| Missing `__init__.py` in `tests/` | Add it, or use `--import-mode=importlib` in pytest config |
| Running pytest from wrong directory | Run from project root, or set `rootdir` in config |
| Package not installed in editable mode | `uv pip install -e .` or `uv run pytest` |
| `src/` layout without `src` in path | Add `pythonpath = ["src"]` to `[tool.pytest.ini_options]` |

### Fixture Cleanup Failures

When fixture teardown raises, it masks the real test failure:

```python
# Bad: cleanup can fail and hide the actual error
@pytest.fixture
def temp_file():
    path = Path("/tmp/test.txt")
    path.write_text("data")
    yield path
    path.unlink()  # Fails if test already deleted it

# Good: defensive cleanup
@pytest.fixture
def temp_file(tmp_path):  # Use pytest's tmp_path — auto-cleaned
    path = tmp_path / "test.txt"
    path.write_text("data")
    yield path
    # No manual cleanup needed
```

**Rule:** Use `tmp_path`/`tmp_path_factory` for filesystem fixtures. For DB/network, wrap cleanup in try/finally.

### Flaky Tests

```
Is the test flaky?
├─ Fails only in CI, passes locally?
│   ├─ Timing-dependent? → Use `freezegun` or `time_machine`, not `time.sleep`
│   └─ Port/file conflicts? → Use random ports, `tmp_path`
├─ Fails intermittently everywhere?
│   ├─ Shared mutable state between tests? → Check fixture scope, use `function` scope
│   └─ Test order dependency? → Run with `pytest-randomly` to expose it
└─ Fails only with `-x` (fail-fast)?
    └─ Previous test's teardown is broken → Check fixture cleanup
```

---

## Anti-Patterns

See `resources/EXAMPLES.md` for before/after code examples of the top 3 anti-patterns.

| Pattern | Why It Fails | Fix |
|---------|--------------|-----|
| **Testing implementation** | Tests break on refactor even when behavior unchanged | Assert on outputs, not internal calls |
| **Mocking internals** | Every internal change breaks tests | Mock at system boundaries only |
| **Giant fixtures** | Hidden dependencies, can't tell what matters | Factory pattern with explicit variations |
| **No marks on slow tests** | CI blocks, devs skip tests locally | Mark and run fast subset by default |
| **Parametrize different logic** | Cryptic names, painful debugging | Separate tests for different behaviors |
| **100% coverage goal** | Diminishing returns past 80% | Cover critical paths and edge cases |
| **Testing only happy path** | Misses rollback bugs, auth bypasses, API failures | See [High-Risk Scenarios](#high-risk-scenarios) |
