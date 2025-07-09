# Testing Cross-Instance ArgoCD Application Linking

This guide helps you reproduce and test the cross-instance application linking issue that was fixed in ArgoCD PR #23266.

## Issue Description

When an ArgoCD instance manages applications that are actually managed by another ArgoCD instance, the "Open application" links were pointing to the wrong ArgoCD instance, causing data loading issues.

## Test Setup

### Prerequisites

1. A Kubernetes cluster with ArgoCD installed
2. Access to the cluster with admin privileges
3. A GitHub repository with the test manifests

### Architecture

```
Primary ArgoCD (namespace-a)
├── Secondary ArgoCD (namespace-b)
│   └── App-of-Apps (argocd-e2e)
│       └── my-app (default)
└── cross-instance-app (argocd-e2e)
```

### Step 1: Create Namespaces

```bash
kubectl create namespace namespace-a
kubectl create namespace namespace-b
kubectl create namespace argocd-e2e
```

### Step 2: Deploy Primary ArgoCD

Deploy ArgoCD in namespace-a (this is your main ArgoCD instance):

```bash
# Install ArgoCD using Helm or your preferred method
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n namespace-a --create-namespace
```

### Step 3: Deploy Secondary ArgoCD

Apply the secondary ArgoCD application:

```bash
kubectl apply -f deploy-secondary-argocd.yaml
```

This will:
- Deploy a secondary ArgoCD instance in namespace-b
- Configure it with the URL `https://argocd-instance-b.example.com`
- Add the `managed-by-url` annotation

### Step 4: Deploy Cross-Instance Application

Apply the cross-instance application:

```bash
kubectl apply -f apps/cross-instance/cross-instance-app.yaml
```

### Step 5: Test the Issue

1. **Access Primary ArgoCD UI** (namespace-a)
2. **Navigate to the cross-instance-app**
3. **Click "Open application" icon**
4. **Expected Issue**: The link should point to the wrong ArgoCD instance

### Step 6: Test the Fix

To test the fix from PR #23266:

1. **Update ArgoCD to a version with the fix** (or build from the PR branch)
2. **Verify the managed-by-url annotation** is present:
   ```bash
   kubectl get application cross-instance-app -n namespace-a -o yaml | grep managed-by-url
   ```
3. **Test the deep links API**:
   ```bash
   # Get the application links
   kubectl port-forward svc/argocd-server 8080:80 -n namespace-a
   curl -H "Authorization: Bearer $(kubectl get secret -n namespace-a argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
        http://localhost:8080/api/v1/applications/cross-instance-app/links
   ```

## Expected Behavior After Fix

- The "Open application" link should point to `https://argocd-instance-b.example.com/applications/cross-instance-app`
- Deep links should use the `managed-by-url` annotation when present
- Fallback to current instance URL when no `managed-by-url` is set

## Verification Steps

1. **Check Application Annotations**:
   ```bash
   kubectl get application cross-instance-app -n namespace-a -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/managed-by-url}'
   ```

2. **Test Deep Links API**:
   ```bash
   # Should return links with managed-by-url
   kubectl exec -n namespace-a deployment/argocd-server -- argocd app links cross-instance-app
   ```

3. **Verify UI Behavior**:
   - Open application should redirect to the correct ArgoCD instance
   - No data loading issues should occur

## Cleanup

```bash
kubectl delete -f deploy-secondary-argocd.yaml
kubectl delete -f apps/cross-instance/cross-instance-app.yaml
kubectl delete namespace namespace-b
kubectl delete namespace argocd-e2e
```

## Troubleshooting

1. **Ingress Issues**: If using local testing, you may need to update the ingress hostnames
2. **Authentication**: Ensure proper RBAC is configured for cross-instance access
3. **Network**: Verify network connectivity between ArgoCD instances

## Related Files

- `deploy-secondary-argocd.yaml`: Deploys secondary ArgoCD
- `apps/cross-instance/cross-instance-app.yaml`: Test application with managed-by-url
- `apps/app-of-apps/`: App-of-Apps pattern for secondary ArgoCD
- `apps/secondary-argocd/`: Secondary ArgoCD configuration 