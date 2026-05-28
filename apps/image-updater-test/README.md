# Image Updater console test

Manifests to exercise the **Image Updaters** UI from [gitops-console-plugin PR #244](https://github.com/redhat-developer/gitops-console-plugin/pull/244). The setup mirrors the contributor test against Image Updater **v1.2.1** (GitOps 1.21).

## What gets created

| Resource | Name | Namespace | Purpose |
|----------|------|-----------|---------|
| `Application` | `app-2` | `openshift-gitops` | Matches `namePattern: app-2` on the ImageUpdater |
| `ImageUpdater` | `image-updater-test` | `openshift-gitops` | semver updates for nginx and memcached |
| `Deployment` | `app-2` | `image-updater-test` | Starts at `nginx:1.17.0` and `memcached:1.6.0` |

The ImageUpdater targets `nginx:1.17.10` and `memcached:1.6.10`. After reconciliation you should see `status` similar to:

- `applicationsMatched: 1`
- `imagesManaged: 2`
- `conditions` with `Ready=True`
- `recentUpdates` for `test-nginx` and `test-memcached`

## Prerequisites

- OpenShift GitOps (or Argo CD) with the **Image Updater** operator/CRD installed
- Image Updater **v1.2.0+** (`status` subresource)
- This repository pushed to a branch Argo CD can read (default: `main` on `aali309/argocd-test-nested`)

## Deploy

```bash
chmod +x apps/image-updater-test/apply-test.sh
./apps/image-updater-test/apply-test.sh
```

Use your own fork/branch if needed:

```bash
REPO_URL=https://github.com/YOU/argocd-test-nested.git \
REPO_REVISION=main \
./apps/image-updater-test/apply-test.sh
```

Or apply manifests manually:

```bash
kubectl apply -f apps/image-updater-test/manifests/namespace.yaml
kubectl apply -f apps/image-updater-test/manifests/rbac.yaml
kubectl apply -f apps/image-updater-test/application.yaml
kubectl apply -f apps/image-updater-test/image-updater.yaml
```

## Verify

```bash
# Application synced
kubectl get application app-2 -n openshift-gitops

# ImageUpdater status (conditions, recentUpdates)
kubectl get imageupdater image-updater-test -n openshift-gitops -o yaml

# Workload images in cluster
kubectl get deployment app-2 -n image-updater-test -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
```

In the console: **GitOps → Image Updaters** → open `image-updater-test` → check **Details** and **Recent updates** tabs.

## Clean up

```bash
kubectl delete -f apps/image-updater-test/image-updater.yaml
kubectl delete -f apps/image-updater-test/application.yaml
kubectl delete -f apps/image-updater-test/manifests/rbac.yaml
kubectl delete -f apps/image-updater-test/manifests/namespace.yaml
```

## Customize

Edit `application.yaml` `spec.source.repoURL` / `targetRevision` if you use a different remote. Image alias and semver targets are in `image-updater.yaml`; workload images are in `manifests/deployment.yaml`.

## Layout

```
apps/image-updater-test/
├── application.yaml      # Argo CD Application (apply manually)
├── image-updater.yaml    # ImageUpdater CR (apply manually)
├── apply-test.sh
├── manifests/            # Synced by Application app-2
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── rbac.yaml
└── README.md
```
