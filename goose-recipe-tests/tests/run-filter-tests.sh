#!/bin/zsh
# tests/run-filter-tests.sh
#
# Unit tests for all jq filter files. Runs entirely from static fixtures —
# no live cluster or Goose install required.
#
# Usage:
#   cd goose-recipes/goose-recipe-tests
#   zsh tests/run-filter-tests.sh
#
#   # If your jq-filters live somewhere else:
#   RECIPES_DIR=/path/to/goose-recipes zsh tests/run-filter-tests.sh
#
# Exit code: 0 = all pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# SCRIPT_DIR = .../goose-recipes/goose-recipe-tests/tests
# Go up two levels to reach the recipes repo root.
# Override with: RECIPES_DIR=/path/to/recipes zsh tests/<script>.sh
RECIPES_DIR="${RECIPES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$RECIPES_DIR"
FIXTURES="$SCRIPT_DIR/fixtures"
# jq-filters live alongside tests/ inside goose-recipe-tests/ — one level up from SCRIPT_DIR
# Use FILTERS_DIR override if your filters live elsewhere (e.g. the repo root copy)
FILTERS="${FILTERS_DIR:-$(cd "$SCRIPT_DIR/../jq-filters" && pwd)}"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ── Colour output ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo "${GREEN}  PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo "${RED}  FAIL${NC}  $1"; echo "        $2"; FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); }
skip() { echo "${YELLOW}  SKIP${NC}  $1 (fixture or filter missing)"; SKIP=$((SKIP+1)); }

# ── Core assertion ────────────────────────────────────────────────────────────
# assert_jq LABEL FIXTURE_FILE FILTER_FILE JQ_ASSERTION
#
# JQ_ASSERTION is a jq expression evaluated against the filter output that must
# return true (or a non-null/non-false value) to pass.
assert_jq() {
  local label="$1"
  local fixture="$FIXTURES/$2"
  local filter="$FILTERS/$3"
  local assertion="$4"

  if [[ ! -f "$fixture" ]]; then skip "$label (missing fixture: $2)"; return; fi
  if [[ ! -f "$filter"  ]]; then skip "$label (missing filter: $3)"; return; fi

  local result
  result=$(jq -f "$filter" "$fixture" 2>&1)
  local jq_exit=$?

  if [[ $jq_exit -ne 0 ]]; then
    fail "$label" "jq error: $result"
    return
  fi

  local verdict
  verdict=$(echo "$result" | jq -e "$assertion" 2>/dev/null)
  if [[ $? -eq 0 && "$verdict" != "false" && "$verdict" != "null" ]]; then
    ok "$label"
  else
    fail "$label" "assertion '$assertion' failed. Filter output: $(echo "$result" | head -c 300)"
  fi
}

# ── assert that jq filter produces valid JSON (not an error) ──────────────────
assert_valid_json() {
  local label="$1"
  local fixture="$FIXTURES/$2"
  local filter="$FILTERS/$3"

  if [[ ! -f "$fixture" ]]; then skip "$label (missing fixture: $2)"; return; fi
  if [[ ! -f "$filter"  ]]; then skip "$label (missing filter: $3)"; return; fi

  local result
  result=$(jq -f "$filter" "$fixture" 2>&1)
  if [[ $? -eq 0 ]]; then
    ok "$label"
  else
    fail "$label" "jq produced an error: $result"
  fi
}

