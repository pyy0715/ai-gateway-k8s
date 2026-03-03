#!/bin/bash
# Test script for mock vLLM EPP routing scenarios
# Usage: ./test/test-mock-scenarios.sh <scenario>
# Scenarios: latency, kvcache, queue, build, clean

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/k8s/mock-vllm"
NAMESPACE="default"
CLUSTER_NAME="${KIND_CLUSTER_NAME:-ai-gateway-lab}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

get_scenario_file() {
    case "$1" in
        latency) echo "scenario1-latency.yaml" ;;
        kvcache) echo "scenario2-kvcache.yaml" ;;
        queue)   echo "scenario3-queue.yaml" ;;
        *)       echo "" ;;
    esac
}

# ── Build ─────────────────────────────────────────────────────────────────────
build_image() {
    print_info "Building mock-vllm image..."
    docker build -t mock-vllm:latest "$PROJECT_ROOT/mock-vllm"
    print_info "Loading into kind cluster..."
    kind load docker-image mock-vllm:latest --name "$CLUSTER_NAME"
    print_success "Image ready"
}

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy_scenario() {
    local scenario=$1
    local scenario_file
    scenario_file=$(get_scenario_file "$scenario")

    if [ -z "$scenario_file" ]; then
        print_error "Unknown scenario: $scenario (latency|kvcache|queue)"
        exit 1
    fi

    print_info "Removing existing vllm-qwen deployments..."
    kubectl delete deployment -n "$NAMESPACE" -l app=vllm-qwen --wait --ignore-not-found=true
    # Wait for pods to be fully deleted
    kubectl wait --for=delete pod -n "$NAMESPACE" -l app=vllm-qwen --timeout=60s 2>/dev/null || true

    print_info "Deploying scenario: $scenario..."
    kubectl apply -f "$K8S_DIR/$scenario_file"

    print_info "Waiting for pods ready..."
    kubectl wait --for=condition=ready pod \
        -n "$NAMESPACE" -l app=vllm-qwen --timeout=90s

    print_success "Deployed"
    kubectl get pods -n "$NAMESPACE" -l app=vllm-qwen -o wide
    echo ""
}

# ── Verify metrics ────────────────────────────────────────────────────────────
verify_metrics() {
    print_info "Verifying /metrics format from pods..."
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app=vllm-qwen \
        -o jsonpath='{.items[*].metadata.name}')

    for pod in $pods; do
        local speed
        speed=$(kubectl get pod -n "$NAMESPACE" "$pod" \
            -o jsonpath='{.metadata.labels.speed}' 2>/dev/null || echo "?")
        echo -e "\n${BLUE}[$speed] $pod${NC}"
        kubectl exec -n "$NAMESPACE" "$pod" -- \
            curl -s localhost:8000/metrics \
            | grep -E "vllm:(num_requests|kv_cache)" || true
    done
    echo ""
}

