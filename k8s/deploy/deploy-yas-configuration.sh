#!/bin/bash
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command helm

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace yas --create-namespace

