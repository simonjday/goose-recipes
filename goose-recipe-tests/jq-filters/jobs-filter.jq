[.items[] | {
  name: (.metadata.name // "unknown"),
  created: (.metadata.creationTimestamp // ""),
  completionTime: (.status.completionTime // null),
  succeeded: (.status.succeeded // 0),
  failed: (.status.failed // 0),
  active: (.status.active // 0),
  ownedByCronJob: ([(.metadata.ownerReferences // [])[] | select(.kind == "CronJob")] | length > 0)
}]
