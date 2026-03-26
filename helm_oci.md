# Design: Helm/OCI Source Integrity Policies Extension

## Overview

This document extends the Source Integrity Policies feature (PR #25148) to support Helm chart and OCI artifact verification **during Argo CD sync operations**.

**Key Point:** Verification happens **during sync** - if a Helm chart or OCI artifact fails verification, the sync is **fails** until verification passes.

**Important Distinction:**
- **Helm charts** (whether in traditional repos or OCI repos) use **Helm provenance** (`.prov` files with GPG signatures) → Configured in `sourceIntegrity.helm`
  - Traditional repos: `.prov` file fetched via HTTP (`{chart-url}.prov`)
  - OCI repos: `.prov` file stored as OCI layer (mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`)
  - **Both use the same verification method:** GPG signature verification via `sourceIntegrity.helm` policies
- **OCI artifacts** (non-Helm, like container images or plain OCI artifacts) use **cosign signatures** (sigstore) → Configured in `sourceIntegrity.oci`
  - Signatures stored as separate OCI artifacts (`sha256-<digest>.sig`)
  - Verified using cosign Go library with public keys from `argocd-cosign-keys-cm`
- Argo CD determines the type based on the Application spec (presence of `helm:` section) and OCI mediaType

## Design Principles

1. **Follow Existing Patterns:** Helm/OCI verification follows the same structure and behavior as Git verification
2. **Reuse Infrastructure:** Leverage existing GPG key management for Helm (same as Git)
3. **Consistent API:** Use the same policy-based structure with glob pattern matching
4. **Backwards Compatible:** No breaking changes, opt-in verification

## Configuration Structure

Extends the `sourceIntegrity` structure from PR #25148:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceIntegrity:
    git:
      policies:
        - repos: ["https://github.com/foo/*"]
          gpg:
            mode: "head"
            keys: ["0xDEAD"]
    helm:
      policies:
        - repos:
            - "https://charts.example.com/*"
            - "oci://registry.example.com/charts/*"
          gpg:
            mode: "none|provenance"
            keys:
              - "0xHELMKEY1"
              - "0xHELMKEY2"
    oci:
      policies:
        - repos:
            - "oci://registry.example.com/images/*"
            - "oci://my-docker-registry/foo/*"
          sigstore:
            mode: "none|signature"
            # Option 1: Public key verification (PEM-encoded)
            publicKey: "-----BEGIN PUBLIC KEY-----\n..."
            # Option 2: Keyless verification (future enhancement)
            # certificateIdentity: "https://github.com/org/repo/.github/workflows/*"
            # certificateOidcIssuer: "https://token.actions.githubusercontent.com"
            # Additional sigstore attributes can be added as needed
```

## Helm Provenance Verification

### Policy Structure

```yaml
helm:
  policies:
    - repos: []  # Glob patterns for Helm repository URLs
      gpg:
        mode: "none|provenance"
        keys: []  # List of GPG key IDs
```

### Verification Modes

- **`none`:** No verification performed. Charts are accepted without checking signatures.
- **`provenance`:** Verify the Helm chart's `.prov` file. If a chart has no `.prov` file when `provenance` mode is required, verification fails.

**Important Difference from Git:**
- **Git** has commit history, so it can verify:
  - `head` mode: Only the commit pointed to by targetRevision
  - `strict` mode: All ancestor commits from targetRevision to init
- **Helm charts** are atomic packages (no history):
  - Each chart version is a separate `.tgz` file (e.g., `mychart-1.0.0.tgz`, `mychart-1.1.0.tgz`)
  - When you deploy a chart, you deploy a **specific version**
  - We only verify **that specific chart package** being deployed
  - There is no "history" so `strict` mode not needed
  - Each chart version is verified independently when it's used

### How It Works

1. When Argo CD fetches a Helm chart, it also attempts to fetch the corresponding `.prov` file:
   - **Traditional repos:** `.prov` file is fetched from the same HTTP path with `.prov` extension (e.g., `chart-1.0.0.tgz.prov`)
   - **OCI repos:** `.prov` file is stored as a **separate layer** in the OCI manifest (if present)
     - When using `helm push`, if `.prov` file exists next to `.tgz`, it's automatically uploaded as a layer
     - Layer has `mediaType: application/vnd.cncf.helm.chart.provenance.v1.prov`
     - `helm pull` should automatically fetch the `.prov` layer if present

2. The `.prov` file contains:
   - Chart.yaml metadata
   - SHA256 checksum of the chart package
   - PGP signature of the entire content

3. If a policy requires `provenance` mode:
   - If `.prov` file is missing → verification fails (chart is unsigned error)
   - If `.prov` file exists → Argo CD verifies it using GPG
   - Verification checks:
     - PGP signature is valid
     - Signature was made by one of the keys in the policy's `keys` array
     - Checksum in `.prov` file matches the actual chart file (detects tampering)
   
   **Note:** We only verify the **specific chart version** being deployed (e.g., `mychart-1.0.0.tgz`). We do not verify other chart versions in the repository. Each chart version is verified independently when it's used during sync.

### Verification Output Example

When verifying a Helm chart, Argo CD will check for the following information (similar to `helm verify` output):

```
Signed by: Atif Ali (new GPG key) <atali@email.com>
Using Key With Fingerprint: F********************
Chart Hash Verified: sha256:8f95********************
```

**Argo CD Verification Process:**
1. Check if `.prov` file exists (if missing, verification fails)
2. Verify PGP signature in `.prov` file is cryptographically valid
3. Extract signer fingerprint from verified signature
4. Verify the signer's fingerprint matches one of the keys in the policy's `keys` array
5. Verify the chart hash in `.prov` file matches the actual chart file (integrity check)
3. Verify the chart hash matches the checksum in `.prov` file
4. If all checks pass → allow chart extraction and manifest generation
5. If any check fails → return error, block sync

### OCI-Based Helm Charts with .prov Files

**Important:** Helm charts stored in OCI registries use **Helm provenance** (`.prov` files), NOT cosign signatures.

**How it works:**
- When you push a Helm chart to OCI with `helm push`, if a `.prov` file exists next to the `.tgz`, it's automatically uploaded as a **separate layer** in the OCI manifest
- The `.prov` file layer has mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`
- When Argo CD pulls the Helm chart from OCI, it should automatically fetch the `.prov` layer (if present)
- Argo CD then verifies the `.prov` file using GPG (same as traditional Helm repos)

**Verification Flow for OCI Helm Charts:**
1. Argo CD pulls Helm chart from OCI registry (e.g., `oci://registry.example.com/charts/mychart:1.0.0`)
2. Argo CD checks OCI manifest for `.prov` layer (mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`)
3. If `.prov` layer exists, fetch it from the OCI manifest (if missing, verification fails)
4. If policy requires `provenance` mode:
   1. Verify PGP signature in `.prov` file is cryptographically valid
   2. Extract signer fingerprint from verified signature
   3. Verify signer fingerprint matches one of the keys in policy's `keys` array
   4. Verify chart hash in `.prov` file matches the actual chart file (integrity check)
5. If verification passes → proceed with chart extraction
6. If verification fails → block sync, return error

**Key Point:** Helm charts in OCI registries are verified using `sourceIntegrity.helm` policies (GPG), NOT `sourceIntegrity.oci` policies (cosign). The `.prov` file is just stored differently (as an OCI layer instead of HTTP file).

4. Verification uses the same GPG keyring as Git verification (`argocd-gpg-keys-cm` ConfigMap).

5. If verification fails, **sync is blocked** - the application will show `ApplicationConditionComparisonError` and will not deploy until verification passes.

### Key Management

Helm provenance uses GPG keys, so we **reuse the existing GPG key management infrastructure**:
- Same keyring as Git verification
- Same `argocd-gpg-keys-cm` ConfigMap
- Same key import/export mechanisms

**Key Challenge - Uid Substring vs Fingerprint:**
- **Helm signing:** Uses uid substring (name/email) for `--key` parameter: `helm package --sign --key 'Atif Ali'`
- **Argo CD storage:** Stores keys by fingerprint: `F**********************`
- **Solution needed:** Map key fingerprint → uid substring, or extract uid from GPG keyring during verification
- **Test confirmation:** Verification shows both uid ("Atif Ali (new GPG key) <atali@email.com>") and fingerprint in output

### Note on Helm-Sigstore Plugin

The `helm-sigstore` plugin can publish Helm provenance to sigstore's immutable transparency log (Rekor) for additional auditability. This can be an **optional enhancement** down the line.

- Our design focuses on basic `.prov` file verification with GPG (same as traditional Helm)

### Local Testing Results

**Helm Provenance Testing:**
- ✅ Successfully tested signing and verification with GPG keys
- ✅ Confirmed `.prov` file format: PGP signed message with YAML (Chart.yaml + checksums) + PGP signature block
- ✅ Verified uid substring format: Helm requires uid substring (name/email) for `--key`, not fingerprint
- ✅ Confirmed verification output shows signer name, email, fingerprint, and chart hash
- ✅ Verification blocks chart extraction if signature is invalid or missing

**Key Finding:**
- Command uses: `helm package --sign --key 'Atif Ali'` (uid substring)
- Verification shows: `F******************` (fingerprint)
- **Challenge:** Argo CD stores keys by fingerprint, but Helm requires uid substring - need mapping strategy

### Integration Point (During Sync)

Verification happens in `util/helm/client.go:ExtractChart()` **during Argo CD sync**:

**For Traditional Helm Repositories:**
- After downloading the chart but before extracting it
- Fetch `.prov` file from HTTP: `{chart-url}.prov`
- If policy requires verification:
  1. Check if `.prov` file exists (if missing, verification fails)
  2. Verify PGP signature in `.prov` file is cryptographically valid
  3. Extract signer fingerprint from verified signature
  4. Verify signer fingerprint matches one of the keys in policy's `keys` array
  5. Verify checksum in `.prov` file matches the actual chart file (integrity check)
- If verification fails, the chart is not extracted and an error is returned

**For OCI Helm Repositories:**
- After pulling the chart from OCI registry but before extracting it
- Check OCI manifest for `.prov` layer (mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`)
- If `.prov` layer exists, fetch it from the OCI manifest
- If policy requires verification:
  1. Check if `.prov` file exists (fetched from OCI layer; if missing, verification fails)
  2. Verify PGP signature in `.prov` file is cryptographically valid
  3. Extract signer fingerprint from verified signature
  4. Verify signer fingerprint matches one of the keys in policy's `keys` array
  5. Verify checksum in `.prov` file matches the actual chart file (integrity check)
- If verification fails, the chart is not extracted and an error is returned

**Error Handling:**
- **Error propagates to controller, which blocks sync** (same as Git verification)
- Application shows `ApplicationConditionComparisonError` until verification passes
- Error messages indicate: missing `.prov` file, invalid signature, wrong key, or checksum mismatch

## OCI Signature Verification

**NOTE** Helm charts stored in OCI registries use Helm provenance (see `helm` section above) and are verified using GPG, not cosign.

### Policy Structure

```yaml
oci:
  policies:
    - repos: []  # Glob patterns for OCI repository URLs
      sigstore:
        mode: "none|signature"
        # Option 1: Public key verification (PEM-encoded)
        publicKey: "-----BEGIN PUBLIC KEY-----\n..."
        # Option 2: Keyless verification (future enhancement)
        # certificateIdentity: "https://github.com/org/repo/.github/workflows/*"
        # certificateOidcIssuer: "https://token.actions.githubusercontent.com"
        # Additional sigstore attributes can be added as needed
```

**Design Note:** Following Blake Pettersson's feedback, the sigstore structure is intentionally flexible to allow adding additional attributes as needed. This doc focuses on public key verification. keyless verification as a future enhancement.

### Local Testing Results

**OCI Cosign Testing:**
- ✅ Successfully tested signing and verification with cosign key pairs
- ✅ Confirmed signature storage: Separate OCI artifact with pattern `sha256-<digest>.sig` in registry
- ✅ Verified signature format: JSON containing image digest, docker-reference, and signature type
- ✅ Confirmed verification output shows image digest: `sha256:a5001d074******************`
- ✅ Public key format: PEM-encoded (`-----BEGIN PUBLIC KEY-----`) - suitable for ConfigMap storage
- ✅ Private key format: Encrypted PEM (`-----BEGIN ENCRYPTED PRIVATE KEY-----`) - password protected
- ✅ Signature type: `https://sigstore.dev/cosign/sign/v1`

**Key Findings:**
- Signatures are stored as **separate OCI artifacts** (not layers in the image)
- Signature artifact pattern: `sha256-<image-digest>.sig` tag in same registry
- Verification confirms image digest matches signature (integrity check)
- Cosign automatically discovers signature artifacts during verification

**Local Registry Considerations:**
- Podman requires `--allow-insecure-registry` flag for local HTTP registries
- Cosign works with both HTTP and HTTPS registries
- Local testing works with `localhost:5000` registry

### Verification Modes

- **`none`:** No verification performed. OCI artifacts are accepted without checking signatures.
- **`signature`:** Verify cosign signatures on the OCI artifact. If no signature exists and `signature` mode is required, verification fails.

**Important Difference from Git:**
- **Git** has commit history, so it can verify:
  - `head` mode: Only the commit pointed to by targetRevision
  - `strict` mode: All ancestor commits from targetRevision to init
- **OCI artifacts** are atomic packages (no history):
  - Each artifact version is a separate image/chart with a specific tag or digest
  - When you deploy an artifact, you deploy a **specific version** (tag or digest)
  - We only verify **that specific artifact** being pulled
  - There is no "history" to verify - no `strict` mode needed
  - Each artifact version is verified independently when it's used

### How It Works

1. When Argo CD pulls an OCI artifact, it checks for cosign signatures.
2. Cosign signatures are stored as separate OCI artifacts with the `sha256-<digest>.sig` tag pattern.
3. Argo CD uses the cosign Go library to verify signatures against the configured public key or certificate identity.
4. Verification checks the artifact digest to ensure integrity (as noted by Blake Pettersson: "verify the image layers by its digest").
5. Verification output confirms the image digest matches the signed artifact (tested: `sha256:a5001d074527dab0a************************`).
5. If verification fails or the artifact is unsigned when required, sync is blocked.

**Note:** We only verify the **specific artifact version** being pulled (e.g., `oci://registry.example.com/image:v1.0.0` or `@sha256:abc123...`). We do not verify other artifact versions in the registry. Each artifact version is verified independently when it's used during sync.

**Distinction from Helm Charts:**
- If the OCI artifact is a Helm chart (mediaType: `application/vnd.cncf.helm.chart.content.v1.tar+gzip`), use `sourceIntegrity.helm` with provenance verification
- If the OCI artifact is a non-Helm artifact (container image, plain OCI artifact), use `sourceIntegrity.oci` with cosign signature verification

### Verification Checks

When verifying an OCI artifact with cosign, the following checks are performed:

1. **Signature Existence:**
   1. Check if cosign signature exists for the artifact (signature artifact pattern: `sha256-<digest>.sig`)
   2. If mode is `signature` and no signature found → verification fails

2. **Signature Validity:**
   - Verify the cryptographic signature is valid (not corrupted or tampered)
   - Check signature format and structure
   - Signature type: `https://sigstore.dev/cosign/sign/v1`

3. **Key/Certificate Trust:**
   - **Public key verification:** Verify signature was made by the configured public key (PEM-encoded)
   - **Keyless verification (future):** Verify certificate identity matches policy (e.g., GitHub Actions workflow)
   - If signature made by untrusted key/certificate → verification fails

4. **Artifact Integrity (Critical):**
   - Verify the signature matches the artifact digest using `verify.WithArtifactDigest()`
   - This ensures the artifact pulled matches exactly what was signed
   - Detects any tampering or modification after signing
   - As noted by Blake Pettersson: "verify the image layers by its digest"
   - Verification output confirms image digest matches signed artifact

**Test Confirmation:**
- Verification output shows JSON with `critical.image.docker-manifest-digest` field
- Confirms signature was made by the public key in ConfigMap
- Verifies integrity by matching digest in signature to actual artifact digest

### Verification Output Example

When verifying an OCI artifact with cosign, Argo CD will receive output similar to:

```json
{
  "critical": {
    "identity": {
      "docker-reference": "localhost:5000/test-oci:1.0.0"
    },
    "image": {
      "docker-manifest-digest": "sha256:a**************"
    },
    "type": "https://sigstore.dev/cosign/sign/v1"
  },
  "optional": {}
}
```

**Argo CD Verification Process:**
1. Pull OCI artifact from registry (e.g., `oci://registry.example.com/image:v1.0.0`)
2. Cosign library discovers signature artifact: `sha256-<digest>.sig`
3. Fetch signature artifact from registry
4. Verify signature using public key from `argocd-cosign-keys-cm` ConfigMap
5. Verify `docker-manifest-digest` in signature matches actual artifact digest
6. Verify `docker-reference` matches the artifact being pulled
7. If all checks pass → allow artifact usage
8. If any check fails → return error, block sync

**Verification Checks Performed:**
- ✅ The cosign claims were validated
- ✅ Existence of the claims in the transparency log was verified offline (if applicable)
- ✅ The signatures were verified against the specified public key
- ✅ Image digest matches (integrity check)
   - Ensure artifact hasn't been modified since signing
   - Cosign signs the artifact digest, so any tampering is detected

### Challenges

1. **Signature Fetching:**
   - Cosign signatures are stored as **separate OCI artifacts** (not layers in the main manifest)
   - Need to fetch signature artifact: `sha256-<digest>.sig` from registry
   - Challenge: Determine correct signature artifact reference from artifact digest
   - Solution: Use cosign library which handles signature artifact discovery

2. **Go Library Integration:**
   - Argo CD doesn't currently use cosign Go library (only CLI for releases)
   - Need to integrate `github.com/sigstore/cosign/v2` package
   - **Implementation pattern (from Blake Pettersson example link):**
     - Use `verify.NewVerifier()` with public keys from ConfigMap
     - Use `verify.WithArtifactDigest()` to verify artifact digest (critical for integrity)
     - Call `sev.Verify()` with artifact digest policy
   - This pattern ensures both signature validity AND artifact integrity (digest verification)

3. **Key Management:**
   - Cosign uses PEM-encoded public keys (different from GPG)
   - Cannot reuse GPG key management infrastructure
   - New ConfigMap structure needed (`argocd-cosign-keys-cm`)
   - try to follow similar pattern to GPG keys but with PEM format

4. **Registry Authentication:**
   - Need to authenticate to registry to fetch signature artifacts
   - Ensure same credentials work for both artifact and signature fetching
   - Try to reuse existing OCI client authentication

5. **Performance:**
   - Additional registry call to fetch signature artifact
   - Cryptographic verification adds latency
   - Minimize impact on sync performance
   - Try to Cache verification results, verify in parallel with artifact pull if possible

6. **Error Handling:**
   - Distinguish between "unsigned" vs "verification failed" vs "wrong key"
   - Provide clear error messages for troubleshooting
   - Using cosign library error types, provide actionable error messages

7. **Helm Charts in OCI:**
   - Helm charts stored as OCI can have both `.prov` (Helm provenance) and cosign signatures
   - **Decision:** Use Helm provenance verification for Helm charts (reuse GPG via `sourceIntegrity.helm`)
   - **Rationale:** Helm provenance is the standard for Helm charts, `.prov` files are automatically handled by Helm tooling
   - **Note:** If a Helm chart has both `.prov` and cosign signatures, we verify using `.prov` (Helm provenance) only
   - Cosign verification (`sourceIntegrity.oci`) is for non-Helm OCI artifacts (container images, plain OCI artifacts)

### Key Management

OCI/cosign uses different key formats than GPG:
- **Public keys:** PEM-encoded public keys (different from GPG)
- **Keyless:** Uses certificate identity and OIDC issuer (no keys needed)

**Proposed approach:**
- Store cosign public keys in a new ConfigMap: `argocd-cosign-keys-cm`
- Similar structure to GPG keys: key ID as name, public key as value
- Future Enhancement: Support keyless verification using certificate identity

**Why Artifact Digest Verification is Critical:**
- As noted by Blake Pettersson: "verify the image layers by its digest"
- Ensures the artifact pulled matches exactly what was signed
- Detects any tampering or modification after signing
- The digest is cryptographically bound to the signature

### Integration Point (During Sync)

Verification happens in `util/oci/client.go` **during Argo CD sync** (for non-Helm OCI artifacts):

**Verification Flow:**
1. After pulling the OCI artifact from registry
2. Get artifact digest (e.g., `sha256:a********************`)
3. Cosign library discovers signature artifact: `sha256-<artifact-digest>.sig`
4. Fetch signature artifact from registry
5. If policy requires verification:
   - Create verifier with public key from `argocd-cosign-keys-cm` ConfigMap
   - Use `verify.WithArtifactDigest()` to verify artifact digest (integrity check)
   - Call `sev.Verify()` with artifact digest policy
   - Verify `docker-reference` matches the artifact being used
6. If verification fails, the artifact is rejected and an error is returned

**Error Handling:**
- **Error propagates to controller, which blocks sync** (same as Git verification)
- Application shows `ApplicationConditionComparisonError` until verification passes
- Error messages indicate: missing signature, invalid signature, wrong key, or digest mismatch

**Important Distinction:**
- **Helm charts in OCI:** Verified using `sourceIntegrity.helm` (GPG, `.prov` files) - NOT this section
- **Non-Helm OCI artifacts:** Verified using `sourceIntegrity.oci` (cosign signatures) - THIS section

## Policy Matching

Policies follow the same matching rules as Git policies:
- Policies are evaluated top-down
- First matching policy wins
- More specific patterns should come before broader ones
- If no policy matches, verification is skipped (backwards compatible)

## Verification Flow (During Argo CD Sync)

The verification flow integrates with the existing Source Integrity system and **blocks sync if verification fails**:

1. **Controller** (`controller/state.go`):
   - Gets `AppProject` with `sourceIntegrity` config
   - Calls `GetRepoObjs()` with `sourceIntegrity` parameter
   - Passes to repo-server via gRPC
   - **If verification fails, sets `ApplicationConditionComparisonError` and blocks sync**

2. **Repo-Server** (`reposerver/repository/repository.go`):
   - Receives `sourceIntegrity` in `ManifestRequest` (during sync operation)
   - For Helm sources: Verifies provenance in `ExtractChart()` **before manifest generation**
   - For OCI sources: Verifies cosign signature **before using artifact**
   - Returns `SourceIntegrityCheckResult` with verification status
   - **If verification fails, manifest generation is skipped and error is returned**

3. **Verification** (`util/sourceintegrity/`):
   - Extends existing package with Helm/OCI verification functions
   - `VerifyHelm()` - verifies Helm provenance
   - `VerifyOCI()` - verifies OCI cosign signatures
   - Returns `SourceIntegrityCheckResult` consistent with Git verification
   - **Same error handling as Git: blocks sync if verification fails**

## Error Handling (Sync Blocking)

Verification failures follow the same pattern as Git verification and **block Argo CD sync**:
- Return `SourceIntegrityCheckResult` with problems
- Controller converts to `ApplicationConditionComparisonError` (same as Git verification)
- **Sync is blocked** - application will not deploy until verification passes
- Application status shows error condition
- Error messages indicate which source failed and why

**This means:**
- If a Helm chart fails verification → sync blocked, no deployment
- If an OCI artifact fails verification → sync blocked, no deployment
- If no policy matches → verification skipped, sync proceeds (backwards compatible)
- If policy mode is "none" → verification skipped, sync proceeds

Example error messages:
- `HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: .prov file missing`
- `HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: signed with key not in keyring (key_id=ABC123)`
- `HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: checksum mismatch (tampering detected)`
- `OCI/SIGSTORE: Failed verifying artifact oci://registry.example.com/image:tag: signature not found`
- `OCI/SIGSTORE: Failed verifying artifact oci://registry.example.com/image:tag: signature verification failed`

## Open Questions

1. **Helm Dependencies:** Should we verify transitive Helm chart dependencies, or only the top-level chart?
   - **Proposed:** Only top-level chart initially. Dependencies can be added later if needed.

2. **.prov File Fetching:** How do we reliably fetch `.prov` files from both traditional and OCI repositories?
   - **Traditional:** HTTP GET to `{chart-url}.prov` (standard Helm repository convention)
   - **OCI:** `.prov` file stored as separate layer in OCI manifest (mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`)
   - **From docs:** Automatically uploaded during `helm push` if `.prov` exists next to `.tgz`
   - **Action:** Test with real OCI Helm repositories during implementation

3. **Verification Method:** Use `helm verify` command or implement direct GPG verification?
   - **helm verify:** Simpler, already handles edge cases, but adds dependency on helm CLI
   - **Direct GPG:** More control, no external command, but need to implement .prov parsing
   - **Tested:** `helm verify` works correctly, shows signer name/email, fingerprint, and chart hash
   - **Proposed:** Start with `helm verify`, consider direct GPG if needed for performance/control

4. **OCI Keyless Verification:** Should we support keyless cosign verification (certificate identity) in the initial implementation?
   - **Proposed:** Public key verification first, keyless as future enhancement.

5. **Cosign Go Library:** What's the best way to use the cosign Go library for verification?
   - **Action:** Research `github.com/sigstore/cosign/v2` API

## Verification Examples

### Example 1: Traditional Helm Repository with .prov File

**Repository:** `https://charts.example.com/`

**Chart:** `mychart-1.0.0.tgz`

**Verification Process:**
```bash
# 1. Fetch chart and .prov file
curl -O https://charts.example.com/mychart-1.0.0.tgz
curl -O https://charts.example.com/mychart-1.0.0.tgz.prov

# 2. Verify using helm verify (what Argo CD will do)
helm verify mychart-1.0.0.tgz

# Expected output:
# Signed by: Chart Maintainer <maintainer@example.com>
# Using Key With Fingerprint: 0xHELMKEY1
# Chart Hash Verified: sha256:8f******************
```

**Argo CD Configuration:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceIntegrity:
    helm:
      policies:
        - repos: ["https://charts.example.com/*"]
          gpg:
            mode: "provenance"
            keys: ["0xHELMKEY1"]
```

**What Argo CD Checks:**
1. `.prov` file exists at `https://charts.example.com/mychart-1.0.0.tgz.prov`
2. PGP signature in `.prov` file is valid
3. Signer fingerprint matches `0xHELMKEY1` (from policy)
4. Chart hash in `.prov` matches actual chart file

---

### Example 2: OCI Helm Repository with .prov File (as OCI Layer)

**Repository:** `oci://registry.example.com/charts`

**Chart:** `mychart:1.0.0`

**Verification Process:**
```bash
# 1. Pull chart from OCI (automatically fetches .prov layer if present)
helm pull oci://registry.example.com/charts/mychart --version 1.0.0

# 2. Verify using helm verify
helm verify mychart-1.0.0.tgz

# Expected output (same as traditional):
# Signed by: Chart Maintainer <maintainer@example.com>
# Using Key With Fingerprint: 0xHELMKEY1
# Chart Hash Verified: sha256:8f********************
```

**Argo CD Configuration:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceIntegrity:
    helm:
      policies:
        - repos: ["oci://registry.example.com/charts/*"]
          gpg:
            mode: "provenance"
            keys: ["0xHELMKEY1"]
```

**What Argo CD Checks:**
1. OCI manifest contains `.prov` layer (mediaType: `application/vnd.cncf.helm.chart.provenance.v1.prov`)
2. Fetch `.prov` layer from OCI manifest
3. PGP signature in `.prov` file is valid
4. Signer fingerprint matches `0xHELMKEY1` (from policy)
5. Chart hash in `.prov` matches actual chart file

**Note:** Same verification method as traditional repos - only the `.prov` file storage differs (OCI layer vs HTTP file).

---

### Example 3: OCI Artifact with Cosign Signature

**Repository:** `oci://registry.example.com/images`

**Artifact:** `myapp:v1.0.0` (digest: `sha256:a5********************`)

**Verification Process:**
```bash
# 1. Sign the artifact (done by publisher)
cosign sign --key cosign.key registry.example.com/images/myapp:v1.0.0

# This creates signature artifact: sha256-a5******************.sig

# 2. Verify using cosign (what Argo CD will do)
cosign verify --key cosign.pub registry.example.com/images/myapp:v1.0.0

# Expected output:
# Verification for registry.example.com/images/myapp:v1.0.0 --
# The following checks were performed on each of these signatures:
#   - The cosign claims were validated
#   - The signatures were verified against the specified public key
# [
#   {
#     "critical": {
#       "identity": {
#         "docker-reference": "registry.example.com/images/myapp:v1.0.0"
#       },
#       "image": {
#         "docker-manifest-digest": "sha256:a5******************"
#       },
#       "type": "https://sigstore.dev/cosign/sign/v1"
#     }
#   }
# ]
```

**Argo CD Configuration:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceIntegrity:
    oci:
      policies:
        - repos: ["oci://registry.example.com/images/*"]
          sigstore:
            mode: "signature"
            publicKey: |
              -----BEGIN PUBLIC KEY-----
              key values...
              -----END PUBLIC KEY-----
```

**What Argo CD Checks (using cosign Go library):**
1. Discover signature artifact: `sha256-a5********************.sig`
2. Fetch signature artifact from registry
3. Create verifier with public key from ConfigMap
4. Verify signature using `verify.WithArtifactDigest()` (digest: `sha256:a************************`)
5. Verify `docker-reference` matches artifact being pulled
6. Confirm signature was made by configured public key

**Go Library Implementation Pattern:**
```go
// 1. Get public key from argocd-cosign-keys-cm ConfigMap
publicKey := getPublicKeyFromConfigMap("key-id")

// 2. Create verifier
sev, err := verify.NewVerifier([]verify.TrustedMaterial{publicKey}, verifierConfig...)

// 3. Get artifact digest
artifactDigest := "sha256:a5001d074527dab0a0a77f0bfe422e83b120fa5d26e703486ca1866ebe4fc627"
artifactDigestBytes, _ := hex.DecodeString(strings.TrimPrefix(artifactDigest, "sha256:"))

// 4. Verify with artifact digest (critical for integrity)
artifactPolicy := verify.WithArtifactDigest("sha256", artifactDigestBytes)
res, err := sev.Verify(signatureBytes, verify.NewPolicy(artifactPolicy))
```

---

### Example 4: Complete AppProject Configuration

**Scenario:** Application uses both Helm charts and OCI artifacts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: secure-project
spec:
  sourceIntegrity:
    # Git verification (existing)
    git:
      policies:
        - repos: ["https://github.com/org/*"]
          gpg:
            mode: "strict"
            keys: ["0xGITKEY1"]
    
    # Helm chart verification
    helm:
      policies:
        # Traditional Helm repo
        - repos: ["https://charts.example.com/*"]
          gpg:
            mode: "provenance"
            keys: ["0xHELMKEY1"]
        # OCI Helm repo (uses .prov files, same verification)
        - repos: ["oci://registry.example.com/charts/*"]
          gpg:
            mode: "provenance"
            keys: ["0xHELMKEY1"]
    
    # OCI artifact verification (non-Helm)
    oci:
      policies:
        - repos: ["oci://registry.example.com/images/*"]
          sigstore:
            mode: "signature"
            publicKey: |
              -----BEGIN PUBLIC KEY-----
              MFkwEwYHKoZIzj0CAQYIKoZIzj0CAQYIKoZIzj0CAQYIKoZIzj0CAQYIKoZIzj0C...
              -----END PUBLIC KEY-----
```

**Application Example:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  project: secure-project
  source:
    # Helm chart from traditional repo
    repoURL: https://charts.example.com/mychart
    targetRevision: 1.0.0
    helm:
      valuesObject:
        key: value
  sources:
    # Multi-source: Helm chart from OCI + OCI artifact
    - repoURL: oci://registry.example.com/charts/nginx
      targetRevision: 15.9.0
      helm:
        valuesObject:
          key: value
    - repoURL: oci://registry.example.com/images/myapp
      targetRevision: v1.0.0
```

**Verification Flow:**
1. **Helm chart from traditional repo** → Verified using `sourceIntegrity.helm` policy (GPG, `.prov` file)
2. **Helm chart from OCI** → Verified using `sourceIntegrity.helm` policy (GPG, `.prov` layer)
3. **OCI artifact** → Verified using `sourceIntegrity.oci` policy (cosign signature)

---

### Example 5: Verification Failure Scenarios

**Helm Chart - Missing .prov File:**
```
Error: HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: .prov file missing
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

**Helm Chart - Wrong Key:**
```
Error: HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: signed with key not in keyring (key_id=0xWRONGKEY)
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

**Helm Chart - Checksum Mismatch:**
```
Error: HELM/GPG: Failed verifying chart mychart-1.0.0.tgz: checksum mismatch (tampering detected)
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

**OCI Artifact - Missing Signature:**
```
Error: OCI/SIGSTORE: Failed verifying artifact oci://registry.example.com/images/myapp:v1.0.0: signature not found
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

**OCI Artifact - Wrong Key:**
```
Error: OCI/SIGSTORE: Failed verifying artifact oci://registry.example.com/images/myapp:v1.0.0: signature verification failed (wrong key)
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

**OCI Artifact - Digest Mismatch:**
```
Error: OCI/SIGSTORE: Failed verifying artifact oci://registry.example.com/images/myapp:v1.0.0: artifact digest mismatch (tampering detected)
Status: ApplicationConditionComparisonError
Sync: BLOCKED
```

---

## Dependencies

* **Source Integrity Policies (Git):** PR #25371 must be merged first (or API stable)
* **Helm:** Uses existing Helm tooling (no new dependencies)
* **Cosign:** Requires cosign Go library (new dependency: `github.com/sigstore/cosign/v2`)

## References

* Source Integrity Policies Proposal: https://github.com/argoproj/argo-cd/pull/25148
* Source Integrity Policies Implementation: https://github.com/argoproj/argo-cd/pull/25371
* Helm Provenance: https://helm.sh/docs/topics/provenance/
* Cosign: https://github.com/sigstore/cosign
* Cosign Go Library: https://pkg.go.dev/github.com/sigstore/cosign/v2
* OCI Distribution Spec: https://github.com/opencontainers/distribution-spec
