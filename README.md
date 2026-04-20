# Goose Kubernetes Recipes

A library of [Goose](https://github.com/aaif-goose/goose) AI agent recipes for Kubernetes platform operations, built around a Confluent for Kubernetes (CFK) / ArgoCD / Kyverno stack running on OpenShift or k3d.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Goose installed | `brew install goose` or see [goose docs](https://block.github.io/goose) |
| Ollama running | `ollama serve` |
| Model pulled | `ollama pull qwen3-coder:30b` |
| kubectl configured | Correct context pointing at your cluster |
| Goose default provider | Set to Ollama via `goose configure` |

---

## Model Selection

Not all recipes need the same model. Using a lighter model for summarisation tasks significantly reduces heat, fan noise, and runtime on Apple Silicon.

| Model | Best for | Approx size |
|---|---|---|
| `qwen3-coder:30b` | Recipes that generate kubectl patches, YAML fixes, or complex code | 18 GB |
| `gemma4:latest` | Health checks, summarisation, RAG status reporting | 9.6 GB |
| `qwen2.5-coder:7b` | Quick single-section checks, low-heat background runs | 4.7 GB |
| `llama3.2:3b` | Minimal resource use, simple queries only | 2.0 GB |

**Recommended split:**

```zsh
# Code-heavy recipes (patch generation, YAML output)
--model qwen3-coder:30b

# Summarisation / health check recipes
--model gemma4:latest

# Background / scheduled / low-priority runs
--model qwen2.5-coder:7b
```

---

## Quick Start

```zsh
# Run any recipe with default parameters
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/<recipe>.yaml

# Non-interactive / no session persistence (recommended for automation)
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/<recipe>.yaml --no-session
```

---

## Overriding Parameters

Every recipe has sensible defaults (usually `confluent` for namespace, `argocd` for ArgoCD namespace). Override any of them with `--params key=value`. You can pass multiple `--params` flags in one command.

```zsh
# Check a different namespace
goose run --model qwen3-coder:30b \
  --recipe ~/goose-recipes/k8s-pod-review.yaml \
  --params namespace=kafka

# Override multiple params at once
goose run --model qwen3-coder:30b \
  --recipe ~/goose-recipes/daily-cluster-health.yaml \
  --params namespace=kafka \
  --params argocd_namespace=openshift-gitops

# mtls-cert-expiry accepts space-separated namespaces in a single param
goose run --model qwen3-coder:30b \
  --recipe ~/goose-recipes/mtls-cert-expiry.yaml \
  --params "namespaces=confluent kafka monitoring"

# To create an output file report
goose run --model qwen3-coder:30b \
  --recipe k8s-pod-review.yaml \
  --params namespace=my-app \
  --no-session \
  > ./pod-review-my-app-$(date +%Y%m%d).md 2>&1
```

To see what parameters a recipe accepts, check the `parameters:` block at the bottom of its YAML file — each entry shows the key name, default value, and a description.

```zsh
# Quick way to see a recipe's parameters
grep -A4 "parameters:" ~/goose-recipes/<recipe>.yaml
```

---

## Parameter Name Cheat Sheet

Recipes use either `namespace` or `scope` as their primary parameter — not all use the same name. Using the wrong one causes the recipe to silently fall back to its default namespace.

| Recipe | Correct param | Example |
|---|---|---|
| `k8s-pod-review.yaml` | `namespace` | `--params namespace=goose-test` |
| `daily-cluster-health.yaml` | `namespace` | `--params namespace=goose-test` |
| `stale-resource-cleanup.yaml` | `namespace` | `--params namespace=goose-test` |
| `kyverno-policy-adherence.yaml` | `namespace` | `--params namespace=goose-test` |
| `kyverno-policy-coverage.yaml` | `namespace` | `--params namespace=goose-test` |
| `kyverno-exception-audit.yaml` | `max_exception_age_days` | `--params max_exception_age_days=60` |
| `confluent-component-health.yaml` | `namespace` | `--params namespace=goose-test` |
| `argocd-sync-status.yaml` | `argocd_namespace` | `--params argocd_namespace=argocd` |
| `argocd-drift-report.yaml` | `argocd_namespace` | `--params argocd_namespace=argocd` |
| `mtls-cert-expiry.yaml` | `namespaces` (space-separated) | `--params "namespaces=confluent kafka"` |
| `image-tag-audit.yaml` | `scope` | `--params scope=goose-test` |
| `pdb-coverage.yaml` | `scope` | `--params scope=goose-test` |
| `pvc-health.yaml` | `scope` | `--params scope=goose-test` |
| `namespace-resource-quota.yaml` | `scope` | `--params scope=goose-test` |
| `node-capacity-planning.yaml` | `warn_threshold` / `critical_threshold` | `--params warn_threshold=70` |

---

## Testing Recipes — goose-test Namespace

A purpose-built namespace with sample resources lets you test recipes without touching production namespaces. Each resource is deliberately good or bad to exercise specific recipe checks.

### What's in the namespace

| Resource | Kind | Replicas | Purpose |
|---|---|---|---|
| `good-app` | Deployment | 3 | Passes all pod-review checks — pinned tag, resources, probes, security ctx |
| `good-app-pdb` | PodDisruptionBudget | — | Covers `good-app` — pdb-coverage should show as protected |
| `bad-app` | Deployment | 2 | Fails: `nginx:latest` + `Always` pull, no probes, no security ctx, no PDB |
| `ugly-app` | Deployment | 2 | Fails: untagged `busybox`, no probes, no security ctx, no PDB |
| `single-app` | Deployment | 1 | Single replica — should NOT be flagged for missing PDB |
| `completed-job` | Job | — | Succeeded job — flagged by stale-resource-cleanup |
| `scheduled-job` | CronJob | — | CronJob present |
| `app-config` | ConfigMap | — | Used by `good-app` — should NOT be flagged as stale |
| `stale-config` | ConfigMap | — | Not referenced by any pod — flagged by stale-resource-cleanup |
| `app-secret` | Secret | — | Used by `good-app` — should NOT be flagged as stale |
| `unused-secret` | Secret | — | Not referenced by any pod — flagged by stale-resource-cleanup |
| `goose-test-quota` | ResourceQuota | — | Present — namespace-resource-quota shows as covered |
| `goose-test-limits` | LimitRange | — | Present — namespace-resource-quota shows as covered |

### Expected results per recipe

| Recipe | Command | Expected |
|---|---|---|
| `k8s-pod-review` | `--params namespace=goose-test` | `good-app` PASS, `bad-app` + `ugly-app` FAIL |
| `image-tag-audit` | `--params scope=goose-test` | `bad-app` CRITICAL (latest), `ugly-app` CRITICAL (untagged) |
| `pdb-coverage` | `--params scope=goose-test` | `good-app` protected, `bad-app` + `ugly-app` missing PDB |
| `stale-resource-cleanup` | `--params namespace=goose-test` | `completed-job`, `stale-config`, `unused-secret` flagged |
| `namespace-resource-quota` | `--params scope=goose-test` | Quota and LimitRange present, usage shown |

### Apply the test namespace

```zsh
# First time setup
kubectl apply -f ~/goose-recipes/goose-test-manifests.yaml

# Tear down and reapply cleanly
kubectl delete namespace goose-test
kubectl apply -f ~/goose-recipes/goose-test-manifests.yaml
```

> **Note:** The manifest includes `app` and `env` labels on all pod templates and minimal resource limits on deliberately-bad workloads (`ugly-app`, Job, CronJob) to satisfy Kyverno `require-pod-labels` and `require-resource-limits` enforce policies. The resources are still bad in the ways the recipes check — no probes, no security context, untagged/latest images.

### Run all test recipes in one pass

```zsh
NS=goose-test
MODEL=qwen3-coder:30b
RECIPES=~/goose-recipes

goose run --model $MODEL --recipe $RECIPES/k8s-pod-review.yaml         --params namespace=$NS --no-session
goose run --model $MODEL --recipe $RECIPES/image-tag-audit.yaml        --params scope=$NS     --no-session
goose run --model $MODEL --recipe $RECIPES/pdb-coverage.yaml           --params scope=$NS     --no-session
goose run --model $MODEL --recipe $RECIPES/stale-resource-cleanup.yaml --params namespace=$NS --no-session
goose run --model $MODEL --recipe $RECIPES/namespace-resource-quota.yaml --params scope=$NS   --no-session
```

---

## Recipe Library

### Previously Built

| Recipe | Description |
|---|---|
| `k8s-pod-review.yaml` | Pod best practice check (resources, probes, security context) |
| `argocd-sync-status.yaml` | ArgoCD app sync and health status |
| `kyverno-policy-adherence.yaml` | Kyverno violations per namespace with fixes |
| `daily-cluster-health.yaml` | Master RAG health check across all areas |

---

### New Recipes

---

#### `mtls-cert-expiry.yaml`

Scans TLS secrets across CFK namespaces, extracts certificate expiry dates and flags anything expiring within 30 days (AMBER) or 7 days (RED).

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `namespaces` | `confluent kafka` | Space-separated list of namespaces to scan |

**Usage**

```zsh
# Scan default CFK namespaces
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/mtls-cert-expiry.yaml

# Scan specific namespaces
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/mtls-cert-expiry.yaml \
  --params "namespaces=confluent kafka monitoring"
```

**What it checks**
- All `kubernetes.io/tls` secrets in each namespace
- Confluent-specific secrets containing `ca.crt`
- CFK component TLS secret references (Kafka, Schema Registry, REST Proxy, Control Center)
- Certificate subject and issuer

**Output**
```
RED    = expires ≤ 7 days  → immediate renewal required
AMBER  = expires ≤ 30 days → schedule renewal this week
GREEN  = expires > 30 days → no action needed
```

---

#### `confluent-component-health.yaml`

Checks all CFK custom resources for Ready/NotReady conditions, degraded replicas, and component-level issues. Cross-references CR status with actual pod state.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `namespace` | `confluent` | Namespace where CFK components are deployed |
| `operator_namespace` | `confluent` | Namespace where Confluent Operator is deployed |

**Usage**

```zsh
# Default
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/confluent-component-health.yaml

# Custom namespaces
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/confluent-component-health.yaml \
  --params namespace=kafka \
  --params operator_namespace=confluent-operator
```

**Components checked**
- Kafka (KRaft mode) — phase, readyReplicas, conditions
- Schema Registry
- Kafka REST Proxy
- Control Center
- Kafka Connect (if present)
- ksqlDB (if present)
- KafkaTopic CRs

**Output**

Tabular component health summary with replica counts, phase, and RAG status. Per-issue detail with describe and log commands.

---

#### `pdb-coverage.yaml`

Cluster-wide audit of all Deployments and StatefulSets with `replicas > 1` that have no matching PodDisruptionBudget. Produces a prioritised fix list with ready-to-apply YAML.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `scope` | `cluster` | Either `cluster` for all namespaces or a specific namespace name |

**Usage**

```zsh
# Cluster-wide
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/pdb-coverage.yaml

# Single namespace
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/pdb-coverage.yaml \
  --params scope=confluent
```

**Priority classification**

| Priority | Condition |
|---|---|
| HIGH | StatefulSet with replicas > 1, no PDB (Kafka brokers, databases) |
| MEDIUM | Deployment with replicas > 1, no PDB |
| LOW | PDB exists but misconfigured (e.g. minAvailable = replicas) |

**Output**

Summary table + per-workload fix with ready-to-apply `kubectl apply` YAML for each missing PDB.

---

#### `kyverno-policy-coverage.yaml`

Coverage gap analysis — identifies which namespaces and resource kinds have no Kyverno policies applied, and which Audit-mode policies should be promoted to Enforce.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `namespace` | `confluent` | Primary namespace for resource kind gap analysis |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/kyverno-policy-coverage.yaml

goose run --model qwen3-coder:30b --recipe ~/goose-recipes/kyverno-policy-coverage.yaml \
  --params namespace=kafka
```

**What it analyses**
- Which namespaces have no policies at all
- Per-namespace coverage of validate / mutate / verifyImages rule types
- Resource kind gaps: Pod, Deployment, StatefulSet, ServiceAccount, ClusterRoleBinding, Ingress, PVC
- Policies in Audit mode that cover security-critical rules (candidates for Enforce promotion)
- Active PolicyExceptions that may mask coverage

**Output**

Namespace coverage table, resource kind gap matrix, enforce promotion candidates with patch commands.

---

#### `stale-resource-cleanup.yaml`

Finds completed/failed Jobs, Pods in terminal states, and unused ConfigMaps/Secrets. Outputs a **commented-out** cleanup script for human review — does NOT auto-delete anything.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `namespace` | `confluent` | Namespace to scan |
| `max_job_age_hours` | `24` | Completed jobs older than this are flagged |
| `max_unused_age_days` | `7` | Unused ConfigMaps/Secrets older than this are flagged |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/stale-resource-cleanup.yaml

goose run --model qwen3-coder:30b --recipe ~/goose-recipes/stale-resource-cleanup.yaml \
  --params namespace=kafka \
  --params max_job_age_hours=48 \
  --params max_unused_age_days=14
```

> **Safety**: TLS secrets are always excluded from the cleanup candidate list. All delete commands in the output script are commented out and must be explicitly reviewed before running.

**Dry-run the generated script**

```zsh
# After saving the output script to cleanup.sh:
sed 's/kubectl delete/kubectl delete --dry-run=client/g' cleanup.sh | zsh
```

---

#### `namespace-resource-quota.yaml`

Checks all namespaces for ResourceQuota and LimitRange presence, flags namespaces missing either, and shows current usage vs limits.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `scope` | `cluster` | Either `cluster` for all namespaces or a specific namespace |

**Usage**

```zsh
# Cluster-wide audit
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/namespace-resource-quota.yaml

# Single namespace
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/namespace-resource-quota.yaml \
  --params scope=confluent
```

**Thresholds**

| Level | Condition |
|---|---|
| RED | Quota usage > 95% |
| AMBER | Quota usage > 80%, or namespace missing ResourceQuota/LimitRange |

**Output**

Quota usage table with percentage consumed, missing quota suggestions with ready-to-apply YAML, LimitRange defaults.

---

#### `node-capacity-planning.yaml`

Produces a per-node headroom report comparing allocatable vs requested vs actual resource consumption. Identifies the largest workload schedulable on each node and shows top namespaces by resource consumption.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `warn_threshold` | `80` | Percentage of allocatable at which to warn (AMBER) |
| `critical_threshold` | `95` | Percentage of allocatable at which to alert (RED) |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/node-capacity-planning.yaml

# Custom thresholds
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/node-capacity-planning.yaml \
  --params warn_threshold=70 \
  --params critical_threshold=90
```

**Metrics required**

`kubectl top nodes` requires metrics-server to be running. If absent the recipe falls back to requested-only analysis.

**Output**

Per-node table (allocatable / requested / actual / %), scheduling headroom per node, top 5 namespaces by resource consumption, specific recommendations.

---

#### `pvc-health.yaml`

Checks all PVCs for Pending/Lost state, PVs with Released/Failed status, StorageClass availability, and identifies unused PVCs not bound to any running pod.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `scope` | `cluster` | Either `cluster` for all namespaces or a specific namespace |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/pvc-health.yaml

goose run --model qwen3-coder:30b --recipe ~/goose-recipes/pvc-health.yaml \
  --params scope=confluent
```

**Status classifications**

| Status | Severity |
|---|---|
| PVC Pending or Lost | RED |
| PV Failed | RED |
| No default StorageClass | RED |
| PV Released (data may exist) | AMBER |
| PVC unmounted by any pod | AMBER |
| FailedMount / FailedAttachVolume events | Reported |

---

#### `image-tag-audit.yaml`

Cluster-wide scan for containers using `latest` or untagged images. Uses `jq` pre-filtering on all kubectl calls to avoid stream stall errors on large clusters.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `scope` | `confluent` | Either a specific namespace or `cluster` for all namespaces. **Always start with a specific namespace** before running cluster-wide. |

**Usage**

```zsh
# Single namespace first (recommended starting point)
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/image-tag-audit.yaml \
  --params scope=confluent

# Cluster-wide (only once single namespace run confirms it works)
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/image-tag-audit.yaml \
  --params scope=cluster
```

**Image classifications**

| Class | Condition |
|---|---|
| CRITICAL | Tag is `latest` or no tag specified |
| HIGH | Named tag present but no SHA digest pinning |
| OK | Image referenced by SHA digest |

**Output**

Per-namespace summary table, full list of offending images, digest pinning instructions, Kyverno policy YAML to enforce compliance.

---

#### `argocd-drift-report.yaml`

For every OutOfSync ArgoCD application, produces a human-readable analysis of what has drifted and classifies it as likely intentional vs accidental.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `argocd_namespace` | `argocd` | Namespace where ArgoCD is deployed |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/argocd-drift-report.yaml

goose run --model qwen3-coder:30b --recipe ~/goose-recipes/argocd-drift-report.yaml \
  --params argocd_namespace=openshift-gitops
```

**Drift classifications**

| Classification | Example |
|---|---|
| LIKELY INTENTIONAL | HPA changed replicas, operator-injected annotations |
| LIKELY ACCIDENTAL | Image tag changed outside Git, manual resource limit patch |
| REQUIRES PRUNING | Resource exists in cluster but not in Git |

**Output**

Per-app drift table with resource-level detail, cause analysis, `ignoreDifferences` YAML recommendations for intentional drift, sync commands for accidental drift.

---

#### `kyverno-exception-audit.yaml`

Compliance audit of all `PolicyException` resources — who created them, when, what rules they bypass, and whether they are still needed.

**Parameters**

| Parameter | Default | Description |
|---|---|---|
| `max_exception_age_days` | `90` | Exceptions older than this are flagged as potentially stale |

**Usage**

```zsh
goose run --model qwen3-coder:30b --recipe ~/goose-recipes/kyverno-exception-audit.yaml

goose run --model qwen3-coder:30b --recipe ~/goose-recipes/kyverno-exception-audit.yaml \
  --params max_exception_age_days=60
```

**Exception flags**

| Flag | Meaning |
|---|---|
| CRITICAL | Bypasses an Enforce-mode security rule |
| BROAD | Targets a namespace or all resources rather than a specific resource |
| STALE | Older than `max_exception_age_days` |
| ORPHANED | Targeted resource no longer exists — safe to delete |

**Output**

Full exception inventory table, per-exception detail with bypassed rule description, `kubectl delete` commands for orphaned exceptions, annotation commands for adding review dates to critical exceptions.

---

## Complete Recipe Library

```
~/goose-recipes/
├── daily-cluster-health.yaml       # Master RAG health check (runs all areas)
│
├── # Confluent / Kafka
├── confluent-component-health.yaml # CFK CR status + pod cross-reference
├── mtls-cert-expiry.yaml           # TLS cert expiry across CFK namespaces
│
├── # ArgoCD / GitOps
├── argocd-sync-status.yaml         # App sync + health status
├── argocd-drift-report.yaml        # OutOfSync drift analysis
│
├── # Kyverno / Policy
├── kyverno-policy-adherence.yaml   # Violations per namespace with fixes
├── kyverno-policy-coverage.yaml    # Coverage gap analysis
├── kyverno-exception-audit.yaml    # PolicyException compliance audit
│
├── # Workload Health
├── k8s-pod-review.yaml             # Pod best practice check
├── pdb-coverage.yaml               # PodDisruptionBudget coverage
├── image-tag-audit.yaml            # latest/untagged image scan
│
├── # Cluster Operations
├── namespace-resource-quota.yaml   # ResourceQuota + LimitRange audit
├── node-capacity-planning.yaml     # Node headroom + capacity report
├── pvc-health.yaml                 # PVC/PV/StorageClass health
└── stale-resource-cleanup.yaml     # Stale jobs, pods, configmaps, secrets
```

---

## Daily Health Check — Performance

### Problem: Model exits mid-run

The daily health check accumulates large amounts of JSON across sections. By the time the model reaches Section 3 (ArgoCD), the context window is often exhausted and Goose exits silently. The fix is twofold: use `jq` to pre-filter kubectl output, and use a lighter model.

### Fix 1 — Use a lighter model

`gemma4:latest` handles the health check's summarisation workload well and runs significantly cooler than `qwen3-coder:30b`:

```zsh
goose run --model gemma4:latest \
  --recipe ~/goose-recipes/daily-cluster-health.yaml \
  --no-session
```

### Fix 2 — Use jq-filtered output in the recipe prompt

Replace raw `kubectl ... -o json` calls with jq-filtered variants that extract only the fields the model needs. This keeps each section's output to a few KB rather than hundreds of KB.

Key patterns used in the optimised `daily-cluster-health.yaml`:

```zsh
# Instead of raw pod JSON (potentially MBs):
kubectl get pods -n confluent -o json

# Use jq to extract only what matters:
kubectl get pods -n confluent -o json | jq '[.items[] | {
  name: .metadata.name,
  phase: .status.phase,
  ready: [.status.containerStatuses[]? | .ready],
  restarts: [.status.containerStatuses[]? | .restartCount] | max,
  oomKilled: [.status.containerStatuses[]? | .lastState.terminated.reason? == "OOMKilled"] | any,
  images: [.spec.containers[].image]
}]'

