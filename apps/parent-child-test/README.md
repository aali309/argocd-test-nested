# Parent-Child App Relationship Test

This folder contains a test setup for ArgoCD parent-child application relationships where you can see the hierarchical structure in the ArgoCD UI resource tree.

## Structure

```
parent-child-test/
├── parent-app.yaml             # Parent Application that manages child apps
├── child-apps/                 # Child applications managed by parent
│   ├── web-app.yaml           # Child app 1: Web application
│   ├── api-service.yaml       # Child app 2: API service
│   └── config-service.yaml    # Child app 3: Configuration service
├── rbac.yaml                   # RBAC configuration for the test
├── web-app/                    # Resources for web app
│   ├── deployment.yaml         # Nginx deployment
│   └── service.yaml           # ClusterIP service
├── api-service/                # Resources for API service
│   ├── statefulset.yaml       # Node.js StatefulSet
│   └── service.yaml           # Headless service
└── config-service/             # Resources for config service
    ├── configmap.yaml         # Configuration data
    └── deployment.yaml        # Nginx deployment with config
```

## How it Works

1. **Parent Application**: The `parent-app.yaml` is a single Application that points to the `child-apps/` directory containing child application definitions.

2. **Child Applications**: The parent application manages three child applications, each defined in the `child-apps/` directory:
   - `web-app`: Nginx deployment with service in `web-app-ns` namespace
   - `api-service`: Node.js StatefulSet with persistent storage in `api-service-ns` namespace  
   - `config-service`: Nginx deployment with ConfigMap in `config-service-ns` namespace

3. **UI Resource Tree**: In the ArgoCD UI, you'll see:
   - **Parent App** (`parent-child-test`) at the top level
   - **Child Apps** (`web-app`, `api-service`, `config-service`) as resources under the parent
   - **Kubernetes Resources** (Deployments, Services, ConfigMaps) under each child app

## Resources Created

### Web App
- **Deployment**: 2 replicas of Nginx with health checks
- **Service**: ClusterIP service on port 80
- **Namespace**: `web-app-ns` (dev) / `web-app-prod-ns` (prod)

### API Service
- **StatefulSet**: Single replica Node.js application with persistent storage
- **Service**: Headless service for StatefulSet
- **Volume**: 1Gi persistent volume claim
- **Namespace**: `api-service-ns` (dev) / `api-service-prod-ns` (prod)

### Config Service
- **ConfigMap**: Application configuration and Nginx config
- **Deployment**: Nginx with mounted configuration
- **Namespace**: `config-service-ns` (dev) / `config-service-prod-ns` (prod)

## Deployment

1. Apply the RBAC configuration:
   ```bash
   kubectl apply -f rbac.yaml
   ```

2. Apply the Parent Application:
   ```bash
   kubectl apply -f parent-app.yaml
   ```

3. Verify the parent application creates child applications:
   ```bash
   kubectl get applications -n argocd-e2e
   kubectl get applications -n argocd-e2e -l app.kubernetes.io/part-of=parent-child-testing
   ```

4. Check the created resources:
   ```bash
   kubectl get all -n web-app-ns
   kubectl get all -n api-service-ns
   kubectl get all -n config-service-ns
   ```

## Testing

This setup is perfect for testing:
- ApplicationSet parent-child relationships
- Multi-environment deployments
- Different resource types (Deployment, StatefulSet, ConfigMap)
- Namespace creation and management
- Automated sync policies
- Resource labeling and organization

## Cleanup

To remove all resources:
```bash
kubectl delete application parent-child-test -n argocd-e2e
kubectl delete -f rbac.yaml
```
