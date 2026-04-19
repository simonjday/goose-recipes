[.items[] | {
  name: .metadata.name,
  action: .spec.validationFailureAction,
  rules: [.spec.rules[] | {
    name: .name,
    type: (if .validate then "validate" elif .mutate then "mutate" elif .generate then "generate" else "other" end)
  }]
}]
