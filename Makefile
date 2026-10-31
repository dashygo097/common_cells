.DEFAULT_GOAL := help
BOOTSTRAP_PYTHON ?= python3
export PROJECT_ROOT := $(CURDIR)
export PROJECT_MAKE := $(MAKE)
.PHONY: help $(MAKECMDGOALS)

help $(filter-out help,$(MAKECMDGOALS)):
	+@if test -x "$(CURDIR)/build/.venv/bin/python"; then \
		"$(CURDIR)/build/.venv/bin/python" "$(CURDIR)/scripts/bootstrap.py" "$@"; \
	else \
		"$(BOOTSTRAP_PYTHON)" "$(CURDIR)/scripts/bootstrap.py" "$@"; \
	fi
