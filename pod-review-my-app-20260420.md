Loading recipe: K8s Pod Best Practice Review
Description: Reviews pods against Kubernetes best practices. Uses pre-built jq filter files — no inline jq required or permitted.
Parameters used to load this recipe:
   namespace: my-app


    __( O)>  ● new session · ollama qwen3-coder:30b
   \____)    20260420_38 · /Users/simonjday/git/goose-recipes
     L L     goose is ready
I'll review the pods in the 'my-app' namespace against Kubernetes best practices following the specified steps.
  ────────────────────────────────────────
  ▸ shell
    command: ls ./jq-filters/pod-review.jq ./jq-filters/pdb-pod-match.jq

./jq-filters/pdb-pod-match.jq
./jq-filters/pod-review.jq
  ────────────────────────────────────────
  ▸ shell
    command: kubectl get pods -n my-app -o json | jq -f ./jq-filters/pod-review.jq

{
  "summary": {
    "total_pods": 3,
    "resources_findings": 0,
    "probes_findings": 6,
    "image_findings": 0,
    "security_findings": 3,
    "security_pod_findings": 3,
    "pods_with_findings": 3,
    "pods_clean": 0
  },
  "pods": [
    {
      "name": "my-app-my-app-dbf66f4bc-2jtrp",
      "phase": "Running",
      "restarts": 21,
      "oomKilled": false,
      "is_job": false,
      "workload": "my-app-my-app",
      "podSecCtx": {
        "runAsNonRoot": false,
        "runAsUser": null
      },
      "containers": [
        {
          "name": "my-app",
          "image": "nginx:stable",
          "hasRequests": true,
          "hasLimits": true,
          "hasLiveness": false,
          "hasReadiness": false,
          "pullPolicy": "IfNotPresent",
          "runAsNonRoot": false,
          "allowPrivEsc": true,
          "readOnlyRoot": false
        }
      ],
      "findings": [
        "[PROBES] my-app: missing livenessProbe",
        "[PROBES] my-app: missing readinessProbe",
        "[SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false",
        "[SECURITY-POD] pod securityContext: runAsNonRoot=false"
      ]
    },
    {
      "name": "my-app-my-app-dbf66f4bc-c8s2g",
      "phase": "Running",
      "restarts": 21,
      "oomKilled": false,
      "is_job": false,
      "workload": "my-app-my-app",
      "podSecCtx": {
        "runAsNonRoot": false,
        "runAsUser": null
      },
      "containers": [
        {
          "name": "my-app",
          "image": "nginx:stable",
          "hasRequests": true,
          "hasLimits": true,
          "hasLiveness": false,
          "hasReadiness": false,
          "pullPolicy": "IfNotPresent",
          "runAsNonRoot": false,
          "allowPrivEsc": true,
          "readOnlyRoot": false
        }
      ],
      "findings": [
        "[PROBES] my-app: missing livenessProbe",
        "[PROBES] my-app: missing readinessProbe",
        "[SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false",
        "[SECURITY-POD] pod securityContext: runAsNonRoot=false"
      ]
    },
    {
      "name": "my-app-my-app-dbf66f4bc-fbh2n",
      "phase": "Running",
      "restarts": 26,
      "oomKilled": false,
      "is_job": false,
      "workload": "my-app-my-app",
      "podSecCtx": {
        "runAsNonRoot": false,
        "runAsUser": null
      },
      "containers": [
        {
          "name": "my-app",
          "image": "nginx:stable",
          "hasRequests": true,
          "hasLimits": true,
          "hasLiveness": false,
          "hasReadiness": false,
          "pullPolicy": "IfNotPresent",
          "runAsNonRoot": false,
          "allowPrivEsc": true,
          "readOnlyRoot": false
        }
      ],
      "findings": [
        "[PROBES] my-app: missing livenessProbe",
        "[PROBES] my-app: missing readinessProbe",
        "[SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false",
        "[SECURITY-POD] pod securityContext: runAsNonRoot=false"
      ]
    }
  ]
}
  ────────────────────────────────────────
  ▸ shell
    command: kubectl get pdb -n my-app -o json | jq -f ./jq-filters/pdb-pod-match.jq

[]
  ────────────────────────────────────────
  ▸ shell
    command: kubectl get deployments,statefulsets -n my-app -o jsonpath='{range .items[*]}{.metadata.name}{" replicas="}{.spec.replicas}{"\n"}{end}'

my-app-my-app replicas=3Based on the information gathered from the steps, I'll now analyze the PDB coverage map and determine the verdict for each pod:

Step 5 - PDB coverage map:
- my-app-my-app: The deployment has 3 replicas (replicas > 1) and there is no PDB in the namespace that covers this workload, so it shows "missing"

Step 6 - Verdict determination:
- All three pods have findings (PROBES, SECURITY, SECURITY-POD) so they all fail regardless of PDB status
- Additionally, since there's no PDB covering this workload and the deployment has more than 1 replica, each pod gets a PDB issue

Step 7 - Output:

## Pod: my-app-my-app-dbf66f4bc-2jtrp
Findings:
  - [PROBES] my-app: missing livenessProbe
  - [PROBES] my-app: missing readinessProbe
  - [SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false
  - [SECURITY-POD] pod securityContext: runAsNonRoot=false
  - [PDB] no PodDisruptionBudget covers this workload
PDB: missing
Fix:
  kubectl patch deployment my-app-my-app -n my-app --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/livenessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 30, "periodSeconds": 10}}, {"op": "add", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 5, "periodSeconds": 5}}, {"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"runAsNonRoot": true, "readOnlyRootFilesystem": true, "allowPrivilegeEscalation": false}}]'

## Pod: my-app-my-app-dbf66f4bc-c8s2g
Findings:
  - [PROBES] my-app: missing livenessProbe
  - [PROBES] my-app: missing readinessProbe
  - [SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false
  - [SECURITY-POD] pod securityContext: runAsNonRoot=false
  - [PDB] no PodDisruptionBudget covers this workload
PDB: missing
Fix:
  kubectl patch deployment my-app-my-app -n my-app --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/livenessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 30, "periodSeconds": 10}}, {"op": "add", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 5, "periodSeconds": 5}}, {"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"runAsNonRoot": true, "readOnlyRootFilesystem": true, "allowPrivilegeEscalation": false}}]'

## Pod: my-app-my-app-dbf66f4bc-fbh2n
Findings:
  - [PROBES] my-app: missing livenessProbe
  - [PROBES] my-app: missing readinessProbe
  - [SECURITY] my-app: allowPrivilegeEscalation=true / runAsNonRoot=false / readOnlyRootFilesystem=false
  - [SECURITY-POD] pod securityContext: runAsNonRoot=false
  - [PDB] no PodDisruptionBudget covers this workload
PDB: missing
Fix:
  kubectl patch deployment my-app-my-app -n my-app --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/livenessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 30, "periodSeconds": 10}}, {"op": "add", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"httpGet": {"path": "/", "port": 80}, "initialDelaySeconds": 5, "periodSeconds": 5}}, {"op": "add", "path": "/spec/template/spec/containers/0/securityContext", "value": {"runAsNonRoot": true, "readOnlyRootFilesystem": true, "allowPrivilegeEscalation": false}}]'

## SUMMARY
-------
Pods reviewed: 3
PASS:  0
FAIL:  3
Findings by category:
  RESOURCES:    0
  PROBES:       6
  IMAGE:        0
  SECURITY:     3
  SECURITY-POD: 3
  PDB:          3
