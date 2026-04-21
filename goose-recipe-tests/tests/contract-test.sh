#!/bin/zsh
# tests/contract-test.sh
#
# LLM-as-judge contract tests. Saves a known-good recipe output to
# tests/expected-outputs/<recipe>.txt and verifies that a re-run still
# produces output satisfying a structural contract.
#
# This script has two modes:
#
#   CAPTURE mode — run a recipe and save its output as the reference:
#     zsh tests/contract-test.sh capture k8s-pod-review
#
#   CHECK mode — verify a saved output against its contract:
#     zsh tests/contract-test.sh check k8s-pod-review
#
#   ALL mode — check all saved expected-outputs:
#     zsh tests/contract-test.sh all
#
# Requirements:
#   - ANTHROPIC_API_KEY set in environment (for LLM judge calls)
#   - curl and jq installed
#   - Goose installed (for capture mode only)
#
# In a CI environment you can skip the LLM judge and just do string-match
# checks by setting: NO_LLM=true zsh tests/contract-test.sh all

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR = .../goose-recipes/goose-recipe-tests/tests
# Go up two levels to reach the recipes repo root.
# Override with: RECIPES_DIR=/path/to/recipes zsh tests/<script>.sh
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"
OUTPUTS_DIR="$SCRIPT_DIR/expected-outputs"

NO_LLM=${NO_LLM:-false}
PASS=0
FAIL=0
ERRORS=()

# ── LLM judge backend selection ───────────────────────────────────────────────
# Set LLM_BACKEND to choose how the judge call is made:
#
#   anthropic  (default if ANTHROPIC_API_KEY is set)
#              Uses the Anthropic Messages API directly via curl.
#              Requires: ANTHROPIC_API_KEY env var
#              Model:    JUDGE_MODEL (default: claude-haiku-4-5-20251001)
#
#   ollama     Uses a local Ollama instance directly via its REST API.
#              Requires: OLLAMA_HOST (default: http://localhost:11434)
#              Model:    JUDGE_MODEL (default: qwen2.5:7b — fast, low heat)
#              Good for: local runs and CI with a self-hosted Ollama runner
#
#   goose      Runs a one-shot goose session with --no-session.
#              Requires: goose in PATH, Ollama running (uses your existing config)
#              Model:    JUDGE_MODEL (default: qwen2.5:7b)
#              Good for: local runs — zero extra config if goose already works
#
#   auto       (default) Tries backends in order: anthropic → ollama → goose
#              Uses the first one that appears to be available.
#
# Examples:
#   LLM_BACKEND=ollama JUDGE_MODEL=qwen2.5:7b zsh tests/contract-test.sh all
#   LLM_BACKEND=goose  JUDGE_MODEL=gemma4:latest zsh tests/contract-test.sh all
#   LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-... zsh tests/contract-test.sh all
#   NO_LLM=true zsh tests/contract-test.sh all   (pattern checks only)

LLM_BACKEND="${LLM_BACKEND:-auto}"

# Default models per backend
_default_model_anthropic="claude-haiku-4-5-20251001"
_default_model_ollama="qwen2.5:7b"
_default_model_goose="qwen2.5:7b"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo "${GREEN}  PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}  FAIL${NC}  $1 — $2"; FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); }

mkdir -p "$OUTPUTS_DIR"

# ── Contract definitions ──────────────────────────────────────────────────────
# Each entry: "recipe_name|contract question for LLM judge|required string patterns (pipe-sep)"
#
# The LLM judge question must be answerable YES/NO from the output alone.
# Required patterns are grep-based checks that run without LLM.
declare -A CONTRACT_QUESTIONS
declare -A CONTRACT_PATTERNS

CONTRACT_QUESTIONS[k8s-pod-review]="Does this output contain: (1) a SUMMARY section with Pods reviewed count, PASS and FAIL counts, (2) findings broken down by RESOURCES/PROBES/IMAGE/SECURITY/PDB categories, and (3) at least one kubectl patch Fix command?"

CONTRACT_PATTERNS[k8s-pod-review]="SUMMARY|PASS:|FAIL:|RESOURCES:|PROBES:|SECURITY:|kubectl patch"

