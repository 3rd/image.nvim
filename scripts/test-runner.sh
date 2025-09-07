#!/usr/bin/env bash
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

color() {
  echo -e "${1}${2}${NC}"
}

# Header
echo ""
color "${CYAN}${BOLD}" "╔══════════════════════════════════════════════════════════════╗"
color "${CYAN}${BOLD}" "║                   image.nvim Test Suite                     ║"
color "${CYAN}${BOLD}" "╚══════════════════════════════════════════════════════════════╝"
echo ""

# check if running in CI
if [ -n "$CI" ]; then
  color "${BLUE}" "Environment: GitHub Actions CI"
  color "${BLUE}" "Neovim Version: ${NEOVIM_VERSION:-unknown}"
else
  color "${BLUE}" "Environment: Local"
  if command -v nvim &>/dev/null; then
    NVIM_VERSION=$(nvim --version | head -n1)
    color "${BLUE}" "Neovim Version: $NVIM_VERSION"
  fi
fi

echo ""
color "${YELLOW}" "Test Files:"
color "${YELLOW}" "───────────"

# list test files
for file in tests/**/*_spec.lua; do
  if [ -f "$file" ]; then
    echo "  • $(basename $file)"
  fi
done

echo ""
color "${CYAN}" "Running Tests..."
color "${CYAN}" "════════════════"
echo ""

if [ "$1" == "--tap" ]; then
  # TAP
  busted --output=TAP --verbose tests/
  TEST_RESULT=$?
elif [ "$1" == "--minimal" ]; then
  # minimal output
  busted tests/
  TEST_RESULT=$?
else
  # default: verbose
  busted --output=gtest --verbose tests/ 2>&1 | sed 's/^/  /'
  TEST_RESULT=${PIPESTATUS[0]}
fi

echo ""
color "${CYAN}" "════════════════"

# summary
if [ $TEST_RESULT -eq 0 ]; then
  echo ""
  color "${GREEN}${BOLD}" "✓ All tests passed!"
  echo ""
else
  echo ""
  color "${RED}${BOLD}" "✗ Tests failed!"
  echo ""
  exit $TEST_RESULT
fi

