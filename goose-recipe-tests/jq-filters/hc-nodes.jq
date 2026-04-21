{
  total: (.items | length),
  notReady: [.items[] | select((.status.conditions[] | select(.type=="Ready") | .status) != "True") | .metadata.name],
  memPressure: [.items[] | select((.status.conditions[] | select(.type=="MemoryPressure") | .status) == "True") | .metadata.name],
  diskPressure: [.items[] | select((.status.conditions[] | select(.type=="DiskPressure") | .status) == "True") | .metadata.name],
  versions: [.items[] | .status.nodeInfo.kubeletVersion] | unique
}
