#!/bin/bash
set -e

# Default values
REQUESTS=${1:-20}
CONCURRENT=${2:-5}
PROMPT=${3:-"Write a short greeting"}

echo "=== Load Test ==="
echo "Requests: $REQUESTS, Concurrent: $CONCURRENT"
echo ""

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    echo "Error: Gateway IP not found"
    echo "Run: kubectl get gateway ai-gateway"
    exit 1
fi

BASE_URL="http://${GATEWAY_IP}"
echo "Gateway: $BASE_URL"
echo ""

# Get Pod list before test
echo "--- Pods Before Test ---"
PODS=$(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}')
echo "Backend Pods: $PODS"
POD_COUNT=$(echo $PODS | wc -w | tr -d ' ')
echo "Pod Count: $POD_COUNT"
echo ""

# Check initial request distribution
echo "--- Initial Request Distribution ---"
for pod in $(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}'); do
    COUNT=$(kubectl exec $pod -- curl -s localhost:8000/metrics 2>/dev/null | grep "^vllm:num_requests_running" | awk '{print $2}' || echo "0")
    echo "$pod: $COUNT running"
done
echo ""

# Run load test
echo "--- Running Load Test ---"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

START=$(date +%s)

for ((i=1; i<=REQUESTS; i++)); do
    (
        curl -sf -o "$TMPDIR/resp_$i.json" -w "%{http_code}|%{time_total}" \
            -X POST "${BASE_URL}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"Qwen/Qwen3-0.6B\", \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}], \"max_tokens\": 20}" \
            --max-time 30 > "$TMPDIR/meta_$i.txt" 2>/dev/null || echo "000|0" > "$TMPDIR/meta_$i.txt"
    ) &

    if (( i % CONCURRENT == 0 )); then
        wait
        echo -n "."
    fi
done
wait

END=$(date +%s)
ELAPSED=$((END - START))

echo ""
echo ""

# Analyze results
SUCCESS=0
FAIL=0
TOTAL_TIME=0

for ((i=1; i<=REQUESTS; i++)); do
    META=$(cat "$TMPDIR/meta_$i.txt" 2>/dev/null || echo "000|0")
    CODE=$(echo "$META" | cut -d'|' -f1)
    TIME=$(echo "$META" | cut -d'|' -f2)

    if [ "$CODE" = "200" ]; then
        ((SUCCESS++))
        TOTAL_TIME=$(echo "$TOTAL_TIME + $TIME" | bc 2>/dev/null || echo "$TOTAL_TIME")
    else
        ((FAIL++))
    fi
done

# Results
echo "--- Results ---"
echo "Total:     $REQUESTS"
echo "Success:   $SUCCESS"
echo "Failed:    $FAIL"
echo "Rate:      $(echo "scale=1; $SUCCESS * 100 / $REQUESTS" | bc)%"
echo ""

if [ "$SUCCESS" -gt 0 ]; then
    AVG_TIME=$(echo "scale=3; $TOTAL_TIME / $SUCCESS" | bc)
    RPS=$(echo "scale=2; $SUCCESS / $ELAPSED" | bc 2>/dev/null || echo "0")
    echo "Avg Time:  ${AVG_TIME}s"
    echo "Total:     ${ELAPSED}s"
    echo "RPS:       $RPS"
fi
echo ""

# Check request distribution after test
echo "--- Request Distribution After Test ---"
CURRENT_PODS=$(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}')
for pod in $CURRENT_PODS; do
    RUNNING=$(kubectl exec $pod -- curl -s localhost:8000/metrics 2>/dev/null | grep "^vllm:num_requests_running" | awk '{print $2}' || echo "0")
    WAITING=$(kubectl exec $pod -- curl -s localhost:8000/metrics 2>/dev/null | grep "^vllm:num_requests_waiting" | awk '{print $2}' || echo "0")
    echo "$pod: running=$RUNNING, waiting=$WAITING"
done
echo ""

# EPP Insights
echo "--- EPP Routing Insights ---"
echo "• EPP should distribute requests based on:"
echo "  - KV-cache utilization"
echo "  - Queue depth"
echo "  - Prefix cache hits"
echo ""

if [ "$POD_COUNT" -gt 1 ]; then
    echo "✓ Multiple pods available for load balancing"
else
    echo "! Only 1 pod - cannot verify EPP distribution"
fi
echo ""

# Show sample response
if [ "$SUCCESS" -gt 0 ]; then
    echo "--- Sample Response ---"
    SAMPLE=$(ls "$TMPDIR"/resp_*.json 2>/dev/null | head -1)
    if [ -f "$SAMPLE" ]; then
        cat "$SAMPLE" | jq -r '.choices[0].message.content' 2>/dev/null | head -c 100
        echo "..."
    fi
fi
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "✓ Load test completed successfully"
    exit 0
else
    echo "! Some requests failed"
    exit 1
fi
