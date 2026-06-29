# 🚀 YAS DevOps – K8s Implementation Plan
> **Project:** Yet Another Shop (YAS) – Đồ án 2: Xây dựng hệ thống CD  
> **Author:** DevOps Mentor Guide  
> **Last Updated:** 2026-06-29  
> **Stack:** GCP VM · Kubernetes · Helm · Argo CD · Istio · Jenkins

---

## 📋 Table of Contents
1. [Current State Assessment](#1-current-state-assessment)
2. [Phase 2 – Kubernetes (Core)](#2-phase-2--kubernetes-core)
3. [Phase 3 – Helm + Argo CD](#3-phase-3--helm--argo-cd)
4. [Phase 4 – Service Mesh (Istio)](#4-phase-4--service-mesh-istio)
5. [Jenkins CD Jobs](#5-jenkins-cd-jobs)
6. [Verification Checklist](#6-verification-checklist)
7. [File Structure](#7-file-structure)

---

## 1. Current State Assessment

### ✅ Already Done
| Component | Status | Notes |
|-----------|--------|-------|
| Jenkins pipeline | ✅ Done | `Jenkinsfile` builds & pushes Docker image |
| Docker Hub push | ✅ Done | Image tagged with `latest` + `BUILD_NUMBER` |
| K8s cluster | ✅ Done | GCP VM with master + worker node |
| Helm charts | ✅ Done | `k8s/charts/` has all microservice charts |
| Deploy scripts | ✅ Done | `deploy-yas-applications.sh` deploys to `yas` ns |
| Infrastructure | ✅ Done | Postgres, Kafka, Keycloak, Elasticsearch deployed |

### ❌ Gap Analysis vs Requirements
| Requirement | Status | Action Needed |
|-------------|--------|---------------|
| Pods Running & services reachable | 🔴 Verify | Confirm all pods healthy in `yas` namespace |
| NodePort / accessible from outside | 🔴 Missing | Expose key services via NodePort |
| `/etc/hosts` domain config | 🔴 Document | Provide worker node IP + domain mapping |
| `developer_build` Jenkins job | 🔴 Missing | Create parameterized Jenkins pipeline |
| Cleanup Jenkins job | 🔴 Missing | Create tear-down Jenkins job |
| Helm `install/upgrade` working | 🟡 Partial | Charts exist; verify `helm upgrade` works |
| Argo CD Application | 🔴 Missing | Install ArgoCD, create Application CRD |
| GitOps folder | 🔴 Missing | Create `gitops/` folder with Helm value overrides |
| Argo CD tracks Helm chart | 🔴 Missing | Point ArgoCD App to `k8s/charts/` |
| Istio sidecar injection | 🔴 Missing | Install Istio, label `yas` namespace |
| mTLS PeerAuthentication | 🔴 Missing | Create YAML manifests |
| AuthorizationPolicy | 🔴 Missing | Service-to-service allow list |
| VirtualService retry policy | 🔴 Missing | Retry on 500 errors |
| Kiali topology | 🔴 Missing | Install Kiali, take screenshot |

---

## 2. Phase 2 – Kubernetes (Core)

> **Goal:** Pods Running, Service reachable from outside cluster via NodePort

### 2.1 Verify All Pods Healthy

```bash
# SSH into master node
kubectl get pods -n yas
kubectl get pods -n postgres
kubectl get pods -n kafka
kubectl get pods -n keycloak
kubectl get pods -n elasticsearch
```

All pods must show `Running` or `Completed`. If any are in `CrashLoopBackOff`, check logs:
```bash
kubectl logs -n yas <pod-name> --previous
kubectl describe pod -n yas <pod-name>
```

### 2.2 Expose Services via NodePort

The requirement says: **"provide domain:port (NodePort) so developer can test"**

Currently all services use `ClusterIP`. We need to expose at minimum:
- `storefront-bff` (frontend BFF)
- `backoffice-bff` (admin BFF)
- `identity` / `keycloak` (auth)

**Action:** Create `k8s/deploy/nodeport-services.yaml`:

```yaml
---
# Storefront BFF – NodePort 30080
apiVersion: v1
kind: Service
metadata:
  name: storefront-nodeport
  namespace: yas
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: storefront-bff
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080

---
# Backoffice BFF – NodePort 30081
apiVersion: v1
kind: Service
metadata:
  name: backoffice-nodeport
  namespace: yas
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: backoffice-bff
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30081

---
# API (product as example) – NodePort 30082
apiVersion: v1
kind: Service
metadata:
  name: api-nodeport
  namespace: yas
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: product
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30082
```

Apply it:
```bash
kubectl apply -f k8s/deploy/nodeport-services.yaml
```

### 2.3 Get Worker Node IP

```bash
# Get all node IPs
kubectl get nodes -o wide
```

Note the `EXTERNAL-IP` of the **worker** node (not the master). Example: `34.123.45.67`

> If running on GCP VM, the external IP is the VM's external IP. Make sure port `30080-30090` are open in GCP firewall rules.

### 2.4 Developer /etc/hosts Setup

Provide the following to each developer (replace `<WORKER_IP>` with actual worker node external IP):

```
# Windows: C:\Windows\System32\drivers\etc\hosts
# Linux/Mac: /etc/hosts
<WORKER_IP>  storefront.yas.local.com
<WORKER_IP>  backoffice.yas.local.com
<WORKER_IP>  identity.yas.local.com
<WORKER_IP>  api.yas.local.com
```

Access via:
- **Storefront:** `http://storefront.yas.local.com:30080`
- **Backoffice:** `http://backoffice.yas.local.com:30081`
- **API docs:** `http://api.yas.local.com:30082`

### 2.5 Open GCP Firewall Ports

```bash
# Allow NodePort range from anywhere (for developer testing)
gcloud compute firewall-rules create yas-nodeport \
  --allow tcp:30080-30090 \
  --target-tags=<YOUR_VM_TAG> \
  --description="YAS K8s NodePort access"
```

---

## 3. Phase 3 – Helm + Argo CD

> **Goal:** `helm install/upgrade` works, Argo CD app is Healthy & Synced, GitOps demo

### 3.1 Verify Helm Charts Work

```bash
# Dry run first
helm upgrade --install product k8s/charts/product \
  --namespace yas --dry-run

# Real deploy with custom image tag
helm upgrade --install product k8s/charts/product \
  --namespace yas \
  --set backend.image.tag=latest

# List all releases
helm list -n yas
```

### 3.2 Install Argo CD

```bash
# Create namespace
kubectl create namespace argocd

# Install stable Argo CD
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods
kubectl wait --for=condition=Ready pod \
  --all -n argocd --timeout=180s

# Expose UI as NodePort
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 30090, "name": "https"}]}}'
```

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```

Access ArgoCD UI: `https://<WORKER_IP>:30090`  
Login: `admin` / `<password from above>`

### 3.3 Create GitOps Folder Structure

Create the `gitops/` directory at the repo root. This is the **source of truth** that ArgoCD watches:

```
gitops/
├── dev/
│   ├── product-values.yaml
│   ├── cart-values.yaml
│   ├── order-values.yaml
│   ├── customer-values.yaml
│   ├── inventory-values.yaml
│   ├── tax-values.yaml
│   ├── media-values.yaml
│   └── search-values.yaml
├── staging/
│   ├── product-values.yaml
│   └── ...
└── argocd/
    ├── yas-dev-app.yaml
    └── yas-staging-app.yaml
```

**Example `gitops/dev/product-values.yaml`:**
```yaml
# GitOps values for product service in dev environment
backend:
  image:
    repository: thaithienphu/product
    tag: latest        # Jenkins CI overwrites this with commit SHA
  ingress:
    enabled: true
    host: api.yas.local.com
```

**Example `gitops/staging/product-values.yaml`:**
```yaml
# GitOps values for product service in staging environment
backend:
  image:
    repository: thaithienphu/product
    tag: v1.0.0        # Only stable release tags go here
  ingress:
    enabled: true
    host: api.yas.local.com
  replicaCount: 2       # More replicas in staging
```

### 3.4 Create ArgoCD Application Manifests

**`gitops/argocd/yas-dev-app.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-product-dev
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_ORG>/yas.git
    targetRevision: main
    path: k8s/charts/product
    helm:
      valueFiles:
        - ../../../gitops/dev/product-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true        # Remove orphaned resources
      selfHeal: true     # Revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**`gitops/argocd/yas-staging-app.yaml`:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-product-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_ORG>/yas.git
    targetRevision: main
    path: k8s/charts/product
    helm:
      valueFiles:
        - ../../../gitops/staging/product-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 3.5 Apply ArgoCD Applications

```bash
# Apply all ArgoCD apps
kubectl apply -f gitops/argocd/yas-dev-app.yaml
kubectl apply -f gitops/argocd/yas-staging-app.yaml

# Check status via CLI
argocd app list
argocd app get yas-product-dev

# Manually trigger sync if needed
argocd app sync yas-product-dev
```

### 3.6 Demo: GitOps Auto-Sync Flow

**How to demonstrate for assessment:**

1. Jenkins CI pipeline runs on branch `main`
2. Builds image → pushes `thaithienphu/product:abc1234` to Docker Hub
3. Jenkins then updates `gitops/dev/product-values.yaml`:
   ```bash
   sed -i "s/tag: .*/tag: abc1234/" gitops/dev/product-values.yaml
   git add gitops/dev/product-values.yaml
   git commit -m "ci: update product image to abc1234"
   git push origin main
   ```
4. Argo CD detects the commit → triggers sync automatically
5. New pod with `abc1234` image starts, old pod terminated
6. ArgoCD UI shows: **Healthy** ✅ **Synced** ✅

---

## 4. Phase 4 – Service Mesh (Istio)

> **Goal:** mTLS enforced, retry policy active, AuthorizationPolicy restricts traffic, Kiali shows topology

### 4.1 Install Istio

```bash
# Download istioctl (run on K8s master node)
curl -L https://istio.io/downloadIstio | sh -
cd istio-1.*/
export PATH=$PWD/bin:$PATH

# Install with demo profile (includes Kiali, Prometheus, Grafana, Jaeger)
istioctl install --set profile=demo -y

# Verify installation
kubectl get pods -n istio-system
istioctl verify-install
```

### 4.2 Enable Sidecar Injection for `yas` namespace

```bash
# Label the namespace to auto-inject Envoy sidecars
kubectl label namespace yas istio-injection=enabled

# Verify label
kubectl get namespace yas --show-labels

# Restart all deployments to inject sidecars
kubectl rollout restart deployment -n yas

# Verify pods show 2/2 (app container + envoy proxy)
kubectl get pods -n yas
# Expected: product-xxx-xxx  2/2  Running
```

### 4.3 Install Kiali + Observability Add-ons

```bash
# Install Kiali, Prometheus, Grafana, Jaeger from Istio samples
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Wait for Kiali
kubectl rollout status deployment/kiali -n istio-system

# Expose Kiali as NodePort
kubectl patch svc kiali -n istio-system \
  -p '{"spec": {"type": "NodePort"}}'

kubectl get svc kiali -n istio-system
# Note NodePort number (e.g., 20001:32XXX/TCP)
# Access at: http://<WORKER_IP>:<nodePort>
```

### 4.4 Configure mTLS (PeerAuthentication)

**File:** `k8s/service-mesh/peer-authentication.yaml`

```yaml
# Enable STRICT mTLS for the entire yas namespace
# All inter-service traffic MUST use TLS mutual authentication
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: yas
spec:
  mtls:
    mode: STRICT
```

```bash
kubectl apply -f k8s/service-mesh/peer-authentication.yaml

# Verify
kubectl get peerauthentication -n yas
```

### 4.5 Configure DestinationRule (mTLS client-side policy)

**File:** `k8s/service-mesh/destination-rules.yaml`

```yaml
# Tell Istio sidecar to use MUTUAL TLS when calling services in yas namespace
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: yas-mtls
  namespace: yas
spec:
  host: "*.yas.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

```bash
kubectl apply -f k8s/service-mesh/destination-rules.yaml
kubectl get destinationrule -n yas
```

### 4.6 Configure AuthorizationPolicy

**File:** `k8s/service-mesh/authorization-policies.yaml`

```yaml
# Step 1: DENY ALL traffic by default in yas namespace
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: yas
spec: {}

---
# Step 2: Allow specific service-to-service communications

# Allow order service to call product service (GET/POST)
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-order-to-product
  namespace: yas
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: product
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/yas/sa/order"
      to:
        - operation:
            methods: ["GET", "POST", "PUT"]

---
# Allow cart service to call product service (read-only)
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-cart-to-product
  namespace: yas
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: product
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/yas/sa/cart"
      to:
        - operation:
            methods: ["GET"]

---
# Allow ingress gateway to reach all BFF services
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-ingress-to-storefront-bff
  namespace: yas
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: storefront-bff
  rules:
    - from:
        - source:
            namespaces: ["istio-system"]

---
# Allow health checks from kubelet (for liveness/readiness probes)
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-health-checks
  namespace: yas
spec:
  rules:
    - to:
        - operation:
            paths: ["/actuator/health/*"]
```

```bash
kubectl apply -f k8s/service-mesh/authorization-policies.yaml
kubectl get authorizationpolicy -n yas
```

### 4.7 Configure VirtualService (Retry Policy)

**File:** `k8s/service-mesh/virtual-services.yaml`

```yaml
# Retry policy for product service
# If product returns 5xx, retry up to 3 times
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: product-vs
  namespace: yas
spec:
  hosts:
    - product
  http:
    - retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: "5xx,gateway-error,connect-failure,retriable-4xx"
      timeout: 20s
      route:
        - destination:
            host: product
            port:
              number: 80

---
# Retry policy for order service
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: order-vs
  namespace: yas
spec:
  hosts:
    - order
  http:
    - retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: "5xx,gateway-error,connect-failure"
      timeout: 20s
      route:
        - destination:
            host: order
            port:
              number: 80

---
# Retry policy for cart service
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: cart-vs
  namespace: yas
spec:
  hosts:
    - cart
  http:
    - retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: "5xx,gateway-error,connect-failure"
      timeout: 20s
      route:
        - destination:
            host: cart
            port:
              number: 80
```

```bash
kubectl apply -f k8s/service-mesh/virtual-services.yaml
kubectl get virtualservice -n yas
```

### 4.8 Configure Istio Gateway (External Ingress)

**File:** `k8s/service-mesh/gateway.yaml`

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: yas-gateway
  namespace: yas
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "storefront.yas.local.com"
        - "backoffice.yas.local.com"
        - "api.yas.local.com"

---
# Route storefront traffic through gateway
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: storefront-gateway-vs
  namespace: yas
spec:
  hosts:
    - "storefront.yas.local.com"
  gateways:
    - yas-gateway
  http:
    - route:
        - destination:
            host: storefront-bff
            port:
              number: 80

---
# Route backoffice traffic through gateway
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: backoffice-gateway-vs
  namespace: yas
spec:
  hosts:
    - "backoffice.yas.local.com"
  gateways:
    - yas-gateway
  http:
    - route:
        - destination:
            host: backoffice-bff
            port:
              number: 80
```

```bash
kubectl apply -f k8s/service-mesh/gateway.yaml

# Get Istio ingress gateway external IP/port
kubectl get svc istio-ingressgateway -n istio-system
```

### 4.9 Test Scenarios

#### Test 1: mTLS – Verify Certificates
```bash
# Check that Envoy sidecar has TLS certificates issued by Istio CA
istioctl proxy-config secret deploy/product -n yas
# Look for: ACTIVE cert with CN matching Istio CA
```

#### Test 2: Allowed Communication (should SUCCEED)
```bash
# order -> product: should return 200 (allowed by AuthorizationPolicy)
kubectl exec -n yas deploy/order -- \
  curl -s -o /dev/null -w "%{http_code}" http://product/actuator/health
# Expected output: 200
```

#### Test 3: Denied Communication (should be BLOCKED)
```bash
# From a test pod (no service account in allow list) -> product: should be REJECTED
kubectl run test-pod \
  --image=curlimages/curl:latest \
  --namespace=yas \
  --restart=Never \
  --rm -it \
  -- curl -v http://product.yas.svc.cluster.local/actuator/health
# Expected: RBAC: access denied  OR  connection reset
```

#### Test 4: Retry Policy Evidence
```bash
# Scale product to 0 replicas (simulate failure)
kubectl scale deploy product -n yas --replicas=0

# From cart, try to call product (should see retries in logs)
kubectl exec -n yas deploy/cart -- \
  curl -v http://product/actuator/health

# Check Envoy proxy logs for retry attempts
kubectl logs -n yas deploy/cart -c istio-proxy | grep "retry"

# Restore
kubectl scale deploy product -n yas --replicas=1
```

---

## 5. Jenkins CD Jobs

### 5.1 Add Kubeconfig Credential to Jenkins

**On K8s master node:**
```bash
cat ~/.kube/config
# Copy the entire content
```

**In Jenkins UI:**
1. Navigate to: `Manage Jenkins → Credentials → System → Global credentials`
2. Click `Add Credentials`
3. Kind: **Secret file**
4. Upload the `~/.kube/config` file
5. ID: `kubeconfig-credentials`
6. Description: `K8s cluster kubeconfig`

### 5.2 `developer_build` Jenkins Job

Create a new **Pipeline** job in Jenkins named `developer_build`.

**Create file `k8s/jenkins/Jenkinsfile.developer_build`:**

```groovy
pipeline {
  agent any

  parameters {
    choice(
      name: 'SERVICE_NAME',
      choices: [
        'product', 'cart', 'order', 'customer',
        'inventory', 'tax', 'media', 'search',
        'storefront-bff', 'backoffice-bff'
      ],
      description: '🔧 Select the service to deploy from your dev branch'
    )
    string(
      name: 'DEV_BRANCH',
      defaultValue: 'main',
      description: '🌿 Dev branch name (e.g. dev_tax_service). Other services stay on main/latest.'
    )
  }

  environment {
    DOCKER_HUB_USER  = 'thaithienphu'
    K8S_NAMESPACE    = 'yas'
    KUBECONFIG_CREDS = 'kubeconfig-credentials'
  }

  stages {
    stage('Resolve Image Tag') {
      steps {
        script {
          // Use branch name as tag, or 'latest' for main
          env.IMAGE_TAG = (params.DEV_BRANCH.trim() == 'main') \
            ? 'latest' \
            : params.DEV_BRANCH.trim().replace('/', '-')
          echo "🏷️  Image tag resolved: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Deploy Service') {
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDS, variable: 'KUBECONFIG')]) {
          script {
            def chartPath = "k8s/charts/${params.SERVICE_NAME}"
            sh """
              echo "🚀 Deploying ${params.SERVICE_NAME}:${env.IMAGE_TAG} to namespace ${env.K8S_NAMESPACE}"
              helm upgrade --install ${params.SERVICE_NAME} ${chartPath} \\
                --namespace ${env.K8S_NAMESPACE} \\
                --create-namespace \\
                --reset-values \\
                --set backend.image.repository=${env.DOCKER_HUB_USER}/${params.SERVICE_NAME} \\
                --set backend.image.tag=${env.IMAGE_TAG} \\
                --set backend.ingress.host=api.yas.local.com \\
                --wait --timeout 5m
            """
          }
        }
      }
    }

    stage('Print Developer Access Info') {
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDS, variable: 'KUBECONFIG')]) {
          script {
            def workerIp = sh(
              script: """kubectl get nodes \\
                --selector='!node-role.kubernetes.io/control-plane' \\
                -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'""",
              returnStdout: true
            ).trim()

            echo """
╔══════════════════════════════════════════════════════════╗
║            ✅ DEPLOYMENT COMPLETE                        ║
╠══════════════════════════════════════════════════════════╣
║  Service:  ${params.SERVICE_NAME}
║  Tag:      ${env.IMAGE_TAG}
║  Branch:   ${params.DEV_BRANCH}
╠══════════════════════════════════════════════════════════╣
║  Add to your /etc/hosts:
║    ${workerIp}  storefront.yas.local.com
║    ${workerIp}  backoffice.yas.local.com
║    ${workerIp}  api.yas.local.com
╠══════════════════════════════════════════════════════════╣
║  Access URLs:
║    Storefront:  http://storefront.yas.local.com:30080
║    Backoffice:  http://backoffice.yas.local.com:30081
║    API:         http://api.yas.local.com:30082
╚══════════════════════════════════════════════════════════╝
            """
          }
        }
      }
    }
  }

  post {
    success {
      echo "✅ ${params.SERVICE_NAME} (${env.IMAGE_TAG}) deployed successfully to namespace ${env.K8S_NAMESPACE}"
    }
    failure {
      echo "❌ Deployment failed for ${params.SERVICE_NAME}. Check Console Output above."
    }
  }
}
```

**Jenkins Job Configuration:**
- Job Type: **Pipeline**
- Pipeline Definition: **Pipeline script from SCM**
- SCM: **Git** → your repo URL
- Script Path: `k8s/jenkins/Jenkinsfile.developer_build`

### 5.3 `cleanup_deployment` Jenkins Job

Create a new **Pipeline** job named `cleanup_deployment`.

**Create file `k8s/jenkins/Jenkinsfile.cleanup`:**

```groovy
pipeline {
  agent any

  parameters {
    choice(
      name: 'SERVICE_NAME',
      choices: [
        'product', 'cart', 'order', 'customer',
        'inventory', 'tax', 'media', 'search',
        'storefront-bff', 'backoffice-bff',
        'ALL_YAS_SERVICES'
      ],
      description: '🗑️  Select service to remove (ALL_YAS_SERVICES = remove entire yas namespace)'
    )
  }

  environment {
    K8S_NAMESPACE    = 'yas'
    KUBECONFIG_CREDS = 'kubeconfig-credentials'
  }

  stages {
    stage('Confirm Cleanup') {
      steps {
        script {
          echo "⚠️  About to remove: ${params.SERVICE_NAME} from namespace ${env.K8S_NAMESPACE}"
        }
      }
    }

    stage('Remove Deployment') {
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDS, variable: 'KUBECONFIG')]) {
          script {
            if (params.SERVICE_NAME == 'ALL_YAS_SERVICES') {
              sh """
                echo "🧨 Removing all YAS services (helm uninstall all releases in yas ns)..."
                helm list -n ${env.K8S_NAMESPACE} -q | xargs -r -I{} helm uninstall {} -n ${env.K8S_NAMESPACE}
                echo "✅ All Helm releases removed from ${env.K8S_NAMESPACE}"
              """
            } else {
              sh """
                echo "🗑️  Uninstalling ${params.SERVICE_NAME}..."
                helm uninstall ${params.SERVICE_NAME} -n ${env.K8S_NAMESPACE} || true
                echo "✅ ${params.SERVICE_NAME} removed from ${env.K8S_NAMESPACE}"
              """
            }
          }
        }
      }
    }

    stage('Verify Removal') {
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDS, variable: 'KUBECONFIG')]) {
          sh "helm list -n ${env.K8S_NAMESPACE}"
          sh "kubectl get pods -n ${env.K8S_NAMESPACE}"
        }
      }
    }
  }

  post {
    success { echo "🗑️  Cleanup complete for: ${params.SERVICE_NAME}" }
    failure { echo "❌ Cleanup failed. Check Console Output." }
  }
}
```

---

## 6. Verification Checklist

### Phase 2 – Kubernetes (Core) ✅
- [ ] `kubectl get pods -n yas` → all pods in `Running` state
- [ ] `kubectl get svc -n yas` → NodePort services visible
- [ ] `curl http://<WORKER_IP>:30080` → storefront UI responds (HTTP 200)
- [ ] `/etc/hosts` documented for developer use
- [ ] GCP firewall rule allows ports 30080-30090

