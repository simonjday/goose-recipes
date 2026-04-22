#!/bin/zsh
# tests/contract-test.sh
#
# LLM-as-judge contract tests. Saves a known-good recipe output to
# tests/expected-outputs/<recipe>.txt and verifies that a re-run still
# produces output satisfying a structural contract.
#
# Usage:
#   cd goose-recipes/goose-recipe-tests
#   zsh tests/contract-test.sh capture k8s-pod-review
#   zsh tests/contract-test.sh check k8s-pod-review
#   zsh tests/contract-test.sh all
#
# LLM judge backends (LLM_BACKEND=auto|anthropic|ollama|goose):
#   auto       — tries anthropic -> ollama -> goose in order
#   anthropic  — requires ANTHROPIC_API_KEY
#   ollama     — requires Ollama running (OLLAMA_HOST, default localhost:11434)
#   goose      — requires goose in PATH and Ollama running
#
# Examples:
#   LLM_BACKEND=ollama zsh tests/contract-test.sh all
#   LLM_BACKEND=goose JUDGE_MODEL=gemma4:latest zsh tests/contract-test.sh all
#   NO_LLM=true zsh tests/contract-test.sh all
#   CAPTURE_NAMESPACE=my-app zsh tests/contract-test.sh capture k8s-pod-review
#   CAPTURE_MODEL=qwen3-coder:30b zsh tests/contract-test.sh capture k8s-pod-review

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"
OUTPUTS_DIR="${OUTPUTS_DIR:-$SCRIPT_DIR/expected-outputs}"
NO_LLM="${NO_LLM:-false}"
LLM_BACKEND="${LLM_BACKEND:-auto}"
JUDGE_MODEL="${JUDGE_MODEL:-}"
_default_model_anthropic="claude-haiku-4-5-20251001"
_default_model_ollama="qwen2.5:7b"
_default_model_goose="qwen2.5:7b"
PASS=0
FAIL=0
ERRORS=()
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo "${GREEN}  PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}  FAIL${NC}  $1 — $2"; FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); }

mkdir -p "$OUTPUTS_DIR"

# ── Contract definitions ──────────────────────────────────────────────────────
declare -A CONTRACT_QUESTIONS
declare -A CONTRACT_PATTERNS

CONTRACT_QUESTIONS[k8s-pod-review]="Does this output contain: (1) a SUMMARY section with Pods reviewed count, PASS and FAIL counts, (2) findings broken down by RESOURCES/PROBES/IMAGE/SECURITY/PDB categories, and (3) at least one kubectl patch Fix command?"
CONTRACT_PATTERNS[k8s-pod-review]="SUMMARY|PASS:|FAIL:|RESOURCES:|PROBES:|SECURITY:|kubectl patch"

CONTRACT_QUESTIONS[daily-cluster-health-v2]="Does this output contain: (1) a health check table with Nodes, Workload Health, ArgoCD Sync, Kyverno Policy, Cert Expiry rows each with a RAG status, (2) a WORKLOAD DETAIL section listing each namespace checked with pod counts, and (3) an OVERALL RED/AMBER/GREEN rating?"
CONTRACT_PATTERNS[daily-cluster-health-v2]="OVERALL:|Nodes|Workload|ArgoCD|Kyverno|GREEN\|AMBER\|RED|WORKLOAD DETAIL"

CONTRACT_QUESTIONS[daily-cluster-health]="Does this output contain: (1) a table or list showing Nodes, Workload Health, ArgoCD Sync, Kyverno Policy, and Cert Expiry sections each with a RAG status, and (2) an OVERALL RED/AMBER/GREEN rating?"
CONTRACT_PATTERNS[daily-cluster-health]="OVERALL:|Nodes|Workload|ArgoCD|Kyverno|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pdb-coverage]="Does this output contain: (1) a SUMMARY line with counts of workloads checked and unprotected, (2) at least one section for StatefulSets or Deployments missing PDB, and (3) a kubectl apply command or YAML snippet for creating a PDB?"
CONTRACT_PATTERNS[pdb-coverage]="SUMMARY:|kubectl apply|PodDisruptionBudget|minAvailable"

