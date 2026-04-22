# Goose Recipe Tests

A three-layer test suite for the Goose Kubernetes recipe library.

---

## Installation

Extract the zip into your goose-recipes repo root so the layout is:

```
goose-recipes/
├── k8s-pod-review.yaml
├── k8s-pod-review-v2.yaml       ← copy from zip (see below)
├── daily-cluster-health.yaml
├── ...                          ← your existing recipe files
├── jq-filters/
│   └── ...
└── goose-recipe-tests/          ← extracted zip contents go here
    ├── jq-filters/              ← fixed/updated copies of your filters
    └── tests/
        ├── run-all-tests.sh
        └── ...
```

The `goose-recipe-tests/` folder contains only the test suite — no recipe YAML files.
Recipe files always live in the `goose-recipes/` root.

The scripts walk up two directory levels from `tests/` to find recipe YAML files
in the repo root. If your layout differs, override with:

```zsh
RECIPES_DIR=/path/to/goose-recipes zsh tests/validate-recipes.sh
```

After extracting, copy the updated files into your repo root:

```zsh
# Updated filter (excludes Succeeded pods, fixes boolean coalescing bug)
cp goose-recipe-tests/jq-filters/pod-review.jq jq-filters/pod-review.jq

# New missing filter required by k8s-pod-review-v2
cp goose-recipe-tests/jq-filters/pdb-pod-match.jq jq-filters/pdb-pod-match.jq

# New recipe
cp goose-recipe-tests/k8s-pod-review-v2.yaml k8s-pod-review-v2.yaml
```

---

## Prerequisites

| Tool | Required for | Install |
|---|---|---|
| `jq` | Filter tests | `brew install jq` |
| `yq` | YAML validation | `brew install yq` |
| `kubectl` | Fixture generation, captures | — |
| `goose` | Recipe captures | `brew install goose` |
| `glow` | Rendering recipe output | `brew install glow` |
| Ollama + `qwen3-coder:30b` | Recipe captures | `ollama pull qwen3-coder:30b` |

---

## Running Recipes

Recipes are run from the `goose-recipes/` directory (not inside `goose-recipe-tests/`).

### Basic run

```zsh
cd ~/git/goose-recipes

goose run \
  --model qwen3-coder:30b \
  --recipe k8s-pod-review-v2.yaml \
  --params namespace=goose-test \
  --no-session
```

### Render output with glow

Goose outputs plain markdown to the terminal. Pipe through `glow` to render
tables, headers, and code blocks properly:

```zsh
goose run \
  --model qwen3-coder:30b \
  --recipe k8s-pod-review-v2.yaml \
  --params namespace=goose-test \
  --no-session 2>&1 | glow -
```

### Save output and view

```zsh
goose run \
  --model qwen3-coder:30b \
  --recipe k8s-pod-review-v2.yaml \
  --params namespace=goose-test \
  --no-session \
  > ./pod-review-goose-test-$(date +%Y%m%d).md 2>&1

# Render the saved file
glow ./pod-review-goose-test-$(date +%Y%m%d).md

# Or open in your editor
open ./pod-review-goose-test-$(date +%Y%m%d).md
```

### Run against a different namespace

```zsh
goose run \
  --model qwen3-coder:30b \
  --recipe k8s-pod-review-v2.yaml \
  --params namespace=my-app \
  --no-session 2>&1 | glow -
```

### Model selection

| Model | Use for |
|---|---|
| `qwen3-coder:30b` | Recipes that execute shell tools and generate kubectl patches |
| `gemma4:latest` | Summarisation and health-check recipes (faster, cooler) |
| `qwen2.5-coder:7b` | **Not suitable** — does not reliably execute shell tools |

```zsh
# Summarisation recipes can use the lighter model
goose run \
  --model gemma4:latest \
  --recipe daily-cluster-health.yaml \
  --params namespace=confluent \
  --no-session 2>&1 | glow -
```

