[.items[] | {
  name: .metadata.name,
  selector: (.spec.selector.matchLabels // {}),
  minAvailable: (.spec.minAvailable // null),
  maxUnavailable: (.spec.maxUnavailable // null)
}]
