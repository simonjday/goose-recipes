[.items[] | {
  name: .metadata.name,
  action: .spec.validationFailureAction,
  rules: [.spec.rules[] | {
    name: .name,
    type: (if .validate then "validate" elif .mutate then "mutate" elif .generate then "generate" elif .verifyImages then "verifyImages" else "other" end),
    kinds: (.match.any[0].resources.kinds // []),
    namespaces: (.match.any[0].resources.namespaces // ["*"])
  }]
}]
