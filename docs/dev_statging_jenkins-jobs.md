# Jenkins Jobs & Flow

## Tổng quan kiến trúc

```
GitHub (yas repo)
│
├── push (any branch) ──► CI (auto)
│                            │
│                            ├── branch ≠ main: build image tag = commit-id → push Docker Hub → dừng
│                            └── branch = main: build image tag = commit-id → push Docker Hub
│                                                → update GitOps values.yaml
│                                                → ArgoCD dev auto-sync
│
├── manual params ──► developer_build (manual)
│                        │
│                        ├── build image tag = commit-id cho service được chọn
│                        ├── dùng image main cho service còn lại
│                        └── deploy NodePort bằng kubectl → dev truy cập test
│
└── tag v* ──► staging-release (auto/manual)
                 │
                 ├── build image tag = v*
                 ├── push Docker Hub
                 ├── update GitOps values.staging.yaml
                 └── ArgoCD staging auto-sync
```

---

## Job 1: CI (auto)

**Trigger:** Push commit lên GitHub (bất kỳ branch nào)

**Luồng:**

1. Detect changed services (`git diff --name-only`)
2. Maven build & test từng service thay đổi
3. Docker build với tag = 7 ký tự commit-id
4. Push image lên Docker Hub
5. Nếu branch = **main**:
   - Clone yas-gitops repo
   - Sửa `tag:` trong `values.yaml` (dev) của từng service
   - Commit & push lên yas-gitops
6. ArgoCD dev phát hiện thay đổi → auto-sync vào namespace **dev**
7. Cleanup image khỏi Jenkins agent

**Nếu branch ≠ main:** chỉ build + push, không update GitOps.

---

## Job 2: developer_build (manual)

**Trigger:** Developer mở Jenkins job, nhập tham số

**Params:**

| Parameter | Ví dụ | Mô tả |
|-----------|-------|-------|
| `tax_branch` | `dev_tax_service` | Branch muốn test cho service tax |
| `cart_branch` | (để trống) | Branch muốn test cho service cart |
| `product_branch` | (để trống) | Branch muốn test cho service product |
| ... | ... | Tương tự cho các service còn lại |

**Luồng:**

1. Với mỗi service:
   - Nếu có branch: checkout branch đó → build image tag = commit-id
   - Nếu không có branch: dùng image tag = `main` có sẵn trên Docker Hub
2. Tạo deployment + service NodePort trong K8S (namespace riêng hoặc namespace `dev`)
3. In ra URL: `http://<worker-node-ip>:<NodePort>`
4. Developer thêm vào `hosts` file, truy cập test

---

## Job 3: staging-release (auto/manual)

**Trigger:** Git tag dạng `v*` (vd: `git tag v1.2.3 && git push origin v1.2.3`)

**Luồng:**

1. Checkout code tại tag (vd: `v1.2.3`)
2. Detect changed services (so với tag trước)
3. Maven build & test
4. Docker build với tag = tên tag (vd: `v1.2.3`)
5. Push image lên Docker Hub
6. Clone yas-gitops
7. Sửa `tag:` trong `values.staging.yaml` của từng service
8. Commit & push lên yas-gitops
9. ArgoCD staging phát hiện thay đổi → auto-sync vào namespace **staging**
10. Cleanup

---

## So sánh 3 job

| Job | Trigger | Build tag | Deploy tới | Cách deploy |
|-----|---------|-----------|------------|-------------|
| CI (main) | Push main | `commit-id` | namespace **dev** | ArgoCD (GitOps) |
| CI (nhánh khác) | Push feature | `commit-id` | không deploy | chỉ push image |
| developer_build | Manual params | `commit-id` / `main` | NodePort | kubectl trực tiếp |
| staging-release | Tag `v*` | `v1.2.3` | namespace **staging** | ArgoCD (GitOps) |

---

## Cấu trúc GitOps repo (yas-gitops)

```
k8s/
├── charts/<service>/
│   ├── values.yaml              # dùng cho DEV (tag được CI update)
│   └── values.staging.yaml      # dùng cho STAGING (tag được staging-release update)
├── argocd-apps/
│   ├── cart-dev.yaml            # namespace: dev,   valueFiles: [values.yaml]
│   ├── cart-staging.yaml        # namespace: staging, valueFiles: [values.staging.yaml]
│   ├── product-dev.yaml
│   ├── product-staging.yaml
│   └── ...
└── root-app/
    └── root.yaml                # App of Apps, quét toàn bộ argocd-apps/
```

---

## Yêu cầu K8S

- 1 Master node + 1 Worker node (hoặc Minikube)
- Service type NodePort cho developer_build
- Namespace: `dev`, `staging` (cho ArgoCD)
- Observability: không cần Grafana/Prometheus
