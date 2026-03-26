#!/usr/bin/env bash
# Print the long key ID for an existing GPG key (for use in AppProject sourceIntegrity.helm.policies[].gpg.keys[]).
# Usage: ./scripts/print-key-id.sh your@email.com   or   ./scripts/print-key-id.sh "Your Name"
set -e
IDENT="${1:-}"
if [[ -z "$IDENT" ]]; then
  echo "Usage: $0 <email-or-name>"
  echo "Example: $0 you@example.com"
  exit 1
fi
KEY_ID=$(gpg --list-keys --keyid-format LONG "$IDENT" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*\/\([A-F0-9]\{16\}\).*/\1/p')
if [[ -z "$KEY_ID" ]]; then
  KEY_ID=$(gpg --list-keys --keyid-format 0xlong "$IDENT" 2>/dev/null | grep "^pub" | head -1 | sed -n 's/.*0x\([A-F0-9]\{16\}\).*/\1/p')
fi
if [[ -z "$KEY_ID" ]]; then
  echo "No key found for: $IDENT"
  exit 1
fi
echo "Key ID (use in 07-pass-custom-signed-helm/project.yaml): $KEY_ID"
