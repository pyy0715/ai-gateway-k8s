#!/bin/bash

# EPP Routing Verification Script
# This script helps verify EPP smart routing behavior in the ai-gateway-k8s deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-default}"
VLLM_SERVICE="${VLLM_SERVICE:-vllm-qwen}"
VLLM_EPP_SERVICE="${VLLM_EPP_SERVICE:-vllm-qwen-epp}"
VLLM_METRICS_PORT="${VLLM_METRICS_PORT:-8000}"  # vLLM metrics are on main server port
EPP_METRICS_PORT="${EPP_METRICS_PORT:-9090}"
PROMETHEUS_NAMESPACE="${PROMETHEUS_NAMESPACE:-default}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    log_success "kubectl is available"
}

# Function to check if we can access the cluster
check_cluster_access() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    log_success "Cluster access verified"
}

# Function to list vLLM pods
list_vllm_pods() {
    log_info "Listing vLLM pods in namespace '${NAMESPACE}'..."
    kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_SERVICE}" -o wide
}

# Function to check vLLM metrics endpoint
check_vllm_metrics() {
    print_section "1. Checking vLLM Metrics Endpoint"

    local pod_name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "${pod_name}" ]]; then
        log_error "No vLLM pods found. Please check if the service is deployed."
        return 1
    fi

    log_info "Found vLLM pod: ${pod_name}"
    echo ""

    # Fetch metrics directly from the pod
    log_info "Fetching metrics from pod ${pod_name}:8000/metrics..."
    echo ""

    local metrics
    metrics=$(kubectl exec -n "${NAMESPACE}" "${pod_name}" -- curl -s http://localhost:8000/metrics 2>/dev/null || true)

    if [[ -z "${metrics}" ]]; then
        log_error "Failed to fetch metrics from vLLM endpoint"
        kill "${pf_pid}" 2>/dev/null || true
        return 1
    fi

    # Check for expected vLLM metrics
    local metrics_to_check=(
        "vllm:num_requests_running"
        "vllm:num_requests_waiting"
        "vllm:gpu_cache_usage_perc"
        "vllm:avg_prompt_throughput_toks_per_s"
        "vllm:avg_generation_throughput_toks_per_s"
    )

    for metric in "${metrics_to_check[@]}"; do
        if echo "${metrics}" | grep -q "^${metric}"; then
            local value
            value=$(echo "${metrics}" | grep "^${metric}" | head -1)
            log_success "Found: ${value}"
        else
            log_warning "Missing metric: ${metric}"
        fi
    done

    echo ""
    log_info "Full vLLM metrics output:"
    echo "${metrics}" | head -50

    # Cleanup port-forward
    kill "${pf_pid}" 2>/dev/null || true
    wait "${pf_pid}" 2>/dev/null || true
}

# Function to check EPP metrics endpoint
check_epp_metrics() {
    print_section "2. Checking EPP Metrics Endpoint"

    local pod_name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_EPP_SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "${pod_name}" ]]; then
        log_error "No EPP pods found. Please check if the service is deployed."
        return 1
    fi

    log_info "Found EPP pod: ${pod_name}"
    echo ""

    # Start port-forward in background
    log_info "Starting port-forward to EPP pod ${pod_name} on port ${EPP_METRICS_PORT}..."
    kubectl port-forward -n "${NAMESPACE}" "${pod_name}" ${EPP_METRICS_PORT}:${EPP_METRICS_PORT} >/dev/null 2>&1 &
    local pf_pid=$!

    # Wait for port-forward to be ready
    sleep 3

    # Check if port-forward is still running
    if ! kill -0 "${pf_pid}" 2>/dev/null; then
        log_error "Port-forward failed to start"
        return 1
    fi

    log_success "Port-forward established on localhost:${EPP_METRICS_PORT}"
    echo ""

    # Fetch metrics
    log_info "Fetching metrics from localhost:${EPP_METRICS_PORT}/metrics..."
    echo ""

    local metrics
    metrics=$(curl -s "http://localhost:${EPP_METRICS_PORT}/metrics" 2>/dev/null || true)

    if [[ -z "${metrics}" ]]; then
        log_error "Failed to fetch metrics from EPP endpoint"
        kill "${pf_pid}" 2>/dev/null || true
        return 1
    fi

    # Check for EPP-specific metrics
    local epp_metrics_found=false
    if echo "${metrics}" | grep -q "epp"; then
        log_success "EPP metrics are being exposed"
        epp_metrics_found=true
    fi

    # Show metrics
    echo ""
    log_info "EPP metrics output:"
    echo "${metrics}" | head -50

    # Cleanup port-forward
    kill "${pf_pid}" 2>/dev/null || true
    wait "${pf_pid}" 2>/dev/null || true

    if [[ "${epp_metrics_found}" == "true" ]]; then
        log_success "EPP metrics endpoint is functional"
    else
        log_warning "No EPP-specific metrics found (might be expected depending on configuration)"
    fi
}

