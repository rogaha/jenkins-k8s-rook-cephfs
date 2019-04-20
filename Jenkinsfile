pipeline {
    agent {
        kubernetes {
            label 'build-pod'
            defaultContainer 'jnlp'
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: docker
    image: docker:stable
    command:
    - cat
    tty: true
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
  - name: k8s-deploy
    image: rogaha/k8s-deploy
    command:
    - cat
    tty: true
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
"""
        }
    }

    environment {
        DOCKERHUB_CREDENTIALS = credentials('dockerhub_credentials')
        DOCKER_REPOSITORY = 'rogaha'
        APP_NAME = 'hello-nginx'
        HELM_RELEASE_NAME = 'dockercon-demo'
    }

    stages {
        stage('Build') {
            steps {
                script {
                    imageTag = imageTag()
                    imageName = "${DOCKERHUB_CREDENTIALS_USR}/${APP_NAME}:${imageTag}"
                }                
                container('docker') {
                    sh "docker build -t ${imageName} hello-nginx"
                }
            }
        }
        stage('Publish') {         
            steps {
                container('docker') {
                    sh "echo ${DOCKERHUB_CREDENTIALS_PSW}" +
                        " | docker login -u ${DOCKERHUB_CREDENTIALS_USR} --password-stdin"
                    sh "docker push ${imageName}"
                }
            }
        }
        stage('Deploy') {
            steps {
                container('k8s-deploy') {
                    sh "helm upgrade -i" +
                        " --namespace jenkins" +
                        " --set image.tag=${imageTag}" +
                        " ${APP_NAME} charts/${APP_NAME}"
                }
            }
        }
    }
}

def imageTag() {
    sh 'git rev-parse --short HEAD > commit-id'
    return readFile('commit-id')
        .replace('\n', '')
        .replace('\r', '')
}