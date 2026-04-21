#!/bin/zsh
# tests/capture-all.sh
#
# Runs every recipe against the goose-test namespace and saves output to
# tests/expected-outputs/ for use by contract-test.sh.
#
# Prerequisites:
#   - kubectl pointing at a cluster with goose-test namespace running
#   - goose installed and configured with Ollama
#   - goose-test-manifests.yaml already applied
#
# Usage:
#   zsh tests/capture-all.sh
#
# Individual recipes can be skipped by setting SKIP_RECIPES:
#   SKIP_RECIPES="daily-cluster-health confluent-component-health" zsh tests/capture-all.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR = .../goose-recipes/goose-recipe-tests/tests
# Go up two levels to reach the recipes repo root.
# Override with: RECIPES_DIR=/path/to/recipes zsh tests/<script>.sh
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"
OUTPUTS_DIR="$SCRIPT_DIR/expected-outputs"
SKIP_RECIPES=(${=SKIP_RECIPES:-})

MODEL=${MODEL:-qwen3-coder:30b}
NAMESPACE=${NAMESPACE:-goose-test}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-15}  # seconds between runs (let Ollama cool down)

mkdir -p "$OUTPUTS_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Recipe list with their param overrides ────────────────────────────────────
# Format: "recipe_name|--params key=val --params key2=val2"
RECIPES=(
  "k8s-pod-review|--params namespace=$NAMESPACE"
  "pdb-coverage|--params scope=$NAMESPACE"
  "image-tag-audit|--params scope=$NAMESPACE"
  "stale-resource-cleanup|--params namespace=$NAMESPACE"
  "namespace-resource-quota|--params scope=$NAMESPACE"
  "kyverno-policy-adherence|--params namespace=$NAMESPACE"
  "kyverno-policy-coverage|--params namespace=$NAMESPACE"
  "kyverno-exception-audit|"
  "argocd-sync-status|"
  "argocd-drift-report|"
  "node-capacity-planning|"
  "pvc-health|--params scope=$NAMESPACE"
  "mtls-cert-expiry|--params namespaces=$NAMESPACE"
  "daily-cluster-health|--params namespace=$NAMESPACE"
  "confluent-component-health|--params namespace=$NAMESPACE"
)

PASS=0
FAIL=0
SKIP=0

echo ""
echo "═══════════════════════════════════════════════"
echo "  Goose Recipe — Capture All Outputs"
echo "  Model:     $MODEL"
echo "  Namespace: $NAMESPACE"
echo "  Output:    $OUTPUTS_DIR"
echo "  Sleep:     ${SLEEP_BETWEEN}s between runs"
echo "═══════════════════════════════════════════════"
echo ""

for entry in "${RECIPES[@]}"; do
  recipe="${entry%%|*}"
  params="${entry##*|}"
  yaml="$REPO_ROOT/${recipe}.yaml"

  # Check if should skip
  if (( ${SKIP_RECIPES[(Ie)$recipe]} )); then
    echo "${YELLOW}  SKIP${NC}  $recipe (in SKIP_RECIPES)"
    SKIP=$((SKIP+1))
    continue
  fi

  if [[ ! -f "$yaml" ]]; then
    echo "${YELLOW}  SKIP${NC}  $recipe (yaml not found)"
    SKIP=$((SKIP+1))
    continue
  fi

  output_file="$OUTPUTS_DIR/${recipe}.txt"
  echo "── $recipe ──"
  echo "   params: ${params:-none}"
  echo "   output: $output_file"

  # Build command
  cmd=(goose run --model "$MODEL" --recipe "$yaml" --no-session)
  if [[ -n "$params" ]]; then
    # Split params string into array elements properly
    cmd+=("${=params}")
  fi

  echo "   running..."
  start=$(date +%s)

  if "${cmd[@]}" > "$output_file" 2>&1; then
    end=$(date +%s)
    elapsed=$((end-start))
    lines=$(wc -l < "$output_file" | tr -d ' ')
    echo "   ${GREEN}done${NC} — ${elapsed}s, ${lines} lines → $output_file"
    PASS=$((PASS+1))
  else
    end=$(date +%s)
    elapsed=$((end-start))
    echo "   ${RED}failed${NC} — ${elapsed}s (partial output saved)"
    FAIL=$((FAIL+1))
  fi

  echo ""
  echo "   Cooling down ${SLEEP_BETWEEN}s ..."
  sleep $SLEEP_BETWEEN
  echo ""
done

echo "═══════════════════════════════════════════════"
printf "  Capture results: ${GREEN}%d ok${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" $PASS $FAIL $SKIP
echo "═══════════════════════════════════════════════"
echo ""
echo "Next step:"
echo "  zsh tests/contract-test.sh all"
echo ""

[[ $FAIL -eq 0 ]]
