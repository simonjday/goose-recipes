[.items[] | select((.spec.replicas // 0) > 1) | {
  kind: (.kind // "unknown"),
  name: (.metadata.name // "unknown"),
  namespace: (.metadata.namespace // "unknown"),
  replicas: (.spec.replicas // 0),
  selector: (.spec.selector.matchLabels // {})
}]
