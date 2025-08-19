# Progressive Sync Test Setup

This folder contains ApplicationSet manifests to test different progressive sync strategies in ArgoCD.

## Test Scenarios

### 1. Default AllAtOnce Strategy
**File:** `applicationset-allatonce-default.yaml`
- Creates 2 applications: `test-app-1` and `test-app-2`
- Uses `apps/app1` from your repo
- No strategy specified (defaults to AllAtOnce)
- All applications should be created simultaneously

### 2. Explicit AllAtOnce Strategy
**File:** `applicationset-explicit-allatonce.yaml`
- Creates 1 application: `test-app-3`
- Uses `apps/app3` from your repo
- Explicitly specifies `AllAtOnce` strategy
- Application should be created immediately

### 3. RollingSync Strategy
**File:** `applicationset-rollingsync.yaml`
- Creates 2 applications: `test-app-4` and `test-app-5`
- Uses `apps/app4` from your repo
- Uses `RollingSync` strategy with 2 steps
- Applications should be created in sequence:
  1. First step: `test-app-4`
  2. Second step: `test-app-5`

## How to Apply

1. Start your ArgoCD instance (if not already running):
   ```bash
   make start-e2e-local
   ```

2. Apply the ApplicationSets:
   ```bash
   # Apply all at once
   kubectl apply -f apps/progressive-sync-test/
   
   # Or apply individually
   kubectl apply -f apps/progressive-sync-test/applicationset-allatonce-default.yaml
   kubectl apply -f apps/progressive-sync-test/applicationset-explicit-allatonce.yaml
   kubectl apply -f apps/progressive-sync-test/applicationset-rollingsync.yaml
   ```

3. Access ArgoCD UI at `http://localhost:4000`

4. Navigate to the `argocd-e2e` namespace and observe:
   - ApplicationSet resources
   - Generated Application resources
   - Sync status and timing

## Expected Behavior

- **AllAtOnce strategies**: Applications should appear and sync simultaneously
- **RollingSync strategy**: Applications should appear and sync in sequence according to the defined steps

## Cleanup

To clean up the test resources:
```bash
kubectl delete -f apps/progressive-sync-test/
```
