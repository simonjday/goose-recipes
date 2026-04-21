{
  total: (.items | length),
  failCount: ([.items[] | .results[]? | select(.result == "fail")] | length),
  failures: [.items[] | .results[]? | select(.result == "fail") | {
    policy: (.policy // "unknown"),
    rule: (.rule // "unknown"),
    resource: ((.resources[0].name? // "unknown") // "unknown"),
    severity: (.severity // "unknown")
  }]
}
