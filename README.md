# Synopsis

This document describes in details the steps required to implement an automated storage management service on top of Kubernetes (a.k.a k8s) using the CSI interface that was promoted to GA in Kubernetes 1.13. The solution presented here will leverage the operator pattern used by Rook and CSI to provide a complete containerized and distributed storage system. Rook will use Ceph CSI and CephFS as its distributed storage engine and shared filesystem, respectively.

# Background

Deploying stateful applications such a Wordpress and Jenkins on top of Kubernetes or any other container orchestrator can be a challenging task. In this context, Rook will be used to showcase how to automatically manage the volume's lifecycle through the its Kubernetes operators (operator pattern approach) by leveraging the recently added CSI GA support.

# Design Goals

The solution described in this document has the following design objectives:

- Ability to deploy stateful applications that can be scaled up (ReadWriteMany) – this allows us to deploy multiple pods using the same volume mount path.
- Ability to manage the volume's lifecycle (attach, provision, snapshot, etc.) automatically.
- Ability to scale up and down the storage cluster automatically.
- All components are containerized (e.g. Jenkins master, Jenkins agents/workers, volume plugin, distributed storage cluster, etc.)

# Architecture

![arch](images/architecture.png?raw=true)

# Prerequisites

1. Kubernetes v1.13 or higher
2. Helm
3. Kubectl (Installed by [Docker for Desktop](https://hub.docker.com/editions/community/docker-ce-desktop-mac))
4. Clone repo [jenkins-k8s-rook-cephfs](https://github.com/rogaha/jenkins-k8s-rook-cephfs)

# Installing Helm on MacOS

## What is Helm?

Helm is the first application package manager running atop Kubernetes. It allows describing the application structure through convenient helm-charts and managing it with simple commands.

## Installation steps

For more details, or for other options, see [the installation guide](https://helm.sh/docs/using_helm/#installing-helm).

```

# Install helm client locally
$ brew install kubernetes-helm

# Install helm on the cluster
$ helm init --history-max 200

# TIP: Setting --history-max on helm init is recommended as configmaps and other objects in helm history can grow large in number if not purged by max limit. Without a max history set the history is kept indefinitely, leaving a large number of records for helm and tiller to maintain.

# Configure RBAC permissions
$ cd jenkins-k8s-rook-cephfs
~/jenkins-k8s-rook-cephfs$ kubectl create -f helm/rbac.yaml

# Update the existing tiller-deploy deployment with the service account created
~/jenkins-k8s-rook-cephfs$ helm init --service-account tiller --upgrade
$HELM_HOME has been configured at /Users/rogaha/.helm.

Tiller (the Helm server-side component) has been upgraded to the current version.
Happy Helming!
```

# Installing Rook

## What is Rook?

Rook is an open source cloud-native storage orchestrator, providing the platform, framework, and support for a diverse set of storage solutions to natively integrate with cloud-native environments.

## Rook's Design

![rook-design](images/rook_design.png?raw=true)

## Installation steps

```
# Create required custom resource definitions (CRDs) and necessary RBAC permissions
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/common.yaml

# Create Rook Operator
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/operator.yaml
```

# Deploying Ceph and CephFS

The Ceph cluster is currently configured to automatically detect all nodes with storage disks available in the cluster and add them to the storage cluster.

## Ceph components

- OSDs (Object Storage Daemon)
  - Serve stored objects to clients
  - Responsible for data rebalancing, recovery and replication
  - Peer to peer communication
- Monitor
  - Maintain cluster membership (use paxos consensus algorithm) – not in the data path.
- Manager
  - Responsible for keeping track of runtime metrics, cluster state, storage utilization as well as monitoring the ceph monitors and managers themselves.

## Installation steps

```
# Create toolbox
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/toolbox.yaml

# Expose dashboard service via ELB
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/dashboard-external-https.yaml

# Fetch dashboard password (default login: admin)
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo
```

## Ceph Dashboard

Ceph has a dashboard in which you can view the status of your cluster. Please see the [dashboard guide](https://github.com/rook/rook/blob/master/Documentation/ceph-dashboard.md) for more details.

```
# Create toolbox
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/toolbox.yaml

# Expose dashboard service via ELB
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/dashboard-external-https.yaml

# Fetch dashboard password (default login: admin)
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo
```

## Debugging

```
# Create ceph cluster tooling
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph create -f rook/toolbox.yaml

# Fetch cluster info
~/jenkins-k8s-rook-cephfs$ kubectl -n rook-ceph exec $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') ceph status
```

# Deploying Ceph CSI Driver

## Deployment steps

```
# Deploy CSI Ceph driver
~/jenkins-k8s-rook-cephfs$ cd rook/cephfs && ./deploy-plugin.sh

# Fetch rook operator password
~/jenkins-k8s-rook-cephfs$ kubectl exec -ti $(kubectl -n rook-ceph get pod -l "app=rook-ceph-operator" -o jsonpath='{.items[0].metadata.name}') ceph auth get-key client.admin|base64

# Update rook/cephfs/secret.yaml file with the password above (https://rook.io/docs/rook/master/ceph-csi-drivers.html)
# Create Ceph CSI secrets
~/jenkins-k8s-rook-cephfs$ kubectl create -f rook/cephfs/secret.yaml

# Update rook/cephfs/storegeclass.yaml file with the proper monitor pool name configurations
# Create Ceph CSI storage class
~/jenkins-k8s-rook-cephfs$ kubectl create -f rook/cephfs/storegeclass.yaml
```

# Installing Jenkins

The Jenkins workers will automatically adjust the docker group ID inside the Jenkins agent containers (see more details here). Agents are created on demands and all logs are streamed and stored into the CephFS shared filesystem, so need to worry about loosing data when a master node dies. Once the jobs are completed, the agents are automatically deleted and the requested resources are released back to the cluster.

#### Installed plugins

- kubernetes:1.15.1
- workflow-aggregator:2.6
- workflow-job:2.32
- credentials-binding:1.18
- docker-workflow:1.18
- docker-commons:1.14
- docker-traceability:1.2
- git:3.9.3
- ghprb:1.42.0
- blueocean:1.14.0
- Installation steps

## Installation steps

```
# Configure RBAC permissions
~/jenkins-k8s-rook-cephfs$ kubectl create -f jenkins/rbac.yaml

# Install Jenkins
~/jenkins-k8s-rook-cephfs$ helm install --name jenkins -f jenkins/chart-values.yaml stable/jenkins

kgp
NAME:   jenkins
LAST DEPLOYED: Sun Apr 21 01:24:01 2019
NAMESPACE: jenkins
STATUS: DEPLOYED

RESOURCES:
==> v1/ConfigMap
NAME           DATA  AGE
jenkins        6     1s
jenkins-tests  1     1s

==> v1/Deployment
NAME     READY  UP-TO-DATE  AVAILABLE  AGE
jenkins  0/1    0           0          1s

==> v1/PersistentVolumeClaim
NAME     STATUS   VOLUME      CAPACITY  ACCESS MODES  STORAGECLASS  AGE
jenkins  Pending  csi-cephfs  1s

==> v1/Secret
NAME     TYPE    DATA  AGE
jenkins  Opaque  2     1s

==> v1/Service
NAME           TYPE          CLUSTER-IP     EXTERNAL-IP  PORT(S)       AGE
jenkins        LoadBalancer  10.96.19.56    <pending>    80:33984/TCP  1s
jenkins-agent  ClusterIP     10.96.207.142  <none>       50000/TCP     1s

==> v1/ServiceAccount
NAME     SECRETS  AGE
jenkins  1        1s

==> v1beta1/ClusterRoleBinding
NAME                  AGE
jenkins-role-binding  1s


NOTES:
#### This chart is undergoing work which may result in breaking changes. ####
#### Please consult the following table and the README ####

Master.HostName --> Master.ingress.hostName
New value - Master.ingress.enabled
Master.Ingress.ApiVersion --> Master.ingress.apiVersion
Master.Ingress.Annotations --> Master.ingress.annotations
Master.Ingress.Labels --> Master.ingress.labels
Master.Ingress.Path --> Master.ingress.path
Master.Ingress.TLS --> Master.ingress.tls
Master.OwnSshKey, a bool, has been replaced with Master.AdminSshKey, which is expected to be a string containing the actual key

1. Get your 'admin' user password by running:
  printf $(kubectl get secret --namespace jenkins jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
2. Get the Jenkins URL to visit by running these commands in the same shell:
  NOTE: It may take a few minutes for the LoadBalancer IP to be available.
        You can watch the status of by running 'kubectl get svc --namespace jenkins -w jenkins'
  export SERVICE_IP=$(kubectl get svc --namespace jenkins jenkins --template "{{ range (index .status.loadBalancer.ingress 0) }}{{ . }}{{ end }}")
  echo http://$SERVICE_IP:80/login

3. Login with the password from step 1 and the username: admin


For more information on running Jenkins on Kubernetes, visit:
https://cloud.google.com/solutions/jenkins-on-container-engine
Configure the Kubernetes plugin in Jenkins to use the following Service Account name jenkins using the following steps:
  Create a Jenkins credential of type Kubernetes service account with service account name jenkins
  Under configure Jenkins -- Update the credentials config in the cloud section to use the service account credential you created in the step above.
```

This repo has a Jenkinsfile in the root directory to showcase an end-to-end application CI/CD pipeline using Docker Hub and Helm (see screenshots below).

### Workflow

![docker_ci_cd](images/docker_ci_cd.png?raw=true)

## Screenshots

![build_stage](images/build_stage.png?raw=true)
![publish_stage](images/publish_stage.png?raw=true)
![deploy_stage](images/deploy_stage.png?raw=true)
![jenkins_job](images/jenkins_job.png?raw=true)

# Reference

- https://rook.io/
- https://github.com/ceph/ceph-csi
- https://rook.io/docs/rook/master/ceph-csi-drivers.html
- https://helm.sh/
- https://github.com/helm/charts/tree/master/stable/jenkins
