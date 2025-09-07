.PHONY: test test-verbose test-minimal test-tap test-ci test-stable test-nightly

test:
	@./scripts/test-runner.sh

test-verbose:
	@./scripts/test-runner.sh --verbose

test-minimal:
	@./scripts/test-runner.sh --minimal

test-tap:
	@./scripts/test-runner.sh --tap

test-ci:
	@command -v act >/dev/null 2>&1 || { echo "act is not installed"; exit 1; }
	act -W .github/workflows/ci.yml

test-ci-stable:
	@command -v act >/dev/null 2>&1 || { echo "act is not installed"; exit 1; }
	act -W .github/workflows/ci.yml -j tests --matrix neovim_version:stable

test-ci-nightly:
	@command -v act >/dev/null 2>&1 || { echo "act is not installed"; exit 1; }
	act -W .github/workflows/ci.yml -j tests --matrix neovim_version:nightly
