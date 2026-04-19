[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  created: .metadata.creationTimestamp,
  exceptions: [.spec.exceptions[]? | {policy: .policyName, rules: .ruleNames}],
  matchAny: (.spec.match.any // []),
  matchAll: (.spec.match.all // [])
}]
