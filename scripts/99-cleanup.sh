#!/bin/bash
set -e

echo "=== Cleanup ==="
echo ""

read -p "Delete all resources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

kind delete cluster --name ai-gateway-lab 2>/dev/null || echo "Cluster not found"

echo ""
echo "Done."
