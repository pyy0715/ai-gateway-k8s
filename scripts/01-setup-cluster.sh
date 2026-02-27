#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Envoy AI Gateway Lab - Cluster Setup ==="
echo ""

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "Installing kind..."
    if command -v brew &> /dev/null; then
        brew install kind
    else
        echo "Please install kind first: https://kind.sigs.k8s.io/docs/user/quick-start/"
        exit 1
    fi
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

CLUSTER_NAME="ai-gateway-lab"

# Check if cluster already exists
if kind get clusters | grep -q "$CLUSTER_NAME"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Keeping existing cluster. Exiting."
        exit 0
    fi
fi

echo "Creating kind cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$PROJECT_DIR/kind-config.yaml"

echo ""
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo ""
echo "=== Cluster Info ==="
kubectl cluster-info
echo ""
kubectl get nodes

echo ""
echo "✅ Cluster setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/02-install-gateway-api.sh"
echo "  2. Run: ./scripts/03-install-envoy-gateway.sh"
echo "  3. Run: ./scripts/04-install-ai-gateway.sh"
