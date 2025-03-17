pipeline {
    agent any
    tools {
        dockerTool "docker"
    }
    // parameters {
    //     string(name: 'build_version', defaultValue: 'V1.6.10', description: 'Build version to use for Docker image')
    // }
    environment {
        // Docker & Helm Registry Credentials
        DOCKER_IMAGE = 'vcnngr/roundcube-ispconfig'
        DOCKER_TAG = 'v1.6.10'
        DOCKER_REGISTRY_CREDENTIALS = 'dockerhub'
        HELM_CHART_NAME = 'roundcube-ispconfig'
    }

    stages {
        stage('Checkout Code') {
            steps {
                // Pull source code from GitHub
                git branch: 'main', url: 'https://github.com/slackarea/roundcube-ispconfig.git'
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    docker.withRegistry('https://registry.hub.docker.com', DOCKER_REGISTRY_CREDENTIALS) {
                        // Build and push Docker image
                        def app = docker.build("${DOCKER_IMAGE}:${DOCKER_TAG}")
                        // app.push()
                    }
                }
            }
        }
        // stage('Deploy to Kubernetes using Helm') {
        //     steps {
        //         script {
        //             sh """
        //             # Update Helm chart values with new Docker image
        //             helm upgrade --install ${HELM_CHART_NAME} ./helm/${HELM_CHART_NAME} \
        //                 --set image.repository=${DOCKER_IMAGE} \
        //                 --set image.tag=${DOCKER_TAG} \
        //                 --namespace default
        //             """
        //         }
        //     }
        // }
    }
    post {
        success {
            echo 'Deployment completed successfully!'
        }
        failure {
            echo 'Deployment failed!'
        }
    }
}
