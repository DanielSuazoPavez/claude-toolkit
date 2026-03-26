---
name: design-tests
type: knowledge
description: Use when writing or reviewing Python tests with pytest. Use when requests mention "pytest", "fixtures", "mocking", "conftest", "parametrize", "pytest structure", "missing pytest tests", "pytest audit", "coverage audit", "pytest test plan", "pytest QA strategy", "pytest regression testing", "release testing".
---

# Test Design Guide

Consistent pytest patterns for reliable, maintainable tests.

## What Are You Doing?

```
What's the testing task?
├─ Starting from scratch / greenfield test plan?
│   → Read resources/QA_STRATEGY.md first for planning framework
│   → Then return here for implementation patterns
│
├─ Reviewing or auditing existing test coverage?
│   → Read resources/QA_STRATEGY.md for risk assessment and release readiness
│   → Use Audit Mode below for gap analysis
│
├─ Adding tests for a specific feature or change?
│   → Use Test Priority Framework below to decide what to test
│   → May skim resources/QA_STRATEGY.md § Test Debt Signals if unsure about coverage depth
│
└─ Debugging test failures?
    → See resources/TROUBLESHOOTING.md
```

## Table of Contents

1. [Test Priority Framework](#test-priority-framework)
2. [Test Debt Signals](#test-debt-signals)
3. [Audit Mode — Gap Analysis](#audit-mode--gap-analysis)
4. [Fixtures](#fixtures)
5. [Mocking](#mocking)
6. [Async Testing](#async-testing)
7. [High-Risk Scenarios](#high-risk-scenarios)
8. [Anti-Patterns](#anti-patterns)
9. [Concrete Examples](#concrete-examples)

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

### Estimating Test Coverage Time

**Quick estimation formula**: `(features × 2) + (integrations × 3) + (risk_factors × 4)` hours

| Component | Smoke (min) | Full (hours) |
|-----------|-------------|--------------|
| Simple CRUD feature | 15 | 2-4 |
| Payment integration | 30 | 4-8 |
| Auth/permissions | 30 | 4-6 |
| File upload/export | 20 | 2-3 |
| Third-party API | 45 | 6-8 |

**Multipliers**: Mobile +50%, accessibility +30%, i18n +20% per locale

---

## Test Debt Signals

Push back on shipping without tests when you see these:
- **Changelog churn**: Same module appears in 3+ recent bug fixes — accumulating debt faster than paying it down
- **Tribal knowledge gates**: Only one person knows how to test a feature — unwritten coverage with a bus factor of 1
- **"It worked on my machine" frequency**: >2 occurrences/sprint means environment-dependent behavior isn't covered
- **Regression recidivism**: A bug you fixed last month is back — the fix wasn't verified with a regression test

**Debt accumulation rate**: Each shipped feature without tests adds ~1.5x its original test effort as future debt. Three consecutive untested sprints typically means a dedicated test-writing sprint is cheaper than continued ad-hoc fixing.

---

## Audit Mode — Gap Analysis

Code-level audit: maps source files to pytest files, flags missing test cases. For strategic planning (release readiness, regression tiers, risk-based prioritization), see `resources/QA_STRATEGY.md`.

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

### Slow Tests? Check Fixture Scope

When test suites are slow, the most common fix is broadening fixture scope — expensive setup running per-test when it could run once:

```
Tests are slow. Is a fixture the cause?
├─ Does the fixture hit a DB, API, or filesystem?
│   ├─ Do tests only READ the data? → Widen to session/module
│   ├─ Do tests WRITE but can rollback? → function with rollback (see High-Risk Scenarios)
│   └─ Do tests WRITE and can't rollback? → function (pay the cost)
├─ Does the fixture build a large object (model, dataset, index)?
│   ├─ Tests use it as-is, no mutation? → session
│   └─ Tests modify it? → Copy per-test from a session-scoped original
└─ Is setup fast (<100ms) but there are 500+ tests?
    ├─ Parametrize explosion or I/O in test bodies? → Fix those first
    └─ Tests are genuinely independent? → Consider `pytest-xdist` (-n auto)
```

**Diagnosis**: Run `pytest --durations=20` to find the slowest tests, then check which fixtures they share. If the same fixture appears across many slow tests, it's a scoping candidate.

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

**Prefer dependency injection** over `@patch`. Use `@patch` only for legacy code without DI. Always mock at your boundary (`myapp.service.tax_api.get_rate`), never at internals (`myapp.service._calculate_tax`).

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
| **Fixture scope pollution** | `session`/`module` fixture mutated by one test, breaks others non-deterministically | Use `function` scope for mutable state; reserve broader scopes for read-only or connection fixtures |
| **conftest.py at wrong level** | Fixtures in root conftest shared everywhere — tests implicitly depend on unrelated setup | Put fixtures in the narrowest conftest that covers their consumers; root conftest only for truly global fixtures (DB connection, app factory) |
| **`__init__.py` with re-exports** | Makes import graphs opaque, hides where things actually live | Keep `__init__.py` to wiring only — no re-exports. Tests should import directly from submodules |
| **Copy-paste test plans** | Reused plans miss feature-specific risks | Start from risk analysis, not templates |
| **Conflating severity with priority** | P1 cosmetic bugs block release while P3 data loss waits | Severity = impact, priority = business urgency |
| **Testing everything equally** | 200 test cases, all medium priority | Risk-weight: P0 exhaustive, P3 smoke only |

## Rationalizations

| Rationalization | Counter |
|-----------------|---------|
| "Too simple to need tests" | Simple code breaks at boundaries. The test takes 30 seconds — the debugging takes 30 minutes. |
| "I'll add tests after the implementation" | You won't. And tests-after verify what you wrote, not what you intended. Write the test first. |
| "I already verified it works" | You verified the happy path once. Tests verify edge cases every time, automatically. |
| "This is just glue code" | Glue fails silently — wrong argument order, missing await, swapped parameters. Integration bugs are the hardest to trace. |
| "The function is too hard to test" | Hard to test = hard to use. The test is telling you the interface needs work. Listen to it. |
| "Existing code has no tests" | You're touching it now. Add tests for what you change — don't inherit the debt. |
| "These edge cases are unlikely" | Unlikely × high-impact = P1. Check the risk matrix. |
| "The code looks correct, no need to test" | Code review finds logic errors. Testing finds integration errors. Different coverage. |
| "We'll catch it in production" | Production bugs cost 10x. Test environment exists for a reason. |
| "We don't have time to test everything" | That's what prioritization is for. P0 paths get 100%, P3 gets skipped with documented risk. |

## See Also

- `code-reviewer` agent — May flag missing tests or over-testing during code review.
- `/design-db` — Schema and migration design; complements the DB transaction testing section.
- `/design-docker` — Testing containerized services and CI/CD pipeline test configuration.
- `/refactor` — If test structure needs updating after module reorganization.