### Phase 3 – Helm + Argo CD ✅
- [ ] `helm upgrade --install product k8s/charts/product -n yas` → success
- [ ] `helm list -n yas` → all releases show `deployed`
- [ ] Argo CD UI accessible at `https://<WORKER_IP>:30090`
- [ ] `argocd app list` → App shows `Synced`
- [ ] `argocd app get yas-product-dev` → `Health: Healthy`
- [ ] Change `gitops/dev/product-values.yaml` image tag → ArgoCD detects and syncs
- [ ] New pod with updated image tag starts automatically

### Phase 4 – Service Mesh (Istio) ✅
- [ ] `kubectl get pods -n yas` → all pods show `2/2` containers (sidecar injected)
- [ ] `kubectl get pods -n istio-system` → all Istio components `Running`
- [ ] Kiali UI accessible and shows service topology graph
- [ ] `kubectl get peerauthentication -n yas` → `default` policy present
- [ ] mTLS test: allowed pod calls product → HTTP 200
- [ ] mTLS test: unauthorized pod calls product → `RBAC: access denied`
- [ ] `kubectl get virtualservice -n yas` → retry policies present
- [ ] Retry test: product scaled to 0 → caller sees retry attempt logs

### Jenkins Jobs ✅
- [ ] `developer_build` job appears in Jenkins UI
- [ ] Job has `SERVICE_NAME` and `DEV_BRANCH` parameters
- [ ] Running job deploys correct image to `yas` namespace
- [ ] Console output shows access URLs with worker node IP
- [ ] `cleanup_deployment` job removes Helm release successfully