# Function to check EPP logs for routing decisions
check_epp_logs() {
    print_section "3. Checking EPP Logs for Routing Decisions"

    local pod_name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_EPP_SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "${pod_name}" ]]; then
        log_error "No EPP pods found"
        return 1
    fi

    log_info "Showing recent logs from EPP pod: ${pod_name}"
    echo ""
    log_info "Look for patterns like:"
    echo "  - 'routing', 'selected', 'chose', 'pod'"
    echo "  - 'cache', 'utilization', 'queue'"
    echo "  - Backend/pod selection decisions"
    echo ""

    # Get recent logs
    log_info "Recent EPP logs (last 50 lines):"
    echo ""
    kubectl logs -n "${NAMESPACE}" "${pod_name}" --tail=50 2>/dev/null || {
        log_error "Failed to fetch logs from EPP pod"
        return 1
    }

    echo ""
    log_info "Searching for routing-related log entries..."
    echo ""

    # Search for common routing log patterns
    local patterns=(
        "routing"
        "selected"
        "backend"
        "endpoint"
        "cache.*util"
        "queue.*depth"
        "kv.*cache"
        "pod.*selected"
    )

    for pattern in "${patterns[@]}"; do
        local matches
        matches=$(kubectl logs -n "${NAMESPACE}" "${pod_name}" --tail=200 2>/dev/null | grep -i "${pattern}" || true)
        if [[ -n "${matches}" ]]; then
            echo -e "${GREEN}Pattern '${pattern}':${NC}"
            echo "${matches}" | head -5
            echo ""
        fi
    done

    log_success "Log analysis complete"
}

# Function to provide Prometheus query examples
show_prometheus_queries() {
    print_section "4. Prometheus Query Examples"

    log_info "Use these queries in Prometheus or Grafana to monitor EPP routing:"
    echo ""

    cat <<'EOF'
# KV-Cache Utilization per Pod
# Shows how much GPU memory cache is being used
vllm:gpu_cache_usage_perc

# Average KV-cache utilization across all pods
avg(vllm:gpu_cache_usage_perc) by (job)


# Queue Depth per Pod
# Number of requests waiting to be processed
vllm:num_requests_waiting

# Total queue depth across all pods
sum(vllm:num_requests_waiting)


# Running Requests per Pod
# Number of requests currently being processed
vllm:num_requests_running

# Total running requests across all pods
sum(vllm:num_requests_running)


# Request Rate
# Requests per second (prompt throughput)
rate(vllm:avg_prompt_throughput_toks_per_s[5m])

# Generation throughput (tokens/sec)
rate(vllm:avg_generation_throughput_toks_per_s[5m])


# EPP Routing Decisions (if EPP exposes routing metrics)
# Number of times each pod was selected
rate(epp_routing_decisions_total{pod=~"vllm-.*"}[5m])


# Cache Efficiency Metrics
# Cache hit rate (if available)
rate(vllm:cache_hits_total[5m]) / rate(vllm:cache_requests_total[5m])


# Time in Queue
# P95 time requests spend waiting
histogram_quantile(0.95, rate(vllm:request_queue_time_seconds_bucket[5m]))


# Request Latency
# P95 total request latency
histogram_quantile(0.95, rate(vllm:request_latency_seconds_bucket[5m]))


# Pod Selection for Routing
# Get all vLLM backend endpoints with their cache usage
vllm:gpu_cache_usage_perc * on (instance) group_left() kube_pod_info


# Advanced: Find least utilized pod
# Pods with cache usage below 80%
vllm:gpu_cache_usage_perc < 80


# Alert: High Queue Depth
# Trigger when queue is too deep
vllm:num_requests_waiting > 10


# Alert: Low Cache Utilization
# Trigger when cache is underutilized (might scale down)
avg(vllm:gpu_cache_usage_perc) < 20

EOF

    log_success "Query examples provided"
}

