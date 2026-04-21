#!/bin/zsh
# tests/run-all-tests.sh
#
# Master test runner. Runs all test layers in order:
#   1. YAML validation (no dependencies)
#   2. jq filter unit tests (needs jq, uses static fixtures)
#   3. Contract tests (needs saved expected-outputs; LLM optional)
#
# Usage:
#   cd goose-recipes/goose-recipe-tests
#   zsh tests/run-all-tests.sh
#
#   # Skip LLM judge (CI-safe, no API key needed):
#   NO_LLM=true zsh tests/run-all-tests.sh
#
#   # If your recipes/filters live elsewhere:
#   RECIPES_DIR=/path/to/goose-recipes zsh tests/run-all-tests.sh
#
# Exit code: 0 = all pass, 1 = any layer failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LAYER_PASS=0
LAYER_FAIL=0
LAYER_SKIP=0

run_layer() {
  local name="$1"
  local script="$2"
  local skip_if_output="$3"  # "skippable" = treat exit 0 with SKIP message as a skip
  shift 3
  local extra_args=("$@")

  echo ""
  echo "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  echo "${BLUE}║${NC}  Layer: $name"
  echo "${BLUE}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  local layer_output
  layer_output=$(zsh "$script" "${extra_args[@]}" 2>&1)
  local exit_code=$?
  echo "$layer_output"

  if [[ $exit_code -ne 0 ]]; then
    echo ""
    echo "${RED}✘ $name — FAILED${NC}"
    LAYER_FAIL=$((LAYER_FAIL+1))
  elif [[ "$skip_if_output" == "skippable" ]] && echo "$layer_output" | grep -q "SKIP.*No saved outputs"; then
    echo ""
    echo "${YELLOW}⊘ $name — SKIPPED (no captures yet)${NC}"
    LAYER_SKIP=$((LAYER_SKIP+1))
  else
    echo ""
    echo "${GREEN}✔ $name — PASSED${NC}"
    LAYER_PASS=$((LAYER_PASS+1))
  fi
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║    Goose Recipe Test Suite                   ║"
echo "║    $(date '+%Y-%m-%d %H:%M:%S')              ║"
echo "╚══════════════════════════════════════════════╝"

# Layer 1 — YAML structure validation
run_layer "YAML Validation" "$SCRIPT_DIR/validate-recipes.sh" "required"

# Layer 2 — jq filter unit tests
run_layer "jq Filter Tests" "$SCRIPT_DIR/run-filter-tests.sh" "required"

# Layer 3 — contract tests (skippable until captures are run)
run_layer "Contract Tests" "$SCRIPT_DIR/contract-test.sh" "skippable" "all"

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
total=$((LAYER_PASS+LAYER_FAIL+LAYER_SKIP))
echo "║  Overall: $LAYER_PASS/$total layers passed, $LAYER_SKIP skipped"
if [[ $LAYER_FAIL -eq 0 ]]; then
  if [[ $LAYER_SKIP -gt 0 ]]; then
    echo "║  ${GREEN}PASSED ✔${NC}  ${YELLOW}($LAYER_SKIP layer(s) skipped — run captures)${NC}"
  else
    echo "║  ${GREEN}ALL LAYERS PASSED ✔${NC}"
  fi
else
  echo "║  ${RED}$LAYER_FAIL LAYER(S) FAILED ✘${NC}"
fi
echo "╚══════════════════════════════════════════════╝"
echo ""

[[ $LAYER_FAIL -eq 0 ]]
