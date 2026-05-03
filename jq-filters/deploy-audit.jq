[.items[] | {
  namespace: (.metadata.namespace // "unknown"),
  name: (.metadata.name // "unknown"),
  containers: [(.spec.template.spec.containers // [])[] | {
    name: (.name // "unknown"),
    image: (.image // ""),
    pullPolicy: (.imagePullPolicy // "IfNotPresent")
  }]
}]