---

## Running the Test Suite

All test commands are run from inside `goose-recipe-tests/`:

```zsh
cd ~/git/goose-recipes/goose-recipe-tests
```

### Run everything

```zsh
# All three layers, no LLM judge (CI safe, no API key needed)
NO_LLM=true zsh tests/run-all-tests.sh
```

### Layer 1 — YAML structure validation

Checks every recipe YAML for required fields, valid extension config, and parameter definitions.
No cluster or API key needed.

```zsh
zsh tests/validate-recipes.sh
```

### Layer 2 — jq filter unit tests

Feeds static fixture JSON through each filter and asserts the output shape.
Runs in under 5 seconds. No cluster needed.

```zsh
zsh tests/run-filter-tests.sh
```

### Layer 3 — Contract tests

Verifies that saved recipe outputs contain the expected structure.

#### Step 1 — Capture a reference output (requires live cluster + goose)

Only `qwen3-coder:30b` reliably executes shell tools. Smaller models narrate
tool calls as text instead of running them, producing empty captures.

```zsh
# Capture a single recipe
CAPTURE_MODEL=qwen3-coder:30b \
zsh tests/contract-test.sh capture k8s-pod-review-v2

# Capture against a different namespace
CAPTURE_NAMESPACE=my-app \
CAPTURE_MODEL=qwen3-coder:30b \
zsh tests/contract-test.sh capture k8s-pod-review-v2

# Capture all recipes (runs sequentially with cool-down pauses)
MODEL=qwen3-coder:30b \
zsh tests/capture-all.sh
```

#### Step 2 — Check a captured output

```zsh
# Check single recipe (pattern checks only)
NO_LLM=true zsh tests/contract-test.sh check k8s-pod-review-v2

# Check all saved outputs
NO_LLM=true zsh tests/contract-test.sh all
```

#### LLM judge backends

The judge makes a YES/NO call on whether the output satisfies its contract.
Set `LLM_BACKEND` to choose — `auto` (default) tries each in order.

```zsh
# Ollama — uses your existing OLLAMA_HOST, no API key needed
LLM_BACKEND=ollama \
JUDGE_MODEL=qwen2.5:7b \
zsh tests/contract-test.sh all

# Goose + Ollama — zero extra config if goose already works
LLM_BACKEND=goose \
JUDGE_MODEL=qwen2.5:7b \
zsh tests/contract-test.sh all

# Anthropic
LLM_BACKEND=anthropic \
ANTHROPIC_API_KEY=sk-... \
zsh tests/contract-test.sh all
```

Default judge models: `qwen2.5:7b` for ollama/goose, `claude-haiku-4-5-20251001` for anthropic.
Override with `JUDGE_MODEL=<model>`.

---

## Folder Structure

```
tests/
├── run-all-tests.sh        # Master runner — runs all three layers in order
│
├── validate-recipes.sh     # Layer 1: YAML structure checks
├── run-filter-tests.sh     # Layer 2: jq filter unit tests (static fixtures)
├── contract-test.sh        # Layer 3: contract checks + LLM judge
│
├── generate-fixtures.sh    # One-off: dump kubectl JSON from goose-test namespace
├── capture-all.sh          # One-off: run all recipes and save reference outputs
│
├── fixtures/               # Static kubectl JSON fixtures (committed to git)
│   ├── pods.json           # 12 pods matching goose-test namespace (9 Running, 3 Succeeded)
│   ├── nodes.json
│   ├── pdbs.json
│   ├── pvcs.json
│   ├── deployments.json
│   ├── jobs.json
│   ├── configmaps.json
│   ├── secrets.json
│   ├── argocd-apps.json
│   └── policyreports.json
│
└── expected-outputs/       # Saved reference outputs (not committed — generate locally)
    ├── k8s-pod-review-v2.txt
    └── ...
```

---

## Regenerating Fixtures

