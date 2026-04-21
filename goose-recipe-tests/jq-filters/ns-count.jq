[.items[] | select(.status.phase == "Running") | .metadata.namespace] |
group_by(.) | map({namespace: .[0], count: length}) | sort_by(-.count) | .[0:5]
