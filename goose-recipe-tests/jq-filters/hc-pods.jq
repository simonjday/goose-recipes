{
  total: (.items | length),
  empty_namespace: ((.items | length) == 0),
  notRunning: [.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | {name: .metadata.name, phase: .status.phase}],
  highRestarts: [.items[] | select(([.status.containerStatuses[]? | .restartCount] | max // 0) > 5) | {name: .metadata.name, restarts: ([.status.containerStatuses[]? | .restartCount] | max)}],
  oomKilled: [.items[] | select([.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any) | .metadata.name],
  notReady: [.items[] | select(([.status.containerStatuses[]? | .ready] | all) == false) | select(.status.phase == "Running") | .metadata.name]
}
