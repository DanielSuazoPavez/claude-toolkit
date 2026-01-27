# Testing Patterns - Concrete Examples

Reference implementations for common testing scenarios.

## Table of Contents

1. [conftest.py Structure](#conftestpy-structure)
2. [Health Checks for Graceful Skipping](#health-checks-for-graceful-skipping)
3. [Real vs Mock Client Fixtures](#real-vs-mock-client-fixtures)
4. [Sample Data Fixtures](#sample-data-fixtures)
5. [Test Class Organization](#test-class-organization)
6. [Makefile Targets](#makefile-targets)
7. [pyproject.toml Configuration](#pyprojecttoml-configuration)
8. [Anti-Pattern Code Examples](#anti-pattern-code-examples)

---

## conftest.py Structure

### Root conftest.py

```python
# tests/conftest.py
"""Shared fixtures for all tests."""
import pytest
from unittest.mock import MagicMock


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "unit: marks tests as unit tests")
    config.addinivalue_line("markers", "integration: marks integration tests")
    config.addinivalue_line("markers", "slow: marks tests as slow (>1s)")
    config.addinivalue_line("markers", "external: requires external services")


# Health check helpers
def is_database_available() -> bool:
    """Check if database is accessible."""
    try:
        # Replace with your connection logic
        from myapp.db import get_connection
        conn = get_connection()
        conn.execute("SELECT 1")
        return True
    except Exception:
        return False


# Session-scoped real fixtures
@pytest.fixture(scope="session")
def db_connection():
    """Real database connection, skipped if unavailable."""
    if not is_database_available():
        pytest.skip("Database not available")
    from myapp.db import get_connection
    conn = get_connection()
    yield conn
    conn.close()


# Function-scoped mocks
@pytest.fixture
def mock_db_connection():
    """Mock database connection for unit tests."""
    mock = MagicMock()
    mock.execute.return_value = []
    mock.fetchone.return_value = None
    mock.fetchall.return_value = []
    return mock


# Deterministic time fixture
@pytest.fixture
def fixed_timestamp():
    """Fixed timestamp for reproducible tests."""
    from datetime import datetime, timezone
    return datetime(2024, 6, 15, 12, 0, 0, tzinfo=timezone.utc)
```

### Module-specific conftest.py

```python
# tests/integration/conftest.py
"""Integration test fixtures."""
import pytest


@pytest.fixture(scope="module")
def test_schema(db_connection):
    """Create and clean up test schema."""
    db_connection.execute("CREATE SCHEMA IF NOT EXISTS test_schema")
    yield "test_schema"
    db_connection.execute("DROP SCHEMA test_schema CASCADE")
```

---

## Health Checks for Graceful Skipping

Pattern for tests that require external services:

```python
import socket


def is_service_available(host: str, port: int, timeout: float = 1.0) -> bool:
    """TCP health check for external service."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        sock.close()
        return True
    except (socket.error, socket.timeout):
        return False


def is_http_service_available(url: str, timeout: float = 2.0) -> bool:
    """HTTP health check for web services."""
    import urllib.request
    try:
        req = urllib.request.Request(url, method="HEAD")
        urllib.request.urlopen(req, timeout=timeout)
        return True
    except Exception:
        return False


# Usage in fixture
@pytest.fixture(scope="session")
def api_client():
    """Real API client, skipped if service unavailable."""
    if not is_service_available("localhost", 8080):
        pytest.skip("API service not available at localhost:8080")
    from myapp.client import APIClient
    return APIClient("http://localhost:8080")
```

---

## Real vs Mock Client Fixtures

Dual fixture pattern for unit vs integration tests:

```python
@pytest.fixture(scope="session")
def real_client():
    """Real client for integration tests."""
    if not is_service_available("localhost", 9200):
        pytest.skip("Service not available")
    from myapp.client import Client
    client = Client(host="localhost", port=9200)
    yield client
    client.close()


@pytest.fixture
def mock_client():
    """Mock client for unit tests."""
    client = MagicMock()
    client.get.return_value = {"status": "ok"}
    client.post.return_value = {"id": "123"}
    client.info.return_value = {"version": "1.0.0"}
    return client


# Tests use the appropriate fixture
@pytest.mark.unit
def test_process_response(mock_client):
    """Unit test with mock."""
    mock_client.get.return_value = {"data": [1, 2, 3]}
    result = process(mock_client)
    assert result == [1, 2, 3]


@pytest.mark.integration
def test_real_connection(real_client):
    """Integration test with real service."""
    info = real_client.info()
    assert "version" in info
```

---

## Sample Data Fixtures

### Simple Data Fixture

```python
@pytest.fixture
def sample_user():
    """Standard test user."""
    return {
        "id": 1,
        "name": "Test User",
        "email": "test@example.com",
        "active": True,
    }
```

### Factory Fixture

```python
@pytest.fixture
def make_user():
    """Factory for creating test users with defaults."""
    _counter = [0]  # Mutable for unique IDs

    def _make_user(
        name: str = "test",
        email: str | None = None,
        active: bool = True,
        **overrides,
    ):
        _counter[0] += 1
        return {
            "id": _counter[0],
            "name": name,
            "email": email or f"{name}@example.com",
            "active": active,
            **overrides,
        }
    return _make_user


def test_inactive_users(make_user):
    users = [make_user(active=False) for _ in range(3)]
    assert all(not u["active"] for u in users)
    assert len({u["id"] for u in users}) == 3  # Unique IDs
```

### Complex Nested Data

```python
@pytest.fixture
def sample_order(make_user):
    """Complete order with nested objects."""
    return {
        "id": "order-001",
        "user": make_user(name="buyer"),
        "items": [
            {"product_id": "prod-1", "quantity": 2, "price": 10.00},
            {"product_id": "prod-2", "quantity": 1, "price": 25.00},
        ],
        "total": 45.00,
        "status": "pending",
    }
```

---

## Test Class Organization

```python
@pytest.mark.unit
class TestUserValidation:
    """Tests for user validation logic."""

    def test_valid_email_accepted(self, make_user):
        user = make_user(email="valid@example.com")
        assert validate_user(user) is True

    def test_invalid_email_rejected(self, make_user):
        user = make_user(email="not-an-email")
        assert validate_user(user) is False

    def test_empty_name_rejected(self, make_user):
        user = make_user(name="")
        assert validate_user(user) is False


@pytest.mark.integration
class TestUserRepository:
    """Integration tests for user persistence."""

    def test_create_and_retrieve(self, db_connection, make_user):
        user = make_user()
        repo = UserRepository(db_connection)

        created = repo.create(user)
        retrieved = repo.get(created["id"])

        assert retrieved["name"] == user["name"]

    def test_update_email(self, db_connection, make_user):
        user = make_user()
        repo = UserRepository(db_connection)

        created = repo.create(user)
        repo.update(created["id"], email="new@example.com")
        retrieved = repo.get(created["id"])

        assert retrieved["email"] == "new@example.com"
```

---

## Makefile Targets

```makefile
.PHONY: test test-unit test-integration test-cov test-fast lint check

test:                    ## Run all tests
	uv run pytest tests/ -v

test-unit:               ## Run unit tests only
	uv run pytest tests/ -v -m unit

test-integration:        ## Run integration tests only
	uv run pytest tests/ -v -m integration

test-fast:               ## Run fast tests (skip slow and integration)
	uv run pytest tests/ -v -m "not slow and not integration"

test-cov:                ## Run tests with coverage
	uv run pytest tests/ -v --cov=src --cov-report=term-missing --cov-report=html

test-watch:              ## Run tests in watch mode
	uv run ptw -- tests/ -v

lint:                    ## Run linting
	uv run pre-commit run --all-files

check: lint test-unit    ## Run lint + unit tests (CI fast check)
```

---

## pyproject.toml Configuration

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v --tb=short"
markers = [
    "unit: marks tests as unit tests (no external dependencies)",
    "integration: marks tests as integration tests (require running services)",
    "slow: marks tests as slow (>1s)",
    "external: requires external services (APIs, etc.)",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=4.0",
]
```

---

## Anti-Pattern Code Examples

### Testing Implementation (The #1 Mistake)

```python
# BAD: Testing HOW it works (implementation)
def test_calculate_total(mock_tax_calculator):
    order = Order(items=[{"price": 100}])
    order.calculate_total()

    # Breaks if you refactor to use a different tax method
    mock_tax_calculator.get_rate.assert_called_once_with("US")
    mock_tax_calculator.apply.assert_called_once()

# GOOD: Testing WHAT it does (behavior)
def test_calculate_total():
    order = Order(items=[{"price": 100}])

    total = order.calculate_total()

    # Survives any refactor that preserves behavior
    assert total == 108.00  # 100 + 8% tax
```

### Mocking at Wrong Level

```python
# BAD: Mocking internal implementation detail
@patch("myapp.orders._apply_discount")  # Private function
@patch("myapp.orders._validate_items")   # Private function
def test_process_order(mock_validate, mock_discount):
    ...  # Breaks when internals change

# GOOD: Mocking at system boundary
@patch("myapp.orders.payment_gateway.charge")  # External service
def test_process_order(mock_charge):
    mock_charge.return_value = {"status": "success", "id": "pay_123"}

    result = process_order(order)

    assert result.payment_id == "pay_123"
```

### Giant Fixture vs Factory

```python
# BAD: Monolithic fixture with everything
@pytest.fixture
def user():
    return User(
        id=1, name="Test", email="test@example.com",
        role="admin", department="engineering",
        manager_id=5, hire_date="2020-01-01",
        # ... 20 more fields
    )

def test_user_can_approve(user):
    # Which fields matter for this test? No idea.
    assert user.can_approve(request)

# GOOD: Factory with explicit variations
@pytest.fixture
def make_user():
    def _make(role="member", **overrides):
        defaults = {"id": 1, "name": "Test", "email": "t@example.com"}
        return User(**{**defaults, "role": role, **overrides})
    return _make

def test_admin_can_approve(make_user):
    admin = make_user(role="admin")  # Clear: role matters
    assert admin.can_approve(request)

def test_member_cannot_approve(make_user):
    member = make_user(role="member")  # Clear: role matters
    assert not member.can_approve(request)
```
