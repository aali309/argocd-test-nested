#!/bin/bash

# Parent-Child App Relationship Test Setup Script

set -e

echo "🚀 Setting up Parent-Child App Relationship Test..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Kubernetes cluster connection verified"

# Apply RBAC configuration
echo "📋 Applying RBAC configuration..."
kubectl apply -f rbac.yaml

# Wait a moment for RBAC to be ready
sleep 2

# Apply Parent Application
echo "🎯 Applying Parent Application..."
kubectl apply -f parent-app.yaml

echo "⏳ Waiting for parent application to create child applications..."
sleep 10

# Check parent application status
echo "📊 Parent Application Status:"
kubectl get application parent-child-test -n argocd-e2e -o wide

# Check created applications
echo "📱 All Applications (Parent + Children):"
kubectl get applications -n argocd-e2e -l app.kubernetes.io/part-of=parent-child-testing

echo "👶 Child Applications:"
kubectl get applications -n argocd-e2e -l app.kubernetes.io/component=child-app

# Show namespaces that will be created
echo "🏷️  Namespaces that will be created:"
echo "  - web-app-ns"
echo "  - api-service-ns" 
echo "  - config-service-ns"
echo "  - web-app-prod-ns"
echo "  - api-service-prod-ns"

echo ""
echo "🎉 Parent-Child App Relationship Test setup complete!"
echo ""
echo "To monitor the deployment:"
echo "  kubectl get applications -n argocd-e2e -w"
echo ""
echo "To check resources in child namespaces:"
echo "  kubectl get all -n web-app-ns"
echo "  kubectl get all -n api-service-ns"
echo "  kubectl get all -n config-service-ns"
echo ""
echo "To cleanup:"
echo "  kubectl delete application parent-child-test -n argocd-e2e"
echo "  kubectl delete -f rbac.yaml"
