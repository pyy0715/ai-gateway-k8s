#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Envoy AI Gateway Lab - Cluster Setup ==="
echo ""

if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed. Install: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed. Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo "Error: Docker is not running."
    exit 1
fi

CLUSTER_NAME="ai-gateway-lab"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kind delete cluster --name "$CLUSTER_NAME"
    else
        exit 0
    fi
fi

echo "Creating kind cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$PROJECT_DIR/kind-config.yaml"

echo ""
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "Installing cloud-provider-kind..."
if ! command -v cloud-provider-kind &> /dev/null; then
    brew install cloud-provider-kind 2>/dev/null || \
    go install sigs.k8s.io/cloud-provider-kind@latest 2>/dev/null || \
    echo "cloud-provider-kind install failed: https://github.com/kubernetes-sigs/cloud-provider-kind"
fi

pkill cloud-provider-kind 2>/dev/null || true
echo "Starting cloud-provider-kind (sudo password required)..."
sudo cloud-provider-kind </dev/null &>/dev/null &

echo ""
kubectl get nodes
echo ""
echo "Next: ./scripts/02-install-envoy-gateway.sh"
