[.items[] | {
  name: (.metadata.name // "unknown"),
  phase: (.status.phase // "Unknown"),
  storageClass: (.spec.storageClassName // ""),
  capacity: (.spec.capacity.storage // "unknown"),
  reclaimPolicy: (.spec.persistentVolumeReclaimPolicy // ""),
  claimRef: {
    name: (.spec.claimRef.name // ""),
    namespace: (.spec.claimRef.namespace // "")
  }
}]
