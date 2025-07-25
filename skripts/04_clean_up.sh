#!/bin/bash

set -e

echo "Deleting custom namespaces..."

for ns in arc-runners platform bad-namespace; do
  echo "Deleting namespace: $ns"
  kubectl delete namespace "$ns" || echo "Failed to delete $ns or it doesn't exist."
done

echo "All specified namespaces deleted (or skipped if not present)."
