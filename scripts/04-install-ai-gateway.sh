#!/bin/bash

set -e

echo "=== Installing Envoy AI Gateway ==="
echo ""

INFERENCE_EXTENSION_VERSION="v1.3.1"
AI_GATEWAY_VERSION="v0.5.0"
AI_GATEWAY_NAMESPACE="envoy-ai-gateway-system"

echo "Inference Extension : $INFERENCE_EXTENSION_VERSION"
echo "AI Gateway          : $AI_GATEWAY_VERSION"
echo ""

# Step 1: InferencePool CRD
echo "[1/3] Installing InferencePool CRDs..."
kubectl apply --server-side \
  -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${INFERENCE_EXTENSION_VERSION}/manifests.yaml"

kubectl wait --for=condition=Established \
  crd/inferencepools.inference.networking.k8s.io --timeout=60s
kubectl wait --for=condition=Established \
  crd/inferenceobjectives.inference.networking.x-k8s.io --timeout=60s

# Step 2: AI Gateway CRD
echo ""
echo "[2/3] Installing AI Gateway CRDs..."
helm upgrade --install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$AI_GATEWAY_NAMESPACE" \
  --create-namespace

kubectl wait --for=condition=Established \
  crd/aigatewayroutes.aigateway.envoyproxy.io --timeout=60s
kubectl wait --for=condition=Established \
  crd/aiservicebackends.aigateway.envoyproxy.io --timeout=60s

# Step 3: AI Gateway Controller
echo ""
echo "[3/3] Installing AI Gateway Controller..."
helm upgrade --install aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$AI_GATEWAY_NAMESPACE" \
  --create-namespace

echo ""
echo "Waiting for AI Gateway Controller to be ready..."
kubectl wait --timeout=5m \
  -n "$AI_GATEWAY_NAMESPACE" deployment/ai-gateway-controller \
  --for=condition=Available

echo ""
echo "=== Status ==="
kubectl get pods -n "$AI_GATEWAY_NAMESPACE"
echo ""
kubectl get crd | grep -E "aigateway.envoyproxy.io|inference.networking.k8s.io"

echo ""
echo "✅ Envoy AI Gateway installed!"
echo ""
echo "Next step: Run ./scripts/05-deploy-all.sh"
