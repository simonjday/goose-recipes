[.items[] | {
  name: (.metadata.name // "unknown"),
  phase: (.status.phase // "Unknown"),
  restarts: ([.status.containerStatuses[]? | .restartCount] | max // 0),
  ready: ([.status.containerStatuses[]? | .ready] | all),
  oomKilled: ([.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any)
}]
