#!/bin/bash
set -e

echo "=== API Connectivity Test ==="
echo ""

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    echo "Gateway IP not found. Setting up port-forward..."
    kubectl port-forward svc/envoy-default-ai-gateway -n envoy-gateway-system 8080:80 &>/dev/null &
    PF_PID=$!
    sleep 3
    GATEWAY_IP="localhost:8080"
    CLEANUP=true
fi

BASE_URL="http://${GATEWAY_IP}"
echo "Gateway: $BASE_URL"
echo ""

pass=0
fail=0

# Test 1: Models List
echo "--- Test 1: Models List ---"
MODELS=$(curl -sf "${BASE_URL}/v1/models" 2>/dev/null || echo "{}")
MODEL_COUNT=$(echo "$MODELS" | jq '.data | length' 2>/dev/null || echo "0")

if [ "$MODEL_COUNT" -gt 0 ]; then
    echo "✓ Found $MODEL_COUNT models:"
    echo "$MODELS" | jq -r '.data[].id' 2>/dev/null
    ((pass++))
else
    echo "✗ No models found"
    ((fail++))
fi
echo ""

# Test 2: Chat Completion (Qwen)
echo "--- Test 2: Chat Completion (Qwen) ---"
RESPONSE=$(curl -sf -X POST "${BASE_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "Qwen/Qwen3-0.6B",
        "messages": [{"role": "user", "content": "Say hello in one word"}],
        "max_tokens": 10
    }' 2>/dev/null || echo "{}")

CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
    echo "✓ Response: $CONTENT"
    ((pass++))
else
    echo "✗ No response"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    ((fail++))
fi
echo ""

# Test 3: Model Routing (header-based)
echo "--- Test 3: Model Routing (header) ---"
RESPONSE=$(curl -sf -X POST "${BASE_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "x-ai-eg-model: Qwen/Qwen3-0.6B" \
    -d '{
        "model": "Qwen/Qwen3-0.6B",
        "messages": [{"role": "user", "content": "1+1=?"}],
        "max_tokens": 5
    }' 2>/dev/null || echo "{}")

MODEL=$(echo "$RESPONSE" | jq -r '.model' 2>/dev/null || echo "")
if [ "$MODEL" = "Qwen/Qwen3-0.6B" ]; then
    echo "✓ Model routing correct: $MODEL"
    ((pass++))
else
    echo "✗ Model routing failed"
    ((fail++))
fi
echo ""

# Summary
echo "=== Summary ==="
echo "Passed: $pass, Failed: $fail"
echo ""

# Cleanup
if [ "$CLEANUP" = true ] && [ -n "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
fi

if [ "$fail" -eq 0 ]; then
    echo "✓ All tests passed"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
