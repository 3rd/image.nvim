SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.RECIPEPREFIX := >
.DEFAULT_GOAL := help
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

SOURCE := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
TMPDIR ?= /tmp
ACT_CACHE_PATH ?= $(TMPDIR)/image.nvim-act
ACT_CACHE_SERVER_PATH ?= $(TMPDIR)/image.nvim-actcache
NIX_CACHE_HOME ?= $(TMPDIR)/image.nvim-nix-cache
ACT ?= env XDG_CACHE_HOME="$(NIX_CACHE_HOME)" nix run path:$(SOURCE)\#act --
ACT_FLAGS := --action-cache-path "$(ACT_CACHE_PATH)" --cache-server-path "$(ACT_CACHE_SERVER_PATH)"

BLUE := $(shell tput -Txterm setaf 4 2>/dev/null || true)
RESET := $(shell tput -Txterm sgr0 2>/dev/null || true)

.PHONY: help format test test-verbose test-minimal test-tap test-ci test-ci-stable test-ci-nightly

help: ## show this help
> @awk 'BEGIN { FS = ":.*## "; print "Available targets:" } /^[a-zA-Z0-9_-]+:.*## / { printf "  $(BLUE)%-18s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

format: ## format Lua files
> stylua lua tests

test: ## run full test suite
> @./scripts/test-runner.sh

test-verbose: ## run full test suite with verbose output
> @./scripts/test-runner.sh --verbose

test-minimal: ## run test suite with minimal output
> @./scripts/test-runner.sh --minimal

test-tap: ## run test suite with TAP output
> @./scripts/test-runner.sh --tap

test-ci: ## run GitHub Actions tests with act
> @command -v nix >/dev/null 2>&1 || { echo "nix is required to run pinned act; override ACT to use another executable"; exit 1; }
> $(ACT) $(ACT_FLAGS) -W .github/workflows/ci.yml

test-ci-stable: ## run stable Neovim CI tests with act
> @command -v nix >/dev/null 2>&1 || { echo "nix is required to run pinned act; override ACT to use another executable"; exit 1; }
> $(ACT) $(ACT_FLAGS) -W .github/workflows/ci.yml -j tests --matrix neovim_version:stable

test-ci-nightly: ## run nightly Neovim CI tests with act
> @command -v nix >/dev/null 2>&1 || { echo "nix is required to run pinned act; override ACT to use another executable"; exit 1; }
> $(ACT) $(ACT_FLAGS) -W .github/workflows/ci.yml -j tests --matrix neovim_version:nightly
