# tests/

Two runners: bash scripts (`test-*.sh`) and pytest (`test_*.py`). Run both via `make test`.

General testing conventions (shared across projects): `.claude/docs/relevant-conventions-testing.md`

## Files

| File | What it tests | Runner |
|------|--------------|--------|
| `run-all.sh` | Unified top-level runner: dispatches all bash suites + pytest in parallel, single summary | bash |
| `hooks/test-*.sh` | Per-hook tests (one file per hook/dispatcher); run via `run-hook-tests.sh` | bash |
| `run-hook-tests.sh` | Parallel runner for `hooks/test-*.sh`, with per-file summary | bash |
| `hooks/run-smoke.sh` | Replays one fixture under env-isolated sandbox; emits `kind:smoketest` row | bash |
| `hooks/run-smoke-all.sh` | Walks `hooks/fixtures/<hook>/*.json` and invokes `run-smoke.sh` per fixture | bash |
| `hooks/fixtures/<hook>/<case>.{json,expect}` | Smoke fixtures: stdin payload + outcome assertions per hook | data |
| `hooks/fixtures/_templates/` | Reference stdin templates (one per `(event, primary-tool)` — V18 ignores) | data |
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
| `test-verify-resource-deps.sh` | Resource cross-reference dependency checker (57 tests, 7 sections + MANIFEST mode) | bash |
| `test-validate-resources-indexed.sh` | Resource index completeness | bash |
| `test_lesson_db.py` | Lessons database (Python, 40 tests) | pytest |
| `perf-session-start.sh` | Session-start hook performance benchmark | bash |
| `perf-surface-lessons.sh` | Surface-lessons hook performance benchmark | bash |

## Three-layer separation: validator tests, real validators, sync-then-validate

Validators (`validate-*.sh`, run by `make validate`) are exercised in three distinct layers. Each catches a different bug class — none is redundant:

| Layer | Inputs | Catches |
|---|---|---|
| `test-validate-*.sh` / `test-verify-*.sh` (in `make test`) | Crafted fixtures: fake `.claude/` trees, missing resources, edge cases | **Validator logic bugs** — false positives, false negatives, silent skips |
| `validate-*.sh` (in `make validate`) | The **real** workshop codebase | **Actual resource drift** — missing index entries, broken refs, real misconfigurations |
| `test-sync-then-validate.sh` (in `make test`) | A consumer fixture populated by a real `claude-toolkit sync` run | **Consumer-side correctness** — validator assumptions that only hold inside the workshop, sync output gaps |

Why all three:

- A validator that passes its **fixture tests** can still mis-flag real resources — fixtures are by design narrow.
- A validator that's clean against the **real codebase** can still break on a freshly synced consumer — the workshop has files (e.g. `BACKLOG.json`, `dist/`) that consumers don't.
- A validator that works in the consumer fixture can still have logic bugs — the fixture is one snapshot, not an exhaustive case set.

Naming convention:
- `validate-foo.sh` — the validator script (under `.claude/scripts/`)
- `test-validate-foo.sh` — fixture-driven tests **of** that validator
- `test-verify-foo.sh` — fixture-driven tests of a `verify-*` script (same pattern, different prefix)

When adding a new validator, add **both** a `test-validate-*.sh` (fixture tests) and ensure it's wired into `validate-all.sh` so `make validate` covers it. `test-sync-then-validate.sh` picks it up automatically through `validate-all.sh`.

## Shared Helpers

`lib/test-helpers.sh` — sourced by all bash tests. Provides:
- `parse_test_args` — `-v` verbose, `-q` quiet
- `report_pass` / `report_fail` / `report_detail` — colored output
- `report_section` — section headers (buffered in quiet mode)
- `print_summary` — final counts + exit code
- `expect_block` / `expect_allow` / `expect_approve` / `expect_silent` / `expect_contains` — hook-expectation helpers (require `$HOOKS_DIR`)

`lib/hook-test-setup.sh` — sourced by `hooks/test-*.sh`. Sets `HOOKS_DIR` and redirects `CLAUDE_ANALYTICS_HOOKS_DIR` to a per-process temp directory so production hook-logs JSONL files are never touched. Exports `TEST_INVOCATIONS_JSONL`, `TEST_SURFACE_LESSONS_JSONL`, `TEST_SESSION_START_JSONL` for assertions. Each sourcing process gets its own dir, so the parallel runner has no contention.

