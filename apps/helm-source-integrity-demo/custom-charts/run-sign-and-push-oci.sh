#!/usr/bin/env bash
# Sign demo-chart, push to OCI, then print next steps for scenario 08 (OCI Helm source integrity).
# Run from repo root: REGISTRY=oci://localhost:5000/charts bash apps/helm-source-integrity-demo/custom-charts/run-sign-and-push-oci.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
chmod +x scripts/*.sh 2>/dev/null || true

echo "========== OCI Helm: sign + push =========="
echo ""

# Ensure chart is signed (same as traditional)
if ! [[ -f repo/demo-chart-1.0.0.tgz && -f repo/demo-chart-1.0.0.tgz.prov ]]; then
  echo "[Step 1] Signing chart..."
  bash run-sign-one-chart.sh
  echo ""
fi

# Push to OCI
REGISTRY="${REGISTRY:-oci://localhost:5000/charts}"
echo "[Step 2] Pushing to OCI: $REGISTRY"
./scripts/push-oci.sh
echo ""

# Key ID for project
KEY_ID=$(./scripts/print-key-id.sh "helm-demo@example.com" 2>/dev/null | grep -oE '[A-F0-9]{16}' | tail -1)
if [[ -z "$KEY_ID" ]]; then
  KEY_ID=$(gpg --list-keys --keyid-format LONG "helm-demo@example.com" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*\/\([A-F0-9]\{16\}\).*/\1/p')
fi

# Strip oci:// for display
REG_DISPLAY="$REGISTRY"
[[ "$REG_DISPLAY" == oci://* ]] && REG_DISPLAY="${REG_DISPLAY#oci://}"

echo "========== Next: use scenario 08 (OCI) =========="
echo ""
echo "# 1. Add public key to Argo CD:"
echo "argocd gpg add --from $SCRIPT_DIR/keys/demo-helm-signing.asc"
echo ""
echo "# 2. Edit 08 project: set key ID and repo URL"
echo "  File: $SCRIPT_DIR/../08-pass-custom-signed-oci/project.yaml"
echo "  keys: [ \"$KEY_ID\" ]"
echo "  repos[].url: \"oci://$REG_DISPLAY/*\" (or match your registry)"
echo ""
echo "# 3. Edit 08 app: set source.repoURL and targetRevision"
echo "  File: $SCRIPT_DIR/../08-pass-custom-signed-oci/app.yaml"
echo "  repoURL: $REGISTRY/demo-chart"
echo "  targetRevision: \"1.0.0\""
echo ""
echo "# 4. Apply:"
echo "kubectl apply -f $SCRIPT_DIR/../08-pass-custom-signed-oci/"
echo ""
echo "========== Done =========="
