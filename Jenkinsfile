pipeline {
    agent any

    environment {
        AWS_REGION      = 'us-east-2'
        ECR_REPO        = '149465511648.dkr.ecr.us-east-2.amazonaws.com/aws_coding_challenge_2-backend'
        CLUSTER_NAME    = 'aws_coding_challenge_2'
        IMAGE_TAG       = "${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout code') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker image') {
            steps {
                script {
                    sh 'docker build -t backend-app:${IMAGE_TAG} ./backend'
                }
            }
        }

        stage('Authenticate to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws_keys']]) {
                    script {
                        sh '''
                            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO
                        '''
                    }
                }
            }
        }

        stage('Tag and Push image to ECR') {
            steps {
                script {
                    sh '''
                        docker tag backend-app:${IMAGE_TAG} $ECR_REPO:${IMAGE_TAG}
                        docker tag backend-app:${IMAGE_TAG} $ECR_REPO:latest
                        docker push $ECR_REPO:${IMAGE_TAG}
                        docker push $ECR_REPO:latest
                    '''
                }
            }
        }

        stage('Deploy to EKS with Helm') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws_keys']]) {
                    script {
                        sh '''
                            aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
                            helm upgrade --install backend ./helm/backend \
                                --set image.repository=$ECR_REPO \
                                --set image.tag=${IMAGE_TAG}
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
