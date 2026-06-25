#!/bin/bash
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

wait_for_crd() {
  kubectl wait --for=condition=Established "crd/$1" --timeout=120s
}

require_command helm
require_command kubectl
require_command yq

if ! yq --version | grep -qi "mikefarah\|version v4"; then
  echo "This script requires Mike Farah yq v4. Install from https://github.com/mikefarah/yq"
  exit 1
fi

#Read configuration value from cluster-config.yaml file
mapfile -t config_values < <(yq -r '.domain,
  .postgresql.username, .postgresql.password,
  .keycloak.bootstrapAdmin.username, .keycloak.bootstrapAdmin.password,
  .keycloak.backofficeRedirectUrl, .keycloak.storefrontRedirectUrl,
  .keycloak.externalAccessPort' ./cluster-config.yaml)
DOMAIN="${config_values[0]}"
POSTGRESQL_USERNAME="${config_values[1]}"
POSTGRESQL_PASSWORD="${config_values[2]}"
BOOTSTRAP_ADMIN_USERNAME="${config_values[3]}"
BOOTSTRAP_ADMIN_PASSWORD="${config_values[4]}"
KEYCLOAK_BACKOFFICE_REDIRECT_URL="${config_values[5]}"
KEYCLOAK_STOREFRONT_REDIRECT_URL="${config_values[6]}"
KEYCLOAK_EXTERNAL_ACCESS_PORT="${config_values[7]}"

#Install CRD keycloak
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n keycloak
wait_for_crd keycloaks.k8s.keycloak.org
wait_for_crd keycloakrealmimports.k8s.keycloak.org
kubectl rollout status deployment/keycloak-operator -n keycloak --timeout=180s

# Install keycloak
helm upgrade --install keycloak ./keycloak/keycloak \
--namespace keycloak \
--set hostname="identity.$DOMAIN" \
--set apiRedirectUrl="http://api.$DOMAIN" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set bootstrapAdmin.username="$BOOTSTRAP_ADMIN_USERNAME" \
--set bootstrapAdmin.password="$BOOTSTRAP_ADMIN_PASSWORD" \
--set backofficeRedirectUrl="$KEYCLOAK_BACKOFFICE_REDIRECT_URL" \
--set storefrontRedirectUrl="$KEYCLOAK_STOREFRONT_REDIRECT_URL" \
--set externalAccessPort="$KEYCLOAK_EXTERNAL_ACCESS_PORT"
kubectl wait --for=condition=Ready keycloak/keycloak -n keycloak --timeout=300s
