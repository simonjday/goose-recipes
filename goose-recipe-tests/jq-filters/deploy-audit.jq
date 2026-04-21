[.items[] | {
  namespace: .metadata.namespace,
  name: .metadata.name,
  containers: [.spec.template.spec.containers[] | {
    name: .name,
    image: .image,
    pullPolicy: .imagePullPolicy
  }]
}]
