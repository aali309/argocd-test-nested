#!/bin/bash

# Script to check if an application is a child application
# Usage: ./check-child-app.sh <app-name> <namespace>

APP_NAME=${1:-""}
NAMESPACE=${2:-"argocd-e2e"}

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name> [namespace]"
    echo "Example: $0 web-app argocd-e2e"
    exit 1
fi

echo "🔍 Checking if '$APP_NAME' is a child application..."
echo ""

# Check if the application exists
if ! kubectl get application "$APP_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "❌ Application '$APP_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

echo "📋 Application Details:"
kubectl get application "$APP_NAME" -n "$NAMESPACE" -o wide
echo ""

# Check for child-app component label
CHILD_COMPONENT=$(kubectl get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/component}' 2>/dev/null)
if [ "$CHILD_COMPONENT" = "child-app" ]; then
    echo "✅ IS A CHILD APPLICATION (has child-app component label)"
    IS_CHILD=true
else
    echo "❓ Component label: '$CHILD_COMPONENT' (not child-app)"
    IS_CHILD=false
fi

# Check for part-of label
PART_OF=$(kubectl get application "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null)
if [ -n "$PART_OF" ]; then
    echo "🏷️  Part of group: '$PART_OF'"
    if [ "$IS_CHILD" = true ]; then
        echo "✅ Confirmed child app of group: '$PART_OF'"
    fi
else
    echo "❓ No part-of label found"
fi

# Find potential parent applications
echo ""
echo "🔍 Searching for parent applications..."
PARENT_APPS=$(kubectl get applications -n "$NAMESPACE" -o name | grep -v "$APP_NAME")
PARENT_FOUND=false

for parent in $PARENT_APPS; do
    parent_name=$(echo "$parent" | cut -d'/' -f2)
    # Check if this parent has our app as a resource
    if kubectl describe "$parent" -n "$NAMESPACE" 2>/dev/null | grep -q "Name: $APP_NAME"; then
        echo "✅ Found parent application: '$parent_name'"
        echo "   Resource details:"
        kubectl describe "$parent" -n "$NAMESPACE" 2>/dev/null | grep -A5 -B5 "Name: $APP_NAME"
        PARENT_FOUND=true
    fi
done

if [ "$PARENT_FOUND" = false ]; then
    echo "❌ No parent application found that manages '$APP_NAME'"
fi

# Summary
echo ""
echo "📊 SUMMARY:"
if [ "$IS_CHILD" = true ] && [ "$PARENT_FOUND" = true ]; then
    echo "✅ '$APP_NAME' IS DEFINITELY A CHILD APPLICATION"
elif [ "$IS_CHILD" = true ] || [ "$PARENT_FOUND" = true ]; then
    echo "⚠️  '$APP_NAME' APPEARS TO BE A CHILD APPLICATION (partial indicators)"
else
    echo "❌ '$APP_NAME' IS NOT A CHILD APPLICATION"
fi
