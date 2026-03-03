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

echo "=== Deploying AI Gateway Resources ==="
echo "Options: monitoring=$DEPLOY_MONITORING, smol=$DEPLOY_SMOL"
echo ""

# Backend
echo "[1/4] Deploying vLLM backend..."
kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml"
[ "$DEPLOY_SMOL" = true ] && kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-smol.yaml"

kubectl wait --for=condition=Ready pods -l app=vllm-qwen --timeout=600s || true
[ "$DEPLOY_SMOL" = true ] && kubectl wait --for=condition=Ready pods -l app=vllm-smol --timeout=600s || true

# InferencePool + EPP
echo ""
echo "[2/4] Deploying InferencePool + EPP..."
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-qwen/"
kubectl wait --for=condition=Ready pods -l app=vllm-qwen-epp --timeout=120s || true

if [ "$DEPLOY_SMOL" = true ]; then
    kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/pool-smol/"
    kubectl wait --for=condition=Ready pods -l app=vllm-smol-epp --timeout=120s || true
fi

# AI Gateway
echo ""
echo "[3/4] Deploying AI Gateway..."
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/"
kubectl wait --for=condition=Programmed gateway/ai-gateway --timeout=120s || true

# Monitoring
if [ "$DEPLOY_MONITORING" = true ]; then
    echo ""
    echo "[4/4] Deploying monitoring..."
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/prometheus.yaml"
    kubectl apply -f "$PROJECT_DIR/k8s/monitoring/grafana.yaml"

    kubectl create configmap grafana-dashboards \
        --from-file=vllm.json="$PROJECT_DIR/k8s/monitoring/dashboards/vllm.json" \
        --from-file=envoy-proxy.json="$PROJECT_DIR/k8s/monitoring/dashboards/envoy-proxy.json" \
        --from-file=envoy-gateway.json="$PROJECT_DIR/k8s/monitoring/dashboards/envoy-gateway.json" \
        --from-file=epp-routing.json="$PROJECT_DIR/k8s/monitoring/dashboards/epp-routing.json" \
        -n default --dry-run=client -o yaml | kubectl apply -f -

    kubectl wait --for=condition=Ready pods -l app=prometheus --timeout=120s || true
    kubectl wait --for=condition=Ready pods -l app=grafana --timeout=120s || true
fi

# Status
echo ""
echo "=== Status ==="
kubectl get pods -l 'app in (vllm-qwen,vllm-qwen-epp,vllm-smol,vllm-smol-epp)' -o wide 2>/dev/null || true
[ "$DEPLOY_MONITORING" = true ] && kubectl get pods -l 'app in (prometheus,grafana)' -o wide 2>/dev/null || true
echo ""
kubectl get gateway,aigatewayroute,inferencepool 2>/dev/null || true

echo ""
echo "Done. API: curl http://<EXTERNAL-IP>/v1/models"
[ "$DEPLOY_MONITORING" = true ] && echo "Grafana: http://localhost:3000 (admin/admin)"
