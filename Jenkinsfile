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
                                docker version
                                exit 0
                            fi
                            echo "Waiting... ($i/30)"
                            sleep 2
                        done
                        echo "Docker failed to start"
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
                sh "mkdir -p ${REPORTS_DIR}"
                echo "Roundcube: ${env.RC_VERSION} | Docker: ${env.DOCKER_TAG} | Chart: ${env.CHART_VER}"
            }
        }
        
        stage('Helm Lint') {
            steps {
                container('helm') {
                    sh 'helm lint ${HELM_CHART_PATH} || true'
                }
            }
        }
        
        stage('Build Docker') {
            when { expression { return !params.SKIP_DOCKER_BUILD } }
            steps {
                container('docker-cli') {
                    sh '''
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
                    withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'U', passwordVariable: 'P')]) {
                        sh '''
                            echo "${P}" | docker login -u "${U}" --password-stdin
                            docker push ${DOCKER_IMAGE}:${DOCKER_TAG}
                            docker push ${DOCKER_IMAGE}:latest
                        '''
                    }
                }
            }
        }
        
        stage('Prepare Helm') {
            steps {
                container('helm') {
                    sh '''
                        cd ${HELM_CHART_PATH}
                        sed -i "s/^version:.*/version: ${CHART_VER}/" Chart.yaml
                        sed -i "s/^appVersion:.*/appVersion: \\"${DOCKER_TAG}\\"/" Chart.yaml
                        cat Chart.yaml
                        helm dependency update .
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
                            mkdir -p helm/packages
                            echo "${GPG_PASS}" > /tmp/pass
                            cd helm
                            helm package roundcube-ispconfig \
                                --sign \
                                --key "VCNNGR Helm Signing" \
                                --keyring ${GNUPGHOME}/secring.gpg \
                                --passphrase-file /tmp/pass \
                                --destination ./packages
                            rm /tmp/pass
                            ls -la packages/
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
                            git clone https://${GH_TOKEN}@github.com/${CHARTS_REPO}.git charts-repo
                            cp helm/packages/*.tgz charts-repo/
                            cp helm/packages/*.prov charts-repo/
                            cd charts-repo
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
                            cd charts-repo
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
