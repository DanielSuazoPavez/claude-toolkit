.PHONY: test test-hooks test-cli test-backlog validate check help

help:
	@echo "Available targets:"
	@echo "  make test              - Run all tests (hooks + cli + backlog)"
	@echo "  make test-hooks        - Run hook tests only"
	@echo "  make test-cli          - Run CLI tests only"
	@echo "  make test-backlog      - Run backlog-query tests only"
	@echo "  make validate          - Run all validations (indexes + deps)"
	@echo "  make check             - Run everything (tests + validate)"

test: test-hooks test-cli test-backlog

test-hooks:
	@bash tests/test-hooks.sh

test-cli:
	@bash tests/test-cli.sh

test-backlog:
	@bash tests/test-backlog-query.sh

validate:
	@bash .claude/scripts/validate-all.sh

check: test validate
