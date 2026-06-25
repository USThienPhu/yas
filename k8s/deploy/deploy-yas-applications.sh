#!/bin/bash
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command helm
require_command kubectl
require_command yq

if ! yq --version | grep -qi "mikefarah\|version v4"; then
  echo "This script requires Mike Farah yq v4. Install from https://github.com/mikefarah/yq"
  exit 1
fi

if ! kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  echo "Missing ServiceMonitor CRD. Run ./setup-cluster.sh successfully before deploying YAS applications."
  exit 1
fi

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

DOMAIN="$(yq -r '.domain' ./cluster-config.yaml)"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace yas --create-namespace

helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="backoffice.$DOMAIN"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace yas --create-namespace

sleep 60

helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace yas --create-namespace \
--set backend.ingress.host="storefront.$DOMAIN"

sleep 60

helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace yas --create-namespace \
--set ingress.host="api.$DOMAIN"

sleep 20

for chart in {"product","cart","order","customer","inventory","tax","media","search","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace yas --create-namespace \
    --set backend.ingress.host="api.$DOMAIN"
    sleep 60
done