CONTRACT_QUESTIONS[image-tag-audit]="Does this output contain: (1) a SUMMARY with counts for CRITICAL, HIGH, and OK images, (2) a section listing CRITICAL images using latest or untagged, and (3) a fix command showing how to pin an image by digest?"
CONTRACT_PATTERNS[image-tag-audit]="SUMMARY|CRITICAL|HIGH|OK|sha256\|imageID\|digest"

CONTRACT_QUESTIONS[kyverno-policy-adherence]="Does this output contain: (1) a SUMMARY with Pass, Fail, Warn counts, (2) a VIOLATIONS section or COMPLIANT confirmation, and (3) either a fix command or COMPLIANT confirmation?"
CONTRACT_PATTERNS[kyverno-policy-adherence]="SUMMARY|Pass:|Fail:|VIOLATIONS\|COMPLIANT"

CONTRACT_QUESTIONS[argocd-sync-status]="Does this output contain: (1) a SUMMARY with Total, Synced, OutOfSync, Healthy, Degraded counts, and (2) either a FLAGGED APPS section or a HEALTHY APPS confirmation?"
CONTRACT_PATTERNS[argocd-sync-status]="SUMMARY|Total:|Synced\|OutOfSync|FLAGGED\|HEALTHY"

CONTRACT_QUESTIONS[argocd-drift-report]="Does this output contain: (1) a SUMMARY with OutOfSync count, (2) a DRIFT DETAILS section, and (3) either ignoreDifferences YAML or a sync command?"
CONTRACT_PATTERNS[argocd-drift-report]="SUMMARY|OutOfSync:|INTENTIONAL\|ACCIDENTAL\|PRUNING"

CONTRACT_QUESTIONS[confluent-component-health]="Does this output contain: (1) a component table with Kafka, Schema Registry, and REST Proxy rows showing replica counts and RAG status, (2) a POD HEALTH section, and (3) an OVERALL RAG status?"
CONTRACT_PATTERNS[confluent-component-health]="Kafka|Schema Registry|POD HEALTH|OVERALL:|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pvc-health]="Does this output contain: (1) a SUMMARY line with Bound, Pending, Lost, and Unused PVC counts, and (2) StorageClass information?"
CONTRACT_PATTERNS[pvc-health]="SUMMARY:|Bound|Pending|STORAGECLASS\|StorageClass"

CONTRACT_QUESTIONS[namespace-resource-quota]="Does this output contain: (1) a QUOTA USAGE table or list with CPU and memory columns, and (2) a SUMMARY with counts of namespaces audited and missing quotas?"
CONTRACT_PATTERNS[namespace-resource-quota]="SUMMARY|Audited:|QUOTA\|quota|LimitRange"

CONTRACT_QUESTIONS[node-capacity-planning]="Does this output contain: (1) a per-node summary showing allocatable CPU and memory, (2) a running pod count, and (3) a RECOMMENDATIONS section?"
CONTRACT_PATTERNS[node-capacity-planning]="Allocatable\|allocatable|Running pods\|podCount|RECOMMENDATIONS"

CONTRACT_QUESTIONS[stale-resource-cleanup]="Does this output contain: (1) a STALE RESOURCE REPORT header with counts, and (2) a CLEANUP SCRIPT section with kubectl delete commands commented out?"
CONTRACT_PATTERNS[stale-resource-cleanup]="STALE RESOURCE REPORT|CLEANUP SCRIPT|# kubectl delete"

