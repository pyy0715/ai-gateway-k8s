#!/bin/bash
#
# load-test.sh - Load testing script for EPP smart routing
#
# This script sends concurrent requests to the AI Gateway to test
# the EPP (Endpoint Picker) smart routing capabilities, including
# KV-cache utilization and queue-based scheduling.
#
# Usage:
#   ./load-test.sh [OPTIONS]
#
# Options:
#   --host HOST              Gateway host (default: localhost)
#   --port PORT              Gateway port (default: 8081)
#   --model MODEL            Model name (default: google/gemma-3-1b-it)
#   --requests NUM           Total number of requests (default: 10)
#   --concurrent NUM         Concurrent requests (default: 1)
#   --prompt-length LENGTH   Prompt length: short|medium|long (default: medium)
#   --max-tokens NUM         Max tokens in response (default: 50)
#   --help                   Show this help message
#
# Examples:
#   # Basic load test with 100 requests, 10 concurrent
#   ./load-test.sh --requests 100 --concurrent 10
#
#   # Test with short prompts for quick KV-cache hits
#   ./load-test.sh --prompt-length short --requests 50 --concurrent 5
#
#   # Stress test with long prompts and high concurrency
#   ./load-test.sh --prompt-length long --requests 200 --concurrent 20
#
#   # Test against remote gateway
#   ./load-test.sh --host 192.168.1.100 --port 8081 --requests 50
#

set -e

# Default values
HOST="localhost"
PORT="8081"
MODEL="Qwen/Qwen3-0.6B"
REQUESTS=10
CONCURRENT=1
PROMPT_LENGTH="medium"
MAX_TOKENS=50
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --requests)
            REQUESTS="$2"
            shift 2
            ;;
        --concurrent)
            CONCURRENT="$2"
            shift 2
            ;;
        --prompt-length)
            PROMPT_LENGTH="$2"
            shift 2
            ;;
        --max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | grep -v '#!' | sed 's/^# //; s/^#//' | sed '1d; /^$/d'
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
    esac
done

# Validate prompt length
case $PROMPT_LENGTH in
    short|medium|long)
        ;;
    *)
        echo -e "${RED}Error: --prompt-length must be one of: short, medium, long${NC}"
        exit 1
        ;;
esac

# Validate numeric inputs
if ! [[ "$REQUESTS" =~ ^[0-9]+$ ]] || [ "$REQUESTS" -lt 1 ]; then
    echo -e "${RED}Error: --requests must be a positive integer${NC}"
    exit 1
fi

if ! [[ "$CONCURRENT" =~ ^[0-9]+$ ]] || [ "$CONCURRENT" -lt 1 ]; then
    echo -e "${RED}Error: --concurrent must be a positive integer${NC}"
    exit 1
fi

if [ "$CONCURRENT" -gt "$REQUESTS" ]; then
    echo -e "${YELLOW}Warning: --concurrent exceeds --requests, setting concurrent to $REQUESTS${NC}"
    CONCURRENT=$REQUESTS
fi

# Generate prompt based on length
generate_prompt() {
    case $PROMPT_LENGTH in
        short)
            echo "Hello"
            ;;
        medium)
            cat <<'EOF'
Artificial intelligence (AI) is a branch of computer science focused on creating systems capable of performing tasks that typically require human intelligence. These tasks include learning, reasoning, problem-solving, perception, and language understanding. Machine learning, a subset of AI, enables systems to improve their performance through experience and data. Deep learning, which uses neural networks with multiple layers, has driven many recent breakthroughs in areas like image recognition, natural language processing, and game playing. As AI technology continues to advance, it raises important questions about ethics, privacy, and the future of work in an increasingly automated world.
EOF
            ;;
        long)
            cat <<'EOF'
# Technical Architecture: Kubernetes Gateway API Inference Extension

## Overview

The Kubernetes Gateway API Inference Extension represents a paradigm shift in how LLM inference workloads are orchestrated within Kubernetes environments. By extending the Gateway API with inference-specific primitives, this architecture enables sophisticated routing, load balancing, and resource optimization strategies specifically tailored for the unique characteristics of large language model workloads.

## Core Components

### 1. Gateway API Integration

The extension builds upon the Kubernetes Gateway API, introducing custom resource definitions (CRDs) that model inference-specific concepts. The primary resources include:

- **InferencePool**: A logical grouping of inference endpoints (e.g., vLLM pods) that can be targeted for model inference requests.
- **InferenceObjective**: Defines optimization goals such as minimizing latency, maximizing throughput, or prioritizing cache affinity.

### 2. Endpoint Picker (EPP)

The EPP serves as the intelligent decision engine within the architecture. It implements advanced scheduling algorithms that consider:

- **KV-Cache State**: The EPP tracks the KV-cache contents across all inference pods, routing requests to pods with existing cache entries for the prompt prefix. This dramatically reduces computation for repeated prompts or multi-turn conversations.
- **Queue Depth**: Real-time monitoring of each pod's request queue helps prevent overload and ensures predictable latency.
- **Resource Availability**: CPU, memory, and GPU utilization metrics inform placement decisions.

### 3. Envoy AI Gateway

