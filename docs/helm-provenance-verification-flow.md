# Helm Chart Provenance Verification — End-to-End Flow

This document explains how Argo CD verifies Helm chart provenance (`.prov` files and GPG) from configuration to sync. No prior knowledge of the codebase is assumed.

---

## Table of Contents

1. [What Is Being Verified](#1-what-is-being-verified)
2. [High-Level Flow (Diagram)](#2-high-level-flow-diagram)
3. [Where Configuration Lives](#3-where-configuration-lives)
4. [Call Hierarchy: Who Calls What](#4-call-hierarchy-who-calls-what)
5. [Step-by-Step Verification](#5-step-by-step-verification)
6. [How Sync Is Blocked When Verification Fails](#6-how-sync-is-blocked-when-verification-fails)
7. [YAML Examples](#7-yaml-examples)
8. [Policy Matching Rules](#8-policy-matching-rules)
9. [Reference: Key Code Locations](#9-reference-key-code-locations)

---

## 1. What Is Being Verified

- **Provenance file (`.prov`)**: A signed file that attests to a Helm chart (name, version, SHA256 of the chart tarball). It is produced by `helm package --sign` (traditional) or by the registry/CI for OCI charts.
- **GPG signature**: The `.prov` file is a PGP cleartext-signed message. Argo CD runs `gpg --verify` and checks that the signer’s key ID is one of the keys allowed in the project’s policy.
- **Chart checksum**: The `.prov` file contains a `files:` section listing chart filenames and their SHA256. Argo CD ensures the downloaded chart’s SHA256 matches what is in the `.prov`.

If any of these checks fail (or the policy requires provenance and it’s missing), the chart is rejected and sync does not proceed.

---

## 2. High-Level Flow (Diagram)

```mermaid
flowchart TB
    subgraph Config["Configuration (Kubernetes)"]
        AppProject["AppProject"]
        AppProject --> SI["spec.sourceIntegrity.helm.policies"]
    end

    subgraph Request["Request Path"]
        App["Application (sources: Helm/OCI)"]
        App --> Server["Argo CD Server / Controller"]
        Server --> HasCriteria["HasCriteria(si, sources)?"]
        HasCriteria -->|Yes| RepoServer["Repo-Server"]
        RepoServer --> Resolve["Resolve revision + fetch chart"]
    end

    subgraph RepoServerDetail["Repo-Server (Helm path)"]
        Resolve --> HelmClient["Helm client (traditional or OCI)"]
        HelmClient --> FetchChart["Fetch chart .tgz"]
        HelmClient --> FetchProv["Fetch .prov"]
        FetchChart --> Verify["Provenance check callback"]
        FetchProv --> Verify
        Verify --> VerifyHelm["VerifyHelm(si, repoURL, chart, prov, filename)"]
        VerifyHelm --> Result["SourceIntegrityCheckResult"]
        Result --> OpCtx["operationContext.sourceIntegrityResult"]
    end

    subgraph ManifestAndSync["Manifest generation & Sync"]
        OpCtx --> Manifest["GenerateManifest response"]
        Manifest --> SourceIntegrityResult["ManifestResponse.SourceIntegrityResult"]
        SourceIntegrityResult --> Controller["Controller (state.go)"]
        Controller --> AsError["SourceIntegrityResult.AsError()"]
        AsError -->|Non-nil| BlockSync["Add ComparisonError condition → sync blocked"]
        AsError -->|Nil| AllowSync["Sync allowed"]
    end

    SI --> HasCriteria
    Config -.->|EffectiveSourceIntegrity()| RepoServer
```

**In one sentence:** The project’s Helm policies are loaded from the AppProject, passed to the repo-server when resolving/generating manifests, the Helm/OCI client fetches the chart and `.prov`, runs `VerifyHelm`, and the result is attached to the manifest response; the controller then uses that result to allow or block sync.

---

## 3. Where Configuration Lives

| What | Where | Meaning |
|------|--------|--------|
| **Policies** | **AppProject** `spec.sourceIntegrity.helm.policies` | List of policies. Each policy has `repos` (URL globs) and `gpg` (mode + keys). Stored in the cluster (YAML or API). |
| **Schema** | CRD (e.g. `appproject-crd.yaml` or embedded in install manifests) | Defines the shape of `sourceIntegrity.helm.policies`. Does not hold actual policy data. |
| **At runtime** | In-memory `*v1alpha1.SourceIntegrity` | Populated from the AppProject when the server/controller/repo-server reads the project. This is the `si` passed to `HasCriteria`, `VerifyHelm`, etc. |

So: **policies are defined in the AppProject (YAML/API); the CRD only validates structure.** The “thing we check” in code is the in-memory `SourceIntegrity` from that project.

---

## 4. Call Hierarchy: Who Calls What

Calls are ordered from “entry” down to “verification.” File paths are relative to the repo root.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. Server / Controller (decide whether source integrity applies)             │
├─────────────────────────────────────────────────────────────────────────────┤
│ server/application/application.go                                            │
│   HasCriteria(proj.EffectiveSourceIntegrity(), a.Spec.GetSources()...)     │
│   → Reject "local manifests" if true                                        │
│ controller/state.go                                                          │
│   HasCriteria(project.EffectiveSourceIntegrity(), sources...)               │
│   → If true and user uses local manifests, clear targets + add condition   │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. Repo-Server (resolve revision + generate manifests)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│ reposerver/repository/repository.go                                         │
│   runRepoOperation(..., sourceIntegrity, operation)                         │
│   → switch source type: OCI vs Helm vs Git                                  │
│   For Helm: newHelmClientResolveRevision(..., sourceIntegrity,              │
│             setHelmSourceIntegrityResult)                                    │
│   For OCI Helm: newOCIClientResolveRevision(..., sourceIntegrity,           │
│                 setOCISourceIntegrityResult)                                │
│   operation() → ExtractChart (Helm) or OCI extract → provenance check runs   │
│   → result stored in helmSourceIntegrityResult / ociSourceIntegrityResult   │
│   → operationContext{ chartPath, helmSourceIntegrityResult }                 │
│   Later: manifestGenResult.SourceIntegrityResult = opContext.sourceIntegrityResult │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    ▼                                       ▼
┌──────────────────────────────┐    ┌──────────────────────────────────────────┐
│ 3a. Traditional Helm        │    │ 3b. OCI Helm                              │
├──────────────────────────────┤    ├──────────────────────────────────────────┤
│ util/helm/client.go          │    │ util/oci/client.go                       │
│   newHelmClientResolveRevision │  │   newOCIClientResolveRevision            │
│   opts += WithProvenanceCheck │    │   opts += WithHelmProvenanceCheck         │
│   opts += WithProvenanceResultReceiver │ WithHelmProvenanceResultReceiver     │
│   ExtractChart()              │    │   extract() when Helm + provenance set  │
│     → fetchProvenance(provURL)│    │     → fetchHelmChartAndProvenance()      │
│     → provenanceCheck(repoURL, chart, prov, chartFilename)                  │
│     → provenanceResultReceiver(result)                                      │
└──────────────────────────────┘    └──────────────────────────────────────────┘
                    │                                       │
                    └───────────────────┬───────────────────┘
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. Provenance check callback (repo-server supplies this to Helm/OCI client)  │
├─────────────────────────────────────────────────────────────────────────────┤
│ reposerver/repository/repository.go                                         │
│   WithProvenanceCheck(func(repoURL, chartContent, provContent, chartFilename) {
│     if !sourceintegrity.HasHelmCriteria(si, repoURL) { return nil, nil }
│     return sourceintegrity.VerifyHelm(si, repoURL, chartContent, provContent, chartFilename)
│   })                                                                         │
│   WithHelmProvenanceResultReceiver / WithHelmProvenanceResultReceiver        │
│     → setHelmSourceIntegrityResult(r) / setOCISourceIntegrityResult(r)       │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. Source integrity package (policy + verification)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ util/sourceintegrity/source_integrity.go                                    │
│   HasHelmCriteria(si, repoURL)     → len(matchingHelmPolicies(...)) > 0     │
│   VerifyHelm(si, repoURL, chart, prov, chartFilename)                       │
│     → helmPolicyToEnforce(si, repoURL)   [policy for this repo; err if >1]  │
│     → helmCheckProvenancePresent(prov)    [.prov not empty]                  │
│     → helmVerifyProvenanceSignature(prov) [GPG verify → signer key ID]      │
│     → helmVerifySignerInPolicy(signerKeyID, policy) [key in policy.Keys]    │
│     → helmVerifyChartChecksum(prov, chartFilename, chartContent)             │
│     → helmCheckResult(problem) → *SourceIntegrityCheckResult                 │
│ util/sourceintegrity/gpg.go                                                 │
│   VerifyCleartextSignedMessage(provContent)  [gpg --verify -; parse key ID]│
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. Controller (sync decision)                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ controller/state.go                                                          │
│   for manifestInfo := range manifestInfos {                                  │
│     if err = manifestInfo.SourceIntegrityResult.AsError(); err != nil {      │
│       conditions += ApplicationCondition{ Type: ComparisonError, Message }   │
│     }                                                                        │
│   }                                                                          │
│   → Sync is effectively blocked when there is a ComparisonError.            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Step-by-Step Verification

Inside `VerifyHelm`, the order of checks is:

| Step | Function | What happens |
|------|----------|----------------|
| 1 | `helmPolicyToEnforce(si, repoURL)` | Find the single policy whose `repos` match `repoURL`. If 0 → skip (no check). If >1 → error. If 1 but `GPG == nil` or `mode == "none"` → skip. |
| 2 | `helmCheckProvenancePresent(provContent)` | If `.prov` is empty → result with problem "missing .prov file (provenance required by policy)". |
| 3 | `helmVerifyProvenanceSignature(provContent)` | Runs `VerifyCleartextSignedMessage(prov)` (i.e. `gpg --verify -`), parses signer key ID from stderr. On failure → result with "provenance signature verification failed". |
| 4 | `helmVerifySignerInPolicy(signerKeyID, policy)` | Normalize each `policy.GPG.Keys` with `KeyID()` and compare to `signerKeyID`. If no match → "provenance signed with unallowed key (key_id=...)". |
| 5 | `helmVerifyChartChecksum(prov, chartFilename, chartContent)` | Parse `files:` in `.prov`, get expected SHA256 for `chartFilename`, compute SHA256 of `chartContent`; mismatch or missing → problem string. |
| 6 | `helmCheckResult("")` | No problem → result with empty `Problems` (verification passed). |

Any non-empty problem from steps 2–5 produces a `SourceIntegrityCheckResult` with that problem in `Checks[].Problems`; the controller then treats it as a comparison error and blocks sync.

---

## 6. How Sync Is Blocked When Verification Fails

1. **Repo-server** attaches the result of provenance verification to the manifest response:  
   `manifestGenResult.SourceIntegrityResult = opContext.sourceIntegrityResult`  
   (e.g. in `reposerver/repository/repository.go` around line 939).

2. **Controller** receives manifest info that includes `SourceIntegrityResult`. In `controller/state.go` (around line 973), for each source it does:
   - `manifestInfo.SourceIntegrityResult.AsError()`
   - If that returns a non-nil error, it appends an `ApplicationCondition` with `Type: ApplicationConditionComparisonError` and the error message.

3. When the app has a **ComparisonError** condition, the UI and sync logic treat the application as not in a healthy/comparable state, so **sync is effectively blocked** until the user fixes the issue (e.g. add valid `.prov`, fix keys, or adjust project policy).

4. **Local manifests** are rejected earlier: if the project has `HasCriteria(si, sources)` true (e.g. Helm policies that match the app’s sources), then using “local manifests” is forbidden (server and controller), so the user cannot bypass verification by uploading manifests directly.

---

## 7. YAML Examples

### AppProject with one Helm policy (one repo pattern)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
spec:
  description: "Helm provenance required for charts.example.com"
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: https://kubernetes.default.svc
  sourceIntegrity:
    helm:
      policies:
        - repos:
            - url: "https://charts.example.com/*"
          gpg:
            mode: provenance
            keys:
              - "A1B2C3D4E5F6789012345678901234567890ABCD"
```
why do we only test for mode none for oci, Also test when all git and helm are needed for strict and provenance all together and none

### AppProject with multiple policies (different repos)

```yaml
  sourceIntegrity:
    helm:
      policies:
        - repos:
            - url: "https://charts.example.com/*"
          gpg:
            mode: provenance
            keys: ["KEY_FOR_EXAMPLE"]
        - repos:
            - url: "oci://myregistry.io/myorg/*"
          gpg:
            mode: provenance
            keys: ["KEY_FOR_REGISTRY"]
        - repos:
            - url: "https://internal-charts.corp/*"
          gpg:
            mode: none
```

For a chart from `https://charts.example.com/stable`, only the first policy matches. For a chart from `oci://myregistry.io/myorg/foo`, only the second. **At most one policy must match a given repo URL**; otherwise the code returns an error.

### Example `.prov` content (conceptually)

The `.prov` file is a PGP cleartext-signed message. The body (before the signature) looks conceptually like:

```
chart: mychart-1.2.3.tgz
files:
  mychart-1.2.3.tgz: sha256:abc123...
-----BEGIN PGP SIGNATURE-----
...
-----END PGP SIGNATURE-----
```

Argo CD verifies the signature, extracts the signer key ID, checks it against the policy’s `keys`, and verifies that the chart tarball’s SHA256 matches the `files:` entry.

---

## 8. Policy Matching Rules

- **Policies** are in `spec.sourceIntegrity.helm.policies` (array). Each element has `repos` (list of `{ url: "<glob>" }`) and `gpg` (optional; `mode` and `keys`).
- **Repo URL** is the chart’s repository URL (e.g. `https://charts.example.com` or `oci://registry.io/org`).
- **Matching**: For each policy, we check if any of its `repos[].url` globs match the repo URL (with support for exclusion patterns prefixed with `!`). Implementation: `findMatchingHelmPolicies` in `util/sourceintegrity/source_integrity.go`.
- **Single policy**: For a given repo URL, exactly **one** policy must match. If none match → no verification. If two or more match → error ("multiple Helm source integrity policies found for repo URL").
- **GPG mode**: `provenance` = require valid `.prov` + allowed key; `none` = skip verification for that policy.

---

## 9. Reference: Key Code Locations

| Purpose | File | Function / area |
|--------|------|------------------|
| API types (SourceIntegrity, Helm policies) | `pkg/apis/application/v1alpha1/source_integrity.go` | `SourceIntegrity`, `SourceIntegrityHelm`, `SourceIntegrityHelmPolicy`, `SourceIntegrityHelmPolicyGPG`, modes |
| HasCriteria / HasHelmCriteria | `util/sourceintegrity/source_integrity.go` | `HasCriteria`, `sourceHasCriteria`, `HasHelmCriteria` |
| Policy matching | `util/sourceintegrity/source_integrity.go` | `matchingHelmPolicies`, `findMatchingHelmPolicies`, `repoMatches` |
| Verify Helm | `util/sourceintegrity/source_integrity.go` | `VerifyHelm`, `helmPolicyToEnforce`, `helmCheckProvenancePresent`, `helmVerifyProvenanceSignature`, `helmVerifySignerInPolicy`, `helmVerifyChartChecksum`, `helmCheckResult` |
| GPG verify .prov | `util/sourceintegrity/gpg.go` | `VerifyCleartextSignedMessage`; regex `verifyKeyIDMatch` for "using ... key ID" |
| Repo-server: pass SI + set result | `reposerver/repository/repository.go` | `runRepoOperation`, `newHelmClientResolveRevision`, `newOCIClientResolveRevision`, assignment to `helmSourceIntegrityResult` / `ociSourceIntegrityResult`, `manifestGenResult.SourceIntegrityResult = opContext.sourceIntegrityResult` |
| Traditional Helm: fetch + check | `util/helm/client.go` | `WithProvenanceCheck`, `WithProvenanceResultReceiver`, `ExtractChart` (fetch chart, fetch `.prov`, call `provenanceCheck`, then `provenanceResultReceiver`) |
| OCI Helm: fetch + check | `util/oci/client.go` | `WithHelmProvenanceCheck`, `WithHelmProvenanceResultReceiver`, `fetchHelmChartAndProvenance`, use of `helmProvenanceCheck` and `helmProvenanceResultReceiver` |
| Reject local manifests (server) | `server/application/application.go` | `HasCriteria(...)` then return FailedPrecondition if local manifests |
| Reject local manifests (controller) | `controller/state.go` | `HasCriteria(...)` then clear targets + add condition |
| Block sync on failed verification | `controller/state.go` | Loop over `manifestInfos`, `SourceIntegrityResult.AsError()`, add `ApplicationConditionComparisonError` |
| Result type | `pkg/apis/application/v1alpha1/source_integrity.go` | `SourceIntegrityCheckResult`, `AsError()`, `IsValid()` |

---

This flow applies to both **traditional Helm repos** (chart + `.prov` fetched via HTTP) and **OCI Helm** (chart and provenance layers fetched from the OCI registry). The only difference is which client (Helm vs OCI) performs the fetch and invokes the same `VerifyHelm` callback.
