# 📦 Đồ Án 2 – Xây Dựng Hệ Thống CD cho YAS (Yet Another Shop)

> **Môn học:** DevOps  
> **Dự án nguồn:** [YAS – Yet Another Shop](https://github.com/nashtech-garage/yas)  
> **Mục tiêu:** Thiết kế và triển khai một hệ thống **CI/CD** đầy đủ, bao gồm xây dựng pipeline, triển khai lên Kubernetes, và tùy chọn nâng cao với Argo CD + Istio Service Mesh.

---

## 📋 Mục Lục

1. [Tổng Quan Dự Án](#1-tổng-quan-dự-án)
2. [Công Nghệ Sử Dụng](#2-công-nghệ-sử-dụng)
3. [Kiến Trúc Hệ Thống](#3-kiến-trúc-hệ-thống)
4. [Luồng Tổng Quan (General Flow)](#4-luồng-tổng-quan-general-flow)
5. [Luồng Chi Tiết (Detailed Flow)](#5-luồng-chi-tiết-detailed-flow)
   - [5.1 CI – Jenkins Build & Test Pipeline](#51-ci--jenkins-build--test-pipeline)
   - [5.2 CI – Jenkins Build & Push Docker Image](#52-ci--jenkins-build--push-docker-image)
   - [5.3 CD – Developer Build & Deploy lên K8s](#53-cd--developer-build--deploy-lên-k8s)
   - [5.4 CD – Dev & Staging Environments (Argo CD)](#54-cd--dev--staging-environments-argo-cd)
   - [5.5 Service Mesh – Istio (Nâng Cao)](#55-service-mesh--istio-nâng-cao)
6. [Các Microservice trong YAS](#6-các-microservice-trong-yas)
7. [Các Jenkins Job](#7-các-jenkins-job)
8. [Checklist Yêu Cầu](#8-checklist-yêu-cầu)

---

## 1. Tổng Quan Dự Án

**YAS (Yet Another Shop)** là một ứng dụng thương mại điện tử kiến trúc microservice viết bằng Java. Đồ án yêu cầu sinh viên xây dựng **hệ thống Continuous Delivery (CD)** để có thể tự động hoá quy trình:

- Build Docker Image từ source code
- Push image lên Docker Hub / Container Registry
- Deploy tất cả các service lên **Kubernetes cluster**
- Cho phép developer test code của mình trên môi trường gần production

```
Developer commit code
       ↓
  Jenkins CI Pipeline
  (Build + Test + Code Quality + Push Image)
       ↓
  Jenkins CD Pipeline
  (Helm deploy lên K8s)
       ↓
  Developer truy cập qua NodePort
```

---

## 2. Công Nghệ Sử Dụng

| Lớp | Công Nghệ |
|-----|-----------|
| **Backend** | Java 21, Spring Boot 3.2 |
| **Frontend** | Next.js (Storefront + Backoffice) |
| **Auth** | Keycloak |
| **Messaging** | Apache Kafka |
| **Search** | Elasticsearch |
| **Database** | PostgreSQL |
| **Container** | Docker, Docker Compose |
| **Orchestration** | Kubernetes (K8s) – 1 Master + 1 Worker |
| **Helm** | Helm Charts (quản lý K8s manifests) |
| **CI/CD** | Jenkins |
| **GitOps** | Argo CD *(nâng cao)* |
| **Service Mesh** | Istio + Kiali *(nâng cao)* |
| **Code Quality** | SonarCloud, Checkstyle, OWASP |
| **Observability** | OpenTelemetry, Grafana, Loki, Prometheus, Tempo |

---

## 3. Kiến Trúc Hệ Thống

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet / Developers                    │
└─────────────────────────────────────────────────────────────────┘
                          │ NodePort (30080-30090)
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster (GCP VM)                  │
│  ┌───────────────┐    ┌────────────────────────────────────────┐ │
│  │  Master Node  │    │              Worker Node               │ │
│  │ (Control Plane│    │  ┌──────────┐  ┌──────────┐          │ │
│  │  API Server,  │    │  │Namespace │  │Namespace │  ...     │ │
│  │  etcd, ...)   │    │  │  "yas"   │  │ "kafka"  │          │ │
│  └───────────────┘    │  │ (core)   │  │"keycloak"│          │ │
│                        │  └──────────┘  └──────────┘          │ │
│                        └────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         ↑ Deploy via Helm
┌──────────────────────────────────────────────────────────┐
│                        Jenkins                            │
│  ┌──────────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  CI: build_image │  │developer_build│  │  cleanup  │  │
│  │  (build+test+    │  │  (CD deploy) │  │(uninstall)│  │
│  │   push image)    │  │              │  │           │  │
│  └──────────────────┘  └──────────────┘  └───────────┘  │
└──────────────────────────────────────────────────────────┘
         │ push image              │ pull image (Helm)
         ↓                        ↓
┌────────────────────────────────────────────────┐
│                  Docker Hub                    │
│  thaithienphu/product:latest                   │
│  thaithienphu/product:abc1234  (commit SHA)    │
│  thaithienphu/product:v1.2.3   (release tag)  │
└────────────────────────────────────────────────┘
```

---

## 4. Luồng Tổng Quan (General Flow)

Toàn bộ pipeline hoạt động theo 3 nhánh chính:

### 🔵 Nhánh 1 – Jenkins CI (Build & Test)

```
[Developer] → git push branch dev_xxx
                    ↓
[Jenkins] phát hiện commit mới (webhook/poll SCM)
                    ↓
[Jenkins CI Job] Build + Test + Code Quality
   → mvn clean install
   → checkstyle, SonarQube
   → docker build + push thaithienphu/<service>:<commit_SHA>
```

### 🟢 Nhánh 2 – Jenkins CD (Developer Build & Test thủ công)

```
[Developer] → vào Jenkins → chạy job "developer_build"
                    ↓
Input: SERVICE_NAME=tax, DEV_BRANCH=dev_tax_service
                    ↓
[Jenkins] resolve image tag → dev_tax_service
                    ↓
[Helm upgrade] deploy service "tax" với tag mới
               deploy tất cả service còn lại với tag "latest"
                    ↓
[Jenkins] in ra NodePort URL để developer test
```

### 🟡 Nhánh 3 – Auto CD (Argo CD GitOps)

```
[main branch] code merged
      ↓
[Jenkins CI] build image → push thaithienphu/product:commit_SHA
      ↓
[Jenkins CD] update gitops/dev/product-values.yaml (image tag)
      ↓
[git push] → repo
      ↓
[Argo CD] phát hiện thay đổi → auto sync
      ↓
[K8s] deploy pod mới, xóa pod cũ
```

---

## 5. Luồng Chi Tiết (Detailed Flow)

### 5.1 CI – Jenkins Build & Test Pipeline

Mỗi service được cấu hình một Jenkins job CI riêng, trigger tự động qua **webhook** hoặc **poll SCM** khi có commit mới.

**Trigger:**
- Developer push commit lên bất kỳ branch nào
- Jenkins nhận webhook từ Git repo → tự động chạy pipeline

**Các bước thực hiện:**

```
1. Checkout source code (git checkout)
       ↓
2. Setup Java (JDK 21) + Maven
       ↓
3. mvn clean install -pl <service> -am
   (Build + Unit Test + Integration Test với Testcontainers)
       ↓
4. mvn checkstyle:checkstyle   ← kiểm tra coding standard
       ↓
5. SonarQube/SonarCloud analysis
   (phát hiện code smell, bug, vulnerability)
       ↓
6. (Nếu pass) Xác định image tag:
   - Branch main / latest → tag: "latest"
   - Branch feature       → tag: "<commit_SHA>"
       ↓
7. docker build → thaithienphu/<service>:<tag>
       ↓
8. docker push → Docker Hub
```

**Ví dụ Jenkinsfile CI cho product service:**

```groovy
pipeline {
  agent any
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Build & Test') {
      steps {
        sh 'mvn clean install -pl product -am'
      }
    }
    stage('Code Quality') {
      steps {
        sh 'mvn checkstyle:checkstyle -pl product'
        sh 'mvn sonar:sonar -f product'
      }
    }
    stage('Build & Push Docker Image') {
      steps {
        script {
          def tag = (env.BRANCH_NAME == 'main') ? 'latest' : env.GIT_COMMIT[0..6]
          withCredentials([usernamePassword(
            credentialsId: 'docker-hub-credentials',
            usernameVariable: 'DOCKER_USER',
            passwordVariable: 'DOCKER_PASS'
          )]) {
            sh "echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin"
            sh "docker build -t thaithienphu/product:${tag} ./product"
            sh "docker push thaithienphu/product:${tag}"
          }
        }
      }
    }
  }
}
```

---

### 5.2 CI – Jenkins Build & Push Docker Image

**Mục đích:** Jenkins job thủ công để build Docker image cho một service cụ thể và push lên Docker Hub (dùng khi cần build lại image ngoài chu trình tự động).

**Pipeline gồm 4 stage:**

```
Stage 1: Khởi tạo thông tin
  → In ra SERVICE_NAME và IMAGE_TAG được chọn

Stage 2: Build Docker Image
  → cd services/<SERVICE_NAME>/
  → docker build -t thaithienphu/<SERVICE>:<IMAGE_TAG>
  → docker build -t thaithienphu/<SERVICE>:<BUILD_NUMBER>

Stage 3: Push Image lên Docker Hub
  → docker login (dùng credential "docker-hub-credentials")
  → docker push thaithienphu/<SERVICE>:<IMAGE_TAG>
  → docker push thaithienphu/<SERVICE>:<BUILD_NUMBER>

Stage 4: Dọn dẹp môi trường local
  → docker rmi (xóa image khỏi agent để không tràn ổ cứng)
```

**Parameters:**

| Parameter | Giá trị mặc định | Mô tả |
|-----------|-----------------|-------|
| `SERVICE_NAME` | `product` | Chọn service cần build |
| `IMAGE_TAG` | `latest` | Tag của Docker image |

---

### 5.3 CD – Developer Build & Deploy lên K8s

**Mục đích:** Cho phép developer tự deploy service đang phát triển để test trực tiếp trên K8s cluster.

**Jenkins Job:** `developer_build`

#### Luồng chi tiết:

```
[Developer] vào Jenkins → chạy job "developer_build"
              ↓
Input Parameters:
  SERVICE_NAME = "tax"
  DEV_BRANCH   = "dev_tax_service"
              ↓
Stage 1: Resolve Image Tag
  Nếu DEV_BRANCH == "main" → IMAGE_TAG = "latest"
  Ngược lại                → IMAGE_TAG = "dev_tax_service"
              ↓
Stage 2: Deploy Service (via Helm)
  helm upgrade --install tax k8s/charts/tax \
    --namespace yas \
    --set backend.image.repository=thaithienphu/tax \
    --set backend.image.tag=dev_tax_service \
    --wait --timeout 5m
              ↓
Stage 3: Print Developer Access Info
  ╔═════════════════════════════════╗
  ║ DEPLOYMENT COMPLETE             ║
  ║ Service: tax                    ║
  ║ Tag:     dev_tax_service        ║
  ╠═════════════════════════════════╣
  ║ Add to /etc/hosts:              ║
  ║  34.x.x.x  storefront.yas.local.com ║
  ╠═════════════════════════════════╣
  ║ Access: http://storefront:30080 ║
  ╚═════════════════════════════════╝
```

#### Cách developer sử dụng:

1. Commit code lên branch `dev_tax_service`
2. **Jenkins CI job** chạy tự động → build + test → push image `thaithienphu/tax:dev_tax_service` lên Docker Hub
3. Vào Jenkins → chạy `developer_build` job
4. Nhập `SERVICE_NAME=tax`, `DEV_BRANCH=dev_tax_service`
5. Jenkins deploy tax service với image mới, các service khác vẫn chạy image `latest`
6. Thêm dòng vào `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`)
7. Truy cập `http://storefront.yas.local.com:30080` để test

---

### 5.4 CD – Dev & Staging Environments (Argo CD)

**Mục đích:** GitOps – tự động sync khi có thay đổi trong repository.

#### Cấu trúc GitOps:

```
gitops/
├── dev/
│   ├── product-values.yaml    ← tag: latest (hoặc commit SHA)
│   ├── cart-values.yaml
│   └── ...
├── staging/
│   ├── product-values.yaml    ← tag: v1.2.3 (release tag)
│   └── ...
└── argocd/
    ├── yas-dev-app.yaml        ← ArgoCD Application CRD
    └── yas-staging-app.yaml
```

#### Luồng Dev Environment (Auto CD):

```
1. Developer merge PR vào nhánh "main"
        ↓
2. Jenkins CI job tự động trigger
   → Build + Test + push image thaithienphu/product:abc1234
        ↓
3. Jenkins CD job cập nhật GitOps:
   sed -i "s/tag: .*/tag: abc1234/" gitops/dev/product-values.yaml
   git commit -m "ci: update product image to abc1234"
   git push origin main
        ↓
4. Argo CD phát hiện commit mới trong repo
        ↓
5. Argo CD tự động sync (prune + selfHeal)
        ↓
6. Kubernetes: pod mới với image abc1234 được tạo, pod cũ bị xóa
        ↓
7. Argo CD UI hiển thị: Health ✅  Synced ✅
```

#### Luồng Staging Environment (Tag-based CD):

```
1. Tạo release tag trên nhánh main: git tag v1.2.3
        ↓
2. Jenkins CI phát hiện tag mới → build image
   → push thaithienphu/product:v1.2.3 lên Docker Hub
        ↓
3. Jenkins cập nhật gitops/staging/product-values.yaml → tag: v1.2.3
   → git push → repo
        ↓
4. Argo CD sync vào namespace "staging" với tag v1.2.3
```

#### ArgoCD Application Manifest (`yas-dev-app.yaml`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yas-product-dev
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/<YOUR_ORG>/yas.git
    targetRevision: main
    path: k8s/charts/product
    helm:
      valueFiles:
        - ../../../gitops/dev/product-values.yaml
  destination:
    namespace: dev
  syncPolicy:
    automated:
      prune: true       # Xóa resource không còn trong Git
      selfHeal: true    # Revert các thay đổi thủ công bằng kubectl
```

---

### 5.5 Service Mesh – Istio (Nâng Cao)

**Mục đích:** Bảo mật và kiểm soát giao tiếp giữa các microservice.

#### Tổng quan các thành phần Istio:

```
┌──────────────────────────────────────────────────────────────┐
│                    Namespace "yas"                            │
│                                                              │
│  ┌─────────────┐    mTLS    ┌─────────────┐                 │
│  │   order     │ ─────────→ │   product   │                 │
│  │ [app+envoy] │            │ [app+envoy] │                 │
│  └─────────────┘            └─────────────┘                 │
│                                                              │
│  ┌─────────────┐            ┌─────────────┐                 │
│  │    cart     │ ─────────→ │   product   │                 │
│  │ [app+envoy] │            │   (GET only)│                 │
│  └─────────────┘            └─────────────┘                 │
│                                                              │
│  ┌─────────────┐   BLOCKED  ┌─────────────┐                 │
│  │  test-pod   │ ─────╳───→ │   product   │                 │
│  │ (no auth)   │            │             │                 │
│  └─────────────┘            └─────────────┘                 │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

#### Các bước cấu hình:

**Bước 1 – Enable mTLS (PeerAuthentication)**

```yaml
# k8s/service-mesh/peer-authentication.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: yas
spec:
  mtls:
    mode: STRICT   # BẮT BUỘC TLS giữa tất cả service trong namespace
```

**Bước 2 – DestinationRule (client-side TLS)**

```yaml
# k8s/service-mesh/destination-rules.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: yas-mtls
  namespace: yas
spec:
  host: "*.yas.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL   # Dùng cert do Istio CA cấp
```

**Bước 3 – AuthorizationPolicy (Service-to-Service Allow List)**

```yaml
# Mặc định CHẶN TẤT CẢ
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: yas
spec: {}   # Không có rule = chặn hết

---
# Chỉ cho phép order → product (GET/POST/PUT)
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
            principals: ["cluster.local/ns/yas/sa/order"]
      to:
        - operation:
            methods: ["GET", "POST", "PUT"]
```

**Bước 4 – VirtualService (Retry Policy)**

```yaml
# k8s/service-mesh/virtual-services.yaml
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
        attempts: 3           # Retry tối đa 3 lần
        perTryTimeout: 5s     # Mỗi lần retry timeout 5s
        retryOn: "5xx,gateway-error,connect-failure"
      timeout: 20s
      route:
        - destination:
            host: product
            port:
              number: 80
```

#### Test Scenarios:

| Test | Lệnh | Kết quả mong đợi |
|------|------|------------------|
| Allowed: order → product | `kubectl exec deploy/order -- curl http://product/actuator/health` | HTTP 200 |
| Denied: test-pod → product | `kubectl run test-pod --image=curlimages/curl -- curl http://product...` | `RBAC: access denied` |
| Retry Evidence | Scale product xuống 0 → check log Envoy | Log hiển thị retry attempts |
| mTLS Certificate | `istioctl proxy-config secret deploy/product -n yas` | ACTIVE cert từ Istio CA |

---

## 6. Các Microservice trong YAS

| Service | Mô tả | Port |
|---------|-------|------|
| `storefront` | Frontend Next.js cho khách hàng | 80 |
| `storefront-bff` | Backend For Frontend – Storefront | 80 |
| `backoffice` | Frontend Next.js cho admin | 80 |
| `backoffice-bff` | Backend For Frontend – Backoffice | 80 |
| `product` | Quản lý sản phẩm | 80 |
| `cart` | Giỏ hàng | 80 |
| `order` | Đặt hàng | 80 |
| `customer` | Thông tin khách hàng | 80 |
| `inventory` | Quản lý kho | 80 |
| `tax` | Tính thuế | 80 |
| `payment` | Thanh toán | 80 |
| `payment-paypal` | Tích hợp PayPal | 80 |
| `media` | Quản lý ảnh/file | 80 |
| `search` | Tìm kiếm (Elasticsearch) | 80 |
| `rating` | Đánh giá sản phẩm | 80 |
| `promotion` | Khuyến mãi | 80 |
| `location` | Địa chỉ/khu vực | 80 |
| `recommendation` | Gợi ý sản phẩm | 80 |
| `webhook` | Webhook handler | 80 |
| `identity` | Keycloak (Auth Server) | 8080 |

---

## 7. Các Jenkins Job

### Job 1: `developer_build`

| Thông tin | Chi tiết |
|-----------|----------|
| **Mục đích** | Deploy 1 service từ dev branch, còn lại dùng `latest` |
| **Parameters** | `SERVICE_NAME` (dropdown), `DEV_BRANCH` (string) |
| **Cách dùng** | Developer chọn service + branch → Jenkins deploy lên K8s |
| **Output** | NodePort URL + `/etc/hosts` config để truy cập |

### Job 2: `cleanup_deployment`

| Thông tin | Chi tiết |
|-----------|----------|
| **Mục đích** | Xóa Helm release khỏi K8s cluster |
| **Parameters** | `SERVICE_NAME` (dropdown, có option `ALL_YAS_SERVICES`) |
| **Cách dùng** | Chọn service cần xóa → Jenkins `helm uninstall` |
| **Output** | Xác nhận release đã bị xóa |

### Job 3: CI Pipeline (Jenkinsfile gốc)

| Thông tin | Chi tiết |
|-----------|----------|
| **Mục đích** | Build Docker image + push lên Docker Hub |
| **Parameters** | `SERVICE_NAME` (dropdown), `IMAGE_TAG` (string) |
| **Stages** | Khởi tạo → Build → Push → Dọn dẹp |

---

## 8. Checklist Yêu Cầu

### ✅ Yêu cầu cơ bản (6 điểm)

- [x] **Image mặc định** – Có sẵn image tag `main` / `latest` cho mọi service
- [ ] **K8s Cluster** – 1 Master + 1 Worker node (hoặc Minikube)
- [ ] **CI branch** – Mỗi commit lên branch → build image với tag là commit SHA → push Docker Hub
- [ ] **Job `developer_build`** – Developer chọn service + branch, các service khác dùng `latest`
- [ ] **NodePort + `/etc/hosts`** – Developer truy cập được hệ thống sau deploy
- [ ] **Job `cleanup_deployment`** – Xóa được deployment sau khi test xong
- [ ] **Dev & Staging CI/CD** – `main` auto deploy vào `dev`; release tag deploy vào `staging`

### 🚀 Yêu cầu nâng cao (2 điểm mỗi phần)

- [ ] **Argo CD GitOps** – Quản lý `dev` và `staging` bằng Argo CD
- [ ] **Istio Service Mesh** – mTLS, AuthorizationPolicy, Retry Policy, Kiali topology

---

## 📂 Cấu Trúc Thư Mục Liên Quan

```
yas/
├── Jenkinsfile                  ← Jenkins CI job: build + test + push image
├── k8s/
│   ├── charts/                  ← Helm Charts cho mỗi service
│   ├── deploy/                  ← Scripts deploy lên K8s
│   │   ├── nodeport-services.yaml
│   │   └── deploy-yas-applications.sh
│   ├── jenkins/                 ← Jenkins Pipelines (CI & CD)
│   │   ├── Jenkinsfile.developer_build   ← CD: deploy service từ dev branch
│   │   └── Jenkinsfile.cleanup           ← CD: xóa deployment
│   ├── service-mesh/            ← Istio manifests (nâng cao)
│   │   ├── peer-authentication.yaml
│   │   ├── destination-rules.yaml
│   │   ├── authorization-policies.yaml
│   │   ├── virtual-services.yaml
│   │   └── gateway.yaml
│   └── DEVOPS_PLAN.md           ← Kế hoạch triển khai chi tiết
└── gitops/                      ← GitOps source of truth (Argo CD)
    ├── dev/
    │   └── <service>-values.yaml
    ├── staging/
    │   └── <service>-values.yaml
    └── argocd/
        ├── yas-dev-app.yaml
        └── yas-staging-app.yaml
```

---

> 💡 **Tip:** Xem thêm kế hoạch triển khai chi tiết tại `k8s/DEVOPS_PLAN.md` và tài liệu kiến trúc tại thư mục `docs/`.
