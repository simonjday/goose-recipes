[.items[] | select(
  (.status.phase == "Succeeded") or
  (.status.phase == "Failed") or
  (.status.reason == "Evicted")
) | {
  name: (.metadata.name // "unknown"),
  phase: (.status.phase // "Unknown"),
  reason: (.status.reason // ""),
  created: (.metadata.creationTimestamp // "")
}]
