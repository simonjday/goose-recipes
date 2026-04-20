# Classify each container image
([ .items[] | {
  namespace: (.metadata.namespace // "unknown"),
  pod: (.metadata.name // "unknown"),
  containers: (
    [(.spec.initContainers // [])[] | {
      name: (.name // ""),
      image: (.image // ""),
      init: true,
      classification: (
        if (.image // "") | test("@sha256:") then "OK"
        elif (.image // "") | test(":") | not then "CRITICAL-untagged"
        elif (.image // "") | endswith(":latest") then "CRITICAL-latest"
        else "HIGH"
        end
      )
    }] +
    [(.spec.containers // [])[] | {
      name: (.name // ""),
      image: (.image // ""),
      init: false,
      classification: (
        if (.image // "") | test("@sha256:") then "OK"
        elif (.image // "") | test(":") | not then "CRITICAL-untagged"
        elif (.image // "") | endswith(":latest") then "CRITICAL-latest"
        else "HIGH"
        end
      )
    }]
  )
}]) as $pods |

# Flatten all containers across all pods for counting
($pods | [.[].containers[]] ) as $all |

{
  summary: {
    total_pods: ($pods | length),
    critical: ($all | map(select(.classification | startswith("CRITICAL"))) | length),
    high:     ($all | map(select(.classification == "HIGH")) | length),
    ok:       ($all | map(select(.classification == "OK")) | length)
  },
  pods: $pods
}
