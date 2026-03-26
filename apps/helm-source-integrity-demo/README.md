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
- **`ARGOCD_GPG_ENABLED=true`** on the repo-server. If `false` or unset in some setups, provenance verification is skipped and apps that should fail (02, 03-oci, 04) will pass instead.

## One-time setup

Run `./demo-setup.sh` from this directory, or apply manually:

```bash
kubectl apply -f namespaces.yaml
kubectl apply -f rbac.yaml
kubectl apply -f cluster-rbac.yaml
```

- `rbac.yaml` – grants the controller permission to manage resources in `helm-integrity-*` namespaces (namespace-scoped).
- `cluster-rbac.yaml` – grants the controller cluster-scoped list/get (for cluster cache sync). Required when Argo CD is in `argocd-e2e` without a ClusterRoleBinding.

## Scenarios

| Folder | Source | Policy | Expected |
|--------|--------|--------|----------|
| **01-pass-mode-none** | OCI Bitnami nginx | `oci://...bitnamicharts/*` → mode none | Sync **passes** (OCI avoids .prov 403) |
| **02-fail-provenance-required** | HTTPS Bitnami nginx | Same repo → mode provenance + key | Sync **fails** (no .prov or 403) |
| **03-pass-non-overlapping** | HTTPS + OCI Bitnami nginx | Two policies (HTTPS none, OCI provenance) | App 1 **passes**, App 2 **fails** (provenance required) |
| **04-fail-overlapping** | HTTPS Bitnami nginx | Two policies both match Bitnami | Sync **fails** (multiple policies) |
| **05-fail-invalid-crd** | — | Project with empty `sourceIntegrity: {}` | **kubectl apply** fails |
| **06-pass-oci-mode-none** | OCI Bitnami nginx | `oci://registry-1.docker.io/bitnamicharts/*` → mode none | Sync **passes** |
| **07-pass-custom-signed-helm** | Your own Helm chart (signed) | Custom repo URL → mode provenance + your key | Sync **passes** (see [custom-charts/](custom-charts/)) |
| **08-pass-custom-signed-oci** | Your own OCI chart (signed) | Custom OCI registry → mode provenance + your key | Sync **passes** (see [custom-charts/](custom-charts/)) |

## Apply order

Create **projects first**, then **applications** (apps reference the project).

```bash
# From repo root

# 1. Pass: mode none (OCI chart — avoids 403 on .prov)
kubectl apply -f apps/helm-source-integrity-demo/01-pass-mode-none/

# 2. Fail: provenance required (no .prov)
kubectl apply -f apps/helm-source-integrity-demo/02-fail-provenance-required/

# 3. Pass/Fail: non-overlapping policies (app 1 passes, app-oci fails)
kubectl apply -f apps/helm-source-integrity-demo/03-pass-non-overlapping/

# 4. Fail: overlapping policies
kubectl apply -f apps/helm-source-integrity-demo/04-fail-overlapping/

# 5. Invalid project (expect apply error)
kubectl apply -f apps/helm-source-integrity-demo/05-fail-invalid-crd/
# Expected: Error ... sourceIntegrity ...

# 6. Pass: OCI Helm with mode none
kubectl apply -f apps/helm-source-integrity-demo/06-pass-oci-mode-none/

# 7–8. Custom signed charts (your own chart + GPG): see custom-charts/README.md
#      After running custom-charts/scripts (gen-gpg-key, package-and-sign, serve or push OCI):
# kubectl apply -f apps/helm-source-integrity-demo/07-pass-custom-signed-helm/
# kubectl apply -f apps/helm-source-integrity-demo/08-pass-custom-signed-oci/
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

- **01, 03 (app only), 06**: In Argo CD UI, `helm-mode-none-demo`, `helm-non-overlapping-demo`, `helm-oci-mode-none-demo` should be **Synced**; check namespaces `helm-integrity-01`, `helm-integrity-03`, `helm-integrity-06`.
- **03 (app-oci)**: `helm-non-overlapping-oci-demo` should **fail** with "Chart is missing the required provenance (.prov) file" (Policy 2 applies, mode provenance).
- **02, 04**: Apps should show **ComparisonError** (e.g. missing provenance, **provenance URL returned 403 Forbidden**, or multiple policies). Bitnami’s HTTPS repo often returns 403 for `.prov` requests, which is one expected form of failure when provenance is required.
- **05**: `kubectl apply` should fail on the project.

**Note:** All Applications and AppProjects use namespace `argocd-e2e`. Ensure that namespace exists (e.g. `kubectl create namespace argocd-e2e`) or that Argo CD is configured to use it.

**If all apps pass:** Check that the repo-server has `ARGOCD_GPG_ENABLED=true`. When GPG is disabled, provenance verification is skipped and 02, 03-oci, and 04 will sync instead of failing. Set the env var on the repo-server deployment and restart.

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
