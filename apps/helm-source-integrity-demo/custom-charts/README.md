# Custom Helm & OCI Charts — Sign and Test Source Integrity

Use **your own** Helm chart, sign it with GPG, then point the source-integrity demo at it so you can test **provenance required** with a chart that actually has a valid `.prov` file.

---

## Run and see results (easy debug)

**Click Run** on the command below (or run it in your terminal). It signs the chart and prints the key ID plus the exact next commands to run.

```bash
bash ./apps/helm-source-integrity-demo/custom-charts/run-sign-one-chart.sh
```

Or make it executable once then run directly: `chmod +x ./apps/helm-source-integrity-demo/custom-charts/run-sign-one-chart.sh && ./apps/helm-source-integrity-demo/custom-charts/run-sign-one-chart.sh`

With your own key:

```bash
KEY_EMAIL="your@email.com" bash ./apps/helm-source-integrity-demo/custom-charts/run-sign-one-chart.sh
```

You’ll see:
- **Step 1** — key generation (if needed) and packaging/signing
- **Results** — `repo/` contents and your **Key ID**
- **Next commands** — copy-paste the argocd gpg add, edit project, serve repo, and kubectl apply lines

If you see **"private key checksum failure"** or a password prompt: remove the old demo key and re-run. Use the key ID (e.g. from the script output, 16 hex chars like `0BF159B338BD717C`): `gpg --batch --delete-secret-keys KEY_ID` then `gpg --batch --delete-keys KEY_ID`, then `rm -f keys/demo-helm-signing.*`, then run the script again.

---

## Sign one chart at a time

We start with **one chart** (`demo-chart`). Do these steps in order. Later you can add more charts and sign them the same way.

### Chart 1: demo-chart (only chart for now)

**Step 1 — Sign this chart**

From `custom-charts/`:

- **If you have your own key:**  
  `KEY_EMAIL="your@email.com" ./scripts/package-and-sign.sh`  
  (Or `KEY_NAME="Your Name"` if you prefer. If your secret key isn’t in the default keyring, see “I already have a GPG key” below for `KEYRING`.)

- **If you need a new key:**  
  `./scripts/gen-gpg-key.sh` then `./scripts/package-and-sign.sh`

When it finishes, **copy the key ID** it prints (you’ll need it in Step 3).

**Step 2 — Add the public key to Argo CD**

- Your key: `gpg --armor --export your@email.com | argocd gpg add --from -`
- Key from gen-gpg-key.sh: `argocd gpg add --from keys/demo-helm-signing.asc`

**Step 3 — Put the key ID in the project**

Edit `../07-pass-custom-signed-helm/project.yaml`: replace `REPLACE_WITH_KEY_ID` with the key ID from Step 1.

**Step 4 — Serve the repo**

```bash
cd repo
python3 -m http.server 8080
```

(If Argo CD runs in-cluster, use a URL it can reach and set that in the app’s `repoURL` and the project’s `repos[].url`.)

**Step 5 — Apply and check sync**

```bash
kubectl apply -f ../07-pass-custom-signed-helm/
```

Open the app **helm-custom-signed-demo** in Argo CD — it should show **Synced**. That’s one chart signed and working with source integrity.

---

*When you’re ready to add another chart, we can add a second chart and repeat the same pattern.*

---

## OCI Helm repos (scenario 08)

Same **signed chart** as above; you **push it to an OCI registry** and point Argo CD at it. Source integrity for OCI uses the same policy (provenance + key); Argo CD fetches chart and `.prov` from the registry.

**One-shot (sign + push, then follow printed steps):**

```bash
REGISTRY=oci://localhost:5000/charts bash ./apps/helm-source-integrity-demo/custom-charts/run-sign-and-push-oci.sh
```

Or with your own registry (e.g. GitHub Container Registry):

```bash
REGISTRY=oci://ghcr.io/YOUR_USER/charts bash ./apps/helm-source-integrity-demo/custom-charts/run-sign-and-push-oci.sh
```

**Manual steps:**

1. Sign the chart (traditional flow): `bash run-sign-one-chart.sh`
2. Push to OCI: `REGISTRY=oci://localhost:5000/charts ./scripts/push-oci.sh` (or your registry)
3. Add public key: `argocd gpg add --from keys/demo-helm-signing.asc`
4. In **08-pass-custom-signed-oci/project.yaml**: set `keys` to your key ID and `repos[].url` to match (e.g. `oci://localhost:5000/*`)
5. In **08-pass-custom-signed-oci/app.yaml**: set `source.repoURL` to e.g. `oci://localhost:5000/charts/demo-chart` and `targetRevision` to `1.0.0`
6. Apply: `kubectl apply -f ../08-pass-custom-signed-oci/`

