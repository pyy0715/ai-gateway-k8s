#!/bin/bash
set -e

echo "=== Installing AI Gateway ==="
echo ""

INFERENCE_EXTENSION_VERSION="v1.3.1"
AI_GATEWAY_VERSION="v0.5.0"
NAMESPACE="envoy-ai-gateway-system"

echo "Inference Extension: $INFERENCE_EXTENSION_VERSION"
echo "AI Gateway: $AI_GATEWAY_VERSION"
echo ""

echo "[1/3] InferencePool CRDs..."
kubectl apply --server-side \
  -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${INFERENCE_EXTENSION_VERSION}/manifests.yaml"
kubectl wait --for=condition=Established crd/inferencepools.inference.networking.k8s.io --timeout=60s
kubectl wait --for=condition=Established crd/inferenceobjectives.inference.networking.x-k8s.io --timeout=60s

echo ""
echo "[2/3] AI Gateway CRDs..."
helm upgrade --install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace
kubectl wait --for=condition=Established crd/aigatewayroutes.aigateway.envoyproxy.io --timeout=60s
kubectl wait --for=condition=Established crd/aiservicebackends.aigateway.envoyproxy.io --timeout=60s

echo ""
echo "[3/3] AI Gateway Controller..."
helm upgrade --install aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace

kubectl wait --timeout=5m -n "$NAMESPACE" deployment/ai-gateway-controller --for=condition=Available

echo ""
kubectl get pods -n "$NAMESPACE"
echo ""
echo "Next: ./scripts/04-deploy-all.sh"
