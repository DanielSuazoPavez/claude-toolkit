# Pytest Troubleshooting

Common pytest failures that waste debugging time.

## Fixture Not Found

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

## Import Errors at Collection

```
E ModuleNotFoundError: No module named 'myapp'
```

| Cause | Fix |
|-------|-----|
| Missing `__init__.py` in `tests/` | Add it, or use `--import-mode=importlib` in pytest config |
| Running pytest from wrong directory | Run from project root, or set `rootdir` in config |
| Package not installed in editable mode | `uv pip install -e .` or `uv run pytest` |
| `src/` layout without `src` in path | Add `pythonpath = ["src"]` to `[tool.pytest.ini_options]` |

## Fixture Cleanup Failures

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

## Flaky Tests

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
