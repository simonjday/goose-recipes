[.items[] | {
  name: (.metadata.name // "unknown"),
  namespace: (.metadata.namespace // "unknown"),
  selector: (.spec.selector.matchLabels // {}),
  minAvailable: (.spec.minAvailable // null),
  maxUnavailable: (.spec.maxUnavailable // null)
}]
