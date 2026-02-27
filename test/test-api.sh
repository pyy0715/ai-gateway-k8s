#!/bin/bash
set -e

echo "=== Testing vLLM + AI Gateway API ==="
echo ""

# Get Gateway IP
echo "Getting Gateway IP..."
GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    echo "Gateway IP not found. Setting up port forwarding..."
    echo "Running port-forward in background..."
    kubectl port-forward -n default service/ai-gateway 8081:80 &
    PORT_FORWARD_PID=$!
    sleep 3
    GATEWAY_IP="localhost:8081"
else
    echo "Gateway IP: $GATEWAY_IP"
fi

echo ""
echo "=============================================="
echo "=== vLLM + InferencePool 테스트 ==="
echo ""
echo "Client → Envoy → AIGatewayRoute → InferencePool → EPP → vLLM Pod"
echo ""

echo "=============================================="
echo "--- Test 1: Chat Completion (body의 model 필드만 사용) ---"
echo "Model: Qwen/Qwen3-0.6B"
echo "설명: Gateway가 body에서 model을 추출해 x-ai-eg-model 헤더 자동 주입"
echo ""
echo "Response:"
curl -s -X POST "http://${GATEWAY_IP}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello! Say hi in one word."}],
    "max_tokens": 20
  }' | jq . 2>/dev/null || cat

echo ""
echo ""
echo "=============================================="
echo "--- Test 2: Chat Completion (x-ai-eg-model 헤더 직접 지정) ---"
echo "Model: Qwen/Qwen3-0.6B"
echo "설명: 헤더를 직접 지정해도 동작함"
echo ""
echo "Response:"
curl -s -X POST "http://${GATEWAY_IP}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: Qwen/Qwen3-0.6B" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "max_tokens": 20
  }' | jq . 2>/dev/null || cat

echo ""
echo ""
echo "=============================================="
echo "--- Test 3: Models List ---"
echo "Response:"
curl -s "http://${GATEWAY_IP}/v1/models" | jq . 2>/dev/null || cat

echo ""
echo ""
echo "=============================================="
echo "--- Test 4: Direct vLLM Health Check ---"
echo "vLLM Pod 직접 호출 (포트 포워딩)"
echo ""

# Get a vLLM pod name
VLLM_POD=$(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$VLLM_POD" ]; then
    echo "Checking vLLM pod: $VLLM_POD"
    kubectl exec -it $VLLM_POD -- curl -s http://localhost:8000/health 2>/dev/null || echo "Health check failed"
else
    echo "No vLLM pod found"
fi

echo ""
echo ""
echo "=============================================="
echo "--- Status ---"
echo ""
echo "vLLM Pods:"
kubectl get pods -l app=vllm-qwen -o wide 2>/dev/null || echo "No vLLM Qwen pods found"
kubectl get pods -l app=vllm-smol -o wide 2>/dev/null || true
echo ""
echo "EPP Pods:"
kubectl get pods -l app=vllm-qwen-epp -o wide 2>/dev/null || echo "No EPP Qwen pods found"
kubectl get pods -l app=vllm-smol-epp -o wide 2>/dev/null || true
echo ""
echo "Gateway:"
kubectl get gateway 2>/dev/null || echo "No gateway found"
echo ""
echo "AIGatewayRoute:"
kubectl get aigatewayroute 2>/dev/null || echo "No aigatewayroute found"
echo ""
echo "InferencePool:"
kubectl get inferencepool 2>/dev/null || echo "No inferencepool found"

# Cleanup port forward if started
if [ ! -z "$PORT_FORWARD_PID" ]; then
    echo ""
    echo "Stopping port-forward..."
    kill $PORT_FORWARD_PID 2>/dev/null || true
fi

echo ""
echo "✅ Tests complete!"
