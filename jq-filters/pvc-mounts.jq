[.items[] | select(.status.phase == "Running") |
  .spec.volumes[]? |
  select(.persistentVolumeClaim != null) |
  .persistentVolumeClaim.claimName
] | unique
