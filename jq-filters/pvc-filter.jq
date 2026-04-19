[.items[] | {
  name: (.metadata.name // "unknown"),
  namespace: (.metadata.namespace // "unknown"),
  phase: (.status.phase // "Unknown"),
  storageClass: (.spec.storageClassName // ""),
  capacity: (.status.capacity.storage // "unknown"),
  volumeName: (.spec.volumeName // ""),
  age: (.metadata.creationTimestamp // "")
}]
