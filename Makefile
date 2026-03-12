.PHONY: install test test-hooks test-cli test-backlog test-raiz test-insights validate check backlog help

install:
	@uv sync --dev

help:
	@echo "Available targets:"
	@echo "  make test              - Run all tests (hooks + cli + backlog + raiz)"
	@echo "  make test-hooks        - Run hook tests only"
	@echo "  make test-cli          - Run CLI tests only"
	@echo "  make test-backlog      - Run backlog-query tests only"
	@echo "  make test-raiz         - Run raiz publish tests only"
	@echo "  make validate          - Run all validations (indexes + deps)"
	@echo "  make backlog           - Show project backlog"
	@echo "  make check             - Run everything (tests + validate)"

test: test-hooks test-cli test-backlog test-raiz test-insights

test-hooks:
	@bash tests/test-hooks.sh

test-cli:
	@bash tests/test-cli.sh

test-backlog:
	@bash tests/test-backlog-query.sh

test-raiz:
	@bash tests/test-raiz-publish.sh

test-insights:
	@uv run pytest tests/test_insights.py -q

backlog:
	@bash .claude/scripts/backlog-query.sh

validate:
	@bash .claude/scripts/validate-all.sh

check: test validate
