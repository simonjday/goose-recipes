[.items[] | select(
  .metadata.name != "kube-root-ca.crt" and
  (.metadata.ownerReferences // []) == []
) | {name: .metadata.name, created: .metadata.creationTimestamp}]
