# Argo Rollouts Test

This folder contains Argo Rollout resources to test the Rollout Details page in Dev Console PR (#7299).

## Prerequisites

**Argo Rollouts Controller must be installed** before applying these resources. The controller processes Rollout resources and creates the necessary ReplicaSets and Pods.

### Installing the Argo Rollouts Controller

**Option 1: Using the install script (Recommended)**
```bash
chmod +x apps/rollout-test/install-controller.sh
./apps/rollout-test/install-controller.sh
```

**Option 2: Manual installation**
```bash
# Create namespace
kubectl create namespace argo-rollouts

# Install controller
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Verify installation
kubectl get pods -n argo-rollouts
```

## Resources

### Rollouts

1. **`simple-rollout.yaml`** - Simple rollout with 3 replicas that will create pods
   - Uses unprivileged nginx image (works in restricted security contexts)
   - Blue-Green strategy with auto-promotion enabled
   - **This rollout will show pods in the UI**

2. **`blue-green-rollout.yaml`** - Blue-Green deployment strategy with 3 replicas
   - Active Service: `blue-green-active-service.yaml`
   - Preview Service: `blue-green-preview-service.yaml`

3. **`canary-rollout.yaml`** - Canary deployment strategy with progressive traffic shifting
   - Stable Service: `canary-stable-service.yaml`
   - Canary Service: `canary-service.yaml`

### Analysis Templates

- **`analysis-template.yaml`** - Namespace-scoped analysis template for success rate
- **`cluster-analysis-template.yaml`** - Cluster-scoped analysis template for HTTP error rate

### ArgoCD Application

- **`rollout-application.yaml`** - ArgoCD Application to manage all rollout resources (optional)

## How to Use

### Step 1: Install Argo Rollouts Controller (if not already installed)

```bash
./apps/rollout-test/install-controller.sh
```

### Step 2: Apply Rollout Resources

```bash
kubectl apply -f apps/rollout-test/
```

This will create:
- The `rollout-test` namespace
- All Rollout resources
- All Services
- Analysis Templates
- ArgoCD Application (if using)

### Step 3: Verify Rollouts and Pods

```bash
# Check rollouts
kubectl get rollouts -n rollout-test

# Check pods (simple-rollout should have 3 pods)
kubectl get pods -n rollout-test -l app=simple-app

# Check rollout status
kubectl get rollout simple-rollout -n rollout-test
```

## Testing the List Page

Access the rollouts in the Dev Console:

**Option A: Via Resource List**
- Navigate to the `rollout-test` namespace in the Dev Console
- Look for "Argo Rollouts" or "Rollouts" in the resource list (left sidebar)
- Click on a rollout to view its details

**Option B: Direct URL**
- Navigate directly to: `/k8s/ns/rollout-test/argoproj.io~v1alpha1~Rollout/simple-rollout`
- Or: `/k8s/ns/rollout-test/argoproj.io~v1alpha1~Rollout/blue-green-rollout`
- Or: `/k8s/ns/rollout-test/argoproj.io~v1alpha1~Rollout/canary-rollout`

**Option C: Via GitOps Plugin**
- Navigate to the GitOps section in the Dev Console
- Look for "Argo Rollouts" in the navigation menu
- This should show a list of all rollouts

## Expected Results

After applying the resources and waiting for the controller to process them:

- **simple-rollout**: Should show **3 pods** in the Pods column (this is the one that works!)
- **blue-green-rollout**: May show pods depending on promotion status
- **canary-rollout**: May show pods depending on canary steps

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

4. **Pods Column**: The `simple-rollout` should display "3" in the Pods column

## Cleanup

To clean up the test resources:

```bash
# Delete rollout resources
kubectl delete -f apps/rollout-test/

# Optional: Uninstall Argo Rollouts controller
kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl delete namespace argo-rollouts
```

## Notes

- The Argo Rollouts controller must be installed for Rollout resources to work properly
- Without the controller, Rollouts will exist but won't create pods or update status
- The `simple-rollout` uses `nginxinc/nginx-unprivileged:1.21` which works in restricted security contexts (OpenShift)
- Some features may require the `ARGO_ROLLOUT` feature flag to be enabled in the console plugin
