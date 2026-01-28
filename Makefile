.PHONY: test test-hooks test-cli test-backlog validate check help

help:
	@echo "Available targets:"
	@echo "  make test              - Run all tests (hooks + cli + backlog)"
	@echo "  make test-hooks        - Run hook tests only"
	@echo "  make test-cli          - Run CLI tests only"
	@echo "  make test-backlog      - Run backlog-query tests only"
	@echo "  make validate          - Run resource index validation"
	@echo "  make check             - Run everything (tests + validate)"

test: test-hooks test-cli test-backlog

test-hooks:
	@bash tests/test-hooks.sh

test-cli:
	@bash tests/test-cli.sh

test-backlog:
	@bash tests/test-backlog-query.sh

validate:
	@bash scripts/validate-resources-indexed.sh

check: test validate
