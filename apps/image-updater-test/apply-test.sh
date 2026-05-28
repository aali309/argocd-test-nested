#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_NS="${ARGOCD_NS:-openshift-gitops}"
REPO_URL="${REPO_URL:-https://github.com/aali309/argocd-test-nested.git}"
REPO_REVISION="${REPO_REVISION:-main}"

echo "Image Updater console test setup"
echo "================================"
echo "Argo CD namespace: ${ARGOCD_NS}"
echo "Git repo:          ${REPO_URL}@${REPO_REVISION}"
echo ""

if ! command -v kubectl &>/dev/null; then
  echo "kubectl is required"
  exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Cannot reach the cluster. Run oc login / configure kubeconfig first."
  exit 1
fi

if ! kubectl get crd imageupdaters.argocd-image-updater.argoproj.io &>/dev/null; then
  echo "ImageUpdater CRD not found. Install Argo CD Image Updater v1.2.0+ (GitOps 1.21 includes v1.2.1)."
  exit 1
fi

if ! kubectl get namespace "${ARGOCD_NS}" &>/dev/null; then
  echo "Namespace ${ARGOCD_NS} not found. Set ARGOCD_NS if Argo CD runs elsewhere."
  exit 1
fi

echo "Applying workload namespace and RBAC (optional pre-sync)..."
kubectl apply -f "${SCRIPT_DIR}/manifests/namespace.yaml"
kubectl apply -f "${SCRIPT_DIR}/manifests/rbac.yaml"

echo "Applying Argo CD Application (app-2)..."
if [[ "${REPO_URL}" != "https://github.com/aali309/argocd-test-nested.git" ]] \
  || [[ "${REPO_REVISION}" != "main" ]]; then
  kubectl apply -f "${SCRIPT_DIR}/application.yaml"
  kubectl patch application app-2 -n "${ARGOCD_NS}" --type merge -p "$(cat <<EOF
{
  "spec": {
    "source": {
      "repoURL": "${REPO_URL}",
      "targetRevision": "${REPO_REVISION}"
    }
  }
}
EOF
)"
else
  kubectl apply -f "${SCRIPT_DIR}/application.yaml"
fi

echo "Applying ImageUpdater CR..."
kubectl apply -f "${SCRIPT_DIR}/image-updater.yaml"

echo ""
echo "Done. Verify with:"
echo "  kubectl get application app-2 -n ${ARGOCD_NS}"
echo "  kubectl get imageupdater image-updater-test -n ${ARGOCD_NS}"
echo "  kubectl get imageupdater image-updater-test -n ${ARGOCD_NS} -o yaml"
echo ""
echo "GitOps console: GitOps -> Image Updaters -> image-updater-test"
echo ""
echo "Push this repo to ${REPO_URL} on branch ${REPO_REVISION} before expecting Image Updater to reconcile."
