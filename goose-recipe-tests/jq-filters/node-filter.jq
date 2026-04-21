[.items[] | {
  name: (.metadata.name // "unknown"),
  instanceType: (.metadata.labels["node.kubernetes.io/instance-type"] // "unknown"),
  allocatableCPU: (.status.allocatable.cpu // "0"),
  allocatableMemory: (.status.allocatable.memory // "0"),
  kubeletVersion: (.status.nodeInfo.kubeletVersion // "unknown")
}]
