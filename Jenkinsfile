pipeline {
    agent any

    parameters {
        // Tham số chọn lựa service linh hoạt (mặc định chọn product theo yêu cầu)
        choice(
            name: 'SERVICE_NAME', 
            choices: ['product', 'cart', 'order', 'customer', 'inventory', 'tax', 'media', 'search', 'storefront-bff', 'backoffice-bff'], 
            description: 'Chọn service core cần build Docker Image'
        )
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Docker Image Tag')
    }

    environment {
        // THAY ĐỔI: Nhập đúng Username Docker Hub của bạn vào đây
        DOCKER_HUB_USER = 'your_dockerhub_username' 
        // ID credentials đã tạo ở Bước 2
        DOCKER_HUB_CREDS = 'docker-hub-credentials' 
        IMAGE_NAME = "${env.DOCKER_HUB_USER}/${params.SERVICE_NAME}"
    }

    stages {
        stage('Khởi tạo thông tin') {
            steps {
                echo "=== BẮT ĐẦU PIPELINE CHO SERVICE: ${params.SERVICE_NAME} ==="
                echo "Tag đích: ${params.IMAGE_TAG}"
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Di chuyển vào đúng thư mục của service được chọn (ví dụ: services/product)
                    // Lưu ý điều chỉnh đường dẫn "services/..." cho đúng với cấu trúc repo YAS của bạn
                    dir("services/${params.SERVICE_NAME}") {
                        echo "Đang build image cho ${params.SERVICE_NAME}..."
                        sh "docker build -t ${env.IMAGE_NAME}:${params.IMAGE_TAG} -t ${env.IMAGE_NAME}:${BUILD_NUMBER} ."
                    }
                }
            }
        }

        stage('Push Image lên Docker Hub') {
            steps {
                script {
                    // Gọi credential bảo mật từ Jenkins
                    withCredentials([usernamePassword(credentialsId: env.DOCKER_HUB_CREDS, usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        echo "Đang đăng nhập Docker Hub..."
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"
                        
                        echo "Đang tiến hành Push Images..."
                        sh "docker push ${env.IMAGE_NAME}:${params.IMAGE_TAG}"
                        sh "docker push ${env.IMAGE_NAME}:${BUILD_NUMBER}"
                    }
                }
            }
        }

        stage('Dọn dẹp môi trường local') {
            steps {
                echo "Xóa các image trung gian tại máy Agent để tránh tràn ổ cứng..."
                sh "docker rmi ${env.IMAGE_NAME}:${params.IMAGE_TAG} ${env.IMAGE_NAME}:${BUILD_NUMBER} || true"
            }
        }
    }

    post {
        success {
            echo "Hoàn thành! Service [${params.SERVICE_NAME}] đã được đẩy lên Docker Hub thành công."
        }
        failure {
            echo "Gặp lỗi trong quá trình thực thi. Vui lòng kiểm tra log ở Console Output."
        }
    }
}