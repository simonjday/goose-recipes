[.items[] | {
  name: .metadata.name,
  hard: {
    cpu:    (.spec.hard["limits.cpu"]    // .spec.hard["requests.cpu"]    // "0"),
    memory: (.spec.hard["limits.memory"] // .spec.hard["requests.memory"] // "0"),
    pods:   (.spec.hard["pods"]          // "0")
  },
  used: {
    cpu:    (.status.used["limits.cpu"]    // .status.used["requests.cpu"]    // "0"),
    memory: (.status.used["limits.memory"] // .status.used["requests.memory"] // "0"),
    pods:   (.status.used["pods"]          // "0")
  }
}]
