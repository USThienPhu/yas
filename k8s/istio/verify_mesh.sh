#!/bin/bash
set -euo pipefail

echo "=== Istio Service Mesh Verification Script ==="

echo "1. Checking Pod Status in yas namespace..."
kubectl get pods -n yas -o wide

echo ""
echo "2. Checking PeerAuthentication (mTLS) configuration..."
kubectl get peerauthentication -n yas

echo ""
echo "3. Testing Authorization Policy..."
echo "  - Running request from test-pod (default SA - denied)..."
DENIED_CODE=$(kubectl exec -n yas test-pod -c test-pod -- curl -s -o /dev/null -w "%{http_code}" http://product/ || true)
echo "    Response code: $DENIED_CODE (Expected: 403)"

echo "  - Running request from test-pod-allowed (storefront-bff SA - allowed)..."
ALLOWED_CODE=$(kubectl exec -n yas test-pod-allowed -c test-pod-allowed -- curl -s -o /dev/null -w "%{http_code}" http://product/ || true)
echo "    Response code: $ALLOWED_CODE (Expected: 200/401/404)"

echo "4. Testing Retry Policy configuration..."
kubectl get virtualservice product-retry -n yas -o jsonpath='{.spec.http[0].retries}'
echo ""
echo "=== Verification complete! ==="

