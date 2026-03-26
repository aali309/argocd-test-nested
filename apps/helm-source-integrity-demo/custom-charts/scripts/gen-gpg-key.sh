#!/usr/bin/env bash
# Generate a GPG key for signing Helm charts (source integrity demo).
# Output: keys/demo-helm-signing.asc (public key for Argo CD). Secret key stays in default keyring (~/.gnupg).
# Prints the key ID to use in AppProject sourceIntegrity.helm.policies[].gpg.keys[].
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="$(cd "$SCRIPT_DIR/../keys" && pwd)"
KEY_NAME="${KEY_NAME:-Helm Source Integrity Demo}"
KEY_EMAIL="${KEY_EMAIL:-helm-demo@example.com}"
mkdir -p "$KEYS_DIR"

echo "Generating GPG key: $KEY_NAME <$KEY_EMAIL> (no passphrase, for demo)"
# Unattended key with %no-protection so helm package --sign won't prompt
BATCH=$(mktemp)
trap "rm -f $BATCH" EXIT
cat > "$BATCH" << EOF
%echo Generating key
Key-Type: RSA
Key-Length: 3072
Subkey-Type: RSA
Subkey-Length: 3072
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF
gpg --batch --generate-key "$BATCH"

# Get key ID (long form = 16 hex chars; Argo CD policy uses this)
KEY_ID=$(gpg --list-keys --keyid-format LONG "$KEY_EMAIL" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*\/\([A-F0-9]\{16\}\).*/\1/p')
if [[ -z "$KEY_ID" ]]; then
  KEY_ID=$(gpg --list-keys --keyid-format 0xlong "$KEY_EMAIL" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*0x\([A-F0-9]\{16\}\).*/\1/p')
fi
echo "Key ID (use in AppProject sourceIntegrity.helm.policies[].gpg.keys[]): $KEY_ID"

# Export public key only (for Argo CD: argocd gpg add --from keys/demo-helm-signing.asc)
# Secret key stays in default keyring (~/.gnupg); helm package --sign will use it without --keyring
gpg --armor --export "$KEY_EMAIL" > "$KEYS_DIR/demo-helm-signing.asc"
echo "Public key written to: $KEYS_DIR/demo-helm-signing.asc"

echo ""
echo "Next: run ./scripts/package-and-sign.sh (from custom-charts/), then add the repo to Argo CD and use key ID: $KEY_ID"
