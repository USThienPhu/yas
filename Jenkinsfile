pipeline {
    agent any

    // ==========================================================================
    // Trigger on every git push (branch or tag) (Requirement 3)
    // Requires: "GitHub Integration" or "Generic Webhook Trigger" plugin
    //           and a Webhook configured on GitHub pointing to Jenkins
    // ==========================================================================
    triggers {
        githubPush()
    }

    environment {
        DOCKER_HUB_USER  = 'thaithienphu'
        DOCKER_HUB_CREDS = 'dockerhub-credentials'
        GIT_OPS_CREDS    = 'gitops-credentials'
        YAS_GITOPS_REPO  = 'https://github.com/tthphat/yas-gitops.git'

        COMMIT_SHA = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'latest'}"

        // For tag push (v*): IMAGE_TAG = tag name, e.g. v1.2.3
        // For main branch:     IMAGE_TAG = latest
        // Otherwise:           IMAGE_TAG = commit SHA
        IMAGE_TAG = "${env.TAG_NAME ?: (env.BRANCH_NAME == 'main' ? 'latest' : env.COMMIT_SHA)}"

        // Detect if this is a staging release (tag v*)
        IS_STAGING = "${env.TAG_NAME != null && env.TAG_NAME =~ /v.*/ ? 'true' : 'false'}"
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
        // For tag triggers: compare with previous tag or build all
        // For branch push:  compare HEAD~1 with HEAD
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

                    // For tag push: compare with previous tag, else build all
                    // For branch push: compare HEAD~1 with HEAD
                    def changedFiles = ''
                    if (env.TAG_NAME) {
                        def prevTag = sh(
                            script: 'git tag --sort=-creatordate | head -2 | tail -1 || true',
                            returnStdout: true
                        ).trim()
                        if (prevTag) {
                            changedFiles = sh(
                                script: "git diff --name-only ${prevTag}..${env.TAG_NAME}",
                                returnStdout: true
                            ).trim()
                        }
                    }
                    if (!changedFiles) {
                        changedFiles = sh(
                            script: 'git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD',
                            returnStdout: true
                        ).trim()
                    }

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
        // Tag convention:
        //   - main branch:    abc1234 (GitOps) + latest (developer_build)
        //   - tag v*:         v1.2.3 (GitOps) only
        //   - feature branch: abc1234 only
        // ----------------------------------------------------------------------
        stage('Build Docker Image') {
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')
                    def extraTag = env.BRANCH_NAME == 'main' ? 'latest' : ''
                    def tags = [env.IMAGE_TAG]
                    if (extraTag) tags.add(extraTag)

                    services.each { service ->
                        def imageName = "${env.DOCKER_HUB_USER}/${service}"
                        def tagArgs = tags.collect { "-t ${imageName}:${it}" }.join(' ')
                        echo "=== Docker build: ${imageName}:${tags.join(', ')} ==="
                        sh "docker build ${tagArgs} ./${service}"
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
                    def extraTag = env.BRANCH_NAME == 'main' ? 'latest' : ''
                    def tags = [env.IMAGE_TAG]
                    if (extraTag) tags.add(extraTag)

                    withCredentials([usernamePassword(
                        credentialsId: env.DOCKER_HUB_CREDS,
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"

                        services.each { service ->
                            def imageName = "${env.DOCKER_HUB_USER}/${service}"
                            tags.each { tag ->
                                echo "=== Pushing: ${imageName}:${tag} ==="
                                sh "docker push ${imageName}:${tag}"
                            }
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // Stage 6: Update GitOps repo and push
        // - main branch → update values.yaml (dev)
        // - tag v*     → update values.staging.yaml (staging)
        // Triggers ArgoCD sync automatically
        // ----------------------------------------------------------------------
        stage('Update GitOps Repo') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.IS_STAGING == 'true' }
                }
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(',')

                    def serviceToChart = [
                        'backoffice': 'backoffice-ui',
                        'storefront': 'storefront-ui',
                    ]

                    def valuesFile = env.IS_STAGING == 'true' ? 'values.staging.yaml' : 'values.yaml'
                    def deployEnv = env.IS_STAGING == 'true' ? 'staging' : 'dev'
                    // For CI (main): use commit SHA as tag (e.g. abc1234)
                    // For staging-release: use version tag (e.g. v1.2.3)
                    def updateTag = env.IS_STAGING == 'true' ? env.IMAGE_TAG : env.COMMIT_SHA
                    def commitMsg = env.IS_STAGING == 'true'
                        ? "Release ${env.TAG_NAME}: update image tags to ${env.COMMIT_SHA}"
                        : "Update image tags to ${env.COMMIT_SHA}"

                    withCredentials([gitUsernamePassword(
                        credentialsId: env.GIT_OPS_CREDS
                    )]) {
                        sh """
                            rm -rf yas-gitops
                            git clone https://github.com/tthphat/yas-gitops.git
                            cd yas-gitops
                            git config user.name 'Jenkins CI'
                            git config user.email 'ci@jenkins'
                        """

                        services.each { service ->
                            def chartName = serviceToChart.get(service, service)
                            def valuesPath = "k8s/charts/${chartName}/${valuesFile}"
                            echo "=== Updating ${valuesPath} → tag: ${updateTag} ==="
                            sh "sed -i 's/^    tag:.*/    tag: ${updateTag}/' yas-gitops/${valuesPath}"
                        }

                        sh """
                            cd yas-gitops
                            git add .
                            git commit -m "${commitMsg}"
                            git push origin main
                            cd .. && rm -rf yas-gitops
                        """
                    }

                    echo "Updated ${deployEnv} GitOps → ArgoCD will auto-sync"
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
                    def extraTag = env.BRANCH_NAME == 'main' ? 'latest' : ''
                    def tags = [env.IMAGE_TAG]
                    if (extraTag) tags.add(extraTag)

                    services.each { service ->
                        def imageName = "${env.DOCKER_HUB_USER}/${service}"
                        tags.each { tag ->
                            sh "docker rmi ${imageName}:${tag} || true"
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            script {
                env.DEPLOY_ENV = env.IS_STAGING == 'true' ? 'staging' : (env.BRANCH_NAME == 'main' ? 'dev' : 'none')
            }
            echo """
============================================================
PIPELINE SUCCEEDED
   Type      : ${env.TAG_NAME ?: env.BRANCH_NAME ?: 'unknown'}
   Commit    : ${env.COMMIT_SHA}
   Image Tag : ${env.IMAGE_TAG}
   Services  : ${env.SERVICES_TO_BUILD}
   Deploy to : ${env.DEPLOY_ENV}
   Docker Hub: https://hub.docker.com/u/${env.DOCKER_HUB_USER}
============================================================
            """
        }
        failure {
            echo """
============================================================
PIPELINE FAILED
   Type   : ${env.TAG_NAME ?: env.BRANCH_NAME ?: 'unknown'}
   Commit : ${env.COMMIT_SHA}
   Check Console Output for details
============================================================
            """
        }
    }
}