CONTRACT_QUESTIONS[kyverno-policy-coverage]="Does this output contain: (1) counts of ClusterPolicies with Enforce vs Audit breakdown, (2) a namespace coverage table or list, and (3) ENFORCE PROMOTION CANDIDATES or full coverage confirmation?"
CONTRACT_PATTERNS[kyverno-policy-coverage]="ClusterPolicies\|clusterpolicies|NAMESPACE COVERAGE\|namespace|Enforce\|Audit"

CONTRACT_QUESTIONS[kyverno-exception-audit]="Does this output contain: (1) a SUMMARY with Total, CRITICAL, BROAD, STALE, ORPHANED counts, and (2) an EXCEPTION DETAILS section?"
CONTRACT_PATTERNS[kyverno-exception-audit]="SUMMARY|Total:|EXCEPTION DETAILS\|CRITICAL\|ORPHANED"

CONTRACT_QUESTIONS[k8s-pod-review-v2]="Does this output contain: (1) a markdown table with Pod, Restarts, RESOURCES, PROBES, IMAGE, SECURITY, PDB columns, (2) a Findings section with at least one FAIL entry, and (3) a SUMMARY section showing Pods reviewed, PASS and FAIL counts, and findings broken down by RESOURCES, PROBES, IMAGE, SECURITY, PDB categories?"
CONTRACT_PATTERNS[k8s-pod-review-v2]="SUMMARY|PASS:|FAIL:|RESOURCES:|PROBES:|IMAGE:|SECURITY:|PDB:"

CONTRACT_QUESTIONS[mtls-cert-expiry]="Does this output contain: (1) a CERTIFICATE EXPIRY REPORT header, (2) sections for RED, AMBER, and GREEN certificates, and (3) a SUMMARY with totals?"
CONTRACT_PATTERNS[mtls-cert-expiry]="CERTIFICATE EXPIRY REPORT|SUMMARY|RED\|AMBER\|GREEN"

# ── LLM judge backends ────────────────────────────────────────────────────────

_judge_prompt() {
  local question="$1" truncated="$2"
  printf 'You are a test harness. Answer only YES or NO.\n\nQuestion: %s\n\nOutput to check:\n%s' "$question" "$truncated"
}

_judge_anthropic() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_anthropic}"
  local payload
  payload=$(jq -n \
    --arg m "$model" \
    --arg c "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $m, max_tokens: 50, messages: [{ role: "user", content: $c }] }')
  curl -s \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "$payload" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null \
  | jq -r '.content[0].text // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_ollama() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_ollama}"
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  local payload
  payload=$(jq -n \
    --arg m "$model" \
    --arg c "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $m, stream: false, messages: [{ role: "user", content: $c }] }')
  curl -s \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${host}/api/chat" 2>/dev/null \
  | jq -r '.message.content // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_goose() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_goose}"
  printf '%s' "$(_judge_prompt "$question" "$truncated")" \
  | goose run --model "$model" --no-session 2>/dev/null \
  | tail -1 | tr -d '\n'
}

_detect_backend() {
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && { echo "anthropic"; return; }
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  curl -sf "${host}/api/tags" > /dev/null 2>&1 && { echo "ollama"; return; }
  command -v goose > /dev/null 2>&1 && { echo "goose"; return; }
  echo "none"
}

llm_judge() {
  local recipe="$1" content="$2"
  local question="${CONTRACT_QUESTIONS[$recipe]:-}"
  [[ -z "$question" ]]       && { echo "NO_CONTRACT";       return; }
  [[ "$NO_LLM" == "true" ]]  && { echo "SKIPPED_NO_LLM";   return; }
  local backend="$LLM_BACKEND"
  [[ "$backend" == "auto" ]] && backend=$(_detect_backend)
  [[ "$backend" == "none" ]] && { echo "SKIPPED_NO_BACKEND"; return; }
  local truncated
  truncated=$(echo "$content" | head -c 3000)
  case "$backend" in
    anthropic)
      [[ -z "${ANTHROPIC_API_KEY:-}" ]] && { echo "SKIPPED_NO_KEY"; return; }
      _judge_anthropic "$question" "$truncated" ;;
    ollama) _judge_ollama "$question" "$truncated" ;;
    goose)  _judge_goose  "$question" "$truncated" ;;
    *)      echo "ERROR_UNKNOWN_BACKEND:$backend" ;;
  esac
}

