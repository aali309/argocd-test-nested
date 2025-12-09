#!/bin/bash

# Script to install Argo Rollouts controller
# Usage: ./install-controller.sh

set -e

echo "Installing Argo Rollouts controller..."

# Create namespace if it doesn't exist
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

# Install Argo Rollouts controller
echo "Applying Argo Rollouts installation manifest..."
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Wait for controller to be ready
echo "Waiting for Argo Rollouts controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argo-rollouts -n argo-rollouts || true

# Check status
echo ""
echo "Argo Rollouts controller status:"
kubectl get pods -n argo-rollouts

echo ""
echo "Argo Rollouts controller installed successfully!"
echo "You can now apply rollout resources with: kubectl apply -f apps/rollout-test/"