# ── assert count ──────────────────────────────────────────────────────────────
# assert_count LABEL FIXTURE FILTER EXPECTED_COUNT
assert_count() {
  local label="$1" fixture="$FIXTURES/$2" filter="$FILTERS/$3" expected="$4"
  if [[ ! -f "$fixture" ]]; then skip "$label"; return; fi
  if [[ ! -f "$filter"  ]]; then skip "$label"; return; fi
  local count
  count=$(jq -f "$filter" "$fixture" | jq 'length' 2>/dev/null)
  if [[ "$count" == "$expected" ]]; then
    ok "$label"
  else
    fail "$label" "expected length $expected, got $count"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  Goose Recipe — jq Filter Tests"
echo "  Fixtures: $FIXTURES"
echo "  Filters:  $FILTERS"
echo "═══════════════════════════════════════════════"
echo ""

# ── pod-review.jq ─────────────────────────────────────────────────────────────
# NOTE: live filter returns {summary:{...}, pods:[...]} not a bare array.
# Assertions use .pods[] and .summary accordingly.
echo "── pod-review.jq ──"
assert_jq     "output is an object"               pods.json  pod-review.jq  '. | type == "object"'
assert_jq     "has summary block"                 pods.json  pod-review.jq  'has("summary")'
assert_jq     "has pods array"                    pods.json  pod-review.jq  '.pods | type == "array"'
assert_jq     "summary has total_pods"            pods.json  pod-review.jq  '.summary.total_pods | type == "number"'
assert_jq     "summary has resources_findings"    pods.json  pod-review.jq  '.summary | has("resources_findings")'
assert_jq     "summary has probes_findings"       pods.json  pod-review.jq  '.summary | has("probes_findings")'
assert_jq     "summary has image_findings"        pods.json  pod-review.jq  '.summary | has("image_findings")'
assert_jq     "summary has security_findings"     pods.json  pod-review.jq  '.summary | has("security_findings")'
assert_jq     "summary total_pods is 4"           pods.json  pod-review.jq  '.summary.total_pods == 4'
assert_jq     "extracts pod name"                 pods.json  pod-review.jq  '.pods[0].name | type == "string"'
assert_jq     "extracts phase"                    pods.json  pod-review.jq  '.pods[0].phase | . == "Running"'
assert_jq     "extracts restartCount"             pods.json  pod-review.jq  '.pods[0].restarts | type == "number"'
assert_jq     "extracts oomKilled boolean"        pods.json  pod-review.jq  '.pods[0].oomKilled | type == "boolean"'
assert_jq     "containers is an array"            pods.json  pod-review.jq  '.pods[0].containers | type == "array"'
assert_jq     "container has hasLiveness field"   pods.json  pod-review.jq  '.pods[0].containers[0] | has("hasLiveness")'
assert_jq     "container has hasReadiness field"  pods.json  pod-review.jq  '.pods[0].containers[0] | has("hasReadiness")'
assert_jq     "container has hasRequests field"   pods.json  pod-review.jq  '.pods[0].containers[0] | has("hasRequests")'
assert_jq     "container has hasLimits field"     pods.json  pod-review.jq  '.pods[0].containers[0] | has("hasLimits")'
assert_jq     "container has allowPrivEsc field"  pods.json  pod-review.jq  '.pods[0].containers[0] | has("allowPrivEsc")'
assert_jq     "container has readOnlyRoot field"  pods.json  pod-review.jq  '.pods[0].containers[0] | has("readOnlyRoot")'
assert_jq     "good-app: hasLiveness=true"        pods.json  pod-review.jq  '.pods[0].containers[0].hasLiveness == true'
assert_jq     "good-app: hasRequests=true"        pods.json  pod-review.jq  '.pods[0].containers[0].hasRequests == true'
assert_jq     "good-app: runAsNonRoot=true"       pods.json  pod-review.jq  '.pods[0].containers[0].runAsNonRoot == true'
assert_jq     "good-app: allowPrivEsc=false"      pods.json  pod-review.jq  '.pods[0].containers[0].allowPrivEsc == false'
assert_jq     "good-app: readOnlyRoot=true"       pods.json  pod-review.jq  '.pods[0].containers[0].readOnlyRoot == true'
assert_jq     "bad-app: allowPrivEsc=true when secCtx absent"  pods.json  pod-review.jq  '.pods[1].containers[0].allowPrivEsc == true'
assert_jq     "bad-app: runAsNonRoot=false when secCtx absent" pods.json  pod-review.jq  '.pods[1].containers[0].runAsNonRoot == false'
assert_jq     "bad-app: hasLiveness=false"        pods.json  pod-review.jq  '.pods[1].containers[0].hasLiveness == false'
assert_jq     "bad-app: pullPolicy=Always"        pods.json  pod-review.jq  '.pods[1].containers[0].pullPolicy == "Always"'
assert_jq     "ugly-app: hasRequests=false"       pods.json  pod-review.jq  '.pods[2].containers[0].hasRequests == false'
assert_jq     "podSecCtx block present"           pods.json  pod-review.jq  '.pods[0] | has("podSecCtx")'
assert_jq     "pods array has 4 entries"          pods.json  pod-review.jq  '.pods | length == 4'
echo ""

# ── pdb-check.jq ─────────────────────────────────────────────────────────────
echo "── pdb-check.jq ──"
assert_jq     "returns array"                     pdbs.json  pdb-check.jq   '. | type == "array"'
assert_jq     "pdb has name"                      pdbs.json  pdb-check.jq   '.[0].name | type == "string"'
assert_jq     "pdb has selector"                  pdbs.json  pdb-check.jq   '.[0].selector | type == "object"'
assert_jq     "pdb has minAvailable"              pdbs.json  pdb-check.jq   '.[0].minAvailable == 2'
assert_count  "one pdb returned"                  pdbs.json  pdb-check.jq   1
echo ""

# ── pdb-pod-match.jq ─────────────────────────────────────────────────────────
echo "── pdb-pod-match.jq ──"
assert_jq     "returns array"                     pdbs.json  pdb-pod-match.jq  '. | type == "array"'
assert_jq     "pdb has name"                      pdbs.json  pdb-pod-match.jq  '.[0].name | type == "string"'
assert_jq     "pdb has namespace"                 pdbs.json  pdb-pod-match.jq  '.[0].namespace | type == "string"'
assert_jq     "pdb has selector object"           pdbs.json  pdb-pod-match.jq  '.[0].selector | type == "object"'
assert_jq     "pdb has minAvailable"              pdbs.json  pdb-pod-match.jq  '.[0].minAvailable == 2'
assert_jq     "pdb has maxUnavailable field"      pdbs.json  pdb-pod-match.jq  '.[0] | has("maxUnavailable")'
assert_jq     "pdb has currentHealthy"            pdbs.json  pdb-pod-match.jq  '.[0] | has("currentHealthy")'
assert_jq     "pdb has desiredHealthy"            pdbs.json  pdb-pod-match.jq  '.[0] | has("desiredHealthy")'
assert_jq     "pdb has expectedPods"              pdbs.json  pdb-pod-match.jq  '.[0] | has("expectedPods")'
assert_jq     "pdb has disruptionsAllowed"        pdbs.json  pdb-pod-match.jq  '.[0] | has("disruptionsAllowed")'
assert_jq     "selector has app label"            pdbs.json  pdb-pod-match.jq  '.[0].selector | has("app")'
assert_count  "one pdb returned"                  pdbs.json  pdb-pod-match.jq  1
echo ""

# ── hc-nodes.jq ──────────────────────────────────────────────────────────────
echo "── hc-nodes.jq ──"
assert_jq     "has total field"                   nodes.json hc-nodes.jq    'has("total")'
assert_jq     "total is 2"                        nodes.json hc-nodes.jq    '.total == 2'
assert_jq     "has notReady array"                nodes.json hc-nodes.jq    '.notReady | type == "array"'
assert_jq     "has memPressure array"             nodes.json hc-nodes.jq    '.memPressure | type == "array"'
assert_jq     "has diskPressure array"            nodes.json hc-nodes.jq    '.diskPressure | type == "array"'
assert_jq     "has versions array"                nodes.json hc-nodes.jq    '.versions | type == "array"'
assert_jq     "healthy nodes: notReady is empty"  nodes.json hc-nodes.jq    '.notReady | length == 0'
assert_jq     "healthy nodes: no mem pressure"    nodes.json hc-nodes.jq    '.memPressure | length == 0'
echo ""

# ── hc-pods.jq ───────────────────────────────────────────────────────────────
echo "── hc-pods.jq ──"
assert_jq     "has total field"                   pods.json  hc-pods.jq     'has("total")'
assert_jq     "has notRunning array"              pods.json  hc-pods.jq     '.notRunning | type == "array"'
assert_jq     "has highRestarts array"            pods.json  hc-pods.jq     '.highRestarts | type == "array"'
assert_jq     "has oomKilled array"               pods.json  hc-pods.jq     '.oomKilled | type == "array"'
assert_jq     "has notReady array"                pods.json  hc-pods.jq     '.notReady | type == "array"'
assert_jq     "bad-app flagged for highRestarts"  pods.json  hc-pods.jq     '.highRestarts | map(.name) | any(. == "bad-app-def456-uvw")'
assert_jq     "good-app NOT in highRestarts"      pods.json  hc-pods.jq     '.highRestarts | map(.name) | any(. == "good-app-abc123-xyz") | not'
assert_jq     "completed pod excluded from notRunning (Succeeded is valid)" pods.json hc-pods.jq '.notRunning | length == 0'
echo ""

# ── pvc-filter.jq ────────────────────────────────────────────────────────────
echo "── pvc-filter.jq ──"
assert_jq     "returns array"                     pvcs.json  pvc-filter.jq  '. | type == "array"'
assert_jq     "pvc has name"                      pvcs.json  pvc-filter.jq  '.[0].name | type == "string"'
assert_jq     "pvc has phase"                     pvcs.json  pvc-filter.jq  '.[0].phase | type == "string"'
assert_jq     "pvc has storageClass"              pvcs.json  pvc-filter.jq  '.[0] | has("storageClass")'
assert_jq     "pvc has capacity"                  pvcs.json  pvc-filter.jq  '.[0].capacity | type == "string"'
assert_jq     "bound pvc: phase=Bound"            pvcs.json  pvc-filter.jq  '.[0].phase == "Bound"'
assert_jq     "pending pvc: phase=Pending"        pvcs.json  pvc-filter.jq  '.[1].phase == "Pending"'
assert_count  "two pvcs returned"                 pvcs.json  pvc-filter.jq  2
echo ""

# ── jobs-filter.jq ───────────────────────────────────────────────────────────
echo "── jobs-filter.jq ──"
assert_jq     "returns array"                     jobs.json  jobs-filter.jq '. | type == "array"'
assert_jq     "job has name"                      jobs.json  jobs-filter.jq '.[0].name | type == "string"'
assert_jq     "job has succeeded count"           jobs.json  jobs-filter.jq '.[0].succeeded | type == "number"'
assert_jq     "job has failed count"              jobs.json  jobs-filter.jq '.[0].failed | type == "number"'
assert_jq     "job has active count"              jobs.json  jobs-filter.jq '.[0].active | type == "number"'
assert_jq     "job has completionTime"            jobs.json  jobs-filter.jq '.[0].completionTime | type == "string"'
assert_jq     "job has ownedByCronJob boolean"    jobs.json  jobs-filter.jq '.[0].ownedByCronJob | type == "boolean"'
assert_jq     "completed job: succeeded=1"        jobs.json  jobs-filter.jq '.[0].succeeded == 1'
echo ""

# ── configmaps-filter.jq ─────────────────────────────────────────────────────
echo "── configmaps-filter.jq ──"
assert_jq     "returns array"                     configmaps.json  configmaps-filter.jq '. | type == "array"'
assert_jq     "configmap has name"                configmaps.json  configmaps-filter.jq '.[0].name | type == "string"'
assert_jq     "configmap has created"             configmaps.json  configmaps-filter.jq '.[0].created | type == "string"'
assert_jq     "kube-root-ca.crt excluded"         configmaps.json  configmaps-filter.jq '[.[].name] | any(. == "kube-root-ca.crt") | not'
echo ""

# ── secrets-filter.jq ────────────────────────────────────────────────────────
echo "── secrets-filter.jq ──"
assert_jq     "returns array"                     secrets.json  secrets-filter.jq '. | type == "array"'
assert_jq     "tls secrets excluded"              secrets.json  secrets-filter.jq '[.[].name] | any(. == "tls-cert") | not'
assert_jq     "sa token secrets excluded"         secrets.json  secrets-filter.jq '[.[].name] | any(. == "default-token-abc") | not'
assert_jq     "opaque secret included"            secrets.json  secrets-filter.jq '[.[].name] | any(. == "app-secret")'
echo ""

# ── pod-cm-refs.jq ───────────────────────────────────────────────────────────
echo "── pod-cm-refs.jq ──"
assert_jq     "returns array of strings"          pods.json  pod-cm-refs.jq '. | type == "array"'
assert_jq     "app-config is referenced"          pods.json  pod-cm-refs.jq 'any(. == "app-config")'
echo ""

# ── pod-secret-refs.jq ───────────────────────────────────────────────────────
echo "── pod-secret-refs.jq ──"
assert_jq     "returns array of strings"          pods.json  pod-secret-refs.jq '. | type == "array"'
assert_jq     "app-secret is referenced"          pods.json  pod-secret-refs.jq 'any(. == "app-secret")'
echo ""

# ── pvc-mounts.jq ────────────────────────────────────────────────────────────
echo "── pvc-mounts.jq ──"
assert_valid_json "parses pods without pvc mounts" pods.json  pvc-mounts.jq
assert_jq         "returns array"                  pods.json  pvc-mounts.jq  '. | type == "array"'
echo ""

# ── pdb-filter.jq (extended) ─────────────────────────────────────────────────
echo "── pdb-filter.jq ──"
assert_jq     "has namespace field"               pdbs.json  pdb-filter.jq  '.[0].namespace | type == "string"'
assert_jq     "has selector field"                pdbs.json  pdb-filter.jq  '.[0].selector | type == "object"'
assert_jq     "has maxUnavailable field"          pdbs.json  pdb-filter.jq  '.[0] | has("maxUnavailable")'
echo ""

# ── workload-filter.jq ───────────────────────────────────────────────────────
echo "── workload-filter.jq ──"
assert_jq     "returns array"                     deployments.json  workload-filter.jq  '. | type == "array"'
assert_jq     "only includes replicas>1"          deployments.json  workload-filter.jq  '[.[].replicas] | all(. > 1)'
assert_jq     "single-app excluded"               deployments.json  workload-filter.jq  '[.[].name] | any(. == "single-app") | not'
assert_jq     "good-app included"                 deployments.json  workload-filter.jq  '[.[].name] | any(. == "good-app")'
assert_jq     "has kind field"                    deployments.json  workload-filter.jq  '.[0].kind | type == "string"'
assert_jq     "has selector field"                deployments.json  workload-filter.jq  '.[0].selector | type == "object"'
echo ""

# ── deploy-audit.jq ──────────────────────────────────────────────────────────
echo "── deploy-audit.jq ──"
assert_jq     "returns array"                     deployments.json  deploy-audit.jq  '. | type == "array"'
assert_jq     "has name"                          deployments.json  deploy-audit.jq  '.[0].name | type == "string"'
assert_jq     "has containers array"              deployments.json  deploy-audit.jq  '.[0].containers | type == "array"'
assert_jq     "container has image"               deployments.json  deploy-audit.jq  '.[0].containers[0].image | type == "string"'
assert_jq     "container has pullPolicy"          deployments.json  deploy-audit.jq  '.[0].containers[0].pullPolicy | type == "string"'
echo ""

# ── img-audit.jq ─────────────────────────────────────────────────────────────
# NOTE: live filter returns {summary:{total_pods,critical,high,ok}, pods:[...]} not a bare array.
echo "── img-audit.jq ──"
assert_jq     "output is an object"               pods.json  img-audit.jq  '. | type == "object"'
assert_jq     "has summary block"                 pods.json  img-audit.jq  'has("summary")'
assert_jq     "has pods array"                    pods.json  img-audit.jq  '.pods | type == "array"'
assert_jq     "summary has total_pods"            pods.json  img-audit.jq  '.summary | has("total_pods")'
assert_jq     "summary has critical count"        pods.json  img-audit.jq  '.summary | has("critical")'
assert_jq     "summary has high count"            pods.json  img-audit.jq  '.summary | has("high")'
assert_jq     "summary has ok count"              pods.json  img-audit.jq  '.summary | has("ok")'
assert_jq     "has namespace"                     pods.json  img-audit.jq  '.pods[0].namespace | type == "string"'
assert_jq     "has containers array"              pods.json  img-audit.jq  '.pods[0].containers | type == "array"'
assert_jq     "container has image"               pods.json  img-audit.jq  '.pods[0].containers[0].image | type == "string"'
echo ""

# ── argo-status.jq ───────────────────────────────────────────────────────────
echo "── argo-status.jq ──"
assert_jq     "returns array"                     argocd-apps.json  argo-status.jq  '. | type == "array"'
assert_jq     "app has name"                      argocd-apps.json  argo-status.jq  '.[0].name | type == "string"'
assert_jq     "app has sync status"               argocd-apps.json  argo-status.jq  '.[0].sync | type == "string"'
assert_jq     "app has health status"             argocd-apps.json  argo-status.jq  '.[0].health | type == "string"'
assert_jq     "app has autoSync boolean"          argocd-apps.json  argo-status.jq  '.[0].autoSync | type == "boolean"'
assert_jq     "app has selfHeal boolean"          argocd-apps.json  argo-status.jq  '.[0].selfHeal | type == "boolean"'
assert_jq     "synced app: sync=Synced"           argocd-apps.json  argo-status.jq  '.[0].sync == "Synced"'
echo ""

# ── argo-apps.jq (OutOfSync filter) ──────────────────────────────────────────
echo "── argo-apps.jq ──"
assert_jq     "returns array"                     argocd-apps.json  argo-apps.jq  '. | type == "array"'
assert_jq     "only OutOfSync apps returned"      argocd-apps.json  argo-apps.jq  '[.[].sync] | all(. == "OutOfSync")'
assert_jq     "drifted app has outOfSyncResources" argocd-apps.json argo-apps.jq  '.[0].outOfSyncResources | type == "array"'
assert_count  "one OutOfSync app"                 argocd-apps.json  argo-apps.jq  1
echo ""

# ── policyreport.jq ──────────────────────────────────────────────────────────
echo "── policyreport.jq ──"
assert_jq     "returns array"                     policyreports.json  policyreport.jq  '. | type == "array"'
assert_jq     "report has name"                   policyreports.json  policyreport.jq  '.[0].name | type == "string"'
assert_jq     "report has failures array"         policyreports.json  policyreport.jq  '.[0].failures | type == "array"'
assert_jq     "failure has policy"                policyreports.json  policyreport.jq  '.[0].failures[0].policy | type == "string"'
assert_jq     "failure has rule"                  policyreports.json  policyreport.jq  '.[0].failures[0].rule | type == "string"'
assert_jq     "failure has severity"              policyreports.json  policyreport.jq  '.[0].failures[0].severity | type == "string"'
assert_jq     "failure has message"               policyreports.json  policyreport.jq  '.[0].failures[0].message | type == "string"'
assert_count  "one report returned"               policyreports.json  policyreport.jq  1
echo ""

# ── hc-policy.jq ─────────────────────────────────────────────────────────────
echo "── hc-policy.jq ──"
assert_jq     "has total field"                   policyreports.json  hc-policy.jq  'has("total")'
assert_jq     "has failCount field"               policyreports.json  hc-policy.jq  'has("failCount")'
assert_jq     "has failures array"                policyreports.json  hc-policy.jq  '.failures | type == "array"'
assert_jq     "failCount is 2"                    policyreports.json  hc-policy.jq  '.failCount == 2'
assert_jq     "failure has policy"                policyreports.json  hc-policy.jq  '.failures[0].policy | type == "string"'
assert_jq     "failure has severity"              policyreports.json  hc-policy.jq  '.failures[0].severity | type == "string"'
echo ""

# ── node-filter.jq ───────────────────────────────────────────────────────────
echo "── node-filter.jq ──"
assert_jq     "returns array"                     nodes.json  node-filter.jq  '. | type == "array"'
assert_jq     "node has name"                     nodes.json  node-filter.jq  '.[0].name | type == "string"'
assert_jq     "node has instanceType"             nodes.json  node-filter.jq  '.[0].instanceType | type == "string"'
assert_jq     "node has allocatableCPU"           nodes.json  node-filter.jq  '.[0].allocatableCPU | type == "string"'
assert_jq     "node has allocatableMemory"        nodes.json  node-filter.jq  '.[0].allocatableMemory | type == "string"'
assert_jq     "node has kubeletVersion"           nodes.json  node-filter.jq  '.[0].kubeletVersion | type == "string"'
assert_count  "two nodes returned"                nodes.json  node-filter.jq  2
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
printf "  Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d skipped${NC}\n" $PASS $FAIL $SKIP
echo "═══════════════════════════════════════════════"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do
    echo "  ${RED}✗${NC} $e"
  done
fi

echo ""
[[ $FAIL -eq 0 ]]  # exit 0 if all pass, 1 if any failed
