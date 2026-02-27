#!/bin/bash
set -e

echo "=== Cleaning Up AI Gateway Lab ==="
echo ""

read -p "This will delete all AI Gateway resources and optionally the cluster. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "1. Deleting AI Gateway resources..."
kubectl delete -f "$PROJECT_DIR/k8s/ai-gateway/" --ignore-not-found=true

echo ""
echo "2. Deleting InferencePool resources..."
kubectl delete -f "$PROJECT_DIR/k8s/inference-pool/" --ignore-not-found=true

echo ""
echo "3. Deleting backend..."
kubectl delete -f "$PROJECT_DIR/k8s/backend/" --ignore-not-found=true

echo ""
echo "4. Deleting AI Gateway Controller..."
helm uninstall aieg -n envoy-ai-gateway-system --ignore-not-found=true
helm uninstall aieg-crd -n envoy-ai-gateway-system --ignore-not-found=true

echo ""
echo "5. Deleting Envoy Gateway..."
helm uninstall eg -n envoy-gateway-system --ignore-not-found=true

echo ""
read -p "Do you also want to delete the kind cluster? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting kind cluster 'ai-gateway-lab'..."
    kind delete cluster --name ai-gateway-lab
fi

echo ""
echo "✅ Cleanup complete!"
