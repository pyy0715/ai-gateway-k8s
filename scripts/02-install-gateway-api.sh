#!/bin/bash
set -e

echo "=== Installing Gateway API CRDs ==="
echo ""

# AI Gateway v0.5.x requires Gateway API v1.4.x
# https://aigateway.envoyproxy.io/docs/compatibility
GATEWAY_API_VERSION="v1.4.1"

echo "Installing Gateway API CRDs (version: $GATEWAY_API_VERSION)..."
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo ""
echo "Waiting for CRDs to be established..."
kubectl wait --for condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=60s
kubectl wait --for condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s
kubectl wait --for condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s

echo ""
echo "=== Installed Gateway API CRDs ==="
kubectl get crd | grep gateway.networking.k8s.io

echo ""
echo "✅ Gateway API CRDs installed!"
echo ""
echo "Next step: Run ./scripts/03-install-envoy-gateway.sh"
