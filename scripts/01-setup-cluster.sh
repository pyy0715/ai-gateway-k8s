
#!/bin/bash
set -e

# Check environment
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: x86_64 required. Current: $ARCH"
    echo "vLLM CPU requires x86_64 with AVX-512."
    exit 1
fi

# Install k3s if not present
if ! command -v k3s &>/dev/null; then
    echo "[1/4] Installing k3s..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml
else
    echo "[1/4] k3s already installed"
fi

# Wait for Kubernetes
echo ""
echo "[2/4] Waiting for Kubernetes..."
sleep 10
until kubectl get nodes &>/dev/null; do
    echo "Waiting for node to be created..."
    sleep 2
done
kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes

# Install Helm
echo ""
if ! command -v helm &>/dev/null; then
    echo "[3/4] Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "[3/4] Helm already installed"
fi

# Install Envoy Gateway
echo ""
echo "[4/4] Installing Envoy Gateway v1.6.3..."
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.6.3 \
  --namespace envoy-gateway-system \
  --create-namespace

kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next: ./scripts/02-install-monitoring.sh"
