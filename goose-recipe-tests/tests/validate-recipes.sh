#!/bin/zsh
# tests/validate-recipes.sh
#
# Validates that every recipe YAML file in the repo root has the required
# top-level fields and well-formed parameters blocks.
# Requires: yq (brew install yq) and python3 (for YAML parsing fallback)
#
# Usage:
#   cd goose-recipes/goose-recipe-tests
#   zsh tests/validate-recipes.sh
#
#   # If your recipes live somewhere else:
#   RECIPES_DIR=/path/to/goose-recipes zsh tests/validate-recipes.sh
#
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR = .../goose-recipes/goose-recipe-tests/tests
# Go up two levels to reach the recipes repo root where *.yaml files live.
# Override with: RECIPES_DIR=/path/to/recipes zsh tests/validate-recipes.sh
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"

PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo "${GREEN}  PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}  FAIL${NC}  $1 — $2"; FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); }

# ── Check yq is available ─────────────────────────────────────────────────────
if ! command -v yq &>/dev/null; then
  echo "${YELLOW}WARNING${NC}: yq not found. Install with: brew install yq"
  echo "  Falling back to python3-based YAML field checks."
  USE_YQ=false
else
  USE_YQ=true
fi

# ── Field presence check ──────────────────────────────────────────────────────
has_field() {
  local file="$1" field="$2"
  if $USE_YQ; then
    local val
    val=$(yq e ".$field" "$file" 2>/dev/null)
    [[ -n "$val" && "$val" != "null" ]]
  else
    python3 -c "
import yaml, sys
with open('$file') as f:
    d = yaml.safe_load(f)
sys.exit(0 if d and '$field' in d and d['$field'] is not None else 1)
" 2>/dev/null
  fi
}

get_field() {
  local file="$1" field="$2"
  if $USE_YQ; then
    yq e ".$field" "$file" 2>/dev/null
  else
    python3 -c "
import yaml
with open('$file') as f:
    d = yaml.safe_load(f)
print(d.get('$field', ''))
" 2>/dev/null
  fi
}

# ── Files to exclude ──────────────────────────────────────────────────────────
# These are Kubernetes manifests or shell scripts, not Goose recipes
EXCLUDED=(
  "goose-test-manifests.yaml"
  "limitrange-suggestion.yaml"
)

is_excluded() {
  local base
  base=$(basename "$1")
  for ex in "${EXCLUDED[@]}"; do
    [[ "$base" == "$ex" ]] && return 0
  done
  return 1
}

# ── Required fields for every recipe ─────────────────────────────────────────
REQUIRED_FIELDS=(version title description extensions instructions prompt)

# ── Valid extension names ─────────────────────────────────────────────────────
VALID_EXTENSIONS=(developer computer)

echo ""
echo "═══════════════════════════════════════════════"
echo "  Goose Recipe — YAML Structure Validation"
echo "  Repo: $REPO_ROOT"
echo "═══════════════════════════════════════════════"
echo ""