CONTRACT_QUESTIONS[daily-cluster-health]="Does this output contain: (1) a table or list showing Nodes, Workload Health, ArgoCD Sync, Kyverno Policy, and Cert Expiry sections each with a RAG status, and (2) an OVERALL RED/AMBER/GREEN rating?"

CONTRACT_PATTERNS[daily-cluster-health]="OVERALL:|Nodes|Workload|ArgoCD|Kyverno|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pdb-coverage]="Does this output contain: (1) a SUMMARY line with counts of workloads checked and unprotected, (2) at least one section for StatefulSets or Deployments missing PDB, and (3) a kubectl apply command or YAML snippet for creating a PDB?"

CONTRACT_PATTERNS[pdb-coverage]="SUMMARY:|kubectl apply|PodDisruptionBudget|minAvailable"

CONTRACT_QUESTIONS[image-tag-audit]="Does this output contain: (1) a SUMMARY with counts for CRITICAL, HIGH, and OK images, (2) a section listing CRITICAL images using latest or untagged, and (3) a fix command showing how to pin an image by digest?"

CONTRACT_PATTERNS[image-tag-audit]="SUMMARY|CRITICAL|HIGH|OK|sha256\|imageID\|digest"

CONTRACT_QUESTIONS[kyverno-policy-adherence]="Does this output contain: (1) a SUMMARY with Pass, Fail, Warn counts, (2) a VIOLATIONS section (or confirmation that the namespace is compliant), and (3) either a fix command or COMPLIANT confirmation?"

CONTRACT_PATTERNS[kyverno-policy-adherence]="SUMMARY|Pass:|Fail:|VIOLATIONS\|COMPLIANT"

CONTRACT_QUESTIONS[argocd-sync-status]="Does this output contain: (1) a SUMMARY with Total, Synced, OutOfSync, Healthy, Degraded counts, and (2) either a FLAGGED APPS section with fix commands or a HEALTHY APPS confirmation?"

CONTRACT_PATTERNS[argocd-sync-status]="SUMMARY|Total:|Synced\|OutOfSync|FLAGGED\|HEALTHY"

CONTRACT_QUESTIONS[argocd-drift-report]="Does this output contain: (1) a SUMMARY with OutOfSync count, (2) a DRIFT DETAILS section classifying each drifted resource, and (3) either ignoreDifferences YAML or a sync command?"

CONTRACT_PATTERNS[argocd-drift-report]="SUMMARY|OutOfSync:|INTENTIONAL\|ACCIDENTAL\|PRUNING"

CONTRACT_QUESTIONS[confluent-component-health]="Does this output contain: (1) a component table with Kafka, Schema Registry, and REST Proxy rows each showing replica counts and a RAG status, (2) a POD HEALTH section, and (3) an OVERALL RAG status?"

CONTRACT_PATTERNS[confluent-component-health]="Kafka|Schema Registry|POD HEALTH|OVERALL:|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pvc-health]="Does this output contain: (1) a SUMMARY line with Bound, Pending, Lost, and Unused PVC counts, and (2) StorageClass information?"

CONTRACT_PATTERNS[pvc-health]="SUMMARY:|Bound|Pending|STORAGECLASS\|StorageClass"

CONTRACT_QUESTIONS[namespace-resource-quota]="Does this output contain: (1) a QUOTA USAGE table or list with CPU and memory columns, (2) a SUMMARY with counts of namespaces audited and missing quotas?"

CONTRACT_PATTERNS[namespace-resource-quota]="SUMMARY|Audited:|QUOTA\|quota|LimitRange"

CONTRACT_QUESTIONS[node-capacity-planning]="Does this output contain: (1) a per-node summary for at least one node showing allocatable CPU and memory, (2) a running pod count, and (3) RECOMMENDATIONS section?"

CONTRACT_PATTERNS[node-capacity-planning]="Allocatable\|allocatable|Running pods\|podCount|RECOMMENDATIONS"

CONTRACT_QUESTIONS[stale-resource-cleanup]="Does this output contain: (1) a STALE RESOURCE REPORT header with counts, (2) a CLEANUP SCRIPT section with kubectl delete commands commented out?"

