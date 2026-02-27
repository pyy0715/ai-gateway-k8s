#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
DEPLOY_MONITORING=false
DEPLOY_SMOL=false

for arg in "$@"; do
    case $arg in
        --monitoring)
            DEPLOY_MONITORING=true
            shift
            ;;
        --smol)
            DEPLOY_SMOL=true
            shift
            ;;
        --all)
            DEPLOY_MONITORING=true
            DEPLOY_SMOL=true
            shift
            ;;
    esac
done

echo "=== Deploying vLLM + AI Gateway Resources ==="
echo ""

# 1. Deploy vLLM Qwen backend (기본)
echo "1. Deploying vLLM Qwen backend..."
kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml"

echo ""
echo "Waiting for vLLM Qwen pods to be ready..."
kubectl wait --for=condition=Ready pods -l app=vllm-qwen --timeout=600s || true

# 1b. Deploy vLLM SmolLM backend (optional)
if [ "$DEPLOY_SMOL" = true ]; then
    echo ""
    echo "1b. Deploying vLLM SmolLM backend..."
    kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-smol.yaml"

    echo ""
    echo "Waiting for vLLM SmolLM pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app=vllm-smol --timeout=600s || true
fi

# 2. Deploy InferencePool + EPP (Qwen pool - 기본)
echo ""
echo "2. Deploying InferencePool + EPP (Qwen pool)..."
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-rbac.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-config.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-deployment.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/inference-pool.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/inference-objective.yaml"

echo ""
echo "Waiting for EPP Qwen pod to be ready..."
kubectl wait --for=condition=Ready pods -l app=vllm-qwen-epp --timeout=120s || true

# 2b. Deploy SmolLM pool (optional)
if [ "$DEPLOY_SMOL" = true ]; then
    echo ""
    echo "2b. Deploying InferencePool + EPP (SmolLM pool)..."
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-rbac.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-config.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-deployment.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/inference-pool.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/inference-objective.yaml"

    echo ""
    echo "Waiting for EPP SmolLM pod to be ready..."
    kubectl wait --for=condition=Ready pods -l app=vllm-smol-epp --timeout=120s || true
fi

# 3. Deploy AI Gateway resources
echo ""
echo "3. Deploying AI Gateway resources..."
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/gateway.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/ai-gateway-route.yaml"

echo ""
echo "Waiting for Gateway to be programmed..."
sleep 5
kubectl wait --for=condition=Programmed gateway/ai-gateway --timeout=120s 2>/dev/null || true

# 4. Deploy monitoring stack (optional)
if [ "$DEPLOY_MONITORING" = true ]; then
    echo ""
    echo "4. Deploying monitoring stack (Prometheus + Grafana)..."
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/prometheus.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/grafana.yaml"

    echo ""
    echo "Waiting for Prometheus pod to be ready..."
    kubectl wait --for=condition=Ready pods -l app=prometheus --timeout=120s || true

    echo ""
    echo "Waiting for Grafana pod to be ready..."
    kubectl wait --for=condition=Ready pods -l app=grafana --timeout=120s || true
fi

echo ""
echo "=== Deployment Status ==="
echo ""
echo "--- vLLM Pods ---"
kubectl get pods -l app=vllm-qwen -o wide 2>/dev/null || echo "No vLLM Qwen pods found"
if [ "$DEPLOY_SMOL" = true ]; then
    kubectl get pods -l app=vllm-smol -o wide 2>/dev/null || echo "No vLLM SmolLM pods found"
fi
echo ""
echo "--- EPP Pods ---"
kubectl get pods -l app=vllm-qwen-epp -o wide 2>/dev/null || echo "No EPP Qwen pods found"
if [ "$DEPLOY_SMOL" = true ]; then
    kubectl get pods -l app=vllm-smol-epp -o wide 2>/dev/null || echo "No EPP SmolLM pods found"
fi
if [ "$DEPLOY_MONITORING" = true ]; then
    echo ""
    echo "--- Monitoring Pods ---"
    kubectl get pods -l 'app in (prometheus,grafana)' -o wide 2>/dev/null || echo "No monitoring pods found"
fi
echo ""
echo "--- Gateway ---"
kubectl get gateway 2>/dev/null || echo "No gateway found"
echo ""
echo "--- AIGatewayRoute ---"
kubectl get aigatewayroute 2>/dev/null || echo "No aigatewayroute found"
echo ""
echo "--- InferencePool ---"
kubectl get inferencepool 2>/dev/null || echo "No inferencepool found"

echo ""
echo "✅ All resources deployed!"
echo ""
echo "Usage:"
echo "  ./test/test-api.sh              # Test the API"
echo "  ./test/load-test.sh             # Run load tests"
echo "  ./test/verify-epp-routing.sh    # Verify EPP routing"
echo ""
if [ "$DEPLOY_MONITORING" = true ]; then
    echo "Monitoring Access:"
    echo "  kubectl port-forward svc/prometheus 9090:9090  # Prometheus UI"
    echo "  kubectl port-forward svc/grafana 3000:3000    # Grafana UI (admin/admin)"
    echo ""
fi
echo "Models:"
echo "  Qwen/Qwen3-0.6B (default)"
if [ "$DEPLOY_SMOL" = true ]; then
    echo "  HuggingFaceTB/SmolLM2-1.7B-Instruct"
fi
echo ""
echo "Note: vLLM may take a few minutes to download the model on first start."
echo "Check logs with: kubectl logs -l app=vllm-qwen -f"
