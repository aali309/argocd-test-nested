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

1. Apply the ArgoCD Application:
   ```bash
   kubectl apply -f apps/rollout-test/rollout-application.yaml
   ```

2. Or apply all resources directly:
   ```bash
   kubectl apply -f apps/rollout-test/
   ```

3. Access ArgoCD UI at `http://localhost:4000` and navigate to the `rollout-test` namespace

4. In the Dev Console, you should see:
   - **Rollouts** in the resource list
   - **Rollout Details** page with:
     - Details tab showing replicas, status, strategy, and services
     - YAML tab
     - Events tab
   - For Blue-Green: Active Service and Preview Service
   - For Canary: Stable Service, Canary Service, and Analysis Templates

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