CONTRACT_PATTERNS[stale-resource-cleanup]="STALE RESOURCE REPORT|CLEANUP SCRIPT|# kubectl delete"

CONTRACT_QUESTIONS[kyverno-policy-coverage]="Does this output contain: (1) counts of ClusterPolicies and their Enforce vs Audit breakdown, (2) a namespace coverage table or list, and (3) either ENFORCE PROMOTION CANDIDATES or confirmation of full coverage?"

CONTRACT_PATTERNS[kyverno-policy-coverage]="ClusterPolicies\|clusterpolicies|NAMESPACE COVERAGE\|namespace|Enforce\|Audit"

CONTRACT_QUESTIONS[kyverno-exception-audit]="Does this output contain: (1) a SUMMARY with Total, CRITICAL, BROAD, STALE, ORPHANED counts, and (2) an EXCEPTION DETAILS section?"

CONTRACT_PATTERNS[kyverno-exception-audit]="SUMMARY|Total:|EXCEPTION DETAILS\|CRITICAL\|ORPHANED"

CONTRACT_QUESTIONS[mtls-cert-expiry]="Does this output contain: (1) a CERTIFICATE EXPIRY REPORT header, (2) sections for RED, AMBER, and GREEN certificates (even if empty), and (3) a SUMMARY with totals?"

CONTRACT_PATTERNS[mtls-cert-expiry]="CERTIFICATE EXPIRY REPORT|SUMMARY|RED\|AMBER\|GREEN"

# ── LLM judge call ────────────────────────────────────────────────────────────

_judge_prompt() {
  local question="$1" truncated="$2"
  echo "You are a test harness. Answer only YES or NO.

Question: $question

Output to check:
$truncated"
}

_judge_anthropic() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_anthropic}"
  local payload
  payload=$(jq -n \
    --arg model "$model" \
    --arg content "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $model, max_tokens: 50,
       messages: [{ role: "user", content: $content }] }')
  local response
  response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "$payload" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)
  echo "$response" | jq -r '.content[0].text // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_ollama() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_ollama}"
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  local payload
  payload=$(jq -n \
    --arg model "$model" \
    --arg content "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $model, stream: false,
       messages: [{ role: "user", content: $content }] }')
  local response
  response=$(curl -s \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${host}/api/chat" 2>/dev/null)
  echo "$response" | jq -r '.message.content // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_goose() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_goose}"
  local prompt
  prompt=$(_judge_prompt "$question" "$truncated")
  # Run goose with --no-session; capture only the final assistant response line
  local response
  response=$(echo "$prompt" | goose run --model "$model" --no-session 2>/dev/null | tail -1)
  echo "$response" | tr -d '\n'
}

_detect_backend() {
  # auto-detect: try anthropic first, then ollama, then goose
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "anthropic"; return
  fi
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  if curl -sf "${host}/api/tags" > /dev/null 2>&1; then
    echo "ollama"; return
  fi
  if command -v goose > /dev/null 2>&1; then
    echo "goose"; return
  fi
  echo "none"
}

llm_judge() {
  local recipe="$1"
  local content="$2"
  local question="${CONTRACT_QUESTIONS[$recipe]:-}"

  if [[ -z "$question" ]]; then
    echo "NO_CONTRACT"; return
  fi

  if [[ "$NO_LLM" == "true" ]]; then
    echo "SKIPPED_NO_LLM"; return
  fi

  # Resolve backend
  local backend="$LLM_BACKEND"
  if [[ "$backend" == "auto" ]]; then
    backend=$(_detect_backend)
  fi

  if [[ "$backend" == "none" ]]; then
    echo "SKIPPED_NO_BACKEND"; return
  fi

  # Truncate to ~3000 chars to keep inference fast
  local truncated
  truncated=$(echo "$content" | head -c 3000)

  case "$backend" in
    anthropic)
      if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then echo "SKIPPED_NO_KEY"; return; fi
      _judge_anthropic "$question" "$truncated"
      ;;
    ollama)
      _judge_ollama "$question" "$truncated"
      ;;
    goose)
      _judge_goose "$question" "$truncated"
      ;;
    *)
      echo "ERROR_UNKNOWN_BACKEND:$backend"
      ;;
  esac
}