---

## 7. File Structure

After implementation, the repo will have:

```
yas/
├── Jenkinsfile                          ← existing CI job
├── k8s/
│   ├── charts/                          ← existing Helm charts
│   │   ├── backend/
│   │   ├── product/
│   │   ├── cart/
│   │   └── ...
│   ├── deploy/                          ← existing deploy scripts
│   │   ├── deploy-yas-applications.sh
│   │   ├── setup-cluster.sh
│   │   └── nodeport-services.yaml       ← NEW
│   ├── service-mesh/                    ← NEW: Istio configs
│   │   ├── peer-authentication.yaml
│   │   ├── destination-rules.yaml
│   │   ├── authorization-policies.yaml
│   │   ├── virtual-services.yaml
│   │   └── gateway.yaml
│   ├── jenkins/                         ← NEW: Jenkins Jenkinsfiles
│   │   ├── Jenkinsfile.developer_build
│   │   └── Jenkinsfile.cleanup
│   └── DEVOPS_PLAN.md                  ← This document
└── gitops/                              ← NEW: GitOps source of truth
    ├── dev/
    │   ├── product-values.yaml
    │   ├── cart-values.yaml
    │   ├── order-values.yaml
    │   ├── customer-values.yaml
    │   ├── inventory-values.yaml
    │   ├── tax-values.yaml
    │   ├── media-values.yaml
    │   └── search-values.yaml
    ├── staging/
    │   └── product-values.yaml
    └── argocd/
        ├── yas-dev-app.yaml
        └── yas-staging-app.yaml
```

