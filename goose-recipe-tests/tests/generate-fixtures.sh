#!/bin/zsh
# tests/generate-fixtures.sh
#
# Generates static kubectl JSON fixture files from the goose-test namespace.
# Run this once against a live cluster after applying goose-test-manifests.yaml.
# Commit the resulting fixtures/ directory — filter tests then run with no cluster needed.
#
# Usage:
#   kubectl apply -f ../goose-test-manifests.yaml
#   zsh tests/generate-fixtures.sh
#
# Optional: point at a different namespace
#   NAMESPACE=my-app zsh tests/generate-fixtures.sh

set -euo pipefail

NAMESPACE=${NAMESPACE:-goose-test}
FIXTURES_DIR="$(dirname "$0")/fixtures"

echo "=== Generating fixtures from namespace: $NAMESPACE ==="
echo "Output dir: $FIXTURES_DIR"
echo ""

mkdir -p "$FIXTURES_DIR"

# ── Helper ────────────────────────────────────────────────────────────────────
dump() {
  local label=$1
  local outfile="$FIXTURES_DIR/$2"
  shift 2
  echo -n "  Dumping $label ... "
  if kubectl "$@" > "$outfile" 2>/dev/null; then
    echo "OK ($(wc -c < "$outfile" | tr -d ' ') bytes)"
  else
    echo "SKIPPED (resource not available or no items)"
    echo '{"items":[]}' > "$outfile"
  fi
}

# ── Wait for pods to be ready ─────────────────────────────────────────────────
echo "Waiting up to 60s for pods in $NAMESPACE to start ..."
kubectl wait --for=condition=ready pod --all -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
echo ""

# ── Namespace-scoped resources ────────────────────────────────────────────────
echo "── Namespace-scoped ($NAMESPACE) ──"
dump "pods"          pods.json          get pods          -n "$NAMESPACE" -o json
dump "deployments"   deployments.json   get deployments   -n "$NAMESPACE" -o json
dump "statefulsets"  statefulsets.json  get statefulsets  -n "$NAMESPACE" -o json
dump "pdbs"          pdbs.json          get pdb           -n "$NAMESPACE" -o json
dump "pvcs"          pvcs.json          get pvc           -n "$NAMESPACE" -o json
dump "jobs"          jobs.json          get jobs          -n "$NAMESPACE" -o json
dump "configmaps"    configmaps.json    get configmaps    -n "$NAMESPACE" -o json
dump "secrets"       secrets.json       get secrets       -n "$NAMESPACE" -o json
dump "events"        events.json        get events        -n "$NAMESPACE" -o json
dump "policyreports" policyreports.json get policyreport.wgpolicyk8s.io -n "$NAMESPACE" -o json

# ── Cluster-scoped resources ──────────────────────────────────────────────────
echo ""
echo "── Cluster-scoped ──"
dump "nodes"            nodes.json            get nodes                              -o json
dump "pvs"              pvs.json              get pv                                 -o json
dump "storageclasses"   storageclasses.json   get storageclass                       -o json
dump "namespaces"       namespaces.json       get namespaces                         -o json
dump "clusterpolicies"  clusterpolicies.json  get clusterpolicies.kyverno.io         -o json
dump "cluspolicyreports" clusterpolicyreports.json get clusterpolicyreport.wgpolicyk8s.io -o json
dump "argocd-apps"      argocd-apps.json      get applications.argoproj.io -n argocd -o json
dump "policyexceptions" policyexceptions.json get policyexceptions.kyverno.io --all-namespaces -o json

echo ""
echo "=== Done. $(ls "$FIXTURES_DIR"/*.json | wc -l | tr -d ' ') fixture files written to $FIXTURES_DIR ==="
echo ""
echo "Next steps:"
echo "  zsh tests/run-filter-tests.sh      # test all jq filters"
echo "  zsh tests/validate-recipes.sh      # validate recipe YAML structure"
