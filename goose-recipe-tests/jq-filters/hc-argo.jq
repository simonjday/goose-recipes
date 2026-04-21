{
  total: (.items | length),
  outOfSync: [.items[] | select(.status.sync.status == "OutOfSync") | {name: .metadata.name, health: .status.health.status}],
  degraded: [.items[] | select(.status.health.status == "Degraded" or .status.health.status == "Missing") | .metadata.name],
  syncFailed: [.items[] | select(.status.operationState.phase == "Failed") | .metadata.name],
  noAutoSync: [.items[] | select(.spec.syncPolicy.automated == null) | .metadata.name]
}
