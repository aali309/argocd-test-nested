#!/bin/bash

# Setup script for testing cross-instance ArgoCD application linking
# This script helps reproduce the issue fixed in PR #23266

set -e

echo "🚀 Setting up ArgoCD cross-instance linking test environment..."

# Create namespaces
echo "📦 Creating namespaces..."
kubectl create namespace namespace-a --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace namespace-b --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd-e2e --dry-run=client -o yaml | kubectl apply -f -

# Check if ArgoCD is already installed in namespace-a
if ! kubectl get deployment argocd-server -n namespace-a >/dev/null 2>&1; then
    echo "📥 Installing ArgoCD in namespace-a..."
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
    helm install argocd argo/argo-cd -n namespace-a --create-namespace \
        --set server.extraArgs[0]="--insecure" \
        --set server.ingress.enabled=true \
        --set server.ingress.annotations."kubernetes\.io/ingress\.class"=nginx \
        --set server.ingress.hosts[0].host=argocd-instance-a.example.com \
        --set server.ingress.hosts[0].paths[0].path=/ \
        --set server.ingress.hosts[0].paths[0].pathType=Prefix
else
    echo "✅ ArgoCD already installed in namespace-a"
fi

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n namespace-a

# Deploy secondary ArgoCD
echo "🔧 Deploying secondary ArgoCD..."
kubectl apply -f deploy-secondary-argocd.yaml

# Deploy cross-instance application
echo "📋 Deploying cross-instance application..."
kubectl apply -f apps/cross-instance/cross-instance-app.yaml

# Wait for applications to be created
echo "⏳ Waiting for applications to be created..."
sleep 10

# Get ArgoCD admin password
echo "🔑 Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl get secret -n namespace-a argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"

# Port forward ArgoCD server
echo "🌐 Setting up port forward for ArgoCD server..."
echo "ArgoCD UI will be available at: http://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""
echo "To test the cross-instance linking:"
echo "1. Open http://localhost:8080 in your browser"
echo "2. Login with admin/$ARGOCD_PASSWORD"
echo "3. Navigate to the 'cross-instance-app' application"
echo "4. Click the 'Open application' icon"
echo "5. Verify if it redirects to the correct ArgoCD instance"
echo ""
echo "To test the API directly:"
echo "curl -H \"Authorization: Bearer $ARGOCD_PASSWORD\" http://localhost:8080/api/v1/applications/cross-instance-app/links"
echo ""
echo "Press Ctrl+C to stop the port forward"

# Start port forward
kubectl port-forward svc/argocd-server 8080:80 -n namespace-a 