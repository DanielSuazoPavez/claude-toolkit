# tests/

Two runners: bash scripts (`test-*.sh`) and pytest (`test_*.py`). Run both via `make test`.

General testing conventions (shared across projects): `.claude/docs/relevant-conventions-testing.md`

## Files

| File | What it tests | Runner |
|------|--------------|--------|
| `run-all.sh` | Unified top-level runner: dispatches all bash suites + pytest in parallel, single summary | bash |
| `hooks/test-*.sh` | Per-hook tests (one file per hook/dispatcher); run via `run-hook-tests.sh` | bash |
| `run-hook-tests.sh` | Parallel runner for `hooks/test-*.sh`, with per-file summary | bash |
| `test-cli.sh` | `bin/claude-toolkit` sync/send commands | bash |
| `test-backlog-query.sh` | Backlog query script | bash |
| `test-docs-query.sh` | Docs query script (`claude-toolkit docs`) | bash |
| `test-evaluation-query.sh` | Evaluation query script | bash |
| `test_format_raiz_changelog.py` | Raiz changelog formatter (`format-raiz-changelog.py`) | pytest |
| `test-raiz-publish.sh` | Raiz distribution builder (`publish.py`) | bash |
| `test-setup-toolkit-diagnose.sh` | Diagnostic script (40 tests, base + raiz) | bash |
| `test-sync-then-validate.sh` | End-to-end: real `sync` into fixture, then `validate-all.sh` + diagnose + orphan detection | bash |
| `test-validate-hook-utils.sh` | `lib/hook-utils.sh` shared library | bash |
| `test-verify-external-deps.sh` | External tool dependency checker | bash |
| `test-validate-resources-indexed.sh` | Resource index completeness | bash |
| `test_lesson_db.py` | Lessons database (Python, 40 tests) | pytest |
| `perf-session-start.sh` | Session-start hook performance benchmark | bash |
| `perf-surface-lessons.sh` | Surface-lessons hook performance benchmark | bash |

## Shared Helpers

`lib/test-helpers.sh` — sourced by all bash tests. Provides:
- `parse_test_args` — `-v` verbose, `-q` quiet
- `report_pass` / `report_fail` / `report_detail` — colored output
- `report_section` — section headers (buffered in quiet mode)
- `print_summary` — final counts + exit code
- `expect_block` / `expect_allow` / `expect_approve` / `expect_silent` / `expect_contains` — hook-expectation helpers (require `$HOOKS_DIR`)

`lib/hook-test-setup.sh` — sourced by `hooks/test-*.sh`. Sets `HOOKS_DIR` and redirects `CLAUDE_ANALYTICS_HOOKS_DIR` to a per-process temp directory so production hook-logs JSONL files are never touched. Exports `TEST_INVOCATIONS_JSONL`, `TEST_SURFACE_LESSONS_JSONL`, `TEST_SESSION_START_JSONL` for assertions. Each sourcing process gets its own dir, so the parallel runner has no contention.

## Hook tests layout

```
tests/hooks/
├── test-approve-safe.sh            # approve-safe-commands.sh
├── test-block-config.sh            # block-config-edits.sh
├── test-block-dangerous.sh         # block-dangerous-commands.sh
├── test-call-id.sh                 # call_id capture (hook-utils.sh)
├── test-enforce-make.sh            # enforce-make-commands.sh
├── test-enforce-uv.sh              # enforce-uv-run.sh
├── test-git-safety.sh              # git-safety.sh
├── test-grouped-bash.sh            # grouped-bash-guard.sh dispatcher
├── test-grouped-read.sh            # grouped-read-guard.sh dispatcher
├── test-secrets-guard.sh           # secrets-guard.sh
├── test-session-id.sh              # session_id propagation (hook-utils.sh)
├── test-session-start.sh           # session-start.sh lesson surfacing (Key/Recent dropped, branch-lesson protected-branch gate, ack suffix)
├── test-session-start-source.sh    # SessionStart .source capture
└── test-suggest-json.sh            # suggest-read-json.sh
```

Each file is standalone: source helpers + setup, run assertions at top level, call `print_summary`.

## Running

```bash
make test                              # all suites via run-all.sh (bash + pytest, parallel, unified summary)
make test-hooks                        # parallel hook tests (via run-hook-tests.sh -q)
make test-cli                          # CLI tests only
make test-pytest                       # pytest only
make check                             # tests + validations
bash tests/run-all.sh -v               # verbose pass-through to all suites
bash tests/run-all.sh cli              # filter: only suites whose label contains "cli"
TEST_JOBS=1 bash tests/run-all.sh      # sequential (debugging)
bash tests/run-hook-tests.sh secrets   # filter hook tests: basename contains "secrets"
HOOK_TEST_JOBS=1 bash tests/run-hook-tests.sh   # hook tests sequential
bash tests/hooks/test-secrets-guard.sh # run one file directly
```

`run-all.sh` treats `run-hook-tests.sh` and `pytest` as single aggregate units in its summary — if pytest fails, re-run `make test-pytest` (or `uv run pytest`) standalone to drill into the Python tests.

Runner aggregation relies on per-file exit codes only. Each failing file's full log is dumped under its own header after the summary. Per-file logs land in `tests/.logs/` (gitignored).

## Perf Baseline

`make test` wall is bounded by **the slowest single hook test file** — parallel runner saturates a 4-core box, so wall ≈ max(per-file). Baseline as of 2026-04-27 (post `tests-perf-review`):

- `make test` wall: ~65–75s
- Pytest standalone (`uv run pytest`): ~7s wall (88 tests)
- `test_lesson_db.py` standalone: ~3s pytest / ~4s wall (40 tests, was ~7s before fixture-scope tightening)
- Hook-test ceiling: slowest file ~40s wall under parallel load

Drift signals to watch: pytest standalone > 12s, slowest hook file > 50s, total wall > 90s. See `output/claude-toolkit/analysis/20260426_1702__analyze-idea__tests-perf-review.md` for the full breakdown.

## Perf Benchmarks

`perf-*.sh` files measure hook execution time. Not included in `make test` — run manually. Set `CLAUDE_TOOLKIT_HOOK_PERF=1` to enable per-phase timing probes in hooks.
