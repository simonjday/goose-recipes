# Input: kubectl get pdb -o json
# Returns PDB selectors as both a map and a string for matching
[.items[] | {
  pdb_name: .metadata.name,
  namespace: .metadata.namespace,
  selector: (.spec.selector.matchLabels // {}),
  minAvailable: (.spec.minAvailable // null),
  maxUnavailable: (.spec.maxUnavailable // null),
  # Build sorted key=value pairs - used for exact workload matching
  # e.g. "app=good-app" only matches workload "good-app", not "bad-app"
  selector_string: (.spec.selector.matchLabels // {} | to_entries | map(.key + "=" + .value) | sort | join(",")),
  # Extract just the label values for easier matching
  selector_values: (.spec.selector.matchLabels // {} | [values[]])
}]
