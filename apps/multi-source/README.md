# Multi-source Application demo

This folder has **two multisource examples**:

1. **Git + Git** — one Application, two Git paths (base + extras), merged at sync.
2. **Helm + Git values** — one Application, external Helm chart + value overrides from this repo.

## Layout

```
apps/multi-source/
├── application.yaml              # Git+Git: two path sources
├── helm-demo-application.yaml    # Helm+Git: chart + $values from Git
├── base/                         # Git+Git source 1
│   ├── namespace.yaml
│   └── deployment.yaml
├── extras/                       # Git+Git source 2
│   └── configmap.yaml
├── helm-values/                  # Helm+Git: value overrides (ref: values)
│   └── values.yaml
├── TEST-HELM-DEMO.md             # How to test the Helm multisource demo
└── README.md
```

## How it works

| Source | Path | What it contributes |
|--------|------|---------------------|
| 1 | `apps/multi-source/base` | Namespace + Deployment |
| 2 | `apps/multi-source/extras` | ConfigMap |

Argo CD does **not** use `spec.source` when `spec.sources` is set. It:

1. Renders manifests for `base/`
2. Renders manifests for `extras/`
3. Merges them into one list
4. Syncs that list to the destination namespace

## Apply

1. Point `application.yaml` at your repo and branch (e.g. set `targetRevision` to `main` or `multiSource`).
2. Apply the Application:

   ```bash
   kubectl apply -f apps/multi-source/application.yaml
   ```

3. In Argo CD UI/CLI you should see one Application syncing all resources from both paths.

## Test the Helm multisource demo

See **[TEST-HELM-DEMO.md](./TEST-HELM-DEMO.md)** for step-by-step instructions to apply and verify the Helm + Git values Application (`helm-demo-application.yaml`).

## Takeaway

- **One Application** → **multiple `sources`** → **one combined sync**.
- Use this for related resources split across paths (or repos), not for grouping many unrelated apps (use ApplicationSets or app-of-apps for that).
