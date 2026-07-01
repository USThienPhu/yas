pipeline {
    agent any

    // ==========================================================================
    // Auto-trigger on every git push to any branch (Requirement 3)
    // Requires: "GitHub Integration" or "Generic Webhook Trigger" plugin
    //           and a Webhook configured on GitHub/GitLab pointing to Jenkins
    // ==========================================================================
    triggers {
        githubPush()
    }

    environment {
        DOCKER_HUB_USER  = 'thaithienphu'
        DOCKER_HUB_CREDS = 'dockerhub-credentials'

        // Take first 7 characters of commit SHA as image tag (e.g. abc1234)
        // If on main branch → use "latest", otherwise use commit SHA
        COMMIT_SHA = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'latest'}"
        IMAGE_TAG  = "${env.BRANCH_NAME == 'main' ? 'latest' : env.COMMIT_SHA}"
    }

    stages {

        // ----------------------------------------------------------------------
        // Stage 1: Print pipeline info for easy debugging in Jenkins console
        // ----------------------------------------------------------------------
        stage('Pipeline Info') {
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
        // Stage 2: Detect which services changed based on git diff
        // Only build services that have file changes in this commit
        // ----------------------------------------------------------------------
        stage('Detect Changed Services') {
            steps {
                script {
                    // ----------------------------------------------------------
                    // Maven (Java/Spring Boot) services — built with mvn
                    // ----------------------------------------------------------
                    def mavenServices = [
                        'product',        // Product catalog — core of the shop
                        'cart',           // Shopping cart
                        'order',          // Order management — test retry policy
                        'customer',       // Customer information
                        'inventory',      // Inventory — order dependency
                        'tax',            // Tax — demo VirtualService retry
                        'media',          // Product image upload
                        'search',         // Search — demo AuthorizationPolicy
                        'storefront-bff', // BFF for storefront UI
                        'backoffice-bff', // BFF for backoffice UI
                        'sampledata'      // Data seeding — run once after initial deploy
                        // swagger-ui → uses public image swaggerapi/swagger-ui, no build needed
                    ]

                    // ----------------------------------------------------------
                    // Node.js (Next.js) services — built with npm
                    // ----------------------------------------------------------
                    def nodeServices = [
                        'storefront',     // → storefront-ui (customer-facing shop)
                        'backoffice'      // → backoffice-ui (admin panel)
                    ]

                    def allServices = mavenServices + nodeServices

                    // Get list of files changed compared to previous commit
                    def changedFiles = sh(
                        script: 'git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD',
                        returnStdout: true
                    ).trim()

                    echo "Files changed:\n${changedFiles}"

                    // Find which services have changed files
                    def changedServices = allServices.findAll { service ->
                        changedFiles.contains("${service}/")
                    }

                    // If nothing detected (e.g. first commit) → build all services
                    if (changedServices.isEmpty()) {
                        echo "No changed services detected → building all services"
                        changedServices = allServices
                    }

                    echo "Services to build: ${changedServices}"
                    env.SERVICES_TO_BUILD = changedServices.join(',')

                    // Separate changed services by build tool for downstream stages
                    env.MAVEN_SERVICES = changedServices.findAll { it in mavenServices }.join(',')
                    env.NODE_SERVICES  = changedServices.findAll { it in nodeServices  }.join(',')

                    echo "Maven services: ${env.MAVEN_SERVICES}"
                    echo "Node services:  ${env.NODE_SERVICES}"
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 3: Build & Test
        // Run Maven build for Java services and npm build for Node.js services
        // ----------------------------------------------------------------------
        stage('Build & Test') {
            parallel {
                // ----------------------------------------------------------
                // 3a: Maven (Java) services
                // ----------------------------------------------------------
                stage('Build & Test (Maven)') {
                    when { expression { env.MAVEN_SERVICES?.trim() } }
                    steps {
                        script {
                            def services = env.MAVEN_SERVICES.split(',')
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

                // ----------------------------------------------------------
                // 3b: Node.js (Next.js) services
                // ----------------------------------------------------------
                stage('Build & Test (Node.js)') {
                    when { expression { env.NODE_SERVICES?.trim() } }
                    steps {
                        script {
                            def services = env.NODE_SERVICES.split(',')
                            services.each { service ->
                                echo "=== npm build: ${service} ==="
                                dir(service) {
                                    sh 'npm ci'
                                    sh 'npm run build'
                                }
                            }
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 4: Build Docker Image
        // Tag image with commit SHA (Requirement 3) + "latest" if on main branch
        // ----------------------------------------------------------------------
        stage('Build Docker Image') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    services.each { service ->
                        def imageName = "${env.DOCKER_HUB_USER}/${service}"
                        echo "=== Docker build: ${imageName}:${env.IMAGE_TAG} ==="

                        // Build with 2 tags:
                        //   1. commit SHA (abc1234) → pinpoints exact version
                        //   2. IMAGE_TAG (latest or SHA) → primary tag
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
        // Stage 5: Push to Docker Hub
        // ----------------------------------------------------------------------
        stage('Push to Docker Hub') {
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
                            echo "=== Pushing: ${imageName} ==="
                            sh "docker push ${imageName}:${env.COMMIT_SHA}"
                            sh "docker push ${imageName}:${env.IMAGE_TAG}"
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 6: Update GitOps repo (values.yaml) and push
        // Triggers ArgoCD sync automatically
        // ----------------------------------------------------------------------
        stage('Update GitOps Repo') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')

                    def serviceToChart = [
                        'backoffice': 'backoffice-ui',
                        'storefront': 'storefront-ui',
                    ]

                    sh """
                        rm -rf yas-gitops
                        git clone https://github.com/tthphat/yas-gitops.git
                        cd yas-gitops
                    """

                    services.each { service ->
                        def chartName = serviceToChart.get(service, service)
                        def valuesPath = "k8s/charts/${chartName}/values.yaml"
                        echo "=== Updating ${valuesPath} → tag: ${env.COMMIT_SHA} ==="
                        sh "sed -i 's/^    tag:.*/    tag: ${env.COMMIT_SHA}/' yas-gitops/${valuesPath}"
                    }

                    sh """
                        cd yas-gitops
                        git add .
                        git -c user.name='Jenkins CI' -c user.email='ci@jenkins' commit -m "Update image tags to ${env.COMMIT_SHA}"
                        git push origin main
                        cd .. && rm -rf yas-gitops
                    """
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 7: Cleanup images on Jenkins agent to prevent disk fill-up
        // ----------------------------------------------------------------------
        stage('Cleanup') {
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
CI PIPELINE SUCCEEDED
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
CI PIPELINE FAILED
   Branch : ${env.BRANCH_NAME}
   Commit : ${env.COMMIT_SHA}
   Check Console Output for details
====================================================
            """
        }
    }
}
