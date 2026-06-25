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

#Read configuration value from cluster-config.yaml file
REDIS_PASSWORD="$(yq -r '.redis.password' ./cluster-config.yaml)"

helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis \
  --reset-values \
  --namespace redis --create-namespace \
  --set auth.password="$REDIS_PASSWORD"
