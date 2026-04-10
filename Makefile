.PHONY: install test test-hooks test-cli test-backlog test-raiz test-raiz-changelog test-eval test-validate-indexed test-validate-hook-utils test-verify-ext-deps validate check backlog tag help

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
	@echo "  make validate          - Run all validations (indexes + deps)"
	@echo "  make tag               - Create git tag from VERSION file"
	@echo "  make backlog           - Show project backlog"
	@echo "  make check             - Run everything (tests + validate)"

test: test-hooks test-cli test-backlog test-raiz test-raiz-changelog test-eval test-validate-indexed test-validate-hook-utils test-verify-ext-deps test-setup-diag

test-hooks:
	@bash tests/test-hooks.sh -q

test-cli:
	@bash tests/test-cli.sh -q

test-backlog:
	@bash tests/test-backlog-query.sh -q

test-raiz:
	@bash tests/test-raiz-publish.sh -q

test-raiz-changelog:
	@bash tests/test-raiz-changelog.sh -q

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

tag:
	@version=$$(cat VERSION) && \
	if git rev-parse "v$$version" >/dev/null 2>&1; then \
		echo "Tag v$$version already exists"; \
	else \
		git tag "v$$version" && echo "Tagged v$$version"; \
	fi

backlog:
	@bash cli/backlog/query.sh

validate:
	@bash .claude/scripts/validate-all.sh

check: test validate
