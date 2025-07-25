#!/bin/bash
set -euo pipefail


DEBUG=${DEBUG:-false}

# === Ensure current context is Minikube ===
current_context=$(kubectl config current-context)

if [[ "$current_context" != "minikube" ]]; then
  echo "❌ Current Kubernetes context is '$current_context'."
  echo "Please switch to 'minikube' before running this script"
  exit 1
fi

NAMESPACES=("arc-runners" "platform" "bad-namespace")

EXPECTED_FAILURES=(
  test-bad-to-arc
  test-arc-to-platform
  test-arc-to-bad
)
kubectl apply -f ../templates/arc-runners.yaml

# === Step 1: Wait for pods to be ready ===
echo "⏳ Waiting for pods to be ready..."
for ns in "${NAMESPACES[@]}"; do
  kubectl wait --for=condition=Ready pod/ncat-server -n "$ns" --timeout=60s || echo "⚠️ Pod not ready in $ns"
done

# === Step 2: Test connectivity ===
function test_connectivity() {
  local from_ns="$1"
  local target_host="$2"
  local test_name="$3"
  local port="${4:-1234}"  # use 1234 if not provided

  echo -e "\nTesting [$from_ns] → [$target_host:$port] ($test_name)"

  kubectl run "$test_name" \
    --restart=Never \
    --image=alpine \
    -n "$from_ns" \
    --labels="run=test" \
    --command -- sh -c "apk add --no-cache busybox-extras && nc -z -w 3 $target_host $port && echo CONNECTED || echo FAILED" || true

  sleep 5

  local log_output
  log_output=$(kubectl logs "$test_name" -n "$from_ns" 2>&1 || echo "")

  $DEBUG && echo -e "📄 Logs from [$test_name] in [$from_ns]:\n--------------------------------------\n$log_output\n--------------------------------------"

  local expected_fail="false"
  for expected in "${EXPECTED_FAILURES[@]}"; do
    if [[ "$test_name" == "$expected" ]]; then
      expected_fail="true"
      break
    fi
  done

  if echo "$log_output" | grep -q "CONNECTED"; then
    if [[ "$expected_fail" == "true" ]]; then
      echo "❌ $test_name: UNEXPECTED SUCCESS — was expected to fail"
    else
      echo "✅ $test_name: SUCCESS"
    fi
  else
    if [[ "$expected_fail" == "true" ]]; then
      echo "✅ $test_name: FAILED as expected (policy enforced)"
    else
      echo "❌ $test_name: FAILED"
    fi
  fi
 }

echo ""
echo "🔍 Running connectivity tests..."

test_connectivity platform ncat-server.arc-runners.svc.cluster.local test-platform-to-arc
test_connectivity bad-namespace ncat-server.arc-runners.svc.cluster.local test-bad-to-arc
test_connectivity arc-runners ncat-server.platform.svc.cluster.local test-arc-to-platform
test_connectivity arc-runners ncat-server.bad-namespace.svc.cluster.local test-arc-to-bad
test_connectivity arc-runners ncat-server.arc-runners.svc.cluster.local test-arc-to-itself
test_connectivity bad-namespace ncat-server.platform.svc.cluster.local test-bad-to-platform
test_connectivity arc-runners google.com test-arc-to-google 443

# === Step 3: Cleanup test pods ===
echo ""
echo "Cleaning up test pods..."
TEST_PODS=(
  test-platform-to-arc
  test-bad-to-arc
  test-arc-to-platform
  test-arc-to-bad
  test-arc-to-itself
  test-bad-to-platform
  test-arc-to-google
)

for pod in "${TEST_PODS[@]}"; do
  for ns in "${NAMESPACES[@]}"; do
    kubectl delete pod "$pod" -n "$ns" --ignore-not-found &
  done
done

sleep 5
echo "✅ All tests completed."