# ── String pattern check (no LLM needed) ─────────────────────────────────────
pattern_check() {
  local recipe="$1"
  local content="$2"
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

  if [[ ! -f "$yaml_file" ]]; then
    echo "${RED}ERROR${NC}: Recipe not found: $yaml_file"
    exit 1
  fi

  echo "Capturing output for: $recipe"
  echo "Recipe:  $yaml_file"
  echo "Output:  $output_file"
  echo ""
  echo "Running goose... (this may take several minutes)"
  echo ""

  if ! command -v goose &>/dev/null; then
    echo "${RED}ERROR${NC}: goose not found in PATH"
    exit 1
  fi

  goose run \
    --model qwen3-coder:30b \
    --recipe "$yaml_file" \
    --no-session \
    --params namespace=goose-test \
    --params scope=goose-test \
    2>&1 | tee "$output_file"

  echo ""
  echo "Saved to: $output_file"
  echo "Now run: zsh tests/contract-test.sh check $recipe"
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

  # String pattern check (always runs)
  local pattern_out
  pattern_out=$(pattern_check "$recipe" "$content" 2>&1)
  local pattern_exit=$?
  if [[ $pattern_exit -eq 0 ]]; then
    ok "$recipe: pattern checks"
  else
    fail "$recipe: pattern checks" "$pattern_out"
  fi

  # LLM judge check
  local verdict
  verdict=$(llm_judge "$recipe" "$content")

  case "$verdict" in
    YES*)
      ok "$recipe: LLM contract check (backend: ${LLM_BACKEND})"
      ;;
    NO*)
      fail "$recipe: LLM contract check" "LLM judge answered NO — output may be malformed"
      ;;
    SKIPPED_NO_LLM)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge disabled (NO_LLM=true)"
      ;;
    SKIPPED_NO_KEY)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (ANTHROPIC_API_KEY not set)"
      ;;
    SKIPPED_NO_BACKEND)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (no backend available — set LLM_BACKEND or ANTHROPIC_API_KEY or start Ollama)"
      ;;
    NO_CONTRACT)
      echo "  ${YELLOW}SKIP${NC}   $recipe: no contract defined"
      ;;
    ERROR_UNKNOWN_BACKEND:*)
      echo "  ${YELLOW}WARN${NC}   $recipe: unknown LLM_BACKEND '${verdict#ERROR_UNKNOWN_BACKEND:}' — use: anthropic, ollama, goose, auto"
      ;;
    ERROR|*)
      echo "  ${YELLOW}WARN${NC}   $recipe: LLM judge call failed (verdict: $verdict)"
      ;;
  esac
  echo ""
}

