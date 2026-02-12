# ArgoCD Multisource Applications — Learning & Contribution Guide

A short guide to **multiple sources** for a single Application and how to contribute to Argo CD.

---

## What are multisource applications?

By default, an Argo CD Application has **one source** (one Git repo path or one Helm chart).  
**Multisource** lets you define **multiple `sources`** in the Application spec. Argo CD:

- Renders manifests for each source
- Merges them into one set
- Syncs that combined set to the cluster

When you use `spec.sources` (plural), Argo CD **ignores** `spec.source` (singular).

**Introduced:** Argo CD 2.6  
**Main PR:** [argoproj/argo-cd#10432](https://github.com/argoproj/argo-cd/pull/10432) (merged Dec 2022)

---

## Official docs

- **User guide:** [Multiple Sources for an Application](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- **In repo:** `docs/user-guide/multiple_sources.md` in [argoproj/argo-cd](https://github.com/argoproj/argo-cd)

---

## Typical use cases

| Use case | Description |
|----------|-------------|
| **Helm + Git values** | External Helm chart + your own value files from a Git repo (no need to fork the chart). |
| **Microservices** | Combine manifests from several repos into one Application. |
| **Shared config** | Common ConfigMaps/Secrets from one repo + app-specific manifests from another. |
| **Override resources** | Same resource (group/kind/name/namespace) from two sources → last source wins (with `RepeatedResourceWarning`). |

**Important:** The feature is **not** for grouping many unrelated apps. For that, use **ApplicationSets** or **app-of-apps**. If you have more than 2–3 sources, reconsider the design.

---

## Multisource in this repo

You’re already using multisource via an **ApplicationSet** that generates Applications with `sources`:

**File:** [`applicationset.yaml`](../applicationset.yaml)

- **Source 1 (Git, `ref: helmValues`):** This repo — provides Helm value files only (no path → no manifests from this source).
- **Source 2 (Helm):** Bitnami chart (e.g. `nginx`) with:
  - `valueFiles` pointing at `$helmValues/apps/{{.app}}/values/...` (the `$helmValues` ref = first source).
  - Values come from `apps/app1/values/` (globals, environments, clusters).

So each generated Application is a **single Application, two sources**: one Git (values), one Helm (chart + ref to Git values).

**App config example:** [`apps/app1/argo-config.json`](../apps/app1/argo-config.json) — drives which chart/revision and overrides (e.g. `helmChart`, `helmChartVersion`, `overrides` per environment).

---

## Minimal Application example (no ApplicationSet)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-billing-app
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  sources:
    - repoURL: https://github.com/mycompany/billing-app.git
      path: manifests
      targetRevision: 8.5.1
    - repoURL: https://github.com/mycompany/common-settings.git
      path: configmaps-billing
      targetRevision: HEAD
```

Helm + Git values (Prometheus example from docs):

```yaml
spec:
  sources:
    - repoURL: 'https://prometheus-community.github.io/helm-charts'
      chart: prometheus
      targetRevision: 15.7.1
      helm:
        valueFiles:
          - $values/charts/prometheus/values.yaml
    - repoURL: 'https://git.example.com/org/value-files.git'
      targetRevision: dev
      ref: values   # $values in valueFiles points here
```

- `ref: values` → that source is referenced as `$values` in Helm `valueFiles`.
- `$values` must be at the start of the path; path is relative to the root of that source.
- A source with `ref` cannot use `chart` (no “Helm chart as value source” yet).

---

## Contributing to Argo CD (multisource and around it)

### 1. Repo and structure

- **Repo:** [github.com/argoproj/argo-cd](https://github.com/argoproj/argo-cd)
- **Docs:** `docs/user-guide/multiple_sources.md`
- **Application types:** Look for `ApplicationSpec` and handling of `Source` vs `Sources` in the codebase.

### 2. Where to look in the codebase

- **Application spec:** `Sources` vs `Source` (e.g. types, validation, defaulting).
- **Manifest generation:** Code that builds the final manifest list from multiple sources (likely in application controller / manifest generation).
- **UI/CLI:** Docs note that multiple sources are still not fully supported in UI/CLI; those areas are good contribution targets.

Search for:

- `sources` (plural) in Application types and controllers
- `multiple_sources` or “multiple sources” in docs and comments
- `RepeatedResourceWarning` (behavior when same resource appears in multiple sources)

### 3. Known issues / enhancement ideas

- **Same repo, different revisions:** [Issue #25605](https://github.com/argoproj/argo-cd/issues/25605) — multisource when the same repo is used with different `targetRevision` can hit revision conflict errors.
- **Optional / ignore missing sources:** [Issue #12679](https://github.com/argoproj/argo-cd/issues/12679) — allow sync to continue if some sources fail (e.g. auth) or are missing, similar to `ignoreMissingValueFiles`.

Contributing to these or to UI/CLI support is valuable.

### 4. How to contribute

1. Read [Contributing to Argo CD](https://github.com/argoproj/argo-cd/blob/master/CONTRIBUTING.md).
2. Set up the dev environment (Go, make targets, maybe kind/k3s for e2e).
3. Find an issue or small doc/code improvement around multisource (or open a well-scoped one).
4. Implement in a branch, add/update tests, update docs if behavior or UX changes.
5. Open a PR and reference the issue; follow maintainer feedback.

---

## Next steps

1. **Experiment here:** Add a standalone `Application` YAML in this repo that uses `spec.sources` (e.g. two Git paths or Helm + Git values) and sync it in your cluster.
2. **Read the code:** Clone `argoproj/argo-cd`, grep for `sources` and `Source` in the application API and controller, and trace how multisource manifests are merged.
3. **Pick an issue:** Start with #12679 or #25605 (or a “good first issue” that touches multisource/docs).
4. **Improve this doc:** As you learn, add “Notes from the codebase” or “Testing multisource” sections to this file.

---

## Quick reference

| Concept | Detail |
|--------|--------|
| **Spec field** | `spec.sources` (array); `spec.source` ignored when `sources` is set |
| **Conflict** | Same resource from multiple sources → last wins; `RepeatedResourceWarning` |
| **Helm + Git** | Use `ref` on the Git source and `$values/...` in Helm `valueFiles` |
| **Status** | Feature in use; UI/CLI support still limited (beta-era behavior) |

Happy learning and contributing.
