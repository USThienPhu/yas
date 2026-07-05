# Hướng dẫn Cài đặt & Cấu hình Istio Service Mesh từng bước

Tài liệu này hướng dẫn bạn tự thực thi toàn bộ yêu cầu cấu hình Service Mesh (Istio) trên Kubernetes cluster chạy Minikube của bạn.

---

## Bước 1: Cài đặt Istio Control Plane và Addons

1. **SSH vào máy ảo của bạn**:
   ```bash
   ssh -i ~/.ssh/yas_devops_shared devops@34.126.162.233
   ```

2. **Tải phiên bản Istio mới nhất**:
   ```bash
   curl -L https://istio.io/downloadIstio | sh -
   ```

3. **Truy cập thư mục Istio mới tải xuống** (Ví dụ bản 1.30.2, thay đổi số phiên bản nếu khác):
   ```bash
   cd istio-1.30.2
   ```

4. **Sao chép công cụ CLI `istioctl` vào đường dẫn hệ thống để chạy toàn cục**:
   ```bash
   sudo cp bin/istioctl /usr/local/bin/
   ```

5. **Cài đặt Istio với profile `demo`** (profile này tự động cấu hình đầy đủ Ingress và Egress Gateway):
   ```bash
   istioctl install --set profile=demo -y
   ```

6. **Cài đặt các Addon giám sát (Prometheus & Kiali)**:
   ```bash
   kubectl apply -f samples/addons/prometheus.yaml
   kubectl apply -f samples/addons/kiali.yaml
   ```

7. **Kiểm tra trạng thái cài đặt**:
   ```bash
   kubectl get pods -n istio-system
   ```
   *Đợi cho đến khi toàn bộ Pods (`istiod`, `kiali`, `prometheus`, `istio-ingressgateway`, `istio-egressgateway`) chuyển sang trạng thái `Running`.*

---

## Bước 2: Bật Sidecar Injection cho Namespace `yas`

Để các microservice của YAS tham gia vào Service Mesh, chúng ta cần kích hoạt tính năng tự động tiêm (injection) sidecar Envoy proxy.

1. **Gán nhãn (label) kích hoạt injection cho namespace `yas`**:
   ```bash
   kubectl label namespace yas istio-injection=enabled --overwrite
   ```

2. **Khởi động lại toàn bộ Deployments trong namespace `yas` để áp dụng sidecar**:
   ```bash
   kubectl rollout restart deployment -n yas
   ```

3. **Kiểm tra trạng thái tiêm sidecar**:
   ```bash
   kubectl get pods -n yas
   ```
   *Bạn sẽ thấy số lượng Container trong mỗi Pod tăng lên dạng `2/2` (1 container ứng dụng + 1 container `istio-proxy`). Đợi cho tất cả các Pod chuyển sang trạng thái `Running`.*

---

## Bước 3: Cấu hình mTLS (STRICT)

Bật mã hóa mTLS STRICT để bắt buộc tất cả kết nối nội bộ giữa các service trong namespace `yas` phải được mã hóa.

1. **Áp dụng file cấu hình PeerAuthentication**:
   ```bash
   kubectl apply -f peer-authentication.yaml
   ```
   *(File cấu hình chi tiết nằm tại `k8s/istio/peer-authentication.yaml`)*

---

## Bước 4: Cấu hình Authorization Policy

Chỉ cho phép service account `storefront-bff` được phép gọi tới service `product`. Tất cả các request từ các service khác (như `customer`, `cart`, hoặc các pod kiểm thử thông thường) sẽ bị chặn với mã lỗi `403 Forbidden`.

1. **Áp dụng file cấu hình Authorization Policy**:
   ```bash
   kubectl apply -f authorization-policy.yaml
   ```
   *(File cấu hình chi tiết nằm tại `k8s/istio/authorization-policy.yaml`)*

---

## Bước 5: Cấu hình Traffic Splitting (80/20) và Retry Policy

Để demo tính năng phân chia lưu lượng, chúng ta cần:
- Gán nhãn `version=v1` cho deployment `product` hiện tại.
- Triển khai một deployment `product-v2` giả lập (mock container bằng Nginx trả về chuỗi text để dễ nhận biết).
- Định nghĩa `DestinationRule` chia thành 2 subset `v1` và `v2`.
- Định nghĩa `VirtualService` để thực hiện điều phối 80% traffic vào V1, 20% vào V2, đồng thời tích hợp chính sách tự động thử lại (Retry) 3 lần nếu gặp lỗi 5xx.

1. **Gán nhãn `version=v1` cho Pod template của deployment `product`**:
   ```bash
   kubectl patch deployment product -n yas -p '{"spec":{"template":{"metadata":{"labels":{"version":"v1"}}}}}'
   ```

2. **Áp dụng file cấu hình Traffic Splitting**:
   ```bash
   kubectl apply -f traffic-splitting.yaml
   ```
   *(File cấu hình chi tiết bao gồm deployment `product-v2` nằm tại `k8s/istio/traffic-splitting.yaml`)*

---

## Bước 6: Kiểm thử và Xác minh

Để việc kiểm thử diễn ra nhanh chóng, mình đã viết sẵn một script tự động chạy các kịch bản test trên VM.

1. **Tạo 2 pod kiểm thử tạm thời trong cluster**:
   * Pod `test-pod` (sử dụng service account `default` - bị chặn gọi vào product):
     ```bash
     kubectl run test-pod -n yas --image=curlimages/curl --restart=Never -- sleep 3600
     ```
   * Pod `test-pod-allowed` (sử dụng service account `storefront-bff` - được phép gọi vào product):
     ```bash
     kubectl run test-pod-allowed -n yas --image=curlimages/curl --restart=Never --overrides='{"spec":{"serviceAccountName":"storefront-bff"}}' -- sleep 3600
     ```

2. **Đợi vài giây cho các pod trên ở trạng thái Running, sau đó chạy script test**:
   ```bash
   chmod +x verify_mesh.sh
   ./verify_mesh.sh
   ```

---

## Bước 7: Xem giao diện trực quan trên Kiali Dashboard

1. **Cấu hình dịch vụ Kiali thành NodePort để dễ truy cập**:
   ```bash
   kubectl patch svc kiali -n istio-system -p '{"spec":{"type":"NodePort"}}'
   ```

2. **Lấy NodePort của Kiali**:
   ```bash
   kubectl get svc kiali -n istio-system
   ```
   *(Ví dụ NodePort trả về là `32090`)*

3. **Chạy port-forward trên máy ảo GCP để mở rộng cổng ra ngoài**:
   ```bash
   nohup kubectl port-forward --address 0.0.0.0 svc/kiali -n istio-system 32090:20001 > /dev/null 2>&1 &
   ```

4. **Tạo SSH tunnel từ máy local của bạn**:
   ```bash
   ssh -i ~/.ssh/yas_devops_shared -L 32090:localhost:32090 devops@34.126.162.233
   ```

5. **Mở trình duyệt web của bạn và truy cập**:
   [http://localhost:32090/kiali/](http://localhost:32090/kiali/)
   *Vào mục **Graph**, chọn namespace `yas` và chạy thử một vài request để xem sơ đồ luồng dữ liệu trực quan.*
