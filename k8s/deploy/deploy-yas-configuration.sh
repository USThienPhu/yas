#!/bin/bash
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command helm
require_command yq

if ! yq --version | grep -qi "mikefarah\|version v4"; then
  echo "This script requires Mike Farah yq v4. Install from https://github.com/mikefarah/yq"
  exit 1
fi

DOMAIN=$(yq -r '.domain' ./cluster-config.yaml)
EXTERNAL_ACCESS_PORT=$(yq -r '.keycloak.externalAccessPort // 80' ./cluster-config.yaml)
KEYCLOAK_INTERNAL_URL=$(yq -r '.keycloak.internalBaseUrl // "http://keycloak-service.keycloak"' ./cluster-config.yaml)

external_url() {
  local host="$1"
  if [[ "$EXTERNAL_ACCESS_PORT" == "80" || "$EXTERNAL_ACCESS_PORT" == "null" ]]; then
    printf "http://%s" "$host"
  else
    printf "http://%s:%s" "$host" "$EXTERNAL_ACCESS_PORT"
  fi
}

IDENTITY_URL=$(external_url "identity.$DOMAIN")
API_URL=$(external_url "api.$DOMAIN")
STOREFRONT_URL=$(external_url "storefront.$DOMAIN")
KEYCLOAK_INTERNAL_REALM_URL="$KEYCLOAK_INTERNAL_URL/realms/Yas"

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--reset-values \
--namespace yas --create-namespace \
--set-string applicationConfig.spring.security.oauth2.resourceserver.jwt.issuer-uri="$IDENTITY_URL/realms/Yas" \
--set-string applicationConfig.spring.security.oauth2.resourceserver.jwt.jwk-set-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/certs" \
--set-string applicationConfig.springdoc.oauthflow.authorization-url="$IDENTITY_URL/realms/Yas/protocol/openid-connect/auth" \
--set-string applicationConfig.springdoc.oauthflow.token-url="$IDENTITY_URL/realms/Yas/protocol/openid-connect/token" \
--set-string backofficeBffExtraConfig.spring.security.oauth2.client.provider.keycloak.authorization-uri="$IDENTITY_URL/realms/Yas/protocol/openid-connect/auth" \
--set-string backofficeBffExtraConfig.spring.security.oauth2.client.provider.keycloak.token-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/token" \
--set-string backofficeBffExtraConfig.spring.security.oauth2.client.provider.keycloak.jwk-set-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/certs" \
--set-string backofficeBffExtraConfig.spring.security.oauth2.client.provider.keycloak.user-info-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/userinfo" \
--set-string storefrontBffExtraConfig.spring.security.oauth2.client.provider.keycloak.authorization-uri="$IDENTITY_URL/realms/Yas/protocol/openid-connect/auth" \
--set-string storefrontBffExtraConfig.spring.security.oauth2.client.provider.keycloak.token-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/token" \
--set-string storefrontBffExtraConfig.spring.security.oauth2.client.provider.keycloak.jwk-set-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/certs" \
--set-string storefrontBffExtraConfig.spring.security.oauth2.client.provider.keycloak.user-info-uri="$KEYCLOAK_INTERNAL_REALM_URL/protocol/openid-connect/userinfo" \
--set-string customerApplicationConfig.keycloak.auth-server-url="$KEYCLOAK_INTERNAL_URL" \
--set-string mediaApplicationConfig.yas.publicUrl="$API_URL/media" \
--set-string paymentPaypalApplicationConfig.yas.public.url="$STOREFRONT_URL/complete-payment"

