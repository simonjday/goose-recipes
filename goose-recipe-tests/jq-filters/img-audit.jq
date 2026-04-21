# Returns {summary, pods} — summary gives image classification counts, pods gives per-pod detail.
{
  summary: {
    total_pods: (.items | length),
    critical: ([.items[] | (.spec.initContainers // [])[] + (.spec.containers // [])[] |
      select((.image | test(":latest$")) or (.image | contains(":") | not))
    ] | length),
    high: ([.items[] | (.spec.initContainers // [])[] + (.spec.containers // [])[] |
      select(
        ((.image | test(":latest$")) or (.image | contains(":") | not)) | not
      ) | select(.image | contains("@sha256:") | not)
    ] | length),
    ok: ([.items[] | (.spec.initContainers // [])[] + (.spec.containers // [])[] |
      select(.image | contains("@sha256:"))
    ] | length)
  },
  pods: [.items[] | {
    namespace: (.metadata.namespace // "unknown"),
    pod: (.metadata.name // "unknown"),
    containers: (
      [(.spec.initContainers // [])[] | {name: (.name // ""), image: (.image // ""), init: true}] +
      [(.spec.containers // [])[] | {name: (.name // ""), image: (.image // ""), init: false}]
    ),
    imageIDs: [(.status.containerStatuses // [])[] | {name: (.name // ""), imageID: (.imageID // "")}]
  }]
}