The fixture files reflect the real `goose-test` namespace. Regenerate them after
applying changes to `goose-test-manifests.yaml`:

```zsh
kubectl apply -f ../goose-test-manifests.yaml
zsh tests/generate-fixtures.sh
```

Commit the updated fixtures — they become the new baseline for filter tests.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no matches found: *.yaml` | Run from inside `goose-recipe-tests/`, not the repo root |
| `Filters: .../goose-recipes/jq-filters` | Wrong path — set `FILTERS_DIR=goose-recipe-tests/jq-filters` |
| Capture produces narrated tool calls | Wrong model — only `qwen3-coder:30b` executes tools reliably |
| Goose session DB error | `rm -rf ~/Library/Application\ Support/Block/goose/` then retry |
| Capture stalls after data collection | Model timed out generating report — increase timeout: `OLLAMA_REQUEST_TIMEOUT=300 ollama serve` |
| `parse error near '\n'` in contract-test.sh | Replace with the clean version from the latest zip |
| Filter tests fail on pod counts | Fixture is stale — run `zsh tests/generate-fixtures.sh` |

---

## CI / Automation

Layers 1 and 2 run without any external dependencies:

```yaml
- name: Validate recipes and test jq filters
  run: |
    cd goose-recipe-tests
    NO_LLM=true zsh tests/run-all-tests.sh
```

Layer 3 pattern checks also need no cluster or API key — just committed
reference outputs in `expected-outputs/`:

```yaml
- name: Contract pattern checks
  run: |
    cd goose-recipe-tests
    NO_LLM=true zsh tests/contract-test.sh all
```

For the LLM judge in CI:

```yaml
# Option A — Anthropic (set ANTHROPIC_API_KEY as a repo secret)
- name: Contract tests with LLM judge
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    cd goose-recipe-tests
    LLM_BACKEND=anthropic zsh tests/contract-test.sh all

# Option B — Self-hosted Ollama runner
- name: Contract tests with Ollama judge
  env:
    OLLAMA_HOST: http://your-ollama-host:11434
  run: |
    cd goose-recipe-tests
    LLM_BACKEND=ollama JUDGE_MODEL=qwen2.5:7b zsh tests/contract-test.sh all
```

---

## Test Coverage by Recipe

| Recipe | YAML | Filters | Contract | Notes |
|---|---|---|---|---|
| k8s-pod-review-v2 | ✓ | pod-review, pdb-pod-match | ✓ | Recommended version |
| k8s-pod-review | ✓ | pod-review, pdb-check | ✓ | Superseded by v2 |
| daily-cluster-health | ✓ | hc-nodes, hc-pods, hc-argo, hc-policy | ✓ | |
| pdb-coverage | ✓ | workload-filter, pdb-filter | ✓ | |
| image-tag-audit | ✓ | img-audit, deploy-audit | ✓ | |
| kyverno-policy-adherence | ✓ | policyreport, kyverno-policies | ✓ | |
| argocd-sync-status | ✓ | argo-status | ✓ | |
| argocd-drift-report | ✓ | argo-apps | ✓ | |
| confluent-component-health | ✓ | cfk-component, pod-health | ✓ | |
| pvc-health | ✓ | pvc-filter, pv-filter, pvc-mounts | ✓ | |
| namespace-resource-quota | ✓ | quota-filter, limitrange-filter | ✓ | |
| node-capacity-planning | ✓ | node-filter, pod-requests, ns-count | ✓ | |
| stale-resource-cleanup | ✓ | jobs-filter, terminal-pods, configmaps-filter, secrets-filter, pod-cm-refs, pod-secret-refs | ✓ | |
| kyverno-policy-coverage | ✓ | clusterpolicies, kyverno-exceptions | ✓ | |
| kyverno-exception-audit | ✓ | kyverno-exceptions | ✓ | |
| mtls-cert-expiry | ✓ | — (cert-check.sh) | ✓ | |
