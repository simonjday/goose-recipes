[.items[] | select(.status.phase == "Running") | {
  vols: [.spec.volumes[]? | .secret.secretName? // empty],
  envFrom: [.spec.containers[].envFrom[]? | .secretRef.name? // empty],
  envVars: [.spec.containers[].env[]? | .valueFrom.secretKeyRef.name? // empty]
} | .vols + .envFrom + .envVars] | flatten | unique