# Events — last 10 warnings only:
kubectl get events -n confluent \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' \
  -o json | jq '[.items[-10:] | .[] | {
    reason: .reason, message: .message,
    object: .involvedObject.name, count: .count
  }]'

# ArgoCD apps — key fields only:
kubectl get applications.argoproj.io -n argocd -o json | jq '[.items[] | {
  name: .metadata.name,
  sync: .status.sync.status,
  health: .status.health.status,
  lastResult: .status.operationState.phase,
  autoSync: (.spec.syncPolicy.automated != null),
  selfHeal: (.spec.syncPolicy.automated.selfHeal == true)
}]'
```

### Fix 3 — Increase Ollama context window

Create a dedicated model variant with a larger context for health check runs:

```zsh
cat > /tmp/Modelfile-health << 'EOF'
FROM gemma4:latest
PARAMETER num_ctx 32768
PARAMETER num_predict 4096
EOF

ollama create gemma4-health -f /tmp/Modelfile-health
```

Then use `--model gemma4-health` for the daily check.

Also set a longer keep-alive to prevent Ollama dropping the connection mid-run:

```zsh
# Add to ~/.zshrc
export OLLAMA_KEEP_ALIVE=30m
```

### Fix 4 — Split into sections with cool-down pauses

Instead of one large recipe, run each section as a separate targeted recipe call with a sleep between them. This prevents context exhaustion and keeps the Mac cool:

```zsh
cat > ~/goose-recipes/run-daily-health.zsh << 'EOF'
#!/bin/zsh
REPORT_DIR="$HOME/cluster-health-reports"
mkdir -p "$REPORT_DIR"
DATE=$(date +%Y%m%d_%H%M)
LOG="$REPORT_DIR/health-$DATE.txt"
MODEL="gemma4:latest"
NS="confluent"
ARGO_NS="argocd"

