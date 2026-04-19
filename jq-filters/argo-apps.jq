[.items[] | {
  name: (.metadata.name // "unknown"),
  sync: (.status.sync.status // "Unknown"),
  health: (.status.health.status // "Unknown"),
  lastSyncResult: (.status.operationState.phase // "Unknown"),
  lastSyncTime: (.status.operationState.finishedAt // null),
  autoSync: (.spec.syncPolicy.automated != null),
  selfHeal: (.spec.syncPolicy.automated.selfHeal == true),
  ignoreDifferences: (.spec.ignoreDifferences // []),
  outOfSyncResources: [
    .status.resources[]? |
    select(.status == "OutOfSync") | {
      kind: (.kind // "unknown"),
      name: (.name // "unknown"),
      namespace: (.namespace // ""),
      requiresPruning: (.requiresPruning // false)
    }
  ]
} | select(.sync == "OutOfSync")]
