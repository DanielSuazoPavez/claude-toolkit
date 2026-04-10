# tests/

Two runners: bash scripts (`test-*.sh`) and pytest (`test_*.py`). Run both via `make test`.

General testing conventions (shared across projects): `.claude/docs/relevant-conventions-testing.md`

## Files

| File | What it tests | Runner |
|------|--------------|--------|
| `test-hooks.sh` | All hook scripts (block/allow cases via JSON stdin) | bash |
| `test-cli.sh` | `bin/claude-toolkit` sync/send commands | bash |
| `test-backlog-query.sh` | Backlog query script | bash |
| `test-evaluation-query.sh` | Evaluation query script | bash |
| `test-raiz-changelog.sh` | Raiz changelog formatter (`format-raiz-changelog.sh`) | bash |
| `test-raiz-publish.sh` | Raiz distribution builder (`publish.py`) | bash |
| `test-setup-toolkit-diagnose.sh` | Diagnostic script (40 tests, base + raiz) | bash |
| `test-validate-hook-utils.sh` | `lib/hook-utils.sh` shared library | bash |
| `test-verify-external-deps.sh` | External tool dependency checker | bash |
| `test-validate-resources-indexed.sh` | Resource index completeness | bash |
| `test_lesson_db.py` | Lessons database (Python, 28 tests) | pytest |
| `perf-session-start.sh` | Session-start hook performance benchmark | bash |
| `perf-surface-lessons.sh` | Surface-lessons hook performance benchmark | bash |

## Shared Helpers

`lib/test-helpers.sh` — sourced by all bash tests. Provides:
- `parse_test_args` — `-v` verbose, `-q` quiet
- `report_pass` / `report_fail` / `report_detail` — colored output
- `report_section` — section headers (buffered in quiet mode)
- `print_summary` — final counts + exit code

## Running

```bash
make test                              # all tests (bash + pytest)
make test-hooks                        # hook tests only
make test-cli                          # CLI tests only
make check                             # tests + validations
bash tests/test-hooks.sh secrets       # filter by hook name
bash tests/test-hooks.sh -v            # verbose
```

## Perf Benchmarks

`perf-*.sh` files measure hook execution time. Not included in `make test` — run manually. Set `HOOK_PERF=1` to enable per-phase timing probes in hooks.
