[
  [.items[] | select((.status.phase // "") == "Running") | {
    node: (.spec.nodeName // "unknown"),
    namespace: (.metadata.namespace // "unknown"),
    pod: (.metadata.name // "unknown"),
    cpuRequest: (.spec.containers[].resources.requests.cpu? // "0m"),
    memRequest: (.spec.containers[].resources.requests.memory? // "0Mi")
  }] |
  group_by(.node) |
  .[] | {
    node: .[0].node,
    podCount: length,
    pods: [.[].pod],
    cpuRequests: [.[].cpuRequest],
    memRequests: [.[].memRequest]
  }
]