The Envoy AI Gateway acts as the data plane proxy, terminating client connections and applying routing rules based on model identifiers. It extracts the model name from either the request body or the `x-ai-eg-model` header, then forwards requests to the appropriate InferencePool.

## Request Flow

1. **Client Request**: A client sends an OpenAI-compatible chat completion request to the Gateway.
2. **Model Routing**: The Envoy AI Gateway extracts the model identifier and matches it against AIGatewayRoute rules.
3. **Pool Selection**: The request is forwarded to the InferencePool responsible for the requested model.
4. **Smart Scheduling**: The EPP evaluates all available endpoints within the pool, selecting the optimal target based on cache affinity, current load, and resource availability.
5. **Inference Execution**: The selected vLLM pod processes the request, leveraging cached KV-states when available.
6. **Response**: The inference result flows back through the gateway to the client.

## Performance Optimization Strategies

### Cache Affinity Routing

By analyzing request prefixes and maintaining a global view of cache states, the EPP can route requests with high similarity to the same pod. This maximizes KV-cache reuse and reduces computational overhead, particularly for scenarios like:

- Batch processing of similar prompts
- Multi-turn conversations with context retention
- Few-shot prompting with shared examples

### Dynamic Load Balancing

Traditional round-robin load balancing is suboptimal for LLM inference due to varying request complexity and cache states. The EPP implements weighted load balancing that considers:

- Expected processing time based on prompt length
- Current queue depth and estimated wait time
- Historical performance metrics for each pod

### Adaptive Scaling

The architecture supports both horizontal and vertical scaling strategies. The EPP can signal the Kubernetes controller to spin up additional inference pods during demand spikes, scaling down during idle periods to optimize resource utilization.

## Monitoring and Observability

Comprehensive metrics are exposed at each layer:

- **Gateway Level**: Request rate, error rate, latency percentiles per model
- **Pool Level**: Cache hit rates, average queue depth, endpoint health
- **Pod Level**: GPU utilization, memory consumption, KV-cache size

These metrics feed back into the scheduling decisions, enabling continuous optimization based on real-time workload patterns.

## Security Considerations

The architecture implements several security measures:

- **Authentication**: Token-based authentication at the gateway layer
- **Authorization**: RBAC policies controlling access to specific models
- **Network Isolation**: Network policies restrict pod-to-pod communication
- **Audit Logging**: All inference requests are logged for compliance and debugging

## Conclusion

The Kubernetes Gateway API Inference Extension represents a significant advancement in LLM orchestration, bringing cloud-native principles to AI inference workloads. By combining intelligent routing with resource-aware scheduling, it enables organizations to deploy scalable, efficient, and cost-effective LLM serving infrastructure.
EOF
            ;;
    esac
}

# URL construction
BASE_URL="http://${HOST}:${PORT}"
API_URL="${BASE_URL}/v1/chat/completions"

# Temporary directory for results
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Statistics
SUCCESS_COUNT=0
FAILURE_COUNT=0
TOTAL_TIME=0
MIN_TIME=999999
MAX_TIME=0

# Print test configuration
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           EPP Smart Routing Load Test                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Host:            ${GREEN}${HOST}${NC}"
echo -e "  Port:            ${GREEN}${PORT}${NC}"
echo -e "  Model:           ${GREEN}${MODEL}${NC}"
echo -e "  Total Requests:  ${GREEN}${REQUESTS}${NC}"
echo -e "  Concurrent:      ${GREEN}${CONCURRENT}${NC}"
echo -e "  Prompt Length:   ${GREEN}${PROMPT_LENGTH}${NC}"
echo -e "  Max Tokens:      ${GREEN}${MAX_TOKENS}${NC}"
echo ""

# Generate the prompt
PROMPT=$(generate_prompt)
PROMPT_WORD_COUNT=$(echo "$PROMPT" | wc -w | tr -d ' ')
echo -e "${YELLOW}Prompt Info:${NC} ${GREEN}${PROMPT_WORD_COUNT} words${NC}"

# Show prompt preview
if [ "$VERBOSE" = true ]; then
    echo ""
    echo -e "${YELLOW}Full Prompt:${NC}"
    echo "$PROMPT"
    echo ""
else
    PROMPT_PREVIEW=$(echo "$PROMPT" | head -c 100)
    echo -e "Preview: ${GREEN}${PROMPT_PREVIEW}...${NC}"
fi
echo ""
echo -e "${YELLOW}Starting load test...${NC}"
echo ""

# Start time
START_TIME=$(date +%s)

