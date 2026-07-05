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

echo ""
echo "4. Testing Traffic Splitting (80/20 split between Product V1 and V2)..."
echo "  - Sending 50 requests to http://product/ from test-pod-allowed..."
V1_COUNT=0
V2_COUNT=0
for i in {1..50}; do
  RESPONSE=$(kubectl exec -n yas test-pod-allowed -c test-pod-allowed -- curl -s http://product/ || true)
  if [[ "$RESPONSE" == *"Hello from Product V2"* ]]; then
    V2_COUNT=$((V2_COUNT+1))
    echo "    Request #$i: Product V2 (Mock)"
  else
    V1_COUNT=$((V1_COUNT+1))
    echo "    Request #$i: Product V1 (Spring Boot)"
  fi
done
echo "  - Summary:"
echo "    Product V1 (Spring Boot) Hits: $V1_COUNT / 50"
echo "    Product V2 (Mock Nginx) Hits: $V2_COUNT / 50"

echo ""
echo "5. Testing Retry Policy configuration..."
kubectl get virtualservice product -n yas -o jsonpath='{.spec.http[0].retries}'
echo ""
echo "=== Verification complete! ==="
