[.items[] | {
  namespace: (.metadata.namespace // "unknown"),
  pod: (.metadata.name // "unknown"),
  containers: (
    [(.spec.initContainers // [])[] | {name: (.name // ""), image: (.image // ""), init: true}] +
    [(.spec.containers // [])[] | {name: (.name // ""), image: (.image // ""), init: false}]
  ),
  imageIDs: [(.status.containerStatuses // [])[] | {name: (.name // ""), imageID: (.imageID // "")}]
}]
