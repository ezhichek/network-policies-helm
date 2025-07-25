#!/bin/bash

set -e
# === Installing Minikube===
echo "Installing Minikube ..."

# Install Minikube if not present
if ! command -v minikube &> /dev/null; then
    echo "Installing Minikube..."
    brew install minikube
fi

# Start Minikube without CNI (will install Calico manually)
echo "Starting Minikube without CNI..."
minikube start --network-plugin=cni --cni=false

# Wait a bit for Minikube to be ready
echo "Waiting for Minikube to be ready..."
sleep 20

# Install Calico network plugin
echo "Installing Calico..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Wait until Calico pods are ready
echo "Waiting for Calico pods to be ready..."

kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n kube-system --timeout=120s
kubectl wait --for=condition=Ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout=120s

# Show the status of all pods in kube-system
echo "Current status of pods in kube-system:"
kubectl get pods -n kube-system

echo "Minikube and Calico are installed and ready."