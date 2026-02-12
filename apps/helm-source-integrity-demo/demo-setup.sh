#!/usr/bin/env bash
# Optional one-time setup for Helm source integrity demo.
# Run against any Argo CD instance (no argo-cd e2e required).
#
# Ensures Bitnami Helm repo is known to Argo CD. OCI Bitnami is public and
# usually works without extra config.
set -e

echo "Helm source integrity demo – optional setup"
echo "Ensure default project allows these repos (or add them):"
echo "  - https://charts.bitnami.com/bitnami (Helm)"
echo "  - oci://registry-1.docker.io/bitnamicharts/nginx (OCI)"
echo ""

if command -v argocd &>/dev/null; then
  echo "Adding Bitnami Helm repo (if not already present)..."
  argocd repo add https://charts.bitnami.com/bitnami --type helm 2>/dev/null || true
  echo "Done. Apply scenarios: kubectl apply -f apps/helm-source-integrity-demo/01-pass-mode-none/"
else
  echo "argocd CLI not found; skip repo add. If apps fail with repo errors, add the repo in UI or install argocd CLI."
fi