recipe_files=("$REPO_ROOT"/*.yaml)
recipe_count=0

for recipe in "${recipe_files[@]}"; do
  [[ -f "$recipe" ]] || continue
  is_excluded "$recipe" && continue

  name=$(basename "$recipe")
  recipe_count=$((recipe_count+1))
  file_errors=0

  echo "${BLUE}──${NC} $name"

  # ── Required top-level fields ────────────────────────────────────────────────
  for field in "${REQUIRED_FIELDS[@]}"; do
    if has_field "$recipe" "$field"; then
      ok "  $name: has '$field'"
    else
      fail "  $name: missing '$field'" "required top-level field not found"
      file_errors=$((file_errors+1))
    fi
  done

  # ── Version format ────────────────────────────────────────────────────────────
  if has_field "$recipe" "version"; then
    version=$(get_field "$recipe" "version")
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      ok "  $name: version format valid ($version)"
    else
      fail "  $name: version format invalid" "got '$version', expected semver e.g. 1.0.0"
      file_errors=$((file_errors+1))
    fi
  fi

  # ── Title is non-empty ────────────────────────────────────────────────────────
  if has_field "$recipe" "title"; then
    title=$(get_field "$recipe" "title")
    if [[ ${#title} -gt 5 ]]; then
      ok "  $name: title is descriptive"
    else
      fail "  $name: title too short" "got '$title'"
    fi
  fi

  # ── Extensions block: type and name ──────────────────────────────────────────
  if $USE_YQ; then
    ext_count=$(yq e '.extensions | length' "$recipe" 2>/dev/null || echo 0)
    if [[ "$ext_count" -gt 0 ]]; then
      ext_type=$(yq e '.extensions[0].type' "$recipe" 2>/dev/null)
      ext_name=$(yq e '.extensions[0].name' "$recipe" 2>/dev/null)
      timeout=$(yq e '.extensions[0].timeout' "$recipe" 2>/dev/null)

      if [[ "$ext_type" == "builtin" ]]; then
        ok "  $name: extension type=builtin"
      else
        fail "  $name: extension type" "expected 'builtin', got '$ext_type'"
        file_errors=$((file_errors+1))
      fi

      if [[ "$ext_name" == "developer" || "$ext_name" == "computer" ]]; then
        ok "  $name: extension name=$ext_name"
      else
        fail "  $name: extension name" "expected developer|computer, got '$ext_name'"
        file_errors=$((file_errors+1))
      fi

      if [[ "$timeout" =~ ^[0-9]+$ ]] && [[ "$timeout" -ge 60 ]]; then
        ok "  $name: timeout=${timeout}s (≥60)"
      else
        fail "  $name: timeout" "expected integer ≥60, got '$timeout'"
        file_errors=$((file_errors+1))
      fi
    fi
  fi

  # ── Parameters block ──────────────────────────────────────────────────────────
  if $USE_YQ; then
    param_count=$(yq e '.parameters | length' "$recipe" 2>/dev/null || echo 0)
    if [[ "$param_count" -gt 0 ]]; then
      ok "  $name: has $param_count parameter(s)"

      # Check each parameter has key, input_type, and default
      for i in $(seq 0 $((param_count-1))); do
        param_key=$(yq e ".parameters[$i].key" "$recipe" 2>/dev/null)
        param_type=$(yq e ".parameters[$i].input_type" "$recipe" 2>/dev/null)
        param_default=$(yq e ".parameters[$i].default" "$recipe" 2>/dev/null)

        if [[ -n "$param_key" && "$param_key" != "null" ]]; then
          ok "  $name: param[$i] has key ($param_key)"
        else
          fail "  $name: param[$i] missing key" ""
          file_errors=$((file_errors+1))
        fi

        if [[ -n "$param_type" && "$param_type" != "null" ]]; then
          ok "  $name: param[$i] has input_type ($param_type)"
        else
          fail "  $name: param[$i] missing input_type" ""
          file_errors=$((file_errors+1))
        fi

        if [[ -n "$param_default" && "$param_default" != "null" ]]; then
          ok "  $name: param[$i] has default ($param_default)"
        else
          fail "  $name: param[$i] missing default" "all params should have sensible defaults"
          file_errors=$((file_errors+1))
        fi
      done
    else
      ok "  $name: no parameters (acceptable)"
    fi
  fi

  # ── Prompt must mention jq-filters or jq -f ───────────────────────────────
  if has_field "$recipe" "prompt"; then
    prompt_content=$(get_field "$recipe" "prompt")
    if echo "$prompt_content" | grep -q "jq-filters\|jq -f"; then
      ok "  $name: prompt references jq-filters (good pattern)"
    else
      # Not a hard failure — some prompts use jsonpath inline
      echo "  ${YELLOW}WARN${NC}   $name: prompt does not reference jq-filters — verify it uses pre-built filters"
    fi
  fi

  # ── Instructions must contain STRICT RULE ─────────────────────────────────
  if has_field "$recipe" "instructions"; then
    instr=$(get_field "$recipe" "instructions")
    if echo "$instr" | grep -qi "STRICT RULE\|NO INLINE JQ"; then
      ok "  $name: instructions contain NO INLINE JQ guard"
    else
      echo "  ${YELLOW}WARN${NC}   $name: instructions missing STRICT RULE / NO INLINE JQ guard"
    fi
  fi

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "  Recipes checked: $recipe_count"
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" $PASS $FAIL
echo "═══════════════════════════════════════════════"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do
    echo "  ${RED}✗${NC} $e"
  done
fi

echo ""
[[ $FAIL -eq 0 ]]
