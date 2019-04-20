pipeline {
  agent any

  environment {
    DOCKERHUB_CREDENTIALS = credentials('dockerhub_credentials')
    DOCKER_REPOSITORY = 'rogaha'
    WEBSERVER_IMAGE = 'hello-nginx'
    HELM_RELEASE_NAME = 'dockercon-demo'
  }

  stages {

    stage('Build') {
      steps {
        sh 'hostname'
        sh 'docker login -u ${DOCKERHUB_CREDENTIALS_USR} -p ${DOCKERHUB_CREDENTIALS_PSW}'
        sh 'docker build -t ${DOCKERHUB_CREDENTIALS_USR}/${WEBSERVER_IMAGE}:${GIT_COMMIT} nginx'
      }
    }

    stage('Test') {
      steps {
        sh 'echo "tbd.."'
      }
    }

    stage('Manual Verification') {
      when {
        expression { return env.BRANCH_NAME == 'master' }
      }

      steps {
        input(message: 'Deploy to Production?', id: 'deploy_to_production')
      }
    }

    stage('deploy') {
      steps {
        sleep 10000
      }
    }
  }
}