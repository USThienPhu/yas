#!/bin/bash
set -euo pipefail

section() {
  printf '\n==> %s\n' "$1"
}

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

section "Adding Helm repositories"
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add strimzi https://strimzi.io/charts/
helm repo add akhq https://akhq.io/
helm repo add elastic https://helm.elastic.co
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

section "Reading cluster configuration"
mapfile -t config_values < <(yq -r '.domain, .postgresql.replicas, .postgresql.username,
 .postgresql.password, .kafka.replicas, .kafka.storeSize, .zookeeper.replicas,
 .elasticsearch.replicas, .grafana.username, .grafana.password' ./cluster-config.yaml)
DOMAIN="${config_values[0]}"
POSTGRESQL_REPLICAS="${config_values[1]}"
POSTGRESQL_USERNAME="${config_values[2]}"
POSTGRESQL_PASSWORD="${config_values[3]}"
KAFKA_REPLICAS="${config_values[4]}"
KAFKA_STORE_SIZE="${config_values[5]}"
ZOOKEEPER_REPLICAS="${config_values[6]}"
ELASTICSEARCH_REPLICAS="${config_values[7]}"
GRAFANA_USERNAME="${config_values[8]}"
GRAFANA_PASSWORD="${config_values[9]}"

section "Installing PostgreSQL operator"
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
 --create-namespace --namespace postgres
kubectl rollout status deployment/postgres-operator -n postgres --timeout=180s
wait_for_crd postgresqls.acid.zalan.do

section "Installing PostgreSQL cluster"
helm upgrade --install postgres ./postgres/postgresql \
--create-namespace --namespace postgres \
--set replicas="$POSTGRESQL_REPLICAS" \
--set username="$POSTGRESQL_USERNAME" \
--set password="$POSTGRESQL_PASSWORD"

section "Installing pgAdmin"
helm upgrade --install pgadmin ./postgres/pgadmin \
--create-namespace --namespace postgres \
--set-string hostname="pgadmin.$DOMAIN" \
--set-string ingress.hosts[0].host="pgadmin.$DOMAIN"

section "Installing Strimzi Kafka operator"
helm upgrade --install kafka-operator strimzi/strimzi-kafka-operator \
--create-namespace --namespace kafka \
--version 0.47.0
kubectl rollout status deployment/strimzi-cluster-operator -n kafka --timeout=180s
wait_for_crd kafkas.kafka.strimzi.io
wait_for_crd kafkaconnects.kafka.strimzi.io
wait_for_crd kafkaconnectors.kafka.strimzi.io

section "Installing Kafka cluster"
helm upgrade --install kafka-cluster ./kafka/kafka-cluster \
--create-namespace --namespace kafka \
--set kafka.replicas="$KAFKA_REPLICAS" \
--set kafka.storeSize="$KAFKA_STORE_SIZE" \
--set zookeeper.replicas="$ZOOKEEPER_REPLICAS" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set debeziumConnect.enabled=false \
--set postgresqlConnector.enabled=false
kubectl wait --for=condition=Ready kafka/kafka-cluster -n kafka --timeout=600s

section "Installing Debezium Kafka Connect and PostgreSQL connector"
helm upgrade --install kafka-cluster ./kafka/kafka-cluster \
--create-namespace --namespace kafka \
--set kafka.replicas="$KAFKA_REPLICAS" \
--set kafka.storeSize="$KAFKA_STORE_SIZE" \
--set zookeeper.replicas="$ZOOKEEPER_REPLICAS" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set debeziumConnect.enabled=true \
--set postgresqlConnector.enabled=true
kubectl wait --for=condition=Ready kafkaconnect/debezium-connect-cluster -n kafka --timeout=300s

section "Installing AKHQ"
helm upgrade --install akhq akhq/akhq \
--create-namespace --namespace kafka \
--values ./kafka/akhq.values.yaml \
--set-string hostname="akhq.$DOMAIN" \
--set-string ingress.hosts[0]="akhq.$DOMAIN"

section "Installing Elastic operator"
helm upgrade --install elastic-operator elastic/eck-operator \
 --create-namespace --namespace elasticsearch
kubectl rollout status deployment/elastic-operator -n elasticsearch --timeout=180s
wait_for_crd elasticsearches.elasticsearch.k8s.elastic.co
wait_for_crd kibanas.kibana.k8s.elastic.co

section "Installing Elasticsearch and Kibana"
helm upgrade --install elasticsearch-cluster ./elasticsearch/elasticsearch-cluster \
--create-namespace --namespace elasticsearch \
--set elasticsearch.replicas="$ELASTICSEARCH_REPLICAS" \
--set kibana.ingress.hostname="kibana.$DOMAIN"

section "Installing Loki"
helm upgrade --install loki grafana/loki \
 --create-namespace --namespace observability \
 -f ./observability/loki.values.yaml \
 --set loki.useTestSchema=true

section "Installing Tempo"
helm upgrade --install tempo grafana/tempo \
--create-namespace --namespace observability \
-f ./observability/tempo.values.yaml

section "Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.0 \
  --set installCRDs=true \
  --set prometheus.enabled=false \
  --set webhook.timeoutSeconds=4 \
  --set admissionWebhooks.certManager.create=true
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=180s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=180s

section "Installing OpenTelemetry operator"
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
--create-namespace --namespace observability
kubectl rollout status deployment -l app.kubernetes.io/instance=opentelemetry-operator -n observability --timeout=180s
wait_for_crd opentelemetrycollectors.opentelemetry.io

section "Installing OpenTelemetry collector"
helm upgrade --install opentelemetry-collector ./observability/opentelemetry \
--create-namespace --namespace observability

section "Installing Promtail"
helm upgrade --install promtail grafana/promtail \
--create-namespace --namespace observability \
--values ./observability/promtail.values.yaml

section "Installing Prometheus and bundled Grafana"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
 --create-namespace --namespace observability \
-f ./observability/prometheus.values.yaml \
--set-string hostname="grafana.$DOMAIN" \
--set-string grafana.ingress.hosts[0]="grafana.$DOMAIN" \
--set-string grafana.grafana\\.ini.database.user="$POSTGRESQL_USERNAME" \
--set-string grafana.grafana\\.ini.database.password="$POSTGRESQL_PASSWORD" \
--set grafana.assertNoLeakedSecrets=false
wait_for_crd prometheuses.monitoring.coreos.com
wait_for_crd servicemonitors.monitoring.coreos.com
wait_for_crd podmonitors.monitoring.coreos.com
wait_for_crd alertmanagers.monitoring.coreos.com

section "Installing Grafana operator"
helm upgrade --install grafana-operator oci://ghcr.io/grafana-operator/helm-charts/grafana-operator \
--version v5.0.2 \
--create-namespace --namespace observability
kubectl rollout status deployment -l app.kubernetes.io/instance=grafana-operator -n observability --timeout=180s
wait_for_crd grafanas.grafana.integreatly.org
wait_for_crd grafanadashboards.grafana.integreatly.org
wait_for_crd grafanadatasources.grafana.integreatly.org

section "Installing Grafana dashboards and datasources"
helm upgrade --install grafana ./observability/grafana \
--create-namespace --namespace observability \
--set hostname="grafana.$DOMAIN" \
--set grafana.username="$GRAFANA_USERNAME" \
--set grafana.password="$GRAFANA_PASSWORD" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD"

section "Installing Zookeeper"
helm upgrade --install zookeeper ./zookeeper \
 --namespace zookeeper --create-namespace
