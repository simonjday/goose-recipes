[.items[] | {
  name: (.metadata.name // "unknown"),
  phase: (.status.phase // "Unknown"),
  replicas: (.spec.replicas // 0),
  readyReplicas: (.status.readyReplicas // 0),
  conditions: [.status.conditions[]? | {
    type: .type,
    status: .status,
    message: (.message // "")
  }]
}]
