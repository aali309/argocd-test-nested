#!/usr/bin/env bash
# Package the demo chart and sign it with a GPG key.
# Option A: Use key from gen-gpg-key.sh (run that first).
# Option B: Use your existing key — set KEY_EMAIL or KEY_NAME and optionally KEYRING:
#   KEY_EMAIL="you@example.com" ./scripts/package-and-sign.sh
#   KEY_NAME="Your Name" KEYRING=~/.gnupg/secring.gpg ./scripts/package-and-sign.sh
# Produces repo/index.yaml, repo/demo-chart-1.0.0.tgz, repo/demo-chart-1.0.0.tgz.prov
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$(cd "$SCRIPT_DIR/../demo-chart" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../repo" && pwd)"
KEYS_DIR="$(cd "$SCRIPT_DIR/../keys" && pwd)"

# Use existing key from env, or the key created by gen-gpg-key.sh
if [[ -n "$KEY_EMAIL" || -n "$KEY_NAME" ]]; then
  KEY_IDENT="${KEY_EMAIL:-$KEY_NAME}"
  KEYRING="${KEYRING:-$HOME/.gnupg/secring.gpg}"
  if [[ ! -f "$KEYRING" ]]; then
    # GnuPG 2 default: private-keys.d (no secring.gpg); helm often needs legacy keyring
    KEYRING="$HOME/.gnupg/pubring.kbx"
    if [[ ! -f "$KEYRING" ]]; then
      echo "KEYRING not found at $KEYRING. Export your secret key to a keyring file, e.g.:"
      echo "  gpg --export-secret-keys YOUR_EMAIL >> $KEYS_DIR/my.secret.gpg"
      echo "  KEY_EMAIL=YOUR_EMAIL KEYRING=$KEYS_DIR/my.secret.gpg ./scripts/package-and-sign.sh"
      exit 1
    fi
  fi
else
  KEY_IDENT="helm-demo@example.com"
  KEYRING="$KEYS_DIR/demo-helm-signing.secret.gpg"
  if [[ -f "$KEYRING" ]]; then
    : # use exported keyring (no passphrase, so no checksum issue)
  elif gpg --list-secret-keys "$KEY_IDENT" &>/dev/null; then
    echo "Exporting secret key to $KEYRING for Helm..."
    gpg --export-secret-keys "$KEY_IDENT" > "$KEYRING"
  else
    echo "Run ./scripts/gen-gpg-key.sh first, or set KEY_EMAIL (or KEY_NAME) to use your own key."
    exit 1
  fi
fi

mkdir -p "$REPO_DIR"
cd "$CHARTS_DIR"
echo "Packaging and signing demo-chart with key: $KEY_IDENT"
helm package --sign --key "$KEY_IDENT" --keyring "$KEYRING" .
for f in demo-chart-*.tgz demo-chart-*.tgz.prov; do
  [[ -f "$f" ]] && mv "$f" "$REPO_DIR/"
done

cd "$REPO_DIR"
helm repo index . --merge index.yaml 2>/dev/null || true
helm repo index .

# Print key ID for use in AppProject sourceIntegrity.helm.policies[].gpg.keys[]
KEY_ID=$(gpg --list-keys --keyid-format LONG "$KEY_IDENT" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*\/\([A-F0-9]\{16\}\).*/\1/p')
if [[ -z "$KEY_ID" ]]; then
  KEY_ID=$(gpg --list-keys --keyid-format 0xlong "$KEY_IDENT" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*0x\([A-F0-9]\{16\}\).*/\1/p')
fi
echo ""
echo "Repo contents:"
ls -la "$REPO_DIR"
echo ""
if [[ -n "$KEY_ID" ]]; then
  echo "Key ID (use in 07-pass-custom-signed-helm/project.yaml): $KEY_ID"
fi
echo "Serve this repo over HTTP and point Argo CD at the base URL (e.g. http://localhost:8080 or GitHub Pages)."
