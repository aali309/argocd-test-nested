# GitOps Console Plugin Test

This folder contains an ApplicationSet and sample applications for testing the gitops-console-plugin functionality.

## Structure

```
apps/gitops-console-test/
├── applicationset.yaml    # ApplicationSet deployed to openshift-gitops namespace
├── app1/                  # Dev environment application
│   └── deployment.yaml
├── app2/                  # Staging environment application  
│   └── deployment.yaml
├── app3/                  # Prod environment application
│   └── deployment.yaml
└── README.md             # This file
```

## ApplicationSet Details

- **Name**: `gitops-console-test`
- **Namespace**: `openshift-gitops`
- **Generator**: List generator with 3 test applications
- **Environments**: dev, staging, prod
- **Namespaces**: gitops-test-ns-1, gitops-test-ns-2, gitops-test-ns-3

## Test Applications

Each application includes:
- Deployment with nginx container
- Service for network access
- Environment-specific resource limits
- Proper labeling for environment tracking

## Deployment

To deploy this test setup:

```bash
kubectl apply -f apps/gitops-console-test/applicationset.yaml
```

This will create:
- 1 ApplicationSet in `openshift-gitops` namespace
- 3 Applications (one for each environment)
- 3 namespaces with deployments and services

## Testing GitOps Console Plugin

This setup provides:
- Multiple applications across different environments
- Proper labeling and annotations for plugin testing
- Automated sync with self-healing enabled
- Namespace creation via sync options

Perfect for testing gitops-console-plugin functionality with real ArgoCD resources.
