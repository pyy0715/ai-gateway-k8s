#!/bin/bash
set -e

echo "=== Installing Envoy Gateway ==="
echo ""

if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed. Install: https://helm.sh/docs/intro/install/"
    exit 1
fi

ENVOY_GATEWAY_VERSION="v1.6.3"
AI_GATEWAY_VERSION="v0.5.0"
NAMESPACE="envoy-gateway-system"

echo "Envoy Gateway: $ENVOY_GATEWAY_VERSION"
echo "AI Gateway values: $AI_GATEWAY_VERSION"
echo ""

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/manifests/envoy-gateway-values.yaml" \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/examples/inference-pool/envoy-gateway-values-addon.yaml"

echo ""
kubectl wait --timeout=5m -n "$NAMESPACE" deployment/envoy-gateway --for=condition=Available

echo ""
kubectl get pods -n "$NAMESPACE"
echo ""
echo "Next: ./scripts/03-install-ai-gateway.sh"