---

## 🎯 Execution Order

```
📅 Day 1 (Now):
  [1] Verify all pods healthy: kubectl get pods -n yas
  [2] Create k8s/deploy/nodeport-services.yaml
  [3] Open GCP firewall ports 30080-30090
  [4] Test access: curl http://<WORKER_IP>:30080
  [5] Add kubeconfig to Jenkins credentials

📅 Day 2:
  [6] Create k8s/jenkins/Jenkinsfile.developer_build
  [7] Create k8s/jenkins/Jenkinsfile.cleanup
  [8] Create Jenkins jobs pointing to those files
  [9] Test developer_build job end-to-end

📅 Day 3-4:
  [10] Install ArgoCD on cluster
  [11] Create gitops/ folder structure with value files
  [12] Create gitops/argocd/*.yaml Application manifests
  [13] Apply ArgoCD Applications
  [14] Demo GitOps: change image tag → auto-sync

📅 Day 5-7:
  [15] Install Istio with demo profile
  [16] Label yas namespace + restart pods for sidecar injection
  [17] Install Kiali + observability add-ons
  [18] Apply peer-authentication.yaml (mTLS)
  [19] Apply destination-rules.yaml
  [20] Apply authorization-policies.yaml
  [21] Apply virtual-services.yaml (retry policy)
  [22] Run all test scenarios, collect evidence
  [23] Screenshot Kiali topology
```

