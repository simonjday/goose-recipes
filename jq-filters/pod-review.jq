[.items[] | {
  name: .metadata.name,
  phase: (.status.phase // "Unknown"),
  restarts: ([.status.containerStatuses[]? | .restartCount] | max // 0),
  oomKilled: ([.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any),
  podSecCtx: {
    runAsNonRoot: (.spec.securityContext.runAsNonRoot // false),
    runAsUser: (.spec.securityContext.runAsUser // null)
  },
  containers: [.spec.containers[] | {
    name: .name,
    image: .image,
    hasRequests: ((.resources.requests.cpu != null) and (.resources.requests.memory != null)),
    hasLimits: ((.resources.limits.cpu != null) and (.resources.limits.memory != null)),
    hasLiveness: (.livenessProbe != null),
    hasReadiness: (.readinessProbe != null),
    pullPolicy: (.imagePullPolicy // "IfNotPresent"),
    runAsNonRoot: (.securityContext.runAsNonRoot // false),
    allowPrivEsc: (.securityContext.allowPrivilegeEscalation // true),
    readOnlyRoot: (.securityContext.readOnlyRootFilesystem // false)
  }]
}]
