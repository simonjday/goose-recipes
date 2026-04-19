[.items[] | {
  name: (.metadata.name // "unknown"),
  sync: (.status.sync.status // "Unknown"),
  health: (.status.health.status // "Unknown"),
  lastSyncTime: (.status.operationState.finishedAt // null),
  lastSyncResult: (.status.operationState.phase // "Unknown"),
  autoSync: (.spec.syncPolicy.automated != null),
  selfHeal: (.spec.syncPolicy.automated.selfHeal == true),
  prune: (.spec.syncPolicy.automated.prune == true),
  source: (.spec.source.repoURL // "unknown"),
  revision: (.spec.source.targetRevision // "HEAD")
}]