---

## 📝 Quick Reference Commands

```bash
# ─── Kubernetes Status ───────────────────────────────────────────────────────
kubectl get pods,svc,ingress -n yas
kubectl get pods -n argocd
kubectl get pods -n istio-system
kubectl top pods -n yas

# ─── Helm ────────────────────────────────────────────────────────────────────
helm list -n yas
helm history product -n yas
helm upgrade --install product k8s/charts/product -n yas --set backend.image.tag=latest

# ─── Argo CD ─────────────────────────────────────────────────────────────────
argocd app list
argocd app sync yas-product-dev
argocd app get yas-product-dev

# ─── Istio / Service Mesh ────────────────────────────────────────────────────
istioctl analyze -n yas
istioctl proxy-config cluster deploy/product -n yas
istioctl x check-inject -n yas
kubectl get peerauthentication,destinationrule,virtualservice,authorizationpolicy -n yas

# ─── Connectivity Tests ───────────────────────────────────────────────────────
# Allowed: order -> product (should return 200)
kubectl exec -n yas deploy/order -- curl -s http://product/actuator/health

# Denied: test-pod -> product (should be blocked)
kubectl run test-pod --image=curlimages/curl -n yas --restart=Never --rm -it \
  -- curl -v http://product.yas.svc.cluster.local/actuator/health

# Check mTLS cert
istioctl proxy-config secret deploy/product -n yas
```

---

> 💡 **Report Tips:** For every phase, take screenshots of:
> - Terminal output of `kubectl get pods` showing healthy state
> - Jenkins console output showing successful deployment
> - Argo CD UI: Healthy + Synced status
> - Kiali: Service Graph topology (navigate to Graph → Namespace: yas)
> - Terminal output of curl tests showing allowed vs denied responses
