# Jenkins Pipeline CI/CD

## Kiến trúc (1 pipeline duy nhất)

```
GitHub (yas repo)
│
├── git push (any branch) ──► Jenkins Pipeline (Jenkinsfile)
│                                │
│                                ├── feature branch:
│                                │     build image tag = commit-id → push Docker Hub → dừng
│                                │
│                                ├── main branch:
│                                │     build image tag = commit-id + latest → push Docker Hub
│                                │     → update GitOps values.yaml
│                                │     → ArgoCD dev auto-sync
│                                │
│                                └── tag v* (e.g. git tag v1.2.3):
│                                      build image tag = v1.2.3 → push Docker Hub
│                                      → update GitOps values.staging.yaml
│                                      → ArgoCD staging auto-sync
│
└── manual params ──► developer_build (job riêng, không gộp pipeline)
```

---

## Pipeline: CI + staging-release (1 Jenkinsfile)

**File:** `Jenkinsfile` (source repo, thư mục gốc)

**Trigger:** GitHub push event (branch hoặc tag)

**Credential cần có trong Jenkins:**

| ID | Loại | Mục đích |
|----|------|----------|
| `dockerhub-credentials` | Username with password | Docker Hub login |
| `gitops-credentials` | Username with password (GitHub token) | Push yas-gitops repo |

### Flow chi tiết

```
1. Pipeline Info
    - In branch, commit SHA, image tag
    ↓
2. Detect Changed Services
    - git diff --name-only → tìm service thay đổi
    ↓
3. Build & Test (parallel)
    ├── Maven: mvn clean install -pl <service> -am -DskipTests=false
    └── Node.js: npm ci && npm run build
    ↓
4. Build Docker Image
    ├── feature branch → tag: commit-id
    ├── main           → tag: commit-id + latest
    └── tag v*         → tag: v1.2.3
    ↓
5. Push to Docker Hub
    ↓
6. Update GitOps Repo  ← chỉ chạy khi branch=main hoặc tag=v*
    ├── main   → sửa values.yaml (dev)
    └── tag v* → sửa values.staging.yaml (staging)
    ↓
7. Cleanup
    - Xoá image khỏi Jenkins agent
```

### Tag convention

| Trigger | Docker Hub tags | GitOps update | Deploy |
|---------|----------------|---------------|--------|
| Push feature | `thaithienphu/product:abc1234` | — | không deploy |
| Push main | `thaithienphu/product:abc1234` + `:latest` | `values.yaml` → `tag: abc1234` | ArgoCD → **dev** |
| Tag `v1.2.3` | `thaithienphu/product:v1.2.3` | `values.staging.yaml` → `tag: v1.2.3` | ArgoCD → **staging** |

**`latest` tag** trên Docker Hub dùng cho `developer_build` job (khi dev muốn deploy NodePort để test, service không build sẽ dùng image `:latest` sẵn có).

---

## Job developer_build (manual)

**Trigger:** Developer mở Jenkins job, nhập tham số

**Params:**

| Parameter | Ví dụ | Mô tả |
|-----------|-------|-------|
| `product_branch` | `dev_product_feature` | Branch muốn test cho service product |
| `cart_branch` | (để trống) | Nếu trống → dùng image `:latest` có sẵn |
| (tương tự cho các service còn lại) |

**Luồng:**

1. Với mỗi service:
   - Nếu có branch: checkout branch → build image tag = commit-id
   - Nếu không có branch: dùng image `:latest` từ Docker Hub
2. Tạo deployment + NodePort service trong K8S
3. In URL `http://<node-ip>:<NodePort>` → dev test

---

## Cấu trúc GitOps repo (yas-gitops)

```
k8s/
├── charts/<service>/
│   ├── values.yaml              # dùng cho DEV (tag được CI update)
│   └── values.staging.yaml      # dùng cho STAGING (tag được staging-release update)
├── argocd-apps/
│   ├── dev/
│   │   ├── product.yaml         # namespace: dev,   valueFiles: [values.yaml]
│   │   ├── cart.yaml
│   │   └── ...
│   ├── staging/
│   │   ├── product.yaml         # namespace: staging, valueFiles: [values.staging.yaml]
│   │   ├── cart.yaml
│   │   └── ...
│   └── root-app/
│       └── root.yaml            # App of Apps, quét toàn bộ argocd-apps/
```
