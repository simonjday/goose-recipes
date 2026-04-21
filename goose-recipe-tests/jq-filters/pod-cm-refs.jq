[.items[] | select(.status.phase == "Running") | {
  volumeCMs: [.spec.volumes[]? | .configMap.name? // empty],
  envFromCMs: [.spec.containers[].envFrom[]? | .configMapRef.name? // empty],
  envCMs: [.spec.containers[].env[]? | .valueFrom.configMapKeyRef.name? // empty]
} | .volumeCMs + .envFromCMs + .envCMs] | flatten | unique