echo "=== DAILY CLUSTER HEALTH: $(date) ===" > "$LOG"

run_check() {
  local label=$1
  local recipe=$2
  shift 2
  echo "\n--- $label ---" >> "$LOG"
  goose run --model $MODEL --recipe "$HOME/goose-recipes/$recipe" \
    --no-session "$@" >> "$LOG" 2>&1
  sleep 30  # cool-down between sections
}

run_check "NODES + WORKLOADS"   k8s-pod-review.yaml           --params namespace=$NS
run_check "ARGOCD SYNC"         argocd-sync-status.yaml       --params argocd_namespace=$ARGO_NS
run_check "KYVERNO ADHERENCE"   kyverno-policy-adherence.yaml --params namespace=$NS
run_check "CERT EXPIRY"         mtls-cert-expiry.yaml         --params "namespaces=$NS kafka"
run_check "PDB COVERAGE"        pdb-coverage.yaml             --params scope=$NS

echo "\n=== COMPLETE: $(date) ===" >> "$LOG"
echo "Report: $LOG"
EOF

chmod +x ~/goose-recipes/run-daily-health.zsh
```

### Scheduling with launchd (recommended over cron)

launchd allows setting `ProcessType: Background` which tells macOS to deprioritise the process, keeping your foreground work responsive:

```zsh
cat > ~/Library/LaunchAgents/com.goose.dailyhealth.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.goose.dailyhealth</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>/Users/simonjday/goose-recipes/run-daily-health.zsh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>7</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.goose.dailyhealth.plist
```

Reports are saved to `~/cluster-health-reports/health-<date>.txt` and ready to review when you sit down.

---

## Avoiding Stream Stall Errors

A common failure pattern across recipes is:

```
Stream decode error: Ollama stream stalled: no data received for 30s.
This may indicate the model is overwhelmed by the request payload.
```

This happens when a recipe runs `kubectl ... -o json` without filtering, dumping potentially megabytes of raw JSON into the model context. The fix is always the same: use `jq` to pre-filter output before it reaches the model.

**Rule of thumb: never pass raw `-o json` output to the model, and never pass multi-line jq as an inline shell argument.**

Two patterns that cause failures:

```zsh
# BAD 1 — raw JSON dumps megabytes into model context
kubectl get pods --all-namespaces -o json

