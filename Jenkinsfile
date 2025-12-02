// VCNNGR Roundcube-ISPConfig Pipeline
// Uses Docker-in-Docker (DinD)

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
        booleanParam(name: 'SKIP_DOCKER_BUILD', defaultValue: false, description: 'Skip Docker build')
        booleanParam(name: 'SKIP_SECURITY_SCANS', defaultValue: false, description: 'Skip security scans')
    }
    
    environment {
        DOCKER_IMAGE = 'vcnngr/roundcube-ispconfig'
        HELM_CHART_NAME = 'roundcube-ispconfig'
        HELM_CHART_PATH = './helm/roundcube-ispconfig'
        CHARTS_REPO = 'slackarea/charts'
        SONAR_HOST_URL = 'http://sonarqube-sonarqube.jenkins.svc.cluster.local:9000'
        SONAR_PROJECT_KEY = 'roundcube-ispconfig'
        REPORTS_DIR = 'security-reports'
    }
    
    stages {
        stage('Wait for Docker') {
            steps {
                container('docker-cli') {
                    sh '''
                        echo "Waiting for Docker daemon..."
                        for i in $(seq 1 30); do
                            if docker info > /dev/null 2>&1; then
                                echo "Docker is ready"
                                exit 0
                            fi
                            sleep 2
                        done
                        exit 1
                    '''
                }
            }
        }
        
        stage('Setup') {
            steps {
                script {
                    env.DOCKER_TAG = "v${params.ROUNDCUBE_VERSION}"
                    env.CHART_VER = params.CHART_VERSION?.trim() ?: params.ROUNDCUBE_VERSION
                    env.RC_VERSION = params.ROUNDCUBE_VERSION
                }
                sh '''
                    mkdir -p ${REPORTS_DIR}
                    echo "=== Workspace contents ==="
                    ls -la
                    echo "=== Helm directory ==="
                    ls -la helm/ || echo "helm/ not found"
                    echo "=== Helm chart directory ==="
                    ls -la helm/roundcube-ispconfig/ || echo "helm/roundcube-ispconfig/ not found"
                    echo "=== Chart.yaml ==="
                    cat helm/roundcube-ispconfig/Chart.yaml || echo "Chart.yaml not found"
                '''
                echo "Roundcube: ${env.RC_VERSION} | Docker: ${env.DOCKER_TAG} | Chart: ${env.CHART_VER}"
            }
        }
        
        stage('Helm Lint') {
            steps {
                container('helm') {
                    sh '''
                        echo "=== Debug ==="
                        pwd
                        ls -la /home/jenkins/agent/workspace/roundcube-ispconfig/helm/roundcube-ispconfig/
                        cat /home/jenkins/agent/workspace/roundcube-ispconfig/helm/roundcube-ispconfig/Chart.yaml
                        echo "=== Helm version ==="
                        helm version
                        echo "=== Running helm lint with full path ==="
                        helm lint /home/jenkins/agent/workspace/roundcube-ispconfig/helm/roundcube-ispconfig || echo "Lint warnings/errors (non-blocking)"
                    '''
                }
            }
        }
        
        stage('Build Docker') {
            when { expression { return !params.SKIP_DOCKER_BUILD } }
            steps {
                container('docker-cli') {
                    sh '''
                        echo "=== Building Docker Image ==="
                        docker build \
                            --build-arg ROUNDCUBE_VERSION=${RC_VERSION} \
                            -t ${DOCKER_IMAGE}:${DOCKER_TAG} \
                            -t ${DOCKER_IMAGE}:latest \
                            .
                        docker images | grep ${DOCKER_IMAGE}
                    '''
                }
            }
        }
        
        stage('Trivy Scan') {
            when {
                allOf {
                    expression { return !params.SKIP_DOCKER_BUILD }
                    expression { return !params.SKIP_SECURITY_SCANS }
                }
            }
            steps {
                container('trivy') {
                    sh 'trivy image --severity HIGH,CRITICAL ${DOCKER_IMAGE}:${DOCKER_TAG} || true'
                }
            }
        }
        
        stage('Push Docker') {
            when { expression { return !params.SKIP_DOCKER_BUILD } }
            steps {
                container('docker-cli') {
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh '''
                            echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                            docker push ${DOCKER_IMAGE}:${DOCKER_TAG}
                            docker push ${DOCKER_IMAGE}:latest
                            echo "Pushed to DockerHub"
                        '''
                    }
                }
            }
        }
        
        stage('Prepare Helm') {
            steps {
                container('helm') {
                    sh '''
                        CHART_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/helm/roundcube-ispconfig"
                        echo "=== Current Chart.yaml ==="
                        cat ${CHART_PATH}/Chart.yaml
                        sed -i "s/^version:.*/version: ${CHART_VER}/" ${CHART_PATH}/Chart.yaml
                        sed -i "s/^appVersion:.*/appVersion: \\"${DOCKER_TAG}\\"/" ${CHART_PATH}/Chart.yaml
                        echo "=== Updated Chart.yaml ==="
                        cat ${CHART_PATH}/Chart.yaml
                    '''
                }
            }
        }
        
        stage('Package Helm') {
            steps {
                container('helm') {
                    withCredentials([
                        file(credentialsId: 'gpg-signing-key', variable: 'GPG_KEY'),
                        string(credentialsId: 'gpg-passphrase', variable: 'GPG_PASS')
                    ]) {
                        sh '''
                            apk add --no-cache gnupg
                            export GNUPGHOME=$(mktemp -d)
                            chmod 700 ${GNUPGHOME}
                            gpg --batch --import ${GPG_KEY}
                            gpg --export-secret-keys > ${GNUPGHOME}/secring.gpg
                            CHART_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/helm/roundcube-ispconfig"
                            PKG_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/helm/packages"
                            mkdir -p ${PKG_PATH}
                            echo "${GPG_PASS}" > /tmp/pass
                            helm package ${CHART_PATH} \
                                --sign \
                                --key "VCNNGR Helm Signing" \
                                --keyring ${GNUPGHOME}/secring.gpg \
                                --passphrase-file /tmp/pass \
                                --destination ${PKG_PATH}
                            rm /tmp/pass
                            ls -la ${PKG_PATH}/
                        '''
                    }
                }
            }
        }
        
        stage('Publish Helm') {
            steps {
                container('tools') {
                    withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
                        sh '''
                            apk add --no-cache git
                            PKG_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/helm/packages"
                            REPO_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/charts-repo"
                            git clone https://${GH_TOKEN}@github.com/${CHARTS_REPO}.git ${REPO_PATH}
                            cp ${PKG_PATH}/*.tgz ${REPO_PATH}/
                            cp ${PKG_PATH}/*.prov ${REPO_PATH}/
                            cd ${REPO_PATH}
                            git config user.email "jenkins@vcnngr.com"
                            git config user.name "Jenkins"
                            git add .
                            git commit -m "Release ${HELM_CHART_NAME}-${CHART_VER}" || true
                            git push origin main
                        '''
                    }
                }
                container('helm') {
                    withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
                        sh '''
                            apk add --no-cache git
                            REPO_PATH="/home/jenkins/agent/workspace/roundcube-ispconfig/charts-repo"
                            cd ${REPO_PATH}
                            helm repo index . --url https://slackarea.github.io/charts --merge index.yaml || helm repo index . --url https://slackarea.github.io/charts
                            git add index.yaml
                            git commit -m "Update index" || true
                            git push origin main
                        '''
                    }
                }
            }
        }
    }
    
    post {
        success { echo "SUCCESS: ${DOCKER_IMAGE}:${env.DOCKER_TAG}" }
        failure { echo "FAILED - check logs" }
    }
}
