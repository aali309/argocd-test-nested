#!/bin/bash

echo "🚀 Progressive Sync Test Setup"
echo "=============================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    echo "Please ensure your cluster is running and kubectl is configured"
    exit 1
fi

echo "✅ Kubernetes cluster connection verified"

# Apply the ApplicationSets
echo ""
echo "📦 Applying ApplicationSet manifests..."

kubectl apply -f applicationset-allatonce-default.yaml
kubectl apply -f applicationset-explicit-allatonce.yaml
kubectl apply -f applicationset-rollingsync.yaml

echo ""
echo "✅ ApplicationSets applied successfully!"
echo ""
echo "🔍 Next steps:"
echo "1. Access ArgoCD UI at: http://localhost:4000"
echo "2. Navigate to namespace: argocd-e2e"
echo "3. Look for ApplicationSet resources:"
echo "   - test-appset-allatonce"
echo "   - test-appset-explicit-allatonce"
echo "   - test-appset-rollingsync"
echo ""
echo "4. Observe the generated Applications and their sync behavior:"
echo "   - AllAtOnce strategies should sync simultaneously"
echo "   - RollingSync should sync in sequence"
echo ""
echo "🧹 To clean up when done:"
echo "   kubectl delete -f ."