`lib/json-fixtures.sh` — sourced by hook tests that build hook-input payloads. One helper per hook event, all `jq -nc --arg`-backed so embedded quotes/backticks/newlines/`$()`/heredocs round-trip safely:
- `mk_pre_tool_use_payload <tool> <args...>` — dispatches on tool name (`Bash`/`Read`/`Write`/`Edit`/`Grep`) to shape `tool_input`. Unknown tool → returns 2.
- `mk_post_tool_use_payload <sid> <tool> <input_json> <response_json> <tool_use_id> <duration_ms> <cwd>` — all 7 args required; pass `""` for fields you don't care about (except `*_json`/`duration_ms` which must be valid JSON values).
- `mk_session_start_payload [source] [sid]` — `source` only emitted when non-empty.
- `mk_permission_denied_payload <sid> <tool> <input_json> <tool_use_id> <pm> [cwd=/tmp]`.
- `mk_user_prompt_submit_payload <sid> <prompt> [cwd=$(pwd)]`.

Migration exceptions kept inline (do not migrate): payloads exercising parser-error paths (`'not-json'`, `"not valid json at all"`), one-off `EnterPlanMode` single-key payloads, and the negative-shape session_id cases (missing key / explicit JSON null) that the helper can't produce. Each carries a `# do not migrate` comment.

## Hook tests layout

```
tests/hooks/
├── test-approve-safe.sh                    # approve-safe-commands.sh
├── test-auto-mode-shared-steps.sh          # auto-mode shared-step machinery (hook-utils.sh)
├── test-block-config.sh                    # block-config-edits.sh
├── test-block-credential-exfil.sh          # block-credential-exfiltration.sh
├── test-block-dangerous.sh                 # block-dangerous-commands.sh
├── test-call-id.sh                         # call_id capture (hook-utils.sh)
├── test-detect-session-start-truncation.sh # detect-session-start-truncation.sh
├── test-detection-registry.sh              # detection-registry.json schema/integrity
├── test-ecosystems-opt-in.sh               # ecosystem opt-in registry
├── test-enforce-make.sh                    # enforce-make-commands.sh
├── test-enforce-uv.sh                      # enforce-uv-run.sh
├── test-git-safety.sh                      # git-safety.sh
├── test-grouped-bash.sh                    # grouped-bash-guard.sh dispatcher
├── test-grouped-read.sh                    # grouped-read-guard.sh dispatcher
├── test-hook-utils.sh                      # lib/hook-utils.sh shared library
├── test-log-permission-denied.sh           # log-permission-denied.sh
├── test-log-tool-uses.sh                   # log-tool-uses.sh
├── test-match-check-pairs.sh               # matcher↔check-spec pairing invariants
├── test-secrets-guard.sh                   # secrets-guard.sh
├── test-session-id.sh                      # session_id propagation (hook-utils.sh)
├── test-session-start.sh                   # session-start.sh lesson surfacing
├── test-session-start-integrity.sh         # session-start integrity check (settings.local.json drift)
├── test-session-start-source.sh            # SessionStart .source capture
├── test-settings-permissions.sh            # settings.json permission rules
├── test-suggest-json.sh                    # suggest-read-json.sh
├── test-surface-lessons-dedup.sh           # surface-lessons.sh intra-session dedup
└── test-surface-lessons-two-hit.sh         # surface-lessons.sh 2+ keyword-hit threshold
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

`make test` wall is bounded by **the slowest single hook test file** — parallel runner saturates a 4-core box, so wall ≈ max(per-file). Baseline as of 2026-05-04 (post `test-helper-fixture-standardization`):

- `make test` wall: ~45–50s (3-run sample: 48.8s / 49.2s / 49.8s, sequential)
- Pytest standalone (`uv run pytest`): ~7s wall (88 tests)
- `test_lesson_db.py` standalone: ~3s pytest / ~4s wall (40 tests, was ~7s before fixture-scope tightening)
- Hook-test ceiling: slowest file ~40s wall under parallel load

Drift signals to watch: pytest standalone > 12s, slowest hook file > 50s, total wall > 70s. See `output/claude-toolkit/analysis/20260426_1702__analyze-idea__tests-perf-review.md` for the original perf-review breakdown.

## Perf Benchmarks

`perf-*.sh` files measure hook execution time. Not included in `make test` — run manually. Set `CLAUDE_TOOLKIT_HOOK_PERF=1` to enable per-phase timing probes in hooks.
