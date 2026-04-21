# Goose Recipe Tests

A three-layer test suite for the Goose Kubernetes recipe library.

---

## Installation

Extract the zip into your goose-recipes repo root so the layout is:

```
goose-recipes/
├── k8s-pod-review.yaml
├── daily-cluster-health.yaml
├── ...                          ← your existing recipe files
├── jq-filters/
│   └── ...
└── goose-recipe-tests/          ← extracted zip contents go here
    ├── jq-filters/              ← fixed copies of your filters
    └── tests/
        ├── run-all-tests.sh
        └── ...
```

The scripts walk up two directory levels from `tests/` to find the recipe
YAML files in the repo root. If your layout differs, override with:

```zsh
RECIPES_DIR=/path/to/goose-recipes zsh tests/validate-recipes.sh
```

---

## Quickstart

```zsh
cd goose-recipes/goose-recipe-tests

# Run layers 1 and 2 immediately (no cluster, no API key needed)
zsh tests/run-filter-tests.sh
zsh tests/validate-recipes.sh

# Run everything (no LLM judge)
NO_LLM=true zsh tests/run-all-tests.sh
```

---

## Folder Structure

```
tests/
├── run-all-tests.sh        # Master runner — runs all three layers in order
│
├── validate-recipes.sh     # Layer 1: YAML structure checks
├── run-filter-tests.sh     # Layer 2: jq filter unit tests (static fixtures)
├── contract-test.sh        # Layer 3: LLM-as-judge output contract checks
│
├── generate-fixtures.sh    # One-off: dump kubectl JSON from goose-test namespace
├── capture-all.sh          # One-off: run all recipes and save outputs
│
├── fixtures/               # Static kubectl JSON fixtures (committed to git)
│   ├── pods.json
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
└── expected-outputs/       # Saved recipe outputs (not committed — generate locally)
    ├── k8s-pod-review.txt
    ├── pdb-coverage.txt
    └── ...
```

---

## Layer 1 — YAML Validation

Checks every `*.yaml` recipe file in the repo root for:
- Required top-level fields: `version`, `title`, `description`, `extensions`, `instructions`, `prompt`
- Semver-formatted `version`
- Extension block: `type: builtin`, valid name, timeout ≥ 60
- Parameters block: each entry has `key`, `input_type`, `default`
- Prompt references `jq-filters` (warns if not)
- Instructions contain `STRICT RULE / NO INLINE JQ` guard

**Requirements:** `yq` (falls back to `python3` if not installed)

```zsh
zsh tests/validate-recipes.sh
```

---

## Layer 2 — jq Filter Unit Tests

Feeds static fixture JSON files through each `jq-filters/*.jq` file and asserts the output shape. Tests run in under 5 seconds with no cluster or Goose install needed.

**Requirements:** `jq`

```zsh
zsh tests/run-filter-tests.sh
```

### Regenerating fixtures from a live cluster

The fixture files in `tests/fixtures/` are pre-populated stubs. To replace them with real data from your `goose-test` namespace:

```zsh
kubectl apply -f goose-test-manifests.yaml
zsh tests/generate-fixtures.sh
```

Commit the updated fixtures. They become the new baseline for filter tests.

---

## Layer 3 — Contract Tests

Checks that saved recipe outputs satisfy a structural contract — either via string pattern matching (no dependencies) or an LLM judge (requires `ANTHROPIC_API_KEY`).

### Step 1 — Capture outputs (once, against live cluster)

```zsh
# Single recipe
zsh tests/contract-test.sh capture k8s-pod-review

# All recipes (runs each in sequence with cool-down pauses)
zsh tests/capture-all.sh
```

### Step 2 — Check against contracts

```zsh
# Single recipe
zsh tests/contract-test.sh check k8s-pod-review

# All saved outputs
zsh tests/contract-test.sh all

# Without LLM judge (pattern checks only — always CI safe)
NO_LLM=true zsh tests/contract-test.sh all
```

### LLM judge backends

The judge call is pluggable. Set `LLM_BACKEND` to choose — `auto` (default) tries each in order until one works.