# ── Pattern check ─────────────────────────────────────────────────────────────
pattern_check() {
  local recipe="$1" content="$2"
  local patterns="${CONTRACT_PATTERNS[$recipe]:-}"
  [[ -z "$patterns" ]] && return 0
  local failed=0
  IFS='|' read -rA pattern_list <<< "$patterns"
  for pattern in "${pattern_list[@]}"; do
    if ! echo "$content" | grep -qi "$pattern"; then
      echo "  missing pattern: '$pattern'"
      failed=$((failed+1))
    fi
  done
  return $failed
}

# ── CAPTURE MODE ──────────────────────────────────────────────────────────────
do_capture() {
  local recipe="$1"
  local yaml_file="$REPO_ROOT/${recipe}.yaml"
  local output_file="$OUTPUTS_DIR/${recipe}.txt"
  local capture_ns="${CAPTURE_NAMESPACE:-goose-test}"
  local capture_model="${CAPTURE_MODEL:-qwen3-coder:30b}"

  [[ ! -f "$yaml_file" ]] && { echo "${RED}ERROR${NC}: Recipe not found: $yaml_file"; exit 1; }
  command -v goose > /dev/null 2>&1 || { echo "${RED}ERROR${NC}: goose not found in PATH"; exit 1; }

  echo "Capturing output for: $recipe"
  echo "Recipe:    $yaml_file"
  echo "Output:    $output_file"
  echo "Namespace: $capture_ns"
  echo "Model:     $capture_model"
  echo ""
  echo "NOTE: Only qwen3-coder:30b reliably executes shell tools."
  echo "      Smaller models print tool calls as text instead of running them."
  echo ""
  echo "Running goose... (this may take several minutes)"
  echo ""

  # Auto-detect params from recipe yaml
  local extra_params=()
  grep -q "key: namespace"  "$yaml_file" 2>/dev/null && extra_params+=(--params "namespace=$capture_ns")
  grep -q "key: scope"      "$yaml_file" 2>/dev/null && extra_params+=(--params "scope=$capture_ns")
  grep -q "key: namespaces" "$yaml_file" 2>/dev/null && extra_params+=(--params "namespaces=$capture_ns")

  goose run \
    --model "$capture_model" \
    --recipe "$yaml_file" \
    --no-session \
    "${extra_params[@]}" \
    2>&1 | tee "$output_file"

  echo ""
  if grep -q '"name": "shell"' "$output_file" 2>/dev/null; then
    echo "${YELLOW}WARN${NC}: Output contains narrated tool calls — model did not execute shell."
    echo "     Re-run: CAPTURE_MODEL=qwen3-coder:30b zsh tests/contract-test.sh capture $recipe"
  fi
  echo "Saved to: $output_file"
  echo "Now run:  zsh tests/contract-test.sh check $recipe"
}

