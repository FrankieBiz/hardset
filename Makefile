# Hardset Hypertrophy Logger — Verification Makefile
.DEFAULT_GOAL := help
.PHONY: check check-core check-store check-parse check-contrast project install mac-sync-check mac-test mac-install help

SWIFT := $(shell which swift)
PY := python3
CHECK := $(PY) Tools/hardset_check.py
MAC_DIR ?= ~/hardset
# The branch the Mac builds: the one checked out here, so a fix that lives on a feature branch is
# what gets installed. `git pull origin main` built main whatever was being tested.
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

check: ## Run honest Linux checks across all targets (parse syntax, Core suite, Store suite, query indexes, palette contrast)
	$(CHECK) all
	$(PY) Tools/check_query_performance.py --require-indexes
	$(PY) Tools/check_contrast.py

install: ## Build, sign, install, and launch Hardset on connected iPhone or Simulator (macOS)
	./Tools/install_device.sh

mac-sync-check:
	@if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/$(BRANCH) 2>/dev/null)" ]; then \
		echo "Warning: local $(BRANCH) differs from origin/$(BRANCH); the Mac builds what is pushed." >&2; fi

mac-test: mac-sync-check ## Run the app tests on the Mac's simulator via SSH bridge (BRANCH=current branch)
	ssh mac "cd $(MAC_DIR) && git fetch origin && git checkout --detach origin/$(BRANCH) && python3 Tools/generate_project.py && xcodebuild test -project Hardset.xcodeproj -scheme Hardset -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -skipMacroValidation -skipPackagePluginValidation CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="

mac-install: mac-sync-check ## Build, sign, and install Hardset onto the iPhone connected to the Mac (BRANCH=current branch)
	ssh mac "cd $(MAC_DIR) && git fetch origin && git checkout --detach origin/$(BRANCH) && ./Tools/install_device.sh"

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

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  make %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
