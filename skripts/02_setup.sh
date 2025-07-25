#!/bin/bash
set -euo pipefail

# === Ensure current context is Minikube ===
current_context=$(kubectl config current-context)

if [[ "$current_context" != "minikube" ]]; then
  echo "❌ Current Kubernetes context is '$current_context'."
  echo "Please switch to 'minikube' before running this script"
  exit 1
fi
# === Creating namespaces ===
echo "Creating namespaces..."
for ns in arc-runners platform bad-namespace; do
  kubectl get ns "$ns" &>/dev/null || kubectl create ns "$ns"
done

echo ""
echo "Deploying ncat-based echo servers..."

for ns in arc-runners platform bad-namespace; do
  pod_name="ncat-server"

  if ! kubectl get pod "$pod_name" -n "$ns" &>/dev/null; then
    kubectl run "$pod_name" \
      --image=alpine \
      -n "$ns" \
      --restart=Never \
      --command -- sh -c "apk add --no-cache nmap-ncat && ncat -l -p 1234 --keep-open --exec /bin/cat"
    echo "✅ Pod $pod_name created in $ns."
  else
    echo "Pod $pod_name already exists in $ns, skipping..."
  fi

  if ! kubectl get svc "$pod_name" -n "$ns" &>/dev/null; then
    kubectl expose pod "$pod_name" \
      --port=1234 \
      --target-port=1234 \
      --name="$pod_name" \
      -n "$ns"
    echo "✅ Service $pod_name exposed in $ns."
  else
    echo "Service $pod_name already exists in $ns, skipping..."
  fi
done

echo ""
echo "✅ All ncat servers deployed and services exposed."