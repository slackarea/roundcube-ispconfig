// VCNNGR Roundcube-ISPConfig Pipeline
// Build Docker image + Helm chart signed + publish
// Uses Docker-in-Docker (DinD) - no host socket required

pipeline {
    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    job: roundcube-ispconfig
spec:
  serviceAccountName: jenkins-agent
  securityContext:
    runAsUser: 0
    fsGroup: 0
  volumes:
    - name: docker-storage
      emptyDir: {}
  containers:
  - name: docker
    image: docker:24-dind
    securityContext:
      privileged: true
    env:
      - name: DOCKER_TLS_CERTDIR
        value: ""
    volumeMounts:
      - name: docker-storage
        mountPath: /var/lib/docker
  - name: docker-cli
    image: docker:24-cli
    command: [cat]
    tty: true
    env:
      - name: DOCKER_HOST
        value: tcp://localhost:2375
  - name: helm
    image: alpine/helm:3.14.0
    command: [cat]
    tty: true
  - name: trivy
    image: aquasec/trivy:latest
    command: [cat]
    tty: true
    env:
      - name: DOCKER_HOST
        value: tcp://localhost:2375
  - name: sonar
    image: sonarsource/sonar-scanner-cli:latest
    command: [cat]
    tty: true
  - name: tools
    image: alpine:3.19
    command: [cat]
    tty: true
'''
        }
    }
    
    parameters {
        string(name: 'ROUNDCUBE_VERSION', defaultValue: '1.6.10', description: 'Roundcube version to build')
        string(name: 'CHART_VERSION', defaultValue: '', description: 'Helm chart version (leave empty to use ROUNDCUBE_VERSION)')
        booleanParam(name: 'SKIP_DOCKER_BUILD', defaultValue: false, description: 'Skip Docker build (use existing image)')
        booleanParam(name: 'SKIP_SECURITY_SCANS', defaultValue: false, description: 'Skip security scans (faster build)')
        booleanParam(name: 'FORCE_BUILD', defaultValue: false, description: 'Force rebuild even if version exists')
    }
    
    environment {
        // Docker configuration
        DOCKER_IMAGE = 'vcnngr/roundcube-ispconfig'
        DOCKER_TAG = "v${params.ROUNDCUBE_VERSION}"
        
        // Helm configuration
        HELM_CHART_NAME = 'roundcube-ispconfig'
        HELM_CHART_PATH = './helm/roundcube-ispconfig'
        CHARTS_REPO = 'slackarea/charts'
        
        // GPG Signing
        GPG_KEY_NAME = 'VCNNGR Helm Signing'
        
        // SonarQube (internal cluster URL)
        SONAR_HOST_URL = 'http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000'
        SONAR_PROJECT_KEY = 'roundcube-ispconfig'
        
        // Reports directory
        REPORTS_DIR = 'security-reports'
        
        // Credentials
        DOCKERHUB = credentials('dockerhub')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
        timeout(time: 2, unit: 'HOURS')
        ansiColor('xterm')
    }
    
    stages {
        stage('Wait for Docker') {
            steps {
                container('docker-cli') {
                    sh '''
                        echo "Waiting for Docker daemon to start..."
                        for i in $(seq 1 30); do
                            if docker info > /dev/null 2>&1; then
                                echo "✅ Docker daemon is ready"
                                docker version
                                break
                            fi
                            echo "Waiting... ($i/30)"
                            sleep 2
                        done
                    '''
                }
            }
        }
        
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/slackarea/roundcube-ispconfig.git'
                
                sh "mkdir -p ${REPORTS_DIR}"
                
                script {
                    env.FINAL_CHART_VERSION = params.CHART_VERSION?.trim() ?: params.ROUNDCUBE_VERSION
                    
                    echo """
╔══════════════════════════════════════════════════════════════╗
║           ROUNDCUBE-ISPCONFIG BUILD                          ║
╠══════════════════════════════════════════════════════════════╣
║  Roundcube Version: ${params.ROUNDCUBE_VERSION}
║  Docker Tag:        ${DOCKER_TAG}
║  Chart Version:     ${env.FINAL_CHART_VERSION}
║  Skip Docker:       ${params.SKIP_DOCKER_BUILD}
║  Skip Security:     ${params.SKIP_SECURITY_SCANS}
╚══════════════════════════════════════════════════════════════╝
                    """
                }
            }
        }
        
        // ============================================================
        // STATIC CODE ANALYSIS
        // ============================================================
        
        stage('Dockerfile Lint') {
            when {
                expression { return !params.SKIP_SECURITY_SCANS }
            }
            steps {
                container('docker-cli') {
                    script {
                        sh '''
                            echo "=== Hadolint - Dockerfile Best Practices ==="
                            docker run --rm -i hadolint/hadolint < Dockerfile > ${REPORTS_DIR}/hadolint-report.txt 2>&1 || true
                            cat ${REPORTS_DIR}/hadolint-report.txt
                        '''
                    }
                }
            }
        }
        
        stage('Helm Lint') {
            steps {
                container('helm') {
                    sh """
                        echo "=== Helm Lint ===" | tee ${REPORTS_DIR}/helm-lint.txt
                        helm lint ${HELM_CHART_PATH} 2>&1 | tee -a ${REPORTS_DIR}/helm-lint.txt || true
                        
                        echo ""
                        echo "=== Helm Template Test ===" | tee -a ${REPORTS_DIR}/helm-lint.txt
                        helm template test ${HELM_CHART_PATH} > /dev/null 2>&1 && echo "Template OK" | tee -a ${REPORTS_DIR}/helm-lint.txt || echo "Template issues found"
                    """
                }
            }
        }
        
        stage('SonarQube Analysis') {
            when {
                expression { return !params.SKIP_SECURITY_SCANS }
            }
            steps {
                container('sonar') {
                    withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                        sh """
                            echo "=== SonarQube Analysis ==="
                            sonar-scanner \
                                -Dsonar.host.url=${SONAR_HOST_URL} \
                                -Dsonar.token=\${SONAR_TOKEN} \
                                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                -Dsonar.projectName="Roundcube ISPConfig" \
                                -Dsonar.projectVersion=${params.ROUNDCUBE_VERSION} \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=**/node_modules/**,**/*.tgz,**/security-reports/** \
                                || echo "SonarQube scan completed with warnings"
                        """
                    }
                }
            }
        }
        
        // ============================================================
        // DOCKER BUILD
        // ============================================================
        
        stage('Build Docker Image') {
            when {
                expression { return !params.SKIP_DOCKER_BUILD }
            }
            steps {
                container('docker-cli') {
                    sh """
                        echo "=== Building Docker Image ==="
                        docker build \
                            --build-arg ROUNDCUBE_VERSION=${params.ROUNDCUBE_VERSION} \
                            --label org.opencontainers.image.version=${params.ROUNDCUBE_VERSION} \
                            --label org.opencontainers.image.created=\$(date -Iseconds) \
                            --label org.opencontainers.image.source=https://github.com/slackarea/roundcube-ispconfig \
                            --no-cache \
                            --pull \
                            -t ${DOCKER_IMAGE}:${DOCKER_TAG} \
                            -t ${DOCKER_IMAGE}:latest \
                            .
                        
                        echo "=== Built Images ==="
                        docker images | grep ${DOCKER_IMAGE}
                    """
                }
            }
        }
        
        // ============================================================
        // SECURITY SCANNING
        // ============================================================
        
        stage('Trivy Vulnerability Scan') {
            when {
                allOf {
                    expression { return !params.SKIP_DOCKER_BUILD }
                    expression { return !params.SKIP_SECURITY_SCANS }
                }
            }
            steps {
                container('trivy') {
                    sh """
                        echo "=== Trivy Vulnerability Scan ===" | tee ${REPORTS_DIR}/trivy-report.txt
                        
                        trivy image \
                            --severity LOW,MEDIUM,HIGH,CRITICAL \
                            --format table \
                            ${DOCKER_IMAGE}:${DOCKER_TAG} 2>&1 | tee -a ${REPORTS_DIR}/trivy-report.txt || true
                        
                        echo ""
                        echo "=== Generating JSON report ==="
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format json \
                            --output ${REPORTS_DIR}/trivy-report.json \
                            ${DOCKER_IMAGE}:${DOCKER_TAG} || true
                    """
                }
            }
        }
        
        stage('Trivy Config Scan') {
            when {
                expression { return !params.SKIP_SECURITY_SCANS }
            }
            steps {
                container('trivy') {
                    sh """
                        echo "=== Trivy Config/IaC Scan ===" | tee ${REPORTS_DIR}/trivy-config.txt
                        trivy config \
                            --severity LOW,MEDIUM,HIGH,CRITICAL \
                            . 2>&1 | tee -a ${REPORTS_DIR}/trivy-config.txt || true
                    """
                }
            }
        }
        
        stage('Generate SBOM') {
            when {
                allOf {
                    expression { return !params.SKIP_DOCKER_BUILD }
                    expression { return !params.SKIP_SECURITY_SCANS }
                }
            }
            steps {
                container('trivy') {
                    sh """
                        echo "=== Generating SBOM ==="
                        
                        trivy image \
                            --format spdx-json \
                            --output ${REPORTS_DIR}/sbom-spdx.json \
                            ${DOCKER_IMAGE}:${DOCKER_TAG} || true
                        
                        trivy image \
                            --format cyclonedx \
                            --output ${REPORTS_DIR}/sbom-cyclonedx.json \
                            ${DOCKER_IMAGE}:${DOCKER_TAG} || true
                        
                        echo "SBOM generated: sbom-spdx.json, sbom-cyclonedx.json"
                    """
                }
            }
        }
        
        // ============================================================
        // DOCKER PUSH
        // ============================================================
        
        stage('Push Docker Image') {
            when {
                expression { return !params.SKIP_DOCKER_BUILD }
            }
            steps {
                container('docker-cli') {
                    sh """
                        echo "=== Logging in to DockerHub ==="
                        echo "\${DOCKERHUB_PSW}" | docker login -u "\${DOCKERHUB_USR}" --password-stdin
                        
                        echo "=== Pushing ${DOCKER_IMAGE}:${DOCKER_TAG} ==="
                        docker push ${DOCKER_IMAGE}:${DOCKER_TAG}
                        
                        echo "=== Pushing ${DOCKER_IMAGE}:latest ==="
                        docker push ${DOCKER_IMAGE}:latest
                        
                        echo "✅ Pushed to DockerHub successfully"
                    """
                }
            }
        }
        
        // ============================================================
        // HELM PACKAGING
        // ============================================================
        
        stage('Prepare Helm Chart') {
            steps {
                container('helm') {
                    sh """
                        cd ${HELM_CHART_PATH}
                        
                        # Backup originale
                        cp Chart.yaml Chart.yaml.bak
                        
                        # Aggiorna Chart.yaml - version e appVersion
                        sed -i 's/^version:.*/version: ${FINAL_CHART_VERSION}/' Chart.yaml
                        sed -i 's/^appVersion:.*/appVersion: "${DOCKER_TAG}"/' Chart.yaml
                        
                        echo "=== Updated Chart.yaml ==="
                        cat Chart.yaml
                        
                        echo ""
                        echo "=== Updating Helm dependencies ==="
                        helm dependency update .
                    """
                }
            }
        }
        
        stage('Package & Sign Helm Chart') {
            steps {
                container('helm') {
                    withCredentials([
                        file(credentialsId: 'gpg-signing-key', variable: 'GPG_KEYRING'),
                        string(credentialsId: 'gpg-passphrase', variable: 'GPG_PASSPHRASE')
                    ]) {
                        sh '''#!/bin/sh
                            set -e
                            
                            # Install GPG in Alpine-based helm container
                            apk add --no-cache gnupg
                            
                            # Setup GPG temporaneo
                            export GNUPGHOME=$(mktemp -d)
                            chmod 700 ${GNUPGHOME}
                            
                            echo "=== Importing GPG key ==="
                            gpg --batch --import ${GPG_KEYRING}
                            gpg --list-secret-keys --keyid-format LONG
                            
                            # Esporta in formato legacy per Helm
                            gpg --export-secret-keys > ${GNUPGHOME}/secring.gpg
                            gpg --export > ${GNUPGHOME}/pubring.gpg
                            
                            # Crea directory packages
                            mkdir -p helm/packages
                            
                            # Passphrase file
                            PASSPHRASE_FILE=$(mktemp)
                            echo "${GPG_PASSPHRASE}" > ${PASSPHRASE_FILE}
                            
                            echo "=== Packaging and signing Helm chart ==="
                            cd helm
                            helm package roundcube-ispconfig \
                                --sign \
                                --key "VCNNGR Helm Signing" \
                                --keyring ${GNUPGHOME}/secring.gpg \
                                --passphrase-file ${PASSPHRASE_FILE} \
                                --destination ./packages
                            
                            rm -f ${PASSPHRASE_FILE}
                            
                            echo "=== Generated packages ==="
                            ls -la ./packages/
                            
                            echo "=== Verifying signature ==="
                            helm verify ./packages/*.tgz --keyring ${GNUPGHOME}/pubring.gpg && echo "✅ Signature valid!"
                            
                            rm -rf ${GNUPGHOME}
                        '''
                    }
                }
            }
        }
        
        // ============================================================
        // PUBLISH HELM CHART
        // ============================================================
        
        stage('Publish to Charts Repo') {
            steps {
                container('tools') {
                    withCredentials([
                        string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')
                    ]) {
                        sh """
                            apk add --no-cache git
                            
                            echo "=== Publishing to GitHub Pages ==="
                            
                            rm -rf charts-repo
                            git clone https://\${GITHUB_TOKEN}@github.com/${CHARTS_REPO}.git charts-repo
                            
                            cd charts-repo
                            
                            # Copia i nuovi packages
                            cp ../helm/packages/*.tgz .
                            cp ../helm/packages/*.prov .
                            
                            # Configura git
                            git config user.email "jenkins@vcnngr.com"
                            git config user.name "Jenkins CI"
                            
                            git add .
                            git commit -m "Release ${HELM_CHART_NAME}-${FINAL_CHART_VERSION}

Docker Image: ${DOCKER_IMAGE}:${DOCKER_TAG}
Roundcube Version: ${ROUNDCUBE_VERSION}
Build: ${BUILD_NUMBER}" || echo "Nothing to commit"
                            
                            git push origin main
                            
                            echo "✅ Published to https://slackarea.github.io/charts"
                        """
                    }
                }
                
                // Update index.yaml with helm container
                container('helm') {
                    withCredentials([
                        string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')
                    ]) {
                        sh """
                            apk add --no-cache git
                            
                            cd charts-repo
                            
                            # Aggiorna index.yaml
                            if [ -f index.yaml ]; then
                                helm repo index . --url https://slackarea.github.io/charts --merge index.yaml
                            else
                                helm repo index . --url https://slackarea.github.io/charts
                            fi
                            
                            git add index.yaml
                            git commit -m "Update index.yaml" || echo "Index already up to date"
                            git push origin main
                        """
                    }
                }
            }
        }
        
        // ============================================================
        // ARCHIVE REPORTS
        // ============================================================
        
        stage('Archive Reports') {
            steps {
                archiveArtifacts artifacts: "${REPORTS_DIR}/**/*", allowEmptyArchive: true
            }
        }
    }
    
    post {
        success {
            echo """
╔══════════════════════════════════════════════════════════════╗
║                    ✅ BUILD SUCCESSFUL                       ║
╠══════════════════════════════════════════════════════════════╣
║  Docker Image: ${DOCKER_IMAGE}:${DOCKER_TAG}
║  Helm Chart:   ${HELM_CHART_NAME}-${FINAL_CHART_VERSION}
║  Charts Repo:  https://slackarea.github.io/charts
║                                                              ║
║  Usage:                                                      ║
║    helm repo add vcnngr https://slackarea.github.io/charts   ║
║    helm repo update                                          ║
║    helm install roundcube vcnngr/${HELM_CHART_NAME}          ║
╚══════════════════════════════════════════════════════════════╝
            """
        }
        failure {
            echo '❌ Build failed! Check logs for details.'
        }
        unstable {
            echo '⚠️ Build completed with warnings (security issues found)'
        }
        cleanup {
            sh 'rm -rf charts-repo helm/packages || true'
        }
    }
}