| Backend | How to use | Best for |
|---|---|---|
| `auto` | Default — tries anthropic → ollama → goose | Local dev |
| `ollama` | `LLM_BACKEND=ollama` — uses `OLLAMA_HOST` (default `localhost:11434`) | Local + self-hosted CI |
| `goose` | `LLM_BACKEND=goose` — runs `goose run --no-session` | Local — zero extra config if goose already works |
| `anthropic` | `LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-...` | GitHub Actions with secret |

```zsh
# Ollama (no API key — uses your existing OLLAMA_HOST)
LLM_BACKEND=ollama zsh tests/contract-test.sh all

# Goose + Ollama (uses your existing goose config)
LLM_BACKEND=goose JUDGE_MODEL=gemma4:latest zsh tests/contract-test.sh all

# Anthropic
LLM_BACKEND=anthropic ANTHROPIC_API_KEY=sk-... zsh tests/contract-test.sh all
```

Override the model with `JUDGE_MODEL=<model>`. Defaults per backend:
- `ollama` / `goose`: `qwen2.5:7b` (fast, low heat, sufficient for YES/NO)
- `anthropic`: `claude-haiku-4-5-20251001`

### Contract format

Each recipe has two contract definitions in `contract-test.sh`:

| Key | Purpose |
|---|---|
| `CONTRACT_PATTERNS[recipe]` | Pipe-separated grep patterns that must all appear in the output |
| `CONTRACT_QUESTIONS[recipe]` | YES/NO question sent to LLM judge to verify output structure |

To add a contract for a new recipe, add entries to both maps.

---

## CI / Automation

Layers 1 and 2 run without any external dependencies:

```yaml
# Example GitHub Actions step
- name: Test jq filters and recipe YAML
  run: |
    NO_LLM=true zsh tests/run-all-tests.sh
```

Layer 3 pattern checks also run without a cluster or API key:

```yaml
- name: Contract pattern checks (no LLM)
  run: |
    NO_LLM=true zsh tests/contract-test.sh all
```

For the LLM judge in CI, pick your backend:

```yaml
# Option A — Anthropic (set ANTHROPIC_API_KEY as a repo secret)
- name: Contract tests (Anthropic judge)
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: |
    LLM_BACKEND=anthropic zsh tests/contract-test.sh all

# Option B — Self-hosted Ollama runner (no API key needed)
- name: Contract tests (Ollama judge)
  env:
    OLLAMA_HOST: http://your-ollama-host:11434
  run: |
    LLM_BACKEND=ollama JUDGE_MODEL=qwen2.5:7b zsh tests/contract-test.sh all
```

---

## Test Coverage by Recipe

| Recipe | YAML ✓ | Filters ✓ | Contract patterns | LLM judge |
|---|---|---|---|---|
| k8s-pod-review | ✓ | pod-review, pdb-check | ✓ | ✓ |
| daily-cluster-health | ✓ | hc-nodes, hc-pods, hc-argo, hc-policy | ✓ | ✓ |
| pdb-coverage | ✓ | workload-filter, pdb-filter | ✓ | ✓ |
| image-tag-audit | ✓ | img-audit, deploy-audit | ✓ | ✓ |
| kyverno-policy-adherence | ✓ | policyreport, kyverno-policies | ✓ | ✓ |
| argocd-sync-status | ✓ | argo-status | ✓ | ✓ |
| argocd-drift-report | ✓ | argo-apps | ✓ | ✓ |
| confluent-component-health | ✓ | cfk-component, pod-health | ✓ | ✓ |
| pvc-health | ✓ | pvc-filter, pv-filter, pvc-mounts | ✓ | ✓ |
| namespace-resource-quota | ✓ | quota-filter, limitrange-filter | ✓ | ✓ |
| node-capacity-planning | ✓ | node-filter, pod-requests, ns-count | ✓ | ✓ |
| stale-resource-cleanup | ✓ | jobs-filter, terminal-pods, configmaps-filter, secrets-filter, pod-cm-refs, pod-secret-refs | ✓ | ✓ |
| kyverno-policy-coverage | ✓ | clusterpolicies, kyverno-exceptions | ✓ | ✓ |
| kyverno-exception-audit | ✓ | kyverno-exceptions | ✓ | ✓ |
| mtls-cert-expiry | ✓ | — (uses cert-check.sh) | ✓ | ✓ |
