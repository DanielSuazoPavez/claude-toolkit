.PHONY: install test test-hooks test-cli test-backlog test-raiz test-raiz-changelog test-eval test-validate-indexed test-validate-hook-utils test-verify-ext-deps test-setup-diag test-pytest lint-bash validate check backlog tag help

install:
	@uv sync --dev

help:
	@echo "Available targets:"
	@echo "  make test              - Run all tests"
	@echo "  make test-hooks        - Run hook tests only"
	@echo "  make test-cli          - Run CLI tests only"
	@echo "  make test-backlog      - Run backlog-query tests only"
	@echo "  make test-raiz         - Run raiz publish tests only"
	@echo "  make test-raiz-changelog - Run raiz changelog format tests only"
	@echo "  make test-eval         - Run evaluation-query tests only"
	@echo "  make test-validate-indexed - Run validate-resources-indexed tests only"
	@echo "  make test-validate-hook-utils - Run validate-hook-utils tests only"
	@echo "  make test-verify-ext-deps - Run verify-external-deps tests only"
	@echo "  make test-pytest       - Run pytest suite only"
	@echo "  make lint-bash         - Shellcheck shipped bash (hooks, scripts, cli)"
	@echo "  make validate          - Run all validations (indexes + deps)"
	@echo "  make tag               - Create git tag from VERSION file"
	@echo "  make backlog           - Show project backlog (hides P99 nice-to-haves — use 'claude-toolkit backlog' for all)"
	@echo "  make check             - Run everything (tests + lint-bash + validate)"

test:
	@bash tests/run-all.sh -q

test-hooks:
	@bash tests/run-hook-tests.sh -q

test-cli:
	@bash tests/test-cli.sh -q

test-backlog:
	@bash tests/test-backlog-query.sh -q

test-raiz:
	@bash tests/test-raiz-publish.sh -q

test-raiz-changelog:
	@uv run pytest tests/test_format_raiz_changelog.py -q

test-eval:
	@bash tests/test-evaluation-query.sh -q

test-validate-indexed:
	@bash tests/test-validate-resources-indexed.sh -q

test-validate-hook-utils:
	@bash tests/test-validate-hook-utils.sh -q

test-verify-ext-deps:
	@bash tests/test-verify-external-deps.sh -q

test-setup-diag:
	@bash tests/test-setup-toolkit-diagnose.sh -q

test-pytest:
	@uv run pytest -q

tag:
	@version=$$(cat VERSION) && \
	if git rev-parse "v$$version" >/dev/null 2>&1; then \
		echo "Tag v$$version already exists"; \
	else \
		git tag "v$$version" && echo "Tagged v$$version"; \
	fi

backlog:
	@bash cli/backlog/query.sh --exclude-priority P99

lint-bash:
	@command -v shellcheck >/dev/null || { \
	  echo "shellcheck not installed — required for bash linting in this repo."; \
	  echo "install: sudo apt install shellcheck   (or: brew install shellcheck)"; \
	  exit 1; \
	}
	@shellcheck -S warning \
	  .claude/hooks/*.sh .claude/hooks/lib/*.sh \
	  .claude/scripts/*.sh .claude/scripts/cron/*.sh \
	  cli/backlog/*.sh cli/eval/*.sh

validate:
	@bash .claude/scripts/validate-all.sh

check: test lint-bash validate
