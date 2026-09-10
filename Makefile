SHELL := /bin/bash
APP_NAME ?= Klopydrome
BUILD_DIR := .build

.PHONY: build test app release package dist run clean help

help: ## Show available targets
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Compile check (swift build)
	swift build

test: ## Run the NavidromeClient test suite (requires full Xcode)
	swift test

app: ## Build a signed debug app bundle
	./scripts/build-app.sh

release: ## Build a signed release app bundle
	./scripts/build-app.sh --release

package dist: release ## Build a release bundle and zip it into dist/
	./scripts/package-release.sh

run: app ## Build the bundle and launch it
	open "$(BUILD_DIR)/app/$(APP_NAME).app"

clean: ## Remove build artifacts
	rm -rf "$(BUILD_DIR)" dist
