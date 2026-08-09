SHELL := /bin/bash

SHELL_SOURCES := .ai-commit.sh .ai-commit-msg.sh install.sh
INTEGRATION_TESTS := $(sort $(wildcard tests/test-*.sh))

.PHONY: test test-lint test-integration guard-main-checkout

test: test-lint test-integration

test-lint:
	bash -n .ctags.sh $(SHELL_SOURCES)
	shellcheck -S error $(SHELL_SOURCES)
	shellcheck -s sh -S error .ctags.sh

# install.sh refuses to run from a linked worktree, so the integration suites
# only pass from the main checkout. See docs/agents/test-stages.md.
guard-main-checkout:
	@if [ -f "$$(git rev-parse --git-dir)/gitdir" ]; then \
		echo "make: run integration tests from the main checkout, not a linked worktree" >&2; \
		echo "make: install.sh's home guard makes tests/test-install-*.sh fail here" >&2; \
		exit 1; \
	fi

test-integration: guard-main-checkout
	@status=0; \
	for t in $(INTEGRATION_TESTS); do \
		echo "### $$t"; \
		bash "$$t" || status=1; \
	done; \
	exit $$status
