# Magic Leap AR Cloud
AR Cloud from Magic Leap allows for shared experiences using features such as 
**mapping**, **localization**, and **spatial anchors**.  It is easily installed
by the customer utilizing Kubernetes on their own preferred cloud infrastructure.

## Setting up AR Cloud
Setting up Magic Leap AR Cloud is a three step process.
1.  Review and setup the [system requirements](#system_requirements).
2.  Download and install AR Cloud.
3.  Verify your installation.

### System Requirements 
- [Kubernetes](https://kubernetes.io) is required with the following [minimum requirements](#kubernetes-minimum-requirements)
- [Istio](https://istio.io/) is required with the following following [minimum requirements](#istio-minimum-requirements)
- [Helm](https://helm.sh/) is required with the following following [minimum requirements](#helm-minimum-requirements)
- The following will be installed by default during the setup process.
  These can be excluded for advanced deployments if using existing installations of these services.
   - [PostgreSQL](https://www.postgresql.org/) w/ the [PostGIS extension](https://postgis.net/)
   - [Nats](https://nats.io/)
   - [Key Cloak](https://www.keycloak.org/)
   - [MinIO](https://min.io/)
   - [Grafana](https://grafana.com/)
   - [Prometheus](https://prometheus.io/)

#### Kubernetes Minimum Requirements
- Version **1.23.x, 1.24.x, 1.25.x**
- 3 Nodes (each with):
  - 4 CPU's
  - 16 GB memory

#### Kubernetes Recommended Requirements
- Version **1.23.x, 1.24.x, 1.25.x**
- 8 Nodes (each with):
  - 8 CPU's
  - 32 GB memory

Example [machine types in GCP](https://cloud.google.com/compute/docs/general-purpose-machines):
- 8 * e2-medium
- 4 * e2-standard-2
- 2 * e2-standard-4

Example [instance types in AWS](https://aws.amazon.com/ec2/instance-types/):
- 8 * t3.medium
- 4 * m5.large
- 2 * m5.xlarge

#### Local Development Requirements
- Version **1.23.x, 1.24.x, 1.25.x**
- 1 Node:
  - 6 CPU's
  - 10 GB memory

#### Istio Minimum Requirements
- AR Cloud requires Istio **version 1.16.x**.
- DNS Pre-configured with corresponding certificate for TLS
- Configure Istio Gateway
- Open the MQTT Port (8883)

#### Helm Minimum Requirements
- Version **3.9.x**

### Tooling
- Ensure you have the following tooling installed on the computer running the installation.
  - [Helm](https://helm.sh/)
  - [Kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
  - [jq](https://stedolan.github.io/jq) _(used in some select scripts)_

## Download AR Cloud
- Download AR Cloud from the [release page](https://github.com/magicleap/arcloud/releases)
- Unzip the release file.  For example: arcloud-1.x.x.zip
- `cd arcloud-1.x.x`

## Environment Settings

In your terminal configure the following variables per your environment.
```sh
# AR Cloud
export NAMESPACE="arcloud"
export DOMAIN="arcloud.domain.tld"

# Container Registry
export REGISTRY_SERVER="quay.io"
export REGISTRY_USERNAME="your-registry-username"
export REGISTRY_PASSWORD="your-registry-password"
```

Alternatively, make a copy of the `./setup/env.example`, update the values
and source it in your terminal:
```sh
cp setup/env.example setup/env.my-cluster
# use your favourite editor to update the setup/env.my-cluster file
. setup/env.my-cluster
```

## Setup of Infrastructure

### Infrastructure on GCP
To get started as quickly as possible, refer to these simple setup steps using [google cloud](https://cloud.google.com/sdk/docs/install).

#### Environment Settings

In your terminal configure the following variables per your environment.
```sh
export GC_PROJECT_ID="your-project"
export GC_REGION="your-region"
export GC_ZONE="your-region-zone"
export GC_DNS_ZONE="your-dns-zone"
export GC_ADDRESS_NAME="your-cluster-ip"
export GC_CLUSTER_NAME="your-cluster-name"
```

_NOTE: These variables are already included in the [env file](#environment-settings) described above._

#### Reserve a static IP
```sh
gcloud compute addresses create "${GC_ADDRESS_NAME}" --project="${GC_PROJECT_ID}" --region="${GC_REGION}"
```

#### Retrieved the reserved static IP Address
```sh
export IP_ADDRESS=$(gcloud compute addresses describe "${GC_ADDRESS_NAME}" --project="${GC_PROJECT_ID}" --region="${GC_REGION}" --format='get(address)')
echo ${IP_ADDRESS}
```

#### Assign the static IP to a DNS Record
```sh
gcloud dns --project="${GC_PROJECT_ID}" record-sets create "${DOMAIN}" --type="A" --zone="${GC_DNS_ZONE}" --rrdatas="${IP_ADDRESS}" --ttl="30"
```

#### Create a Cluster

_NOTE: Be sure to create a VPC prior to running this command and supply it as the subnetwork. Refer to google cloud documentation for best practices [VPC](https://cloud.google.com/vpc/docs/vpc), [Subnets](https://cloud.google.com/vpc/docs/subnets)
and [Regions / Zones](https://cloud.google.com/compute/docs/regions-zones)_

```sh
gcloud container clusters create "${GC_CLUSTER_NAME}" \
    --project="${GC_PROJECT_ID}" \
    --zone "${GC_ZONE}" \
    --release-channel "regular" \
    --machine-type "e2-standard-4" \
    --num-nodes "3" \
    --enable-shielded-nodes
```

#### Login kubectl into the remote Cluster
```sh
gcloud container clusters get-credentials ${GC_CLUSTER_NAME} --zone=${GC_ZONE} --project=${GC_PROJECT_ID}
```

#### Confirm kubectl is directed at the correct context
```sh
kubectl config current-context
```

*NOTE: Expected response: `gke_{your-project}-{your-region}-{your-cluster}`*

### Infrastructure on AWS

Make sure that the following tools are installed and configured:
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)
- [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
-   SSH client - a key pair is required and can be generated using:
    ```sh
    ssh-keygen -t rsa -b 4096
    ```

#### Environment Settings

In your terminal configure the following variables per your environment.
```sh
export AWS_PROFILE="your-profile"
export AWS_ACCOUNT_ID="your-account-id"
export AWS_REGION="your-region"
export AWS_CLUSTER_NAME="your-cluster-name"
```

_NOTE: These variables are already included in the [env file](#environment-settings) described above._

#### Sample cluster configurations

The two options below are alternatives that can be used depending on your preferences:
- Option 1 - an unmanaged node group is used, manual installation of add-ons is required
- Option 2 - an managed node group is used, add-ons and service accounts are installed automatically

##### Option 1: Bare-bone cluster with non-managed node group

Adjust the `./setup/eks-cluster.yaml` file to your needs and create the cluster:
```sh
cat ./setup/eks-cluster.yaml | envsubst | eksctl create cluster -f -
```
Wait until the command finishes and verify the results in [CloudFormation](https://console.aws.amazon.com/cloudformation).

Confirm kubectl is directed at the correct context:
```sh
kubectl config current-context
```

*NOTE: Expected response: `{your-email}@{your-cluster}.{your-region}.eksctl.io`*

Complete the following guides to install additional required cluster components:
- [Amazon EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html):
    - [Creating the Amazon EBS CSI driver IAM role for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html)
    - [Managing the Amazon EBS CSI driver as an Amazon EKS add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html)
- [Installing the AWS Load Balancer Controller add-on](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [Managing the Amazon VPC CNI plugin for Kubernetes add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)

*NOTE: In case of problems installing the VPC CNI plugin, do not provide the version, so the default one is used instead.*

##### Option 2: Preconfigured cluster with managed node group and preinstalled add-ons

Adjust the `./setup/eks-cluster-managed-with-addons.yaml` file to your needs and create
the cluster:
```sh
cat ./setup/eks-cluster-managed-with-addons.yaml | envsubst | eksctl create cluster -f -
```
Wait until the command finishes and verify the results in [CloudFormation](https://console.aws.amazon.com/cloudformation).

Confirm kubectl is directed at the correct context:
```sh
kubectl config current-context
```

*NOTE: Expected response: `{your-email}@{your-cluster}.{your-region}.eksctl.io`*

Install the AWS Load Balancer Controller (use the image repository for the selected region based on this
[list](https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html)), e.g.:
```sh
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$AWS_CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set image.repository=602401143452.dkr.ecr.eu-west-3.amazonaws.com/amazon/aws-load-balancer-controller
```

#### Cluster verification

To make sure the cluster is correctly configured you can run the following commands:

1.  Check if your cluster is accessible using eksctl:
    ```sh
    eksctl get cluster --region $AWS_REGION --name $AWS_CLUSTER_NAME -o yaml
    ```

    The cluster status should be ACTIVE.

1.  Verify that the OIDC issuer is configured, e.g.:
    ```yaml
      Identity:
        Oidc:
          Issuer: https://oidc.eks.eu-west-3.amazonaws.com/id/0A6729247C19177211F7EE71E85F9F50
    ```

1.  Check if the add-ons are installed on your cluster:
    ```sh
    eksctl get addons --region $AWS_REGION --cluster $AWS_CLUSTER_NAME -o yaml
    ```

    There should be 2 add-ons and their status should be ACTIVE.

### Alternative deployments

For other cloud providers or infrastructure, refer to their specific documentation.

## Install Cluster Services

### Install Istio

Download and extract Istio.  Important, AR Cloud requires Istio version 1.16.
```sh
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.16.0 sh -
cd istio-1.16.0
```

Install Istio with the static IP address reserved earlier in GCP. For AWS just run the command as is.
```sh
cat ../setup/istio.yaml | envsubst | ./bin/istioctl install -y -f -
```

Install the Istio gateway.
```sh
kubectl -n istio-system apply -f ../setup/gateway.yaml
```

#### For AWS only:

1.  Check the ELB address for the just created service and export it for later use:
    ```sh
    export AWS_ELB_DOMAIN=$(kubectl -n istio-system get svc istio-ingressgateway --template '{{(index .status.loadBalancer.ingress 0).hostname}}')
    echo $AWS_ELB_DOMAIN
    ```

1. Modify your DNS zone by adding a CNAME entry for your domain pointing to the ELB address displayed in the previous step.

1.  Update the load balancer attributes to increase the idle timeout:
    ```sh
    aws elb modify-load-balancer-attributes \
        --load-balancer-name ${AWS_ELB_DOMAIN%%-*} \
        --region $AWS_REGION \
        --load-balancer-attributes ConnectionSettings={IdleTimeout=360}
    ```

Navigate back to the base AR Cloud directory.
```sh
cd ../
```

### Install Certificate Manager

Certificate Manager uses LetsEncrypt to sign the domain certificate.

_NOTE: This step can be skipped if you are configuring your own certificates, or do not intend to use TLS with your local development installation._

```sh
CERT_MANAGER_VERSION=1.9.1
helm upgrade --install --wait --repo https://charts.jetstack.io cert-manager cert-manager \
  --version ${CERT_MANAGER_VERSION} \
  --create-namespace \
  --namespace cert-manager \
  --set installCRDs=true
```

Configure the LetsEncrypt Issuer
```sh
kubectl -n istio-system apply -f ./setup/issuer.yaml
```

Request a Certificate for DNS.
```sh
cat ./setup/certificate.yaml | envsubst | kubectl -n istio-system apply -f -
```

## Install AR Cloud

### Create the namespace, and enable Istio.
```sh
kubectl create namespace ${NAMESPACE}
kubectl label namespace ${NAMESPACE} istio-injection=enabled
```

### Create the container registry secret.

This secret is used to access the AR Cloud images, and is provided at the time of purchase.

```sh
kubectl --namespace ${NAMESPACE} delete secret container-registry --ignore-not-found
kubectl --namespace ${NAMESPACE} create secret docker-registry container-registry --docker-server=${REGISTRY_SERVER} --docker-username=${REGISTRY_USERNAME} --docker-password=${REGISTRY_PASSWORD}
```

### Docker Login

Login docker to the container registry

_NOTE: This step is only necessary if you are setting up a local development installation._

```sh
echo ${REGISTRY_PASSWORD} | docker login ${REGISTRY_SERVER} \
  --username "${REGISTRY_USERNAME}" \
  --password-stdin
```

### Configuration

Review the `values.yaml` file, as default values have been supplied for setup.

Review the Magic Leap 2 SLA at https://www.magicleap.com/software-license-agreement-ml2

_NOTE: To indicate your acceptance of the SLA, you will need to add the `--accept-sla` flag to the following commands_

### Option 1: Install AR Cloud to your Kubernetes Cluster

The following step is used to install AR Cloud into a multi-node Kubernetes cluster.

```sh
./setup.sh --set global.domain=${DOMAIN}
```

### Option 2: Install AR Cloud for Local Development

The following step configures an **insecure** install of AR Cloud meant for local development purposes.

_NOTE: To consume fewer resources, observability can be disabled with the addition of the `--no-observability` flag._

```sh
./setup.sh --set global.domain=${DOMAIN} --update-docker --no-secure
```

## Verify your installation
After installation of AR Cloud, the script will output important information that should be noted and saved. Below is an example of that output.
To validate the installation we recommend going to the enterprise web console at the address displayed. To log into the site, use the Keycloak
credentials displayed as part of the output.  Once logged in a simple dashboard will show the health of the services after installation.
```sh
Enterprise Web:
--------------
https://arcloud.acme.io/

Username: aradmin
Password: ZfX8JlQKSmoFh3zbbaqOJZ56Id0xsm6k

Keycloak:
---------
https://arcloud.acme.io/auth/

Username: admin
Password: 02cewPjTxy7baUCaJL10OGHggTmHQfmW

MinIO:
------
kubectl -n arcloud port-forward svc/minio 8082:81
http://127.0.0.1:8082/

Username: 5QrjxFC2JRHWLSMZT7IO
Password: XDFJgFSBVGQaN9yH93qFMhe8vtVW7nBtqWT0DTlU

PostgreSQL:
------
kubectl -n arcloud port-forward svc/postgresql 5432:5432
psql -h 127.0.0.1 -p 5432 -U postgres -W

Username: postgres
Password: UaL0qZH4lv5mdqiiRF8etgBSvwJYHL8w

Grafana:
---------
kubectl -n arcloud port-forward svc/grafana 8080:80
http://127.0.0.1:8080/

Username: admin
Password: NZiJfE4N18B4ir8CE9I0A1lWGr35xaM2OWscCjcf

Prometheus:
---------
kubectl -n arcloud port-forward svc/prometheus-server 8081:80
http://127.0.0.1:8081/
```

### Configure Magic Leap 2 devices to use AR Cloud
To configure Magic Leap 2 devices to use the newly installed instance of AR Cloud, the device must be aware of where AR Cloud exists.
This is done by scanning the QR Code on the **device configuration** page of the enterprise console.  This page is located under the
*Device Management* menu and then the *Configure* option.


## Secure deployment best pratices
Magic Leap recommends reviewing the installed infrastructure to align with security best practices listed below.
- Configure Kubernetes secrets to use a secret manager such as Vault together with an
[external secret operator](https://github.com/external-secrets/external-secrets).
- Follow security best practices when deploying each of the preexisting components
  - Best practices for a [Kubernetes Secure Deployment](https://kubernetes.io/blog/2016/08/security-best-practices-kubernetes-deployment/)
  - Follow the [Kubernetes Hardening Guide](https://www.cisa.gov/uscert/ncas/current-activity/2022/03/15/updated-kubernetes-hardening-guide)
  - Deployment guide for [OPA](https://www.openpolicyagent.org/docs/latest/deployments/)
  - Deployment best practices for [Istio](https://istio.io/latest/docs/ops/best-practices/deployment/)
  - Secuirty guidelines for [PostgreSQL](https://www.postgresql.org/docs/7.0/security.htm)
  - IAM (GCP)
    - Use [workload identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
    - Useage of [GCP Cloud SQL proxy with IAM authentication](https://cloud.google.com/sql/docs/postgres/authentication)
- Enable SSL, for example [here](https://docs.gitlab.com/ee/topics/offline/quick_start_guide.html#enabling-ssl)
- What do Avoid?
  - Avoid permissive IAM policies in your environment
  - Avoid public IPs for nodes
- General pointers
  - Deploy the system on its own namespace
  - Isolate the deployment’s namespace from other deployed assets on the network level
  - Limit access to relevant container registries only
  - Make sure to run nodes running Apparmor with Container OS for the host nodes (or other minimal OS)
  - Keep all components up-to-date


## Advanced Setup
What is described above is used to get AR Cloud running quickly and in its simplest manor.
However, AR Cloud is built to be flexible and can support many configurations.
For example, MinIO can be configured to use object storage, and even managed PostgreSQL
instances with high availability and integrated backups.

### Managed Database

The following steps outline the steps for connecting AR Cloud to the managed database instance.

*NOTE: These steps only apply to a new installation of AR Cloud.*

#### PostgreSQL Minimum Requirements
- PostgreSQL Version: `14+`
- PostGIS Version: `3.3+`

*NOTE: The PostGIS extension must be enabled on the `arcloud` database.*

#### Database Configuration

- Review and configure all settings within the `./scripts/setup-database.sh` script.

- Execute the `./scripts/setup-database.sh` script against the managed database instance.

- Create Kubernetes database secrets for each application within your AR Cloud namespace. Secret names are referenced for each AR Cloud application, see the `values.yaml` file `postgresql.existingSecret` keys.

#### AR Cloud Setup

When running the `./setup.sh` script, you will need to supply the following additional settings in order to disable the default installation of postgresql, and point application connections to the managed database.

```sh
./setup.sh ... --set postgresql.enabled=false,global.postgresql.host=${POSTGRESQL_HOST},global.postgresql.port=${POSTGRESQL_PORT}
```

## Integrations
AR Cloud logs telemetry information and service logs using [OpenTelemetry](https://opentelemetry.io/).
The default installation installs [Grafana](https://grafana.com/) and [Prometheus](https://prometheus.io/),
but these can be substituted with other OTEL compliant solutions.

The **Health Check Endpoints** can be used to monitor the health of the system.  These primarily focus on 
connectivity to the underlying resources such as database access and file storage.

[Key Cloak](https://www.keycloak.org/) is provided by default to manage users and manage access to API's.
Users can be managed directly in Key Cloak or it can be used to federate an existing identity solution.
