# Helm Source Integrity Demo

Test **Helm chart source integrity** (provenance verification) for both **traditional Helm repos** and **OCI Helm charts**. Uses public Bitnami charts so you can run this against any Argo CD instance without e2e fixtures.

## What this tests

- **AppProject `spec.sourceIntegrity.helm.policies`**: per-repo policy with `mode: none` (skip verification) or `mode: provenance` (require signed `.prov` and allowed GPG key).
- **Traditional Helm**: `repoURL: https://charts.bitnami.com/bitnami`, `chart: nginx`.
- **OCI Helm**: `repoURL: oci://registry-1.docker.io/bitnamicharts/nginx`.

See [docs/helm-provenance-verification-flow.md](../../docs/helm-provenance-verification-flow.md) for the full flow.

## Prerequisites

- Argo CD installed (with source integrity support; Argo CD 2.10+).
- `kubectl` and optionally `argocd` CLI.
- Namespace `argocd-e2e` exists (e.g. `kubectl create namespace argocd-e2e`). All Applications and AppProjects use this namespace.
- Default project allows `https://charts.bitnami.com/bitnami` and OCI; or add repos (see below).

## Scenarios

| Folder | Source | Policy | Expected |
|--------|--------|--------|----------|
| **01-pass-mode-none** | Helm (HTTPS) Bitnami nginx | `https://charts.bitnami.com/*` → mode none | Sync **passes** |
| **02-fail-provenance-required** | Same | Same repo → mode provenance + key | Sync **fails** (no .prov) |
| **03-pass-non-overlapping** | Same | Two policies (Bitnami HTTPS none, OCI provenance) | Sync **passes** (one match) |
| **04-fail-overlapping** | Same | Two policies both match Bitnami | Sync **fails** (multiple policies) |
| **05-fail-invalid-crd** | — | Project with empty `sourceIntegrity: {}` | **kubectl apply** fails |
| **06-pass-oci-mode-none** | OCI Bitnami nginx | `oci://registry-1.docker.io/bitnamicharts/*` → mode none | Sync **passes** |

## Apply order

Create **projects first**, then **applications** (apps reference the project).

```bash
# From repo root

# 1. Pass: mode none (traditional Helm)
kubectl apply -f apps/helm-source-integrity-demo/01-pass-mode-none/

# 2. Fail: provenance required (no .prov)
kubectl apply -f apps/helm-source-integrity-demo/02-fail-provenance-required/

# 3. Pass: non-overlapping policies
kubectl apply -f apps/helm-source-integrity-demo/03-pass-non-overlapping/

# 4. Fail: overlapping policies
kubectl apply -f apps/helm-source-integrity-demo/04-fail-overlapping/

# 5. Invalid project (expect apply error)
kubectl apply -f apps/helm-source-integrity-demo/05-fail-invalid-crd/
# Expected: Error ... sourceIntegrity ...

# 6. Pass: OCI Helm with mode none
kubectl apply -f apps/helm-source-integrity-demo/06-pass-oci-mode-none/
```

## Optional: add repos to default project

If your Argo CD restricts repos by project, ensure the default project (or the one used by these apps) allows:

- `https://charts.bitnami.com/bitnami`
- `oci://registry-1.docker.io/bitnamicharts/nginx` (or use a project that allows `*`).

Or add them explicitly:

```bash
argocd repo add https://charts.bitnami.com/bitnami --type helm
# OCI is usually allowed by default for public registries
```

## Verify

- **01, 03, 06**: In Argo CD UI, apps should be **Synced**; check namespaces `helm-integrity-01`, `helm-integrity-03`, `helm-integrity-06`.
- **02, 04**: Apps should show **ComparisonError** (or similar) with message about missing provenance or multiple policies.
- **05**: `kubectl apply` should fail on the project.

**Note:** All Applications and AppProjects use namespace `argocd-e2e`. Ensure that namespace exists (e.g. `kubectl create namespace argocd-e2e`) or that Argo CD is configured to use it.

## Cleanup

```bash
kubectl delete -f apps/helm-source-integrity-demo/06-pass-oci-mode-none/
kubectl delete -f apps/helm-source-integrity-demo/04-fail-overlapping/
kubectl delete -f apps/helm-source-integrity-demo/03-pass-non-overlapping/
kubectl delete -f apps/helm-source-integrity-demo/02-fail-provenance-required/
kubectl delete -f apps/helm-source-integrity-demo/01-pass-mode-none/
# 05: if project was applied before validation existed, delete manually
kubectl delete appproject helm-invalid-crd -n argocd-e2e 2>/dev/null || true
```
