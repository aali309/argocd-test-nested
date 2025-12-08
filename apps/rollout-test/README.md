# Argo Rollouts Test

This folder contains Argo Rollout resources to test the Rollout Details page in Dev Console PR (#7299).

## Resources

### Blue-Green Rollout
- **Rollout**: `blue-green-rollout.yaml` - A Blue-Green deployment strategy with 3 replicas
- **Active Service**: `blue-green-active-service.yaml` - Service pointing to the active version
- **Preview Service**: `blue-green-preview-service.yaml` - Service pointing to the preview version

### Canary Rollout
- **Rollout**: `canary-rollout.yaml` - A Canary deployment strategy with progressive traffic shifting
- **Stable Service**: `canary-stable-service.yaml` - Service pointing to the stable version
- **Canary Service**: `canary-service.yaml` - Service pointing to the canary version

### Analysis Templates
- **AnalysisTemplate**: `analysis-template.yaml` - Namespace-scoped analysis template for success rate
- **ClusterAnalysisTemplate**: `cluster-analysis-template.yaml` - Cluster-scoped analysis template for HTTP error rate

### ArgoCD Application
- **Application**: `rollout-application.yaml` - ArgoCD Application to manage all rollout resources

## How to Use

### Option 1: Using ArgoCD Application (Recommended)

Apply the ArgoCD Application (for OpenShift GitOps, use `openshift-gitops` namespace):
```bash
kubectl apply -f apps/rollout-test/rollout-application.yaml
```

The Application will automatically create the namespace and sync all resources.

### Option 2: Apply Resources Directly

If applying directly with kubectl, apply the namespace first, then the rest:
```bash
# Apply namespace first
kubectl apply -f apps/rollout-test/namespace.yaml

# Wait a moment for namespace to be ready, then apply the rest
kubectl apply -f apps/rollout-test/ --ignore-not-found
```

3. Access the rollouts in the Dev Console:

   **Option A: Via Resource List**
   - Navigate to the `rollout-test` namespace in the Dev Console
   - Look for "Argo Rollouts" or "Rollouts" in the resource list (left sidebar)
   - Click on a rollout to view its details

   **Option B: Direct URL**
   - Navigate directly to: `/k8s/ns/rollout-test/argoproj.io~v1alpha1~Rollout/blue-green-rollout`
   - Or: `/k8s/ns/rollout-test/argoproj.io~v1alpha1~Rollout/canary-rollout`

   **Option C: Via GitOps Plugin**
   - Navigate to the GitOps section in the Dev Console
   - Look for "Argo Rollouts" in the navigation menu
   - This should show a list of all rollouts

4. In the Rollout Details page, you should see:
   - **Details tab** showing:
     - Replicas (editable)
     - Status
     - Strategy (Blue-Green or Canary)
     - Services (Active/Preview for Blue-Green, Stable/Canary for Canary)
     - Analysis Templates (for Canary strategy)
   - **YAML tab** - View/edit the rollout YAML
   - **Events tab** - View rollout events

**Note**: If you don't see "Argo Rollouts" in the resource list, the console plugin might need the `ARGO_ROLLOUT` feature flag enabled. Check your console plugin configuration.

## Testing the PR Features

The PR adds the following features that you can test:

1. **Rollout Details Tab**: View rollout information including:
   - Replicas (editable)
   - Status
   - Strategy (Blue-Green or Canary)
   - Services (Active/Preview for Blue-Green, Stable/Canary for Canary)
   - Analysis Templates (for Canary strategy)

2. **Topology View**: Click the topology icon to view the rollout in the topology graph

3. **Conditions**: View rollout conditions in the Conditions section

## Cleanup

To clean up the test resources:
```bash
kubectl delete -f apps/rollout-test/
```