**Note:** `helm push` uploads only the chart. For Argo CD to verify provenance, the registry must also serve the `.prov` file (e.g. some registries do this; otherwise you may need to push the `.prov` as a separate OCI artifact with a tool like [ORAS](https://oras.land/)).

---

## I already have a GPG key

Use your key to sign the chart and get the key ID for the project:

1. **Sign the chart** (use your key’s email or name as Helm’s `--key`; it must match the key’s UID):
   ```bash
   cd apps/helm-source-integrity-demo/custom-charts
   chmod +x scripts/*.sh
   KEY_EMAIL="your@email.com" ./scripts/package-and-sign.sh
   ```
   Or by name: `KEY_NAME="Your Name" ./scripts/package-and-sign.sh`  
   If your secret key isn’t in the default keyring, export it and pass `KEYRING`:
   ```bash
   gpg --export-secret-keys your@email.com > keys/my.secret.gpg
   KEY_EMAIL="your@email.com" KEYRING="$(pwd)/keys/my.secret.gpg" ./scripts/package-and-sign.sh
   ```
   The script prints the **key ID** at the end — use it in step 3. To get your key ID without packaging: `./scripts/print-key-id.sh your@email.com`

2. **Add your public key to Argo CD:**
   ```bash
   gpg --armor --export your@email.com | argocd gpg add --from -
   ```
   Or from a file: `argocd gpg add --from /path/to/public.asc`

3. **Set the key ID in the project**  
   Edit `07-pass-custom-signed-helm/project.yaml`: replace `REPLACE_WITH_KEY_ID` with the key ID from step 1.

4. **Serve the repo** and **apply** (same as “Quick test” steps 4–5 below).

---

## Quick test: “Does sync work for source integrity?”

Minimal steps to get a **passing** sync with provenance required:

1. **Sign the chart** (from repo root or `custom-charts/`):
   ```bash
   cd apps/helm-source-integrity-demo/custom-charts
   chmod +x scripts/*.sh
   ./scripts/gen-gpg-key.sh
   ./scripts/package-and-sign.sh
   ```
   Copy the **key ID** printed by `gen-gpg-key.sh`.

2. **Add the public key to Argo CD:**
   ```bash
   argocd gpg add --from apps/helm-source-integrity-demo/custom-charts/keys/demo-helm-signing.asc
   ```

3. **Set the key ID in the project**  
   Edit `07-pass-custom-signed-helm/project.yaml`: replace `REPLACE_WITH_KEY_ID` with the key ID from step 1.

4. **Serve the repo** (so Argo CD can fetch the chart and `.prov`):
   ```bash
   cd apps/helm-source-integrity-demo/custom-charts/repo
   python3 -m http.server 8080
   ```
   If Argo CD runs in-cluster, use a URL it can reach (e.g. GitHub Pages or a reachable host:port) and set that in the app’s `repoURL` and the project’s `repos[].url`.

5. **Apply the Application and project:**
   ```bash
   kubectl apply -f apps/helm-source-integrity-demo/07-pass-custom-signed-helm/
   ```

If source integrity is working, the app **helm-custom-signed-demo** should sync successfully (Synced, no comparison error).

---

## What you get

- **demo-chart**: minimal Helm chart (ConfigMap + Deployment).
- **Scripts**: generate a GPG key, package+sign the chart, optionally push to OCI.
- **Scenarios 07 & 08**: Argo CD Applications that require provenance and use your key; they sync only when the chart is signed and the key is allowed.

## Prerequisites

- `helm` (v3)
- `gpg` (GnuPG)
- For OCI: a registry you can push to (e.g. `localhost:5000`, `ghcr.io`, Docker Hub)

## 1. Generate a GPG key

From this directory (`custom-charts/`):

```bash
cd apps/helm-source-integrity-demo/custom-charts
chmod +x scripts/*.sh
./scripts/gen-gpg-key.sh
```

This creates:

- `keys/demo-helm-signing.asc` — public key (for Argo CD).
- `keys/demo-helm-signing.secret.gpg` — secret key (for signing).
- Prints the **key ID** (e.g. `A1B2C3D4E5F67890`). Copy it; you’ll put it in the AppProject.

## 2. Package and sign the chart

```bash
./scripts/package-and-sign.sh
```

This produces:

- `repo/demo-chart-1.0.0.tgz`
- `repo/demo-chart-1.0.0.tgz.prov`
- `repo/index.yaml`

## 3a. Test with traditional Helm repo (scenario 07)

Serve the repo over HTTP. From `custom-charts/repo/`:

```bash
cd repo
python3 -m http.server 8080
```

**If Argo CD runs inside the cluster:** `localhost:8080` from your machine is not reachable by the repo-server. Use one of:
- A URL the cluster can reach (e.g. `http://host.docker.internal:8080` from kind, or a NodePort/LoadBalancer).
- **GitHub Pages** (see “Optional: Host the repo on GitHub Pages” below) and use that URL in the Application.

In another terminal:

1. **Add the public key to Argo CD** (so it can verify the signature):

   ```bash
   argocd gpg add --from apps/helm-source-integrity-demo/custom-charts/keys/demo-helm-signing.asc
   ```

2. **Set the key ID in the project**  
   Edit `07-pass-custom-signed-helm/project.yaml`: replace `REPLACE_WITH_KEY_ID` with the key ID from step 1.  
   If your repo is not at `http://localhost:8080`, also change the `repos[].url` pattern (e.g. `https://YOUR_USER.github.io/*` for GitHub Pages).

3. **Set the repo URL in the app**  
   Edit `07-pass-custom-signed-helm/app.yaml`: set `source.repoURL` to your repo base URL (e.g. `http://localhost:8080`).

4. **Apply and sync**

   ```bash
   kubectl apply -f apps/helm-source-integrity-demo/07-pass-custom-signed-helm/
   ```

The app should sync successfully (provenance required and satisfied).

## 3b. Test with OCI (scenario 08)

1. **Push the chart to an OCI registry**

   ```bash
   # Local registry (e.g. kind with a local registry)
   REGISTRY=oci://localhost:5000/charts ./scripts/push-oci.sh

   # Or GitHub Container Registry
   REGISTRY=oci://ghcr.io/YOUR_USER/charts ./scripts/push-oci.sh
   ```

2. **Add the public key to Argo CD** (same as 3a).

3. **Edit `08-pass-custom-signed-oci/project.yaml`**  
   Replace `REPLACE_WITH_KEY_ID` with your key ID, and set `repos[].url` to match your registry (e.g. `oci://localhost:5000/*` or `oci://ghcr.io/YOUR_USER/*`).

4. **Edit `08-pass-custom-signed-oci/app.yaml`**  
   Set `source.repoURL` to the chart ref (e.g. `oci://localhost:5000/charts/demo-chart`) and `targetRevision` to `1.0.0`.

5. **Apply and sync**

   ```bash
   kubectl apply -f apps/helm-source-integrity-demo/08-pass-custom-signed-oci/
   ```

**Note:** OCI provenance support depends on the registry. Some registries store or serve the `.prov` artifact in a way Argo CD expects; others may not. If sync fails with a provenance error, try scenario 07 (traditional Helm) first.

## Optional: Host the repo on GitHub Pages

1. Create a branch `gh-pages` (or use `docs/` and GitHub Pages from branch).
2. Copy `repo/index.yaml`, `repo/demo-chart-1.0.0.tgz`, and `repo/demo-chart-1.0.0.tgz.prov` into the path GitHub serves (e.g. `charts/`).
3. Set `source.repoURL` in the Application to `https://YOUR_USER.github.io/YOUR_REPO/charts` and the project policy to match that URL.

## File layout

```
custom-charts/
├── README.md           # This file
├── demo-chart/         # Source chart
│   ├── Chart.yaml
│   └── templates/
├── keys/               # GPG keys (do not commit *.secret.*)
├── repo/               # Built index + .tgz + .prov (generate with scripts)
└── scripts/
    ├── gen-gpg-key.sh
    ├── package-and-sign.sh
    └── push-oci.sh
```

## Troubleshooting

- **“provenance signature verification failed”** — Argo CD doesn’t have your public key. Run `argocd gpg add --from keys/demo-helm-signing.asc` and ensure the key ID in the project matches the signer.
- **“Chart is missing the required provenance”** — The repo URL must serve the `.prov` at the same path as the chart (e.g. `.../demo-chart-1.0.0.tgz.prov`). Check that `package-and-sign.sh` ran and the server serves the `repo/` directory.
- **“multiple Helm source integrity policies found”** — Only one policy must match the repo URL; tighten or change the `repos[].url` pattern.
