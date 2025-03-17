pipeline {
    agent {
        docker
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
            environment {
                // DOCKER_IMAGE = "vcnngr/demo-java-app:${build_version}"
                REGISTRY_CREDENTIALS = credentials('dockerhub')
                // PATH="${tool 'docker'}/bin:${env.PATH}"
            }   
            steps {
                script {
                    sh 'docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} .'
                    def dockerImage = docker.image("${DOCKER_IMAGE}")
                    docker.withRegistry('https://index.docker.io/v1/', "dockerhub") {
                        dockerImage.push()
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
