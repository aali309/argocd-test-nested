#!/usr/bin/env bash
# Push the signed chart (and optionally .prov) to an OCI registry.
# Usage: REGISTRY=oci://localhost:5000/charts ./scripts/push-oci.sh
#        REGISTRY=oci://ghcr.io/myuser/charts ./scripts/push-oci.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../repo" && pwd)"

REGISTRY="${REGISTRY:-oci://localhost:5000/charts}"
if [[ "$REGISTRY" != oci://* ]]; then
  REGISTRY="oci://$REGISTRY"
fi

TGZ=$(ls "$REPO_DIR"/demo-chart-*.tgz 2>/dev/null | head -1)
PROV="${TGZ}.prov"
if [[ -z "$TGZ" ]]; then
  echo "Run ./scripts/package-and-sign.sh first."
  exit 1
fi

echo "Pushing chart: $TGZ -> $REGISTRY"
helm push "$TGZ" "$REGISTRY"
echo "Chart ref: $REGISTRY/demo-chart, tag: 1.0.0"

# Push .prov so the registry has both chart and provenance (Argo CD can verify)
if [[ -f "$PROV" ]] && command -v oras &>/dev/null; then
  # Strip oci:// for oras (oras uses host:port/repo)
  ORAS_REF="${REGISTRY#oci://}/demo-chart:1.0.0.prov"
  echo "Pushing provenance to $ORAS_REF"
  (cd "$REPO_DIR" && oras push "$ORAS_REF" \
    --artifact-type "application/vnd.cncf.helm.chart.provenance.v1.prov" \
    "demo-chart-1.0.0.tgz.prov:application/vnd.cncf.helm.chart.provenance.v1.prov")
  echo "Provenance pushed; chart + .prov are on OCI."
elif [[ -f "$PROV" ]]; then
  echo "Provenance exists but 'oras' not installed. Install oras to push .prov so Argo CD can verify (e.g. brew install oras)."
fi
