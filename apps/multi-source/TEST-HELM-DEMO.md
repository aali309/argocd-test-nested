# Test the Helm multisource demo

This runs the **Helm + Git values** multisource Application so you can see one app built from an external chart and your Git-hosted values.

## Prerequisites

- Argo CD installed and running (e.g. in-cluster or local).
- `kubectl` configured for that cluster.
- This repo (or your fork) reachable by Argo CD — repo must be in the same project’s `sourceRepos` (e.g. `default` allows common public repos and you may need to add your fork).

## 1. Point the Application at your repo/branch

Edit **`helm-demo-application.yaml`** and set:

- **`repoURL`** (under the source with `ref: values`) to your repo, e.g.  
  `https://github.com/<your-org>/argocd-test-nested.git`
- **`targetRevision`** to the branch you’re using, e.g. `main` or `multiSource`.

## 2. Add the repo to Argo CD (if needed)

If the Git repo isn’t in the project’s allowed sources, add it:

```bash
# Optional: add repo (replace with your repo URL and credentials if private)
argocd repo add https://github.com/aali309/argocd-test-nested.git
```

Or configure the `default` project to allow that repo.

## 3. Apply the Application

From the **repo root**:

```bash
kubectl apply -f apps/multi-source/helm-demo-application.yaml
```

Or with a full path:

```bash
kubectl apply -f /path/to/argocd-test-nested/apps/multi-source/helm-demo-application.yaml
```

## 4. Verify in Argo CD

- **UI:** Open the Application **helm-multisource-demo**. It should show **Synced** and list resources (e.g. Deployment, Service, from the nginx chart) in namespace `helm-multisource-demo`.
- **CLI:**

  ```bash
  argocd app get helm-multisource-demo
  argocd app manifests helm-multisource-demo   # optional: show rendered manifests
  ```

## 5. Verify in the cluster

```bash
kubectl get all -n helm-multisource-demo
kubectl get deployment -n helm-multisource-demo helm-multisource-demo -o yaml
```

You should see the nginx deployment with name `helm-multisource-demo` and replica count from **`apps/multi-source/helm-values/values.yaml`**.

## 6. Confirm it’s multisource

- In the Application spec you have **two** entries under `sources`: one Helm (Bitnami nginx), one Git with `ref: values`.
- The chart’s `valueFiles` use `$values/values.yaml`; `$values` is the Git source — so the chart is rendered with your Git-hosted values. No chart copy in your repo.

## Troubleshooting

| Issue | Check |
|-------|--------|
| App stays **OutOfSync** or **Progressing** | Sync policy and destination namespace; check Application events and Argo CD logs. |
| **InvalidSourceError** or revision errors | Repo URL and `targetRevision` (branch/tag) and that the path `apps/multi-source/helm-values` exists on that revision. |
| **Chart not found** | Bitnami repo is public; ensure project allows `https://charts.bitnami.com/bitnami`. |
| **values file not found** | Ensure `path: apps/multi-source/helm-values` and file `values.yaml` exist in that path on the chosen `targetRevision`. |

## Clean up

```bash
kubectl delete application helm-multisource-demo -n argocd
kubectl delete namespace helm-multisource-demo
```
