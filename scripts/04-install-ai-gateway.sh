#!/bin/bash
set -e

echo "=== Installing Envoy AI Gateway Controller ==="
echo ""

AI_GATEWAY_VERSION="v0.0.0-latest"
NAMESPACE="envoy-ai-gateway-system"

echo "Installing AI Gateway CRDs (version: $AI_GATEWAY_VERSION)..."
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace

echo ""
echo "Waiting for CRDs to be established..."
sleep 5

echo ""
echo "Installing AI Gateway Controller..."
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace

echo ""
echo "Waiting for AI Gateway Controller to be ready..."
kubectl wait --timeout=5m -n "$NAMESPACE" deployment/ai-gateway-controller --for=condition=Available

echo ""
echo "=== AI Gateway Status ==="
kubectl get pods -n "$NAMESPACE"

echo ""
echo "=== Installed AI Gateway CRDs ==="
kubectl get crd | grep aigateway.envoyproxy.io

echo ""
echo "✅ Envoy AI Gateway installed!"
echo ""
echo "Next step: Run ./scripts/05-deploy-all.sh"
