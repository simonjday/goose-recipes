[.items[] | {
  name: (.metadata.name // "unknown"),
  summary: (.summary // {}),
  failures: [.results[]? | select(.result == "fail") | {
    policy: (.policy // "unknown"),
    rule: (.rule // "unknown"),
    resource: ((.resources[0].name? // (.resources[0] | tostring)) // "unknown"),
    severity: (.severity // "unknown"),
    message: (.message // "")
  }]
}]
