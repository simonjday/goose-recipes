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
#   - qwen3-coder:30b pulled in Ollama (required — smaller models don't use tools)
#
# Usage:
#   zsh tests/capture-all.sh
#
# Individual recipes can be skipped:
#   SKIP_RECIPES="daily-cluster-health confluent-component-health" zsh tests/capture-all.sh
#
# MODEL NOTE: Only qwen3-coder:30b reliably invokes shell tools.
# Smaller models (qwen2.5-coder:7b, gemma4) narrate tool calls as text instead
# of executing them, producing empty or broken captures.
# Override with MODEL= only if you know your model handles tool use.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUTPUTS_DIR="$SCRIPT_DIR/expected-outputs"
SKIP_RECIPES=(${=SKIP_RECIPES:-})

MODEL="${MODEL:-qwen3-coder:30b}"
NAMESPACE="${NAMESPACE:-goose-test}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-15}"

mkdir -p "$OUTPUTS_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Recipe list ───────────────────────────────────────────────────────────────
# Format: "recipe_name|param_key=val param_key2=val2"
# Params are passed as --params key=val for each space-separated pair.
# Use the exact param keys from each recipe's parameters: block.
RECIPES=(
  "k8s-pod-review|namespace=$NAMESPACE"
  "pdb-coverage|scope=$NAMESPACE"
  "image-tag-audit|scope=$NAMESPACE"
  "stale-resource-cleanup|namespace=$NAMESPACE"
  "namespace-resource-quota|scope=$NAMESPACE"
  "kyverno-policy-adherence|namespace=$NAMESPACE"
  "kyverno-policy-coverage|namespace=$NAMESPACE"
  "kyverno-exception-audit|"
  "argocd-sync-status|"
  "argocd-drift-report|"
  "node-capacity-planning|"
  "pvc-health|scope=$NAMESPACE"
  "mtls-cert-expiry|namespaces=$NAMESPACE"
  "daily-cluster-health|namespace=$NAMESPACE"
  "confluent-component-health|namespace=$NAMESPACE"
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
  param_str="${entry##*|}"
  yaml="$REPO_ROOT/${recipe}.yaml"

  # Skip check
  if (( ${SKIP_RECIPES[(Ie)$recipe]} )); then
    echo "${YELLOW}  SKIP${NC}  $recipe (in SKIP_RECIPES)"
    SKIP=$((SKIP+1))
    continue
  fi

  if [[ ! -f "$yaml" ]]; then
    echo "${YELLOW}  SKIP${NC}  $recipe (yaml not found at $yaml)"
    SKIP=$((SKIP+1))
    continue
  fi

  output_file="$OUTPUTS_DIR/${recipe}.txt"
  echo "── $recipe ──"
  echo "   model:  $MODEL"
  echo "   params: ${param_str:-none}"
  echo "   output: $output_file"

  # Build --params flags from "key=val key2=val2" string
  cmd=(goose run --model "$MODEL" --recipe "$yaml" --no-session)
  if [[ -n "$param_str" ]]; then
    for pair in ${=param_str}; do
      cmd+=(--params "$pair")
    done
  fi

  echo "   running..."
  start=$(date +%s)

  if "${cmd[@]}" > "$output_file" 2>&1; then
    end=$(date +%s)
    elapsed=$((end-start))
    lines=$(wc -l < "$output_file" | tr -d ' ')
    echo "   ${GREEN}done${NC} — ${elapsed}s, ${lines} lines → $output_file"

    # Sanity check: warn if output looks like narrated tool calls (model didn't execute tools)
    if grep -q '"name": "shell"' "$output_file" 2>/dev/null; then
      echo "   ${YELLOW}WARN${NC}  Output contains narrated tool calls — model did not execute shell tools."
      echo "         Try: MODEL=qwen3-coder:30b zsh tests/capture-all.sh"
    fi

    PASS=$((PASS+1))
  else
    end=$(date +%s)
    elapsed=$((end-start))
    echo "   ${RED}failed${NC} — ${elapsed}s (partial output saved to $output_file)"
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
