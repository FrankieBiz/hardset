# Hardset Hypertrophy Logger — Multi-Model Orchestration & Verification Makefile
.DEFAULT_GOAL := help
.PHONY: check check-core check-store check-parse check-contrast project install orchestrate-probe orchestrate-stats test help

SWIFT := $(shell which swift)
PY := python3
CHECK := $(PY) Tools/hardset_check.py

check: ## Run honest Linux checks across all targets (parse syntax, Core suite, Store suite, query indexes, palette contrast)
	$(CHECK) all
	$(PY) Tools/check_query_performance.py --require-indexes
	$(PY) Tools/check_contrast.py

install: ## Build, sign, install, and launch Hardset on connected iPhone or Simulator (macOS)
	./Tools/install_device.sh

check-core: ## Run HardsetCore unit test suite
	$(CHECK) core

check-store: ## Run HardsetStore test suite (with SQLite UUID support)
	$(CHECK) store

check-parse: ## Parse Swift syntax across all repository files
	$(CHECK) parse

check-contrast: ## Verify the HardsetUI palette meets DESIGN.md's 7:1 text and 3:1 control floors
	$(PY) Tools/check_contrast.py

project: ## Regenerate Hardset.xcodeproj from Tools/generate_project.py
	$(PY) Tools/generate_project.py

test: ## Run the full HardsetKit suite via test.sh
	./test.sh

orchestrate-probe: ## Test connectivity and latencies of all mandated frontier model workers
	$(PY) scripts/orchestrate.py probe

orchestrate-stats: ## Display multi-model token ledger, dispatches, and cost accounting
	$(PY) scripts/orchestrate.py stats

orchestrate-children: ## List active child worktrees for the current workspace
	./scripts/orca-child.sh list

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  make %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
