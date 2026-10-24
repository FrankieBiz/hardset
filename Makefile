# Hardset Hypertrophy Logger — Multi-Model Orchestration & Verification Makefile
.DEFAULT_GOAL := help
.PHONY: check check-core check-store check-parse project orchestrate-probe orchestrate-stats test help

SWIFT := $(shell which swift)
PY := python3

check: ## Run honest Linux checks across all targets (parse syntax, Core suite, Store suite)
	hardset-check all

check-core: ## Run HardsetCore unit test suite
	hardset-check core

check-store: ## Run HardsetStore test suite (with SQLite UUID support)
	hardset-check store

check-parse: ## Parse Swift syntax across all repository files
	hardset-check parse

project: ## Regenerate Hardset.xcodeproj from Tools/generate_project.py
	$(PY) Tools/generate_project.py

test: ## Run the full HardsetKit suite via test.sh
	./test.sh

orchestrate-probe: ## Test connectivity and latencies of all mandated frontier model workers
	$(PY) scripts/orchestrate.py probe

orchestrate-stats: ## Display multi-model token ledger, dispatches, and cost accounting
	$(PY) scripts/orchestrate.py stats

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  make %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