# BAD 2 — multi-line jq inline causes shell quoting errors
kubectl get pods -n confluent -o json | jq '[
  .items[] | {
    namespace: .metadata.namespace   ← shell breaks here
  }
]'

# GOOD 1 — jq filter file avoids all quoting issues
cat > /tmp/pods.jq << 'JQ'
[.items[] | {
  namespace: .metadata.namespace,
  pod: .metadata.name,
  phase: .status.phase
}]
JQ
kubectl get pods -n confluent -o json | jq -f /tmp/pods.jq
rm /tmp/pods.jq

# GOOD 2 — single-line jq is safe inline (no quoting issues)
kubectl get pods -n confluent -o json | jq -r '.items[] | .metadata.name'
```

All recipes in this library use the `jq -f /tmp/filter.jq` pattern for any multi-line filter, and clean up temp files at the end of each run. Single-line jq expressions are used inline where the filter is short enough.

**Additional mitigations if stalls persist:**

```zsh
# 1. Use a namespace-scoped run before cluster-wide
--params scope=confluent      # instead of scope=cluster

# 2. Use gemma4 instead of qwen3-coder for read/summarise recipes
--model gemma4:latest

# 3. Increase Ollama timeout
export OLLAMA_KEEP_ALIVE=30m  # in ~/.zshrc

