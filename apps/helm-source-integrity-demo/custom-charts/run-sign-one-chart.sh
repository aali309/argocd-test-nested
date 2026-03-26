#!/usr/bin/env bash
# Run this script to sign demo-chart and see results (for easy debug).
# From repo root: ./apps/helm-source-integrity-demo/custom-charts/run-sign-one-chart.sh
# Or from custom-charts/: ./run-sign-one-chart.sh
# Optional: KEY_EMAIL="your@email.com" ./run-sign-one-chart.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
chmod +x scripts/*.sh 2>/dev/null || true

echo "========== Sign one chart (demo-chart) =========="
echo ""

# Step 1: Ensure we have a key and sign
if [[ -n "$KEY_EMAIL" || -n "$KEY_NAME" ]]; then
  echo "[Step 1] Using your key: ${KEY_EMAIL:-$KEY_NAME}"
  ./scripts/package-and-sign.sh
else
  if ! gpg --list-secret-keys "helm-demo@example.com" &>/dev/null; then
    echo "[Step 1a] No demo key found. Generating GPG key (in default keyring, no passphrase)..."
    ./scripts/gen-gpg-key.sh
    echo ""
  fi
  echo "[Step 1b] Packaging and signing demo-chart..."
  ./scripts/package-and-sign.sh
fi

# Get key ID for "next commands" (package-and-sign already printed it)
if [[ -n "$KEY_EMAIL" ]]; then
  KEY_ID=$(./scripts/print-key-id.sh "$KEY_EMAIL" 2>/dev/null | grep -oE '[A-F0-9]{16}' | tail -1)
elif [[ -n "$KEY_NAME" ]]; then
  KEY_ID=$(./scripts/print-key-id.sh "$KEY_NAME" 2>/dev/null | grep -oE '[A-F0-9]{16}' | tail -1)
else
  KEY_ID=$(./scripts/print-key-id.sh "helm-demo@example.com" 2>/dev/null | grep -oE '[A-F0-9]{16}' | tail -1)
fi
if [[ -z "$KEY_ID" ]]; then
  KEY_ID=$(gpg --list-keys --keyid-format LONG 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*\/\([A-F0-9]\{16\}\).*/\1/p')
fi

echo ""
echo "========== Results =========="
echo "Repo contents:"
ls -la repo/ 2>/dev/null || true
echo ""
if [[ -n "$KEY_ID" ]]; then
  echo "Key ID (copy for project.yaml): $KEY_ID"
else
  echo "Key ID: (see output above from package-and-sign.sh)"
fi
echo ""
echo "========== Next commands (run these yourself) =========="
echo ""
echo "# 2. Add public key to Argo CD:"
if [[ -f keys/demo-helm-signing.asc ]]; then
  echo "argocd gpg add --from $SCRIPT_DIR/keys/demo-helm-signing.asc"
else
  echo "gpg --armor --export YOUR_EMAIL | argocd gpg add --from -"
fi
echo ""
echo "# 3. Set key ID in project (replace REPLACE_WITH_KEY_ID with: $KEY_ID)"
echo "  Edit: $SCRIPT_DIR/../07-pass-custom-signed-helm/project.yaml"
echo ""
echo "# 4. Serve repo (in another terminal):"
echo "cd $SCRIPT_DIR/repo && python3 -m http.server 8080"
echo ""
echo "# 5. Apply Application:"
echo "kubectl apply -f $SCRIPT_DIR/../07-pass-custom-signed-helm/"
echo ""
echo "========== Done =========="
