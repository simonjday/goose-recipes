# Returns {summary, pods}
# Boolean fields use null-safe coalescing to correctly handle explicit false values.
# A pod "has findings" if any container fails resources, probes, image, or security checks,
# OR if the pod-level securityContext fails.

def has_findings:
  (.containers | any(
    (.hasRequests == false) or (.hasLimits == false) or
    (.hasLiveness == false) or (.hasReadiness == false) or
    (.image | test(":latest$") or (contains(":") | not)) or
    .allowPrivEsc or (.runAsNonRoot == false) or (.readOnlyRoot == false)
  )) or (.podSecCtx.runAsNonRoot == false);

{
  summary: {
    total_pods: (.items | length),
    resources_findings: ([.items[] | .spec.containers[] | select(
      ((.resources.requests.cpu == null) or (.resources.requests.memory == null)) or
      ((.resources.limits.cpu == null) or (.resources.limits.memory == null))
    )] | length),
    probes_findings: ([.items[] | .spec.containers[] | select(
      (.livenessProbe == null) or (.readinessProbe == null)
    )] | length),
    image_findings: ([.items[] | .spec.containers[] | select(
      (.image | test(":latest$")) or (.image | contains(":") | not)
    )] | length),
    security_findings: ([.items[] | .spec.containers[] | select(
      ((.securityContext.allowPrivilegeEscalation) | if . == null then true else . end) or
      ((.securityContext.runAsNonRoot) | if . == null then false else . end | not) or
      ((.securityContext.readOnlyRootFilesystem) | if . == null then false else . end | not)
    )] | length),
    security_pod_findings: ([.items[] | select(
      ((.spec.securityContext.runAsNonRoot) | if . == null then false else . end | not)
    )] | length),
    pods_with_findings: ([.items[] | {
      podSecCtx: {
        runAsNonRoot: ((.spec.securityContext.runAsNonRoot) | if . == null then false else . end)
      },
      containers: [.spec.containers[] | {
        hasRequests: ((.resources.requests.cpu != null) and (.resources.requests.memory != null)),
        hasLimits: ((.resources.limits.cpu != null) and (.resources.limits.memory != null)),
        hasLiveness: (.livenessProbe != null),
        hasReadiness: (.readinessProbe != null),
        image: .image,
        allowPrivEsc: ((.securityContext.allowPrivilegeEscalation) | if . == null then true else . end),
        runAsNonRoot: ((.securityContext.runAsNonRoot) | if . == null then false else . end),
        readOnlyRoot: ((.securityContext.readOnlyRootFilesystem) | if . == null then false else . end)
      }]
    } | select(has_findings)] | length),
    pods_clean: ([.items[] | {
      podSecCtx: {
        runAsNonRoot: ((.spec.securityContext.runAsNonRoot) | if . == null then false else . end)
      },
      containers: [.spec.containers[] | {
        hasRequests: ((.resources.requests.cpu != null) and (.resources.requests.memory != null)),
        hasLimits: ((.resources.limits.cpu != null) and (.resources.limits.memory != null)),
        hasLiveness: (.livenessProbe != null),
        hasReadiness: (.readinessProbe != null),
        image: .image,
        allowPrivEsc: ((.securityContext.allowPrivilegeEscalation) | if . == null then true else . end),
        runAsNonRoot: ((.securityContext.runAsNonRoot) | if . == null then false else . end),
        readOnlyRoot: ((.securityContext.readOnlyRootFilesystem) | if . == null then false else . end)
      }]
    } | select(has_findings | not)] | length)
  },
  pods: [.items[] | {
    name: .metadata.name,
    phase: (.status.phase // "Unknown"),
    restarts: ([.status.containerStatuses[]? | .restartCount] | max // 0),
    oomKilled: ([.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any),
    podSecCtx: {
      runAsNonRoot: ((.spec.securityContext.runAsNonRoot) | if . == null then false else . end),
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
      runAsNonRoot: ((.securityContext.runAsNonRoot) | if . == null then false else . end),
      allowPrivEsc: ((.securityContext.allowPrivilegeEscalation) | if . == null then true else . end),
      readOnlyRoot: ((.securityContext.readOnlyRootFilesystem) | if . == null then false else . end)
    }]
  }]
}
