#!/bin/bash
set -e

echo "=== Installing Envoy Gateway with AI Gateway Support ==="
echo ""

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed. Please install helm first."
    exit 1
fi

ENVOY_GATEWAY_VERSION="v0.0.0-latest"
NAMESPACE="envoy-gateway-system"

echo "Installing Envoy Gateway (version: $ENVOY_GATEWAY_VERSION)..."
echo "This includes AI Gateway configuration and InferencePool support."
echo ""

# Install Envoy Gateway with AI Gateway values
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/manifests/envoy-gateway-values.yaml \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/examples/inference-pool/envoy-gateway-values-addon.yaml

echo ""
echo "Waiting for Envoy Gateway deployment to be ready..."
kubectl wait --timeout=5m -n "$NAMESPACE" deployment/envoy-gateway --for=condition=Available

echo ""
echo "=== Envoy Gateway Status ==="
kubectl get pods -n "$NAMESPACE"

echo ""
echo "✅ Envoy Gateway installed with AI Gateway support!"
echo ""
echo "Next step: Run ./scripts/04-install-ai-gateway.sh"
