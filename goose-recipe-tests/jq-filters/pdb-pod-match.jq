# pdb-pod-match.jq
# Input: kubectl get pdb -n <namespace> -o json
# Output: structured list of PDBs with their selectors, ready for pod coverage matching.
# The model uses this alongside pod-review.jq output to determine which pods are covered.
#
# Each PDB entry includes:
#   - name, namespace
#   - selector: the matchLabels map used to match pods
#   - minAvailable / maxUnavailable: the disruption budget values
#   - currentHealthy / desiredHealthy / expectedPods: live status fields
#   - disruptionsAllowed: how many pods can currently be disrupted
#
# Usage:
#   kubectl get pdb -n <namespace> -o json | jq -f ./jq-filters/pdb-pod-match.jq

[.items[] | {
  name: (.metadata.name // "unknown"),
  namespace: (.metadata.namespace // "unknown"),
  selector: (.spec.selector.matchLabels // {}),
  selectorExpressions: (.spec.selector.matchExpressions // []),
  minAvailable: (.spec.minAvailable // null),
  maxUnavailable: (.spec.maxUnavailable // null),
  currentHealthy: (.status.currentHealthy // 0),
  desiredHealthy: (.status.desiredHealthy // 0),
  expectedPods: (.status.expectedPods // 0),
  disruptionsAllowed: (.status.disruptionsAllowed // 0)
}]