# ── CHECK MODE ────────────────────────────────────────────────────────────────
do_check() {
  local recipe="$1"
  local output_file="$OUTPUTS_DIR/${recipe}.txt"

  if [[ ! -f "$output_file" ]]; then
    echo "${YELLOW}SKIP${NC}  $recipe — no saved output (run capture first)"
    return
  fi

  local content
  content=$(cat "$output_file")
  echo "── $recipe ──"

  # Fail immediately if narrated tool calls detected
  if echo "$content" | grep -q '"name": "shell"'; then
    fail "$recipe: capture quality" "Narrated tool calls detected — re-capture with qwen3-coder:30b"
    return
  fi

  # Pattern check
  local pattern_out
  pattern_out=$(pattern_check "$recipe" "$content" 2>&1)
  if [[ $? -eq 0 ]]; then
    ok "$recipe: pattern checks"
  else
    fail "$recipe: pattern checks" "$pattern_out"
  fi

  # LLM judge
  local verdict
  verdict=$(llm_judge "$recipe" "$content")
  case "$verdict" in
    YES*)                ok   "$recipe: LLM contract check (${LLM_BACKEND})" ;;
    NO*)                 fail "$recipe: LLM contract check" "LLM judge answered NO" ;;
    SKIPPED_NO_LLM)      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge disabled (NO_LLM=true)" ;;
    SKIPPED_NO_KEY)      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (no ANTHROPIC_API_KEY)" ;;
    SKIPPED_NO_BACKEND)  echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (no backend available)" ;;
    NO_CONTRACT)         echo "  ${YELLOW}SKIP${NC}   $recipe: no contract defined" ;;
    ERROR_UNKNOWN_BACKEND:*) echo "  ${YELLOW}WARN${NC}   $recipe: unknown LLM_BACKEND '${verdict#ERROR_UNKNOWN_BACKEND:}'" ;;
    *)                   echo "  ${YELLOW}WARN${NC}   $recipe: LLM judge failed (verdict: $verdict)" ;;
  esac
  echo ""
}

# ── ALL MODE ──────────────────────────────────────────────────────────────────
do_all() {
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  Goose Recipe — Contract Tests"
  echo "  Outputs dir: $OUTPUTS_DIR"
  echo "  LLM judge: $( [[ "$NO_LLM" == "true" ]] && echo "disabled" || echo "$LLM_BACKEND" )"
  echo "═══════════════════════════════════════════════"
  echo ""

  local found=0
  setopt nullglob 2>/dev/null || true
  local outputs=("$OUTPUTS_DIR"/*.txt)
  unsetopt nullglob 2>/dev/null || true

  for output in "${outputs[@]:-}"; do
    [[ -f "$output" ]] || continue
    local recipe
    recipe=$(basename "$output" .txt)
    do_check "$recipe"
    found=$((found+1))
  done

  if [[ $found -eq 0 ]]; then
    echo "${YELLOW}  SKIP${NC}  No saved outputs found — contract tests not yet captured."
    echo ""
    echo "  Run to populate:"
    echo "    zsh tests/contract-test.sh capture k8s-pod-review"
    echo "    zsh tests/capture-all.sh"
    return 0
  fi

  echo "═══════════════════════════════════════════════"
  printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" $PASS $FAIL
  echo "═══════════════════════════════════════════════"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for e in "${ERRORS[@]}"; do echo "  ${RED}✗${NC} $e"; done
  fi
  echo ""
  [[ $FAIL -eq 0 ]]
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
MODE="${1:-all}"
RECIPE="${2:-}"

case "$MODE" in
  capture)
    [[ -z "$RECIPE" ]] && { echo "Usage: $0 capture <recipe-name>"; exit 1; }
    do_capture "$RECIPE"
    ;;
  check)
    [[ -z "$RECIPE" ]] && { echo "Usage: $0 check <recipe-name>"; exit 1; }
    do_check "$RECIPE"
    ;;
  all)
    do_all
    ;;
  *)
    echo "Usage: $0 <capture|check|all> [recipe-name]"
    echo ""
    echo "  capture k8s-pod-review              — run recipe, save output as reference"
    echo "  check k8s-pod-review                — verify saved output against contract"
    echo "  all                                 — check all saved outputs"
    echo ""
    echo "  NO_LLM=true $0 all                  — pattern checks only (no LLM)"
    echo "  LLM_BACKEND=ollama $0 all           — use local Ollama as judge"
    echo "  LLM_BACKEND=goose $0 all            — use goose+Ollama as judge"
    echo "  CAPTURE_MODEL=qwen3-coder:30b $0 capture <recipe>"
    echo "  CAPTURE_NAMESPACE=my-app $0 capture <recipe>"
    exit 1
    ;;
esac