# 4. Create a larger context model variant
cat > /tmp/Modelfile-ops << 'EOF'
FROM qwen3-coder:30b
PARAMETER num_ctx 32768
EOF
ollama create qwen3-coder-ops -f /tmp/Modelfile-ops
# Then use: --model qwen3-coder-ops
```

Recipes that have been updated with jq filtering: all recipes in this library. If you add new recipes, always apply the jq pattern to every kubectl call that returns `-o json`.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `model not found` | Use bare model name: `--model qwen3-coder:30b` not `ollama/qwen3-coder:30b` |
| `sqlx-sqlite panic` | Run with `--no-session` or clear `~/Library/Application Support/Block/goose/sessions/` |
| `RecipeExtensionConfigInternal` | Extensions must use structured format: `type: builtin` / `name: developer` |
| `unexpected argument` | Don't use `--` for prompts — use `--recipe` or pipe via stdin |
| `metrics not available` | Install metrics-server; capacity planning falls back to requested-only mode |
| Goose exits mid-recipe | Context window exhausted — use jq-filtered prompts and/or `gemma4-health` model variant |
| Mac overheating / fans | Switch to `gemma4:latest`, use split script with `sleep 30` between sections, schedule via launchd at 07:00 |
| Ollama drops connection | Set `export OLLAMA_KEEP_ALIVE=30m` in `~/.zshrc` and restart `ollama serve` |
| `Stream stalled: no data for 30s` | Recipe passing raw `-o json` to model — add `\| jq '[...]'` filter to all kubectl calls; see Avoiding Stream Stall Errors section above |
| Wrong namespace used | Check param name — recipes use either `namespace` or `scope`, not both. See Parameter Name Cheat Sheet above |
| `can't open input file: ./cert-check.sh` | Running from Desktop or wrong directory — use absolute path: `zsh ~/git/goose-recipes/cert-check.sh` |

---

## Notes for MCP Server Variant

If switching recipes to use the `kubernetes-local` MCP server instead of kubectl, always use fully-qualified CRD names:

```
policyreport.wgpolicyk8s.io          (not: policyreport)
clusterpolicyreport.wgpolicyk8s.io   (not: clusterpolicyreport)
clusterpolicies.kyverno.io           (not: clusterpolicy)
applications.argoproj.io             (not: application)
kafka.platform.confluent.io          (not: kafka)
```

Plain short names return no results via MCP tool calls.