# Function to run verification checklist
run_verification_checklist() {
    print_section "5. Verification Checklist"

    local all_passed=true

    echo "Running through EPP routing verification checklist..."
    echo ""

    # Check 1: vLLM metrics enabled
    log_info "Checking if vLLM metrics are enabled..."
    local pod_name
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "${pod_name}" ]]; then
        if kubectl get pod -n "${NAMESPACE}" "${pod_name}" -o jsonpath='{.spec.containers[0].args}' 2>/dev/null | grep -q -- "--enable-metrics"; then
            log_success "vLLM metrics flag (--enable-metrics) is set"
        else
            log_warning "Could not verify --enable-metrics flag (check container args)"
        fi
    else
        log_error "No vLLM pod found to check metrics configuration"
        all_passed=false
    fi
    echo ""

    # Check 2: EPP can reach vLLM metrics
    log_info "Checking if EPP can reach vLLM metrics..."
    local epp_pod
    epp_pod=$(kubectl get pods -n "${NAMESPACE}" -l app="${VLLM_EPP_SERVICE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "${epp_pod}" ]]; then
        if kubectl exec -n "${NAMESPACE}" "${epp_pod}" -c main -- curl -s "http://${VLLM_SERVICE}.${NAMESPACE.svc}:${VLLM_METRICS_PORT}/metrics" >/dev/null 2>&1; then
            log_success "EPP can reach vLLM metrics endpoint"
        else
            log_warning "EPP may not be able to reach vLLM metrics (network test failed)"
        fi
    else
        log_warning "No EPP pod found to test metrics reachability"
    fi
    echo ""

    # Check 3: Prometheus is scraping metrics
    log_info "Checking if Prometheus is scraping metrics..."
    if kubectl get svc -n "${PROMETHEUS_NAMESPACE}" prometheus-k8s >/dev/null 2>&1 || \
       kubectl get svc -n "${PROMETHEUS_NAMESPACE}" prometheus-operated >/dev/null 2>&1 || \
       kubectl get svc -n "${PROMETHEUS_NAMESPACE}" prometheus-server >/dev/null 2>&1; then
        log_success "Prometheus service found in namespace '${PROMETHEUS_NAMESPACE}'"
        echo ""
        log_info "To verify scraping is working, check Prometheus targets:"
        echo "  kubectl port-forward -n ${PROMETHEUS_NAMESPACE} svc/prometheus-k8s 9090:9090"
        echo "  Then visit: http://localhost:9090/targets"
    else
        log_warning "Prometheus service not found in namespace '${PROMETHEUS_NAMESPACE}'"
        log_info "Set PROMETHEUS_NAMESPACE to your Prometheus namespace"
    fi
    echo ""

    # Check 4: ServiceMonitor or PodMonitor exists
    log_info "Checking for monitoring configuration..."
    if kubectl get servicemonitor -n "${NAMESPACE}" "${VLLM_SERVICE}" >/dev/null 2>&1; then
        log_success "ServiceMonitor '${VLLM_SERVICE}' found"
    elif kubectl get podmonitor -n "${NAMESPACE}" "${VLLM_SERVICE}" >/dev/null 2>&1; then
        log_success "PodMonitor '${VLLM_SERVICE}' found"
    else
        log_warning "No ServiceMonitor or PodMonitor found for vLLM"
    fi
    echo ""

    # Check 5: Services are accessible
    log_info "Checking service endpoints..."
    local vllm_endpoints
    vllm_endpoints=$(kubectl get endpoints -n "${NAMESPACE}" "${VLLM_SERVICE}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    if [[ -n "${vllm_endpoints}" ]]; then
        log_success "vLLM service has endpoints: ${vllm_endpoints}"
    else
        log_error "vLLM service has no endpoints (pods may not be ready)"
        all_passed=false
    fi

    local epp_endpoints
    epp_endpoints=$(kubectl get endpoints -n "${NAMESPACE}" "${VLLM_EPP_SERVICE}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    if [[ -n "${epp_endpoints}" ]]; then
        log_success "EPP service has endpoints: ${epp_endpoints}"
    else
        log_error "EPP service has no endpoints (pods may not be ready)"
        all_passed=false
    fi
    echo ""

    # Summary
    print_section "Verification Summary"
    if [[ "${all_passed}" == "true" ]]; then
        log_success "All critical checks passed!"
    else
        log_warning "Some checks failed. Please review the output above."
    fi
}

# Function to show usage
show_usage() {
    cat <<EOF
EPP Routing Verification Script

USAGE:
    $(basename "$0") [OPTIONS] COMMAND

COMMANDS:
    check-all               Run all verification checks
    check-vllm-metrics      Check vLLM metrics endpoint
    check-epp-metrics       Check EPP metrics endpoint
    check-logs              Check EPP logs for routing decisions
    show-queries            Show Prometheus query examples
    verify-checklist        Run the verification checklist
    list-pods               List vLLM pods
    help                    Show this help message

OPTIONS:
    -n, --namespace NAMESPACE    Kubernetes namespace (default: default)
    -v, --vllm-service NAME      vLLM service name (default: vllm)
    -e, --epp-service NAME       EPP service name (default: vllm-epp)
    -p, --prometheus-ns NS       Prometheus namespace (default: monitoring)
    --vllm-port PORT             vLLM metrics port (default: 8000)
    --epp-port PORT              EPP metrics port (default: 9090)

ENVIRONMENT VARIABLES:
    NAMESPACE                    Kubernetes namespace
    VLLM_SERVICE                 vLLM service name
    VLLM_EPP_SERVICE             EPP service name
    PROMETHEUS_NAMESPACE         Prometheus namespace
    VLLM_METRICS_PORT            vLLM metrics port
    EPP_METRICS_PORT             EPP metrics port

EXAMPLES:
    # Run all checks
    $(basename "$0") check-all

    # Check specific namespace
    $(basename "$0") -n production check-all

    # Only check vLLM metrics
    $(basename "$0") check-vllm-metrics

    # View Prometheus queries
    $(basename "$0") show-queries

    # Run verification checklist
    $(basename "$0") verify-checklist

EOF
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -v|--vllm-service)
                VLLM_SERVICE="$2"
                shift 2
                ;;
            -e|--epp-service)
                VLLM_EPP_SERVICE="$2"
                shift 2
                ;;
            -p|--prometheus-ns)
                PROMETHEUS_NAMESPACE="$2"
                shift 2
                ;;
            --vllm-port)
                VLLM_METRICS_PORT="$2"
                shift 2
                ;;
            --epp-port)
                EPP_METRICS_PORT="$2"
                shift 2
                ;;
            -h|--help|help)
                show_usage
                exit 0
                ;;
            *)
                COMMAND="$1"
                shift
                ;;
        esac
    done

    # Default command if none specified
    COMMAND="${COMMAND:-check-all}"

    # Pre-flight checks
    check_kubectl
    check_cluster_access

    # Execute command
    case "${COMMAND}" in
        check-all)
            check_vllm_metrics
            check_epp_metrics
            check_epp_logs
            show_prometheus_queries
            run_verification_checklist
            ;;
        check-vllm-metrics)
            check_vllm_metrics
            ;;
        check-epp-metrics)
            check_epp_metrics
            ;;
        check-logs)
            check_epp_logs
            ;;
        show-queries)
            show_prometheus_queries
            ;;
        verify-checklist)
            run_verification_checklist
            ;;
        list-pods)
            list_vllm_pods
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