# ── Load + monitor ────────────────────────────────────────────────────────────
run_test() {
    local scenario=$1

    print_info "Starting load test in background..."
    "$PROJECT_ROOT/test/load-test.sh" 60 20 &
    local load_pid=$!

    print_info "Monitoring metrics for 15s..."
    for i in $(seq 1 15); do
        echo -e "\n${YELLOW}── sample $i ──${NC}"
        # Get fresh pod list each iteration
        local pods
        pods=$(kubectl get pods -n "$NAMESPACE" -l app=vllm-qwen \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        for pod in $pods; do
            local speed
            speed=$(kubectl get pod -n "$NAMESPACE" "$pod" \
                -o jsonpath='{.metadata.labels.speed}' 2>/dev/null || echo "?")
            local running waiting kvcache
            running=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
                curl -s localhost:8000/metrics 2>/dev/null \
                | grep 'vllm:num_requests_running' | awk '{print $2}' || echo "N/A")
            waiting=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
                curl -s localhost:8000/metrics 2>/dev/null \
                | grep 'vllm:num_requests_waiting' | awk '{print $2}' || echo "N/A")
            kvcache=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
                curl -s localhost:8000/metrics 2>/dev/null \
                | grep 'vllm:kv_cache_usage_perc' | awk '{print $2}' || echo "N/A")
            printf "  [%-4s] %-50s running=%-3s waiting=%-3s kv=%-6s\n" \
                "$speed" "$pod" "$running" "$waiting" "$kvcache"
        done
        sleep 1
    done

    wait $load_pid 2>/dev/null || true

    # ── pass/fail 판정 ──────────────────────────────────────────────────────
    echo ""
    print_info "Evaluating routing..."

    local fast_pod slow_pod
    fast_pod=$(kubectl get pods -n "$NAMESPACE" \
        -l app=vllm-qwen,speed=fast \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    slow_pod=$(kubectl get pods -n "$NAMESPACE" \
        -l app=vllm-qwen,speed=slow \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$fast_pod" ] || [ -z "$slow_pod" ]; then
        print_warning "Could not identify fast/slow pods"
        return
    fi

    local fast_w slow_w fast_kv slow_kv
    fast_w=$(kubectl exec -n "$NAMESPACE" "$fast_pod" -- \
        curl -s localhost:8000/metrics 2>/dev/null \
        | grep 'vllm:num_requests_waiting' | awk '{print $2}' || echo "0")
    slow_w=$(kubectl exec -n "$NAMESPACE" "$slow_pod" -- \
        curl -s localhost:8000/metrics 2>/dev/null \
        | grep 'vllm:num_requests_waiting' | awk '{print $2}' || echo "0")
    fast_kv=$(kubectl exec -n "$NAMESPACE" "$fast_pod" -- \
        curl -s localhost:8000/metrics 2>/dev/null \
        | grep 'vllm:kv_cache_usage_perc' | awk '{print $2}' || echo "0")
    slow_kv=$(kubectl exec -n "$NAMESPACE" "$slow_pod" -- \
        curl -s localhost:8000/metrics 2>/dev/null \
        | grep 'vllm:kv_cache_usage_perc' | awk '{print $2}' || echo "0")

    echo "  fast pod — waiting=${fast_w%.*}, kv_cache=${fast_kv}"
    echo "  slow pod — waiting=${slow_w%.*}, kv_cache=${slow_kv}"

    case $scenario in
        latency|queue)
            if [ "${slow_w%.*}" -gt "${fast_w%.*}" ] 2>/dev/null; then
                print_success "slow pod queue(${slow_w%.*}) > fast pod queue(${fast_w%.*}) — EPP should prefer fast"
            else
                print_warning "Queue difference not visible — try higher load or longer wait"
            fi
            ;;
        kvcache)
            # kv_cache는 부동소수점이라 awk로 비교
            local result
            result=$(awk "BEGIN { print (${slow_kv:-0} > ${fast_kv:-0}) ? \"yes\" : \"no\" }")
            if [ "$result" = "yes" ]; then
                print_success "slow pod kv_cache(${slow_kv}) > fast pod kv_cache(${fast_kv}) — EPP should prefer fast"
            else
                print_warning "KV-cache difference not clear — check KV_CACHE_BASE env values"
            fi
            ;;
    esac
}

# ── EPP 로그 ──────────────────────────────────────────────────────────────────
show_epp_routing() {
    print_info "EPP routing decisions (last 20 lines)..."
    kubectl logs -n "$NAMESPACE" -l app=vllm-qwen-epp \
        --tail=100 2>/dev/null \
        | grep -iE "(select|score|pod|pick|endpoint|route)" \
        | tail -20 || print_warning "No EPP routing logs found"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local scenario=${1:-latency}

    case $scenario in
        build)
            build_image
            exit 0
            ;;
        clean)
            print_info "Cleaning up mock deployments..."
            kubectl delete deployment -n "$NAMESPACE" \
                -l app=vllm-qwen --wait --ignore-not-found=true
            print_success "Done"
            exit 0
            ;;
        latency|kvcache|queue)
            ;;
        *)
            print_error "Unknown command: $scenario"
            echo "Usage: $0 <latency|kvcache|queue|build|clean>"
            exit 1
            ;;
    esac

    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE} Mock vLLM EPP Test: $scenario${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"

    build_image
    deploy_scenario "$scenario"
    verify_metrics
    run_test "$scenario"
    show_epp_routing

    echo -e "\n${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN} Done: $scenario${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}\n"
    echo "Next:"
    echo "  Grafana → EPP Inference Routing 대시보드"
    echo "  kubectl logs -n default -l app=vllm-qwen-epp -f"
    echo "  $0 <latency|kvcache|queue|clean>"
}

main "$@"
