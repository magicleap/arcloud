# Magic Leap AR Cloud
AR Cloud from Magic Leap allows for shared experiences using features such as 
**mapping**, **localization**, and **spacial anchors**.  It is easily installed
by the customer utilizing Kubernetes on their own preferred cloud infrastructure.


## Setting up AR Cloud
Setting up Magic Leap AR Cloud is a three step process.
1.  Review and setup the [system requirements](#system_requirements).
2.  Download and install AR Cloud.
3.  Verify your installation.


### System Requirements 
- [Kubernetes](https://kubernetes.io) is required with the following [minimum requirements](#kubernetes-minimum-requirements)
- [Istio](https://istio.io/) is required with the following following [minimum requirements](#istio-minimum-requirements)
- The following will be installed by default during the setup process.\
  These can be excluded for advanced deployments if using existing installations of these services.
   - [PostgreSQL](https://www.postgresql.org/)
   - [Nats](https://nats.io/)
   - [Key Cloak](https://www.keycloak.org/)
   - [MinIO](https://min.io/)
   - [Grafana](https://grafana.com/)
   - [Prometheus](https://prometheus.io/)


#### Kubernetes Minimum Requirements 
- Version 1.23 or above
- 4 CPU's
- 16 GB memory
- Enable HTTP load balancing


#### Istio Minimum Requirements 
- AR Cloud requires Istio **version 1.14** exactly. 
- DNS Preconfigured with cooresponding certificate for TLS
- Configure Istio Gateway
- Open the MQTT Port (8883)


## Setup of Infrastructure
To get started as quickly as possible, refer to these simple setup steps using google cloud.
For other cloud providers or infrastructure, refer to their specific documenation. 

Reserve a static IP
Reserver a Static IP address and assign it a DNS Record.
```sh
gcloud compute addresses create istio-ip --project={your-project} --region=us-central1
gcloud dns --project={your-project} record-sets create {your-domain} --type="A" --zone="{your-domain}" --rrdatas="{public-ip}" --ttl="30"
```


Create a Cluster.  Be sure to create a VPC prior to running this command and supply it as the subnetwork.
Refer to google cloud documentation for best practices [VPC](https://cloud.google.com/vpc/docs/vpc) and [Subnets](https://cloud.google.com/vpc/docs/subnets)
```sh
gcloud beta container --project "{your-project}" clusters create "cluster-1" --zone "us-central1-a" --no-enable-basic-auth --cluster-version "1.23.7-gke.1900" --release-channel "regular" --machine-type "e2-standard-4" --image-type "COS_CONTAINERD" --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --max-pods-per-node "110" --num-nodes "3" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/{your-project}/global/networks/default" --subnetwork "projects/{your-project}/regions/us-central1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --enable-shielded-nodes --node-locations "us-central1-a"
```

Login kubectl into the remote Cluster
```sh
gcloud container clusters get-credentials cluster-1 --zone us-central1-a --project {your-project}
```

Download and extract Istio.  Importan, AR Cloud requires Istio version 1.14.
```sh
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.14.1 sh -
cd istio-1.14.1
```

Install Istio with the static IP address reserved earlier.  Edit the istio.yaml
file to have the correct static IP address.
```sh
./bin/istioctl install -y -f ../setup/istio.yaml
```

Install the Istio gateway.
```sh
kubectl -n istio-system apply -f ../setup/gateway.yaml
```

Install Certificate Manager
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
kubectl -n istio-system apply -f ../setup/issuer.yaml
```

Request a Certificate for DNS. Edit the certificate.yaml
file to have the correct DNS name.
```sh
kubectl -n istio-system apply -f ../setup/certificate.yaml
```

Create the namespace
```sh
kubectl create namespace arcloud
kubectl label namespace arcloud istio-injection=enabled
```

Create the container registry secret.  This secret is used to access the AR Cloud images and is provided at the time of purchase.
```sh
kubectl --namespace arcloud create secret docker-registry container-registry --docker-server=quay.io --docker-username={username-to-quay} --docker-password={secret-to-quay}
```

## Install AR Cloud
- Download AR Cloud from the [release page](https://github.com/orgs/magicleap)
- Unzip the file release file.  For example: arcloud-bundle-0.25.25.zip
- cd arcloud-bundle-0.25.25
- Review and edit the values.yaml file.  Default values have been supplied for quick setup.
- Edit the **domain** field with your domain 
- Make sure you have the following installed on the computer running the installation
    - [Helm](https://helm.sh/)
    - [Kubctl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
    - [Istioctl](https://istio.io/latest/docs/setup/install/istioctl)
- Run the AR Cloud installation script
```sh
./setup.sh --set global.domain={your-domain}
```


## Verify your installation
After installation of AR Cloud, the script will output important information that should be noted and saved. Below is an example of that output.
To validate the installation we recommend going to the enterprise web console at the address displayed. To log into the site, use the Keycloak
credentials displayed as part of the output.  Once logged in a simple dashboard will show the health of the services after installation.
```sh
Enterprise Web:
--------------
http://arcloud.acme.io/

Username: aradmin
Password: ZfX8JlQKSmoFh3zbbaqOJZ56Id0xsm6k

Keycloak:
---------
http://arcloud.acme.io/auth/

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



## Advanced Setup
What is described above is used to get AR Cloud running quickly and in its simplest manor.
However, AR Cloud is built to be flexibile and support many configurations.
For example, MinIO can be configured to use object storage.  As part of the health check
routes used on the dashboard, access to this infrastructure will be validated.

Magic Leap recommends reviewing the installed infrastructure to align with best securitypractices listed below.
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
  - Avoid using nodes running Apparmor with container OS for the host nodes (or other minimal OS)
- General pointers
  - Deploy the system on its own namespace
  - Isolate the deployment’s namespace from other deployed assets on the network level
  - Limit access to relevant container registries only
  - Keep all components up-to-date
- Create Different DB users
- Assign different users their relevant permissions
- Create separate users when accessing Minio
  - https://docs.min.io/minio/baremetal/security/minio-identity-management/basic-authentication-with-minio-identity-provider.html
- Create a user for each system working the system
- Assign access to each user based on the following chart



## Integrations
AR Cloud logs telemetry information and service logs using [OpenTelemetry](https://opentelemetry.io/).
The default installation installs [Grafana](https://grafana.com/) and [Prometheus](https://prometheus.io/),
but these can be substitued with other OTEL complient solutions.

The **Health Check Endpoints** can be used to monitor the health of the system.  These primarily focus on 
connectivity to the underlying resources such as database access and file storage.

[Key Cloak](https://www.keycloak.org/) is provided by default to manage users and manage access to API's.
Users can be managed directly in Key Cloak or it can be used to federate an existing identity solution.