# ── ALL MODE ──────────────────────────────────────────────────────────────────
do_all() {
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  Goose Recipe — Contract Tests"
  echo "  Outputs dir: $OUTPUTS_DIR"
  echo "  LLM judge: $( [[ "$NO_LLM" == "true" ]] && echo "disabled" || echo "$JUDGE_MODEL" )"
  echo "═══════════════════════════════════════════════"
  echo ""

  # nullglob-safe: setopt nullglob so unmatched *.txt returns empty, not an error
  local found=0
  setopt nullglob 2>/dev/null || true
  local outputs=("$OUTPUTS_DIR"/*.txt)
  unsetopt nullglob 2>/dev/null || true
  for output in "${outputs[@]:-}"; do
    [[ -f "$output" ]] || continue
    recipe=$(basename "$output" .txt)
    do_check "$recipe"
    found=$((found+1))
  done

  if [[ $found -eq 0 ]]; then
    echo "${YELLOW}  SKIP${NC}  No saved outputs found — contract tests not yet captured."
    echo ""
    echo "  This is expected on first run. To populate outputs:"
    echo "    zsh tests/contract-test.sh capture k8s-pod-review"
    echo "    zsh tests/capture-all.sh   (runs all recipes)"
    echo ""
    echo "  Layers 1 and 2 (YAML validation + filter tests) run without captures."
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
    echo "  capture k8s-pod-review   — run recipe and save output as reference"
    echo "  check k8s-pod-review     — verify saved output against contract"
    echo "  all                      — check all saved outputs"
    echo ""
    echo "  NO_LLM=true $0 all                              — pattern checks only (no LLM)"
    echo "  LLM_BACKEND=ollama $0 all                      — use local Ollama"
    echo "  LLM_BACKEND=goose JUDGE_MODEL=gemma4:latest $0 all — use goose+Ollama"
    echo "  LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-... $0 all — use Anthropic"
    exit 1
    ;;
esac

#   cd goose-recipes/goose-recipe-tests
#   zsh tests/contract-test.sh capture k8s-pod-review   (save reference output)
#   zsh tests/contract-test.sh check k8s-pod-review     (check against contract)
#   zsh tests/contract-test.sh all                      (check all saved outputs)
#
# LLM judge backends (set LLM_BACKEND= to choose):
#   auto       — default: tries anthropic → ollama → goose in order
#   anthropic  — requires ANTHROPIC_API_KEY
#   ollama     — requires Ollama running; uses OLLAMA_HOST (default localhost:11434)
#   goose      — requires goose in PATH and Ollama running
#
# Model override: JUDGE_MODEL=<model>  (e.g. qwen2.5:7b, gemma4:latest)
#
# Examples:
#   LLM_BACKEND=ollama zsh tests/contract-test.sh all
#   LLM_BACKEND=goose JUDGE_MODEL=gemma4:latest zsh tests/contract-test.sh all
#   LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-... zsh tests/contract-test.sh all
#   NO_LLM=true zsh tests/contract-test.sh all   (pattern checks only, no LLM)
#
# Requirements: jq, curl (for anthropic/ollama), goose (for capture + goose backend)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR = .../goose-recipes/goose-recipe-tests/tests
# Go up two levels to reach the recipes repo root.
# Override with: RECIPES_DIR=/path/to/recipes zsh tests/<script>.sh
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"
OUTPUTS_DIR="$SCRIPT_DIR/expected-outputs"

NO_LLM=${NO_LLM:-false}
PASS=0
FAIL=0
ERRORS=()

# ── LLM judge backend selection ───────────────────────────────────────────────
# Set LLM_BACKEND to choose how the judge call is made:
#
#   anthropic  (default if ANTHROPIC_API_KEY is set)
#              Uses the Anthropic Messages API directly via curl.
#              Requires: ANTHROPIC_API_KEY env var
#              Model:    JUDGE_MODEL (default: claude-haiku-4-5-20251001)
#
#   ollama     Uses a local Ollama instance directly via its REST API.
#              Requires: OLLAMA_HOST (default: http://localhost:11434)
#              Model:    JUDGE_MODEL (default: qwen2.5:7b — fast, low heat)
#              Good for: local runs and CI with a self-hosted Ollama runner
#
#   goose      Runs a one-shot goose session with --no-session.
#              Requires: goose in PATH, Ollama running (uses your existing config)
#              Model:    JUDGE_MODEL (default: qwen2.5:7b)
#              Good for: local runs — zero extra config if goose already works
#
#   auto       (default) Tries backends in order: anthropic → ollama → goose
#              Uses the first one that appears to be available.
#
# Examples:
#   LLM_BACKEND=ollama JUDGE_MODEL=qwen2.5:7b zsh tests/contract-test.sh all
#   LLM_BACKEND=goose  JUDGE_MODEL=gemma4:latest zsh tests/contract-test.sh all
#   LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-... zsh tests/contract-test.sh all
#   NO_LLM=true zsh tests/contract-test.sh all   (pattern checks only)

LLM_BACKEND="${LLM_BACKEND:-auto}"

# Default models per backend
_default_model_anthropic="claude-haiku-4-5-20251001"
_default_model_ollama="qwen2.5:7b"
_default_model_goose="qwen2.5:7b"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo "${GREEN}  PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}  FAIL${NC}  $1 — $2"; FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); }

mkdir -p "$OUTPUTS_DIR"

# ── Contract definitions ──────────────────────────────────────────────────────
# Each entry: "recipe_name|contract question for LLM judge|required string patterns (pipe-sep)"
#
# The LLM judge question must be answerable YES/NO from the output alone.
# Required patterns are grep-based checks that run without LLM.
declare -A CONTRACT_QUESTIONS
declare -A CONTRACT_PATTERNS

CONTRACT_QUESTIONS[k8s-pod-review]="Does this output contain: (1) a SUMMARY section with Pods reviewed count, PASS and FAIL counts, (2) findings broken down by RESOURCES/PROBES/IMAGE/SECURITY/PDB categories, and (3) at least one kubectl patch Fix command?"

CONTRACT_PATTERNS[k8s-pod-review]="SUMMARY|PASS:|FAIL:|RESOURCES:|PROBES:|SECURITY:|kubectl patch"

CONTRACT_QUESTIONS[daily-cluster-health]="Does this output contain: (1) a table or list showing Nodes, Workload Health, ArgoCD Sync, Kyverno Policy, and Cert Expiry sections each with a RAG status, and (2) an OVERALL RED/AMBER/GREEN rating?"

CONTRACT_PATTERNS[daily-cluster-health]="OVERALL:|Nodes|Workload|ArgoCD|Kyverno|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pdb-coverage]="Does this output contain: (1) a SUMMARY line with counts of workloads checked and unprotected, (2) at least one section for StatefulSets or Deployments missing PDB, and (3) a kubectl apply command or YAML snippet for creating a PDB?"

CONTRACT_PATTERNS[pdb-coverage]="SUMMARY:|kubectl apply|PodDisruptionBudget|minAvailable"

CONTRACT_QUESTIONS[image-tag-audit]="Does this output contain: (1) a SUMMARY with counts for CRITICAL, HIGH, and OK images, (2) a section listing CRITICAL images using latest or untagged, and (3) a fix command showing how to pin an image by digest?"

CONTRACT_PATTERNS[image-tag-audit]="SUMMARY|CRITICAL|HIGH|OK|sha256\|imageID\|digest"

CONTRACT_QUESTIONS[kyverno-policy-adherence]="Does this output contain: (1) a SUMMARY with Pass, Fail, Warn counts, (2) a VIOLATIONS section (or confirmation that the namespace is compliant), and (3) either a fix command or COMPLIANT confirmation?"

CONTRACT_PATTERNS[kyverno-policy-adherence]="SUMMARY|Pass:|Fail:|VIOLATIONS\|COMPLIANT"

CONTRACT_QUESTIONS[argocd-sync-status]="Does this output contain: (1) a SUMMARY with Total, Synced, OutOfSync, Healthy, Degraded counts, and (2) either a FLAGGED APPS section with fix commands or a HEALTHY APPS confirmation?"

CONTRACT_PATTERNS[argocd-sync-status]="SUMMARY|Total:|Synced\|OutOfSync|FLAGGED\|HEALTHY"

CONTRACT_QUESTIONS[argocd-drift-report]="Does this output contain: (1) a SUMMARY with OutOfSync count, (2) a DRIFT DETAILS section classifying each drifted resource, and (3) either ignoreDifferences YAML or a sync command?"

CONTRACT_PATTERNS[argocd-drift-report]="SUMMARY|OutOfSync:|INTENTIONAL\|ACCIDENTAL\|PRUNING"

CONTRACT_QUESTIONS[confluent-component-health]="Does this output contain: (1) a component table with Kafka, Schema Registry, and REST Proxy rows each showing replica counts and a RAG status, (2) a POD HEALTH section, and (3) an OVERALL RAG status?"

CONTRACT_PATTERNS[confluent-component-health]="Kafka|Schema Registry|POD HEALTH|OVERALL:|GREEN\|AMBER\|RED"

CONTRACT_QUESTIONS[pvc-health]="Does this output contain: (1) a SUMMARY line with Bound, Pending, Lost, and Unused PVC counts, and (2) StorageClass information?"

CONTRACT_PATTERNS[pvc-health]="SUMMARY:|Bound|Pending|STORAGECLASS\|StorageClass"

CONTRACT_QUESTIONS[namespace-resource-quota]="Does this output contain: (1) a QUOTA USAGE table or list with CPU and memory columns, (2) a SUMMARY with counts of namespaces audited and missing quotas?"

CONTRACT_PATTERNS[namespace-resource-quota]="SUMMARY|Audited:|QUOTA\|quota|LimitRange"

CONTRACT_QUESTIONS[node-capacity-planning]="Does this output contain: (1) a per-node summary for at least one node showing allocatable CPU and memory, (2) a running pod count, and (3) RECOMMENDATIONS section?"

CONTRACT_PATTERNS[node-capacity-planning]="Allocatable\|allocatable|Running pods\|podCount|RECOMMENDATIONS"

CONTRACT_QUESTIONS[stale-resource-cleanup]="Does this output contain: (1) a STALE RESOURCE REPORT header with counts, (2) a CLEANUP SCRIPT section with kubectl delete commands commented out?"

CONTRACT_PATTERNS[stale-resource-cleanup]="STALE RESOURCE REPORT|CLEANUP SCRIPT|# kubectl delete"

CONTRACT_QUESTIONS[kyverno-policy-coverage]="Does this output contain: (1) counts of ClusterPolicies and their Enforce vs Audit breakdown, (2) a namespace coverage table or list, and (3) either ENFORCE PROMOTION CANDIDATES or confirmation of full coverage?"

CONTRACT_PATTERNS[kyverno-policy-coverage]="ClusterPolicies\|clusterpolicies|NAMESPACE COVERAGE\|namespace|Enforce\|Audit"

CONTRACT_QUESTIONS[kyverno-exception-audit]="Does this output contain: (1) a SUMMARY with Total, CRITICAL, BROAD, STALE, ORPHANED counts, and (2) an EXCEPTION DETAILS section?"

CONTRACT_PATTERNS[kyverno-exception-audit]="SUMMARY|Total:|EXCEPTION DETAILS\|CRITICAL\|ORPHANED"

CONTRACT_QUESTIONS[mtls-cert-expiry]="Does this output contain: (1) a CERTIFICATE EXPIRY REPORT header, (2) sections for RED, AMBER, and GREEN certificates (even if empty), and (3) a SUMMARY with totals?"

CONTRACT_PATTERNS[mtls-cert-expiry]="CERTIFICATE EXPIRY REPORT|SUMMARY|RED\|AMBER\|GREEN"

# ── LLM judge call ────────────────────────────────────────────────────────────

_judge_prompt() {
  local question="$1" truncated="$2"
  echo "You are a test harness. Answer only YES or NO.

Question: $question

Output to check:
$truncated"
}

_judge_anthropic() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_anthropic}"
  local payload
  payload=$(jq -n \
    --arg model "$model" \
    --arg content "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $model, max_tokens: 50,
       messages: [{ role: "user", content: $content }] }')
  local response
  response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "$payload" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)
  echo "$response" | jq -r '.content[0].text // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_ollama() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_ollama}"
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  local payload
  payload=$(jq -n \
    --arg model "$model" \
    --arg content "$(_judge_prompt "$question" "$truncated")" \
    '{ model: $model, stream: false,
       messages: [{ role: "user", content: $content }] }')
  local response
  response=$(curl -s \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${host}/api/chat" 2>/dev/null)
  echo "$response" | jq -r '.message.content // "ERROR"' 2>/dev/null | tr -d '\n'
}

_judge_goose() {
  local question="$1" truncated="$2"
  local model="${JUDGE_MODEL:-$_default_model_goose}"
  local prompt
  prompt=$(_judge_prompt "$question" "$truncated")
  # Run goose with --no-session; capture only the final assistant response line
  local response
  response=$(echo "$prompt" | goose run --model "$model" --no-session 2>/dev/null | tail -1)
  echo "$response" | tr -d '\n'
}

_detect_backend() {
  # auto-detect: try anthropic first, then ollama, then goose
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "anthropic"; return
  fi
  local host="${OLLAMA_HOST:-http://localhost:11434}"
  if curl -sf "${host}/api/tags" > /dev/null 2>&1; then
    echo "ollama"; return
  fi
  if command -v goose > /dev/null 2>&1; then
    echo "goose"; return
  fi
  echo "none"
}

llm_judge() {
  local recipe="$1"
  local content="$2"
  local question="${CONTRACT_QUESTIONS[$recipe]:-}"

  if [[ -z "$question" ]]; then
    echo "NO_CONTRACT"; return
  fi

  if [[ "$NO_LLM" == "true" ]]; then
    echo "SKIPPED_NO_LLM"; return
  fi

  # Resolve backend
  local backend="$LLM_BACKEND"
  if [[ "$backend" == "auto" ]]; then
    backend=$(_detect_backend)
  fi

  if [[ "$backend" == "none" ]]; then
    echo "SKIPPED_NO_BACKEND"; return
  fi

  # Truncate to ~3000 chars to keep inference fast
  local truncated
  truncated=$(echo "$content" | head -c 3000)

  case "$backend" in
    anthropic)
      if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then echo "SKIPPED_NO_KEY"; return; fi
      _judge_anthropic "$question" "$truncated"
      ;;
    ollama)
      _judge_ollama "$question" "$truncated"
      ;;
    goose)
      _judge_goose "$question" "$truncated"
      ;;
    *)
      echo "ERROR_UNKNOWN_BACKEND:$backend"
      ;;
  esac
}

# ── String pattern check (no LLM needed) ─────────────────────────────────────
pattern_check() {
  local recipe="$1"
  local content="$2"
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

  if [[ ! -f "$yaml_file" ]]; then
    echo "${RED}ERROR${NC}: Recipe not found: $yaml_file"
    exit 1
  fi

  echo "Capturing output for: $recipe"
  echo "Recipe:  $yaml_file"
  echo "Output:  $output_file"
  echo ""
  echo "Running goose... (this may take several minutes)"
  echo ""

  if ! command -v goose &>/dev/null; then
    echo "${RED}ERROR${NC}: goose not found in PATH"
    exit 1
  fi

  goose run \
    --model qwen3-coder:30b \
    --recipe "$yaml_file" \
    --no-session \
    --params namespace=goose-test \
    --params scope=goose-test \
    2>&1 | tee "$output_file"

  echo ""
  echo "Saved to: $output_file"
  echo "Now run: zsh tests/contract-test.sh check $recipe"
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

  # String pattern check (always runs)
  local pattern_out
  pattern_out=$(pattern_check "$recipe" "$content" 2>&1)
  local pattern_exit=$?
  if [[ $pattern_exit -eq 0 ]]; then
    ok "$recipe: pattern checks"
  else
    fail "$recipe: pattern checks" "$pattern_out"
  fi

  # LLM judge check
  local verdict
  verdict=$(llm_judge "$recipe" "$content")

  case "$verdict" in
    YES*)
      ok "$recipe: LLM contract check (backend: ${LLM_BACKEND})"
      ;;
    NO*)
      fail "$recipe: LLM contract check" "LLM judge answered NO — output may be malformed"
      ;;
    SKIPPED_NO_LLM)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge disabled (NO_LLM=true)"
      ;;
    SKIPPED_NO_KEY)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (ANTHROPIC_API_KEY not set)"
      ;;
    SKIPPED_NO_BACKEND)
      echo "  ${YELLOW}SKIP${NC}   $recipe: LLM judge skipped (no backend available — set LLM_BACKEND or ANTHROPIC_API_KEY or start Ollama)"
      ;;
    NO_CONTRACT)
      echo "  ${YELLOW}SKIP${NC}   $recipe: no contract defined"
      ;;
    ERROR_UNKNOWN_BACKEND:*)
      echo "  ${YELLOW}WARN${NC}   $recipe: unknown LLM_BACKEND '${verdict#ERROR_UNKNOWN_BACKEND:}' — use: anthropic, ollama, goose, auto"
      ;;
    ERROR|*)
      echo "  ${YELLOW}WARN${NC}   $recipe: LLM judge call failed (verdict: $verdict)"
      ;;
  esac
