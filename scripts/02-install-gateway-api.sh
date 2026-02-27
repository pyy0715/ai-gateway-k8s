#!/bin/bash
set -e

echo "=== Installing Gateway API CRDs ==="
echo ""

# Gateway API v1.2.0 standard CRDs
GATEWAY_API_VERSION="v1.2.0"

echo "Installing Gateway API CRDs (version: $GATEWAY_API_VERSION)..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

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
