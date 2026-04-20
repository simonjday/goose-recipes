([ .items[] |
  ((.metadata.ownerReferences // []) | map(select(.kind == "Job" or .kind == "CronJob")) | length > 0) as $is_job |
  # Get the correct workload name from ownerReferences chain
  # For Deployment pods: ownerRef is a ReplicaSet - strip the RS hash suffix to get deployment name
  # For Job pods: mark as job
  (if $is_job then "job"
   else
     (.metadata.ownerReferences[0].name // .metadata.name) |
     # Strip trailing -<hash> where hash is 9-10 alphanumeric chars (ReplicaSet suffix)
     gsub("-[bcdfghjklmnpqrstvwxz2456789]{9,10}$"; "")
   end
  ) as $workload |
  {
    name: .metadata.name,
    phase: (.status.phase // "Unknown"),
    restarts: ([.status.containerStatuses[]? | .restartCount] | max // 0),
    oomKilled: ([.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any),
    is_job: $is_job,
    workload: $workload,
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
    }],
    findings: [
      (.spec.containers[] |
        if ((.resources.requests.cpu == null) or (.resources.requests.memory == null) or
            (.resources.limits.cpu == null) or (.resources.limits.memory == null)) then
          "[RESOURCES] " + .name + ": missing cpu/memory requests or limits"
        else empty end
      ),
      (.spec.containers[] |
        if (.livenessProbe == null) then
          "[PROBES] " + .name + ": missing livenessProbe"
        else empty end
      ),
      (.spec.containers[] |
        if (.readinessProbe == null) then
          "[PROBES] " + .name + ": missing readinessProbe"
        else empty end
      ),
      (.spec.containers[] |
        if (.image | test(":") | not) or (.image | endswith(":latest")) then
          "[IMAGE] " + .name + ": image \"" + .image + "\" uses latest or untagged"
        else empty end
      ),
      (.spec.containers[] |
        if (.securityContext.runAsNonRoot != true) or
           (.securityContext.allowPrivilegeEscalation != false) or
           (.securityContext.readOnlyRootFilesystem != true) then
          "[SECURITY] " + .name + ": allowPrivilegeEscalation=" +
            (if .securityContext.allowPrivilegeEscalation == false then "false" else "true" end) +
            " / runAsNonRoot=" +
            (if .securityContext.runAsNonRoot == true then "true" else "false" end) +
            " / readOnlyRootFilesystem=" +
            (if .securityContext.readOnlyRootFilesystem == true then "true" else "false" end)
        else empty end
      ),
      (if (.spec.securityContext.runAsNonRoot != true) then
        "[SECURITY-POD] pod securityContext: runAsNonRoot=false"
      else empty end)
    ]
  }
]) as $pods |

{
  summary: {
    total_pods: ($pods | length),
    resources_findings: ($pods | [.[].findings[] | select(startswith("[RESOURCES]"))] | length),
    probes_findings:    ($pods | [.[].findings[] | select(startswith("[PROBES]"))] | length),
    image_findings:     ($pods | [.[].findings[] | select(startswith("[IMAGE]"))] | length),
    security_findings:  ($pods | [.[].findings[] | select(startswith("[SECURITY]") and (startswith("[SECURITY-POD]") | not))] | length),
    security_pod_findings: ($pods | [.[].findings[] | select(startswith("[SECURITY-POD]"))] | length),
    pods_with_findings: ($pods | [.[] | select(.findings | length > 0)] | length),
    pods_clean:         ($pods | [.[] | select(.findings | length == 0)] | length)
  },
  pods: $pods
}
