#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DEPLOY_MONITORING=false
DEPLOY_SMOL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --monitoring) DEPLOY_MONITORING=true; shift ;;
        --smol)       DEPLOY_SMOL=true;       shift ;;
        --all)        DEPLOY_MONITORING=true; DEPLOY_SMOL=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "=== Deploying vLLM + AI Gateway Resources ==="
echo ""
echo "Options: monitoring=$DEPLOY_MONITORING, smol=$DEPLOY_SMOL"
echo ""

# ──────────────────────────────────────────────────────────
# 1. vLLM Backends
# ──────────────────────────────────────────────────────────
echo "[1] Deploying vLLM Qwen backend..."
kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml"

if [ "$DEPLOY_SMOL" = true ]; then
    echo "[1b] Deploying vLLM SmolLM backend..."
    kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-smol.yaml"
fi

# 모델 다운로드 포함 → 긴 timeout, 실패해도 계속 진행 (|| true)
echo ""
echo "Waiting for vLLM pods (may take several minutes for model download)..."
kubectl wait --for=condition=Ready pods -l app=vllm-qwen --timeout=600s || true
if [ "$DEPLOY_SMOL" = true ]; then
    kubectl wait --for=condition=Ready pods -l app=vllm-smol --timeout=600s || true
fi

# ──────────────────────────────────────────────────────────
# 2. InferencePool + EPP
# ──────────────────────────────────────────────────────────
echo ""
echo "[2] Deploying InferencePool + EPP (Qwen)..."
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-rbac.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-config.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/epp-deployment.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/inference-pool.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/inference-objective.yaml"

kubectl wait --for=condition=Ready pods -l app=vllm-qwen-epp --timeout=120s || true

if [ "$DEPLOY_SMOL" = true ]; then
    echo ""
    echo "[2b] Deploying InferencePool + EPP (SmolLM)..."
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-rbac.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-config.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/epp-deployment.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/inference-pool.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/inference-objective.yaml"

    kubectl wait --for=condition=Ready pods -l app=vllm-smol-epp --timeout=120s || true
fi

# ──────────────────────────────────────────────────────────
# 3. AI Gateway Resources
# ──────────────────────────────────────────────────────────
echo ""
echo "[3] Deploying AI Gateway resources..."
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/gateway.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/ai-gateway-route.yaml"

kubectl wait --for=condition=Programmed gateway/ai-gateway --timeout=120s || true

# ──────────────────────────────────────────────────────────
# 4. Monitoring (optional)
# ──────────────────────────────────────────────────────────
if [ "$DEPLOY_MONITORING" = true ]; then
    echo ""
    echo "[4] Deploying monitoring stack..."
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/prometheus.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/grafana.yaml"

    kubectl wait --for=condition=Ready pods -l app=prometheus --timeout=120s || true
    kubectl wait --for=condition=Ready pods -l app=grafana    --timeout=120s || true

    # Import official dashboards via Grafana API
    echo "Importing dashboards via Grafana API..."
    DASHBOARDS_DIR="$PROJECT_DIR/k8s/monitoring/dashboards"

    # Port-forward Grafana in background
    kubectl port-forward svc/grafana 3000:3000 &
    GRAFANA_PID=$!
    sleep 3

    # Import vLLM dashboard
    curl -s -X POST "http://admin:admin@localhost:3000/api/dashboards/import" \
        -H "Content-Type: application/json" \
        -d @"$DASHBOARDS_DIR/vllm.json" > /dev/null 2>&1 && echo "  ✓ vLLM dashboard imported"

    # Import Envoy Proxy dashboard
    curl -s -X POST "http://admin:admin@localhost:3000/api/dashboards/import" \
        -H "Content-Type: application/json" \
        -d @"$DASHBOARDS_DIR/envoy-proxy-global.json" > /dev/null 2>&1 && echo "  ✓ Envoy Proxy dashboard imported"

    # Import Envoy Gateway dashboard
    curl -s -X POST "http://admin:admin@localhost:3000/api/dashboards/import" \
        -H "Content-Type: application/json" \
        -d @"$DASHBOARDS_DIR/envoy-gateway-global.json" > /dev/null 2>&1 && echo "  ✓ Envoy Gateway dashboard imported"

    kill $GRAFANA_PID 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────
# Status
# ──────────────────────────────────────────────────────────
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
    kubectl get pods -l 'app in (prometheus,grafana)' -o wide 2>/dev/null || true
fi

echo ""
echo "--- Gateway / Routes / Pools ---"
kubectl get gateway,aigatewayroute,inferencepool 2>/dev/null || true

echo ""
echo "✅ All resources deployed!"
echo ""
echo "Usage:"
echo "  ./test/test-api.sh            # Test the API"
echo "  ./test/load-test.sh           # Run load tests"
echo "  ./test/verify-epp-routing.sh  # Verify EPP routing"
echo ""
echo "Models available:"
echo "  Qwen/Qwen3-0.6B (default)"
if [ "$DEPLOY_SMOL" = true ]; then
    echo "  HuggingFaceTB/SmolLM2-1.7B-Instruct"
fi
echo ""
if [ "$DEPLOY_MONITORING" = true ]; then
    echo "Monitoring:"
    echo "  kubectl port-forward svc/prometheus 9090:9090"
    echo "  kubectl port-forward svc/grafana 3000:3000  (admin/admin)"
    echo ""
fi
echo "Note: vLLM may take a few minutes on first start (model download)."
echo "  kubectl logs -l app=vllm-qwen -f"
