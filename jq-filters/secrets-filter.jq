[.items[] | select(
  .type != "kubernetes.io/tls" and
  .type != "kubernetes.io/service-account-token" and
  (.metadata.ownerReferences // []) == []
) | {name: .metadata.name, type: .type, created: .metadata.creationTimestamp}]