# Function to send a single request
send_request() {
    local req_id=$1
    local req_start=$(date +%s%N)  # Nanoseconds
    local output_file="$TMPDIR/req_${req_id}.json"
    local time_file="$TMPDIR/req_${req_id}.time"

    # Create JSON payload
    local payload=$(cat <<EOF
{
    "model": "$MODEL",
    "messages": [{"role": "user", "content": $(echo "$PROMPT" | jq -Rs .)}],
    "max_tokens": $MAX_TOKENS
}
EOF
)

    # Send request and capture response
    local http_code=$(curl -s -o "$output_file" -w "%{http_code}" \
        -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "x-ai-eg-model: $MODEL" \
        -d "$payload" \
        --connect-timeout 30 \
        --max-time 120)

    local req_end=$(date +%s%N)
    local duration_ns=$((req_end - req_start))
    local duration_ms=$((duration_ns / 1000000))

    # Record time
    echo "$duration_ms" > "$time_file"

    # Check for success
    if [ "$http_code" = "200" ]; then
        # Validate JSON response
        if jq -e '.choices[0].message.content' "$output_file" >/dev/null 2>&1; then
            echo "success|$req_id|$duration_ms"
            return 0
        else
            echo "failure|$req_id|$duration_ms|invalid_json"
            return 1
        fi
    else
        echo "failure|$req_id|$duration_ms|http_$http_code"
        return 1
    fi
}

export -f send_request
export API_URL MODEL PROMPT MAX_TOKENS TMPDIR
export NC RED GREEN YELLOW

# Send requests concurrently using xargs
for ((batch=0; batch<REQUESTS; batch+=CONCURRENT)); do
    batch_size=$((CONCURRENT))
    if [ $((batch + batch_size)) -gt "$REQUESTS" ]; then
        batch_size=$((REQUESTS - batch))
    fi

    # Generate request IDs for this batch
    req_ids=()
    for ((i=0; i<batch_size; i++)); do
        req_ids+=($((batch + i + 1)))
    done

    # Send requests in parallel
    printf "%s\n" "${req_ids[@]}" | xargs -P "$batch_size" -I {} bash -c 'send_request "$@"' _ "{}" > "$TMPDIR/batch_${batch}.results"
done

# End time
END_TIME=$(date +%s)
TOTAL_ELAPSED=$((END_TIME - START_TIME))

# Process results
for result_file in "$TMPDIR"/batch_*.results; do
    while IFS='|' read -r status req_id duration detail; do
        if [ "$status" = "success" ]; then
            ((SUCCESS_COUNT++))
            TOTAL_TIME=$((TOTAL_TIME + duration))
            if [ "$duration" -lt "$MIN_TIME" ]; then
                MIN_TIME=$duration
            fi
            if [ "$duration" -gt "$MAX_TIME" ]; then
                MAX_TIME=$duration
            fi
        else
            ((FAILURE_COUNT++))
            if [ "$VERBOSE" = true ]; then
                echo -e "${RED}Request $req_id failed: $detail${NC}"
            fi
        fi
    done < "$result_file"
done

# Calculate statistics
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    AVG_TIME=$((TOTAL_TIME / SUCCESS_COUNT))
else
    AVG_TIME=0
    MIN_TIME=0
fi

REQUESTS_PER_SEC=0
if [ "$TOTAL_ELAPSED" -gt 0 ]; then
    REQUESTS_PER_SEC=$(echo "scale=2; $REQUESTS / $TOTAL_ELAPSED" | bc)
fi

# Print results
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Test Results                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Request Summary:${NC}"
echo -e "  Total Requests:     ${GREEN}${REQUESTS}${NC}"
echo -e "  Successful:         ${GREEN}${SUCCESS_COUNT}${NC}"
echo -e "  Failed:             ${RED}${FAILURE_COUNT}${NC}"
echo -e "  Success Rate:       ${GREEN}$(echo "scale=1; $SUCCESS_COUNT * 100 / $REQUESTS" | bc)%${NC}"
echo ""
echo -e "${YELLOW}Response Times (ms):${NC}"
echo -e "  Average:            ${GREEN}${AVG_TIME}${NC}"
echo -e "  Min:                ${GREEN}${MIN_TIME}${NC}"
echo -e "  Max:                ${YELLOW}${MAX_TIME}${NC}"
echo ""
echo -e "${YELLOW}Throughput:${NC}"
echo -e "  Total Time:         ${GREEN}${TOTAL_ELAPSED}s${NC}"
echo -e "  Requests/sec:       ${GREEN}${REQUESTS_PER_SEC}${NC}"
echo ""

# Show sample response if successful
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    sample_response=$(ls "$TMPDIR"/req_*.json 2>/dev/null | head -1)
    if [ -n "$sample_response" ]; then
        echo -e "${YELLOW}Sample Response:${NC}"
        jq -r '.choices[0].message.content' "$sample_response" 2>/dev/null | head -c 200
        echo ""
        echo -e "${GREEN}...${NC}"
        echo ""
    fi
fi

# EPP Insights
echo -e "${YELLOW}EPP Smart Routing Insights:${NC}"
echo -e "  • Lower response times may indicate KV-cache hits"
echo -e "  • Consistent times suggest balanced pod utilization"
echo -e "  • High variance may indicate cache misses or queue delays"
echo ""

if [ "$FAILURE_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠️  Some requests failed. Check gateway and pod logs:${NC}"
    echo "  kubectl get pods -l app=vllm"
    echo "  kubectl logs -l app=vllm-epp --tail=50"
    echo ""
fi

if [ "$SUCCESS_COUNT" -eq "$REQUESTS" ]; then
    echo -e "${GREEN}✅ All requests completed successfully!${NC}"
    exit 0
else
    exit 1
fi
