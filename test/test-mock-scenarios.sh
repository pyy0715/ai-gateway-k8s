#!/bin/bash
# Mock vLLM EPP routing test
# Usage: ./test/test-mock-scenarios.sh <latency|kvcache|queue|build|clean>

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

build_image() {
    print_info "Building mock-vllm image..."
    docker build -t mock-vllm:latest "$PROJECT_ROOT/mock-vllm"
    print_info "Loading into kind cluster..."
    kind load docker-image mock-vllm:latest --name "$CLUSTER_NAME"
    print_success "Image ready"
}

deploy_scenario() {
    local scenario=$1
    local scenario_file
    scenario_file=$(get_scenario_file "$scenario")

    if [ -z "$scenario_file" ]; then
        print_error "Unknown scenario: $scenario (latency|kvcache|queue)"
        exit 1
    fi

    print_info "Removing existing deployments..."
    kubectl delete deployment -n "$NAMESPACE" -l app=vllm-qwen --wait --ignore-not-found=true
    kubectl wait --for=delete pod -n "$NAMESPACE" -l app=vllm-qwen --timeout=60s 2>/dev/null || true

    print_info "Deploying scenario: $scenario..."
    kubectl apply -f "$K8S_DIR/$scenario_file"

    print_info "Waiting for pods ready..."
    kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app=vllm-qwen --timeout=90s

    print_success "Deployed"
    kubectl get pods -n "$NAMESPACE" -l app=vllm-qwen -o wide
}

run_test() {
    local scenario=$1

    print_info "Starting load test (60 requests, 20 concurrent)..."
    print_info "Monitoring request distribution..."

    "$PROJECT_ROOT/test/load-test.sh" 60 20 > /dev/null 2>&1 &
    local load_pid=$!

    local fast_total=0 slow_total=0 samples=0

    while kill -0 $load_pid 2>/dev/null; do
        samples=$((samples + 1))
        echo -e "\n${YELLOW}── sample $samples ──${NC}"
        for pod in $(kubectl get pods -n "$NAMESPACE" -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            local speed=$(kubectl get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.metadata.labels.speed}' 2>/dev/null || echo "?")
            local running=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -s localhost:8000/metrics 2>/dev/null | grep 'vllm:num_requests_running' | awk '{print $2}' || echo "0")
            local waiting=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -s localhost:8000/metrics 2>/dev/null | grep 'vllm:num_requests_waiting' | awk '{print $2}' || echo "0")
            local kv=$(kubectl exec -n "$NAMESPACE" "$pod" -- curl -s localhost:8000/metrics 2>/dev/null | grep 'vllm:kv_cache_usage_perc' | awk '{print $2}' || echo "0")
            printf "  [%-4s] running=%-2s waiting=%-2s kv=%s\n" "$speed" "$running" "$waiting" "$kv"

            if [ "$speed" = "fast" ]; then
                fast_total=$((fast_total + running + waiting))
            elif [ "$speed" = "slow" ]; then
                slow_total=$((slow_total + running + waiting))
            fi
        done
        sleep 1
    done

    echo ""
    print_info "Load test completed"
    echo ""
    print_info "Request distribution summary:"
    echo "  fast pod total: $fast_total (sum of running+waiting across samples)"
    echo "  slow pod total: $slow_total"

    if [ "$fast_total" -gt "$slow_total" ]; then
        print_success "EPP prefers fast pod (more requests routed)"
    elif [ "$slow_total" -gt "$fast_total" ]; then
        print_warning "EPP prefers slow pod (unexpected)"
    else
        print_warning "No clear preference"
    fi
}

main() {
    local scenario=${1:-latency}

    case $scenario in
        build)
            build_image
            exit 0
            ;;
        clean)
            print_info "Cleaning up..."
            kubectl delete deployment -n "$NAMESPACE" -l app=vllm-qwen --wait --ignore-not-found=true
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
    run_test "$scenario"

    echo -e "\n${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN} Done: $scenario${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}\n"
    echo "Check Grafana dashboard for EPP routing visualization"
}

main "$@"
