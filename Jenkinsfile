pipeline {
    agent any

    // ==========================================================================
    // Tự động trigger khi có git push lên bất kỳ branch nào (Requirement 3)
    // Yêu cầu: cài plugin "GitHub Integration" hoặc "Generic Webhook Trigger"
    //          và cấu hình Webhook trên GitHub/GitLab trỏ về Jenkins
    // ==========================================================================
    triggers {
        githubPush()
    }

    environment {
        DOCKER_HUB_USER  = 'thaithienphu'
        DOCKER_HUB_CREDS = 'docker-hub-credentials'

        // Lấy 7 ký tự đầu của commit SHA làm image tag (ví dụ: abc1234)
        // Nếu là nhánh main thì dùng "latest", ngược lại dùng commit SHA
        COMMIT_SHA = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'latest'}"
        IMAGE_TAG  = "${env.BRANCH_NAME == 'main' ? 'latest' : env.COMMIT_SHA}"
    }

    stages {

        // ----------------------------------------------------------------------
        // Stage 1: In thông tin để dễ debug trên Jenkins console
        // ----------------------------------------------------------------------
        stage('Thông tin Pipeline') {
            steps {
                echo "======================================================"
                echo " Branch    : ${env.BRANCH_NAME}"
                echo " Commit SHA: ${env.COMMIT_SHA}"
                echo " Image Tag : ${env.IMAGE_TAG}"
                echo "======================================================"
                sh 'git log -1 --oneline'
            }
        }

        // ----------------------------------------------------------------------
        // Stage 2: Detect service thay đổi dựa trên git diff
        // Chỉ build service nào có file thay đổi trong commit này
        // ----------------------------------------------------------------------
        stage('Detect Changed Services') {
            steps {
                script {
                    def allServices = [
                        // Backend services
                        'product',        // Sản phẩm — trung tâm của shop
                        'cart',           // Giỏ hàng
                        'order',          // Đơn hàng — test retry policy
                        'customer',       // Thông tin khách hàng
                        'inventory',      // Kho hàng
                        'tax',            // Thuế — demo VirtualService retry
                        'media',          // Upload hình ảnh
                        'search',         // Tìm kiếm — demo AuthorizationPolicy
                        // BFF services
                        'storefront-bff', // BFF cho giao diện người dùng
                        'backoffice-bff', // BFF cho quản trị
                        // UI services (folder name ≠ service name)
                        'storefront',     // → storefront-ui (giao diện cửa hàng)
                        'backoffice',     // → backoffice-ui (giao diện quản trị)
                        // Data seeding — chỉ chạy 1 lần sau khi deploy
                        'sampledata'
                        // ❌ swagger-ui → dùng public image swaggerapi/swagger-ui, không cần build
                    ]

                    // Lấy danh sách file thay đổi so với commit trước
                    def changedFiles = sh(
                        script: 'git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD',
                        returnStdout: true
                    ).trim()

                    echo "Files changed:\n${changedFiles}"

                    // Tìm service nào có file thay đổi
                    def changedServices = allServices.findAll { service ->
                        changedFiles.contains("${service}/")
                    }

                    // Nếu không detect được gì (ví dụ: commit đầu tiên) → build tất cả
                    if (changedServices.isEmpty()) {
                        echo "Không detect được service thay đổi → build tất cả services"
                        changedServices = allServices
                    }

                    echo "Services cần build: ${changedServices}"
                    env.SERVICES_TO_BUILD = changedServices.join(',')
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 3: Build + Test bằng Maven
        // Chạy unit test và integration test trước khi build Docker image
        // ----------------------------------------------------------------------
        stage('Build & Test (Maven)') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    services.each { service ->
                        echo "=== Maven build & test: ${service} ==="
                        sh """
                            mvn clean install \
                                -pl ${service} -am \
                                -DskipTests=false \
                                --no-transfer-progress \
                                --batch-mode
                        """
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 4: Build Docker Image
        // Tag image với commit SHA (Requirement 3) + "latest" nếu trên main
        // ----------------------------------------------------------------------
        stage('Build Docker Image') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    services.each { service ->
                        def imageName = "${env.DOCKER_HUB_USER}/${service}"
                        echo "=== Docker build: ${imageName}:${env.IMAGE_TAG} ==="

                        // Build với 2 tag:
                        //   1. commit SHA (abc1234)  → nhận diện chính xác version
                        //   2. IMAGE_TAG (latest hoặc SHA) → tag chính
                        sh """
                            docker build \
                                -t ${imageName}:${env.COMMIT_SHA} \
                                -t ${imageName}:${env.IMAGE_TAG} \
                                ./${service}
                        """
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 5: Push lên Docker Hub
        // ----------------------------------------------------------------------
        stage('Push lên Docker Hub') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    withCredentials([usernamePassword(
                        credentialsId: env.DOCKER_HUB_CREDS,
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"

                        services.each { service ->
                            def imageName = "${env.DOCKER_HUB_USER}/${service}"
                            echo "=== Push: ${imageName} ==="
                            sh "docker push ${imageName}:${env.COMMIT_SHA}"
                            sh "docker push ${imageName}:${env.IMAGE_TAG}"
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 6: Dọn dẹp image trên Jenkins agent để tránh đầy ổ cứng
        // ----------------------------------------------------------------------
        stage('Dọn dẹp') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    services.each { service ->
                        def imageName = "${env.DOCKER_HUB_USER}/${service}"
                        sh "docker rmi ${imageName}:${env.COMMIT_SHA} ${imageName}:${env.IMAGE_TAG} || true"
                    }
                }
            }
        }
    }

    post {
        success {
            echo """
====================================================
✅ CI PIPELINE THÀNH CÔNG
   Branch    : ${env.BRANCH_NAME}
   Commit    : ${env.COMMIT_SHA}
   Image Tag : ${env.IMAGE_TAG}
   Services  : ${env.SERVICES_TO_BUILD}
   Docker Hub: https://hub.docker.com/u/${env.DOCKER_HUB_USER}
====================================================
            """
        }
        failure {
            echo """
====================================================
❌ CI PIPELINE THẤT BẠI
   Branch : ${env.BRANCH_NAME}
   Commit : ${env.COMMIT_SHA}
   Kiểm tra Console Output để biết nguyên nhân
====================================================
            """
        }
    }
}