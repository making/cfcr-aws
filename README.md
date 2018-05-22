## Deloy Cloud Foundry Container Runtime (Kubernetes on BOSH) on AWS

### Deploy CFCR

I have customized [the official way](https://docs-cfcr.cfapps.io/installing/) to install CFCR on AWS so that it would be more bosh-friendly.
Also changed Terraform template to get rid of manual operations by hands.

#### Pave the AWS environment with Terraform

First we will pave the AWS environment required for BOSH and Kubernete. We will use Terraform here.

Obtain [customized Terraform template]((https://github.com/making/cfcr-aws)).

```bash
git clone https://github.com/making/cfcr-aws.git
cd cfcr-aws/terraform
```

Prepare `terraform.tfvars`. `access_key` and `secret_key` are for an IAM user to run Terraform who has the `AdministratorAccess` Role.

```bash
cat <<EOF > terraform.tfvars
prefix                   = "demo"
access_key               = "abcdef"
secret_key               = "foobar"
region                   = "ap-northeast-1"
zone                     = "ap-northeast-1a"
vpc_cidr                 = "10.0.0.0/16"
public_subnet_ip_prefix  = "10.0.1"
private_subnet_ip_prefix = "10.0.2"
EOF
```

Execute Terraform with the following command.

```
terraform init
terraform plan -out plan
terraform apply plan
```

The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/40372551-eb314806-5e1f-11e8-97df-d665b321c33a.png)


#### Login to Bastion server

Next we will provision BOSH on a paved environment, but we will do the work on the Bastion server.

```bash
cat terraform.tfstate | jq -r '.modules[0].resources["tls_private_key.deployer"].primary.attributes.private_key_pem' > deployer.pem
chmod 600 deployer.pem
export BASTION_IP=`cat terraform.tfstate | jq -r '.modules[0].outputs["bosh_bastion_ip"].value'`

echo "ssh -o StrictHostKeyChecking=no -i $(pwd)/deployer.pem ubuntu@${BASTION_IP}" > ssh-bastion.sh
chmod +x ssh-bastion.sh
```

Execute ssh login to Bastion server by the following script.

```bash
./ssh-bastion.sh
```

#### Provision BOSH

Provision BOSH (BOSH Director) using [bosh-deployment](https://github.com/cloudfoundry/bosh-deployment). 
We also have [kubo-deployment](https://github.com/cloudfoundry-incubator/kubo-deployment) and manage with git.

```bash
mkdir cfcr-manifests
cd cfcr-manifests
git init
git submodule add https://github.com/cloudfoundry/bosh-deployment.git
git submodule add https://github.com/cloudfoundry-incubator/kubo-deployment.git
cd kubo-deployment
git checkout v0.16.0
cd ..
git add -A
git commit -m "import CFCR v0.16.0"
```

We will manage the difference file (ops-file) of YAML in the `ops-files` directory.

```bash
mkdir -p ops-files
```

Create an ops-file that makes the BOSH Director VM size smaller (`t2.small`).

```yaml
cat <<EOF > ops-files/director-size-aws.yml
- type: replace
  path: /resource_pools/name=vms/cloud_properties/instance_type
  value: t2.small
EOF
```

Create a script to provisioning BOSH. Environment variables have already been set to Bastion server in Terraform.

```bash
cat <<'EOF' > deploy-bosh.sh
#!/bin/bash
bosh create-env bosh-deployment/bosh.yml \
    -o bosh-deployment/aws/cpi.yml \
    -o bosh-deployment/uaa.yml \
    -o bosh-deployment/credhub.yml \
    -o bosh-deployment/jumpbox-user.yml \
    -o bosh-deployment/local-dns.yml \
    -o ops-files/director-size-aws.yml \
    -o kubo-deployment/configurations/generic/dns-addresses.yml \
    -o kubo-deployment/configurations/generic/bosh-admin-client.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/bosh/tags.yml \
    -v director_name=bosh-aws \
    -v internal_cidr=${private_subnet_ip_prefix}.0/24 \
    -v internal_gw=${private_subnet_ip_prefix}.1 \
    -v internal_ip=${private_subnet_ip_prefix}.252 \
    -v access_key_id=${AWS_ACCESS_KEY_ID} \
    -v secret_access_key=${AWS_SECRET_ACCESS_KEY} \
    -v region=${region} \
    -v az=${zone} \
    -v default_key_name=${default_key_name} \
    -v default_security_groups=[${default_security_groups}] \
    --var-file private_key=${HOME}/deployer.pem \
    -v subnet_id=${private_subnet_id} \
    --vars-store=bosh-aws-creds.yml \
    --state bosh-aws-state.json
EOF
chmod +x deploy-bosh.sh
```

Execute the script to create BOSH Director.

```bash
./deploy-bosh.sh
```

The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/40372434-a36b332e-5e1f-11e8-90e0-7ea768bb2b2f.png)

If you want to update the BOSH Director , you can do `git pull` in `bosh-deployment` directory and then re-run `./deploy-bosh`.

#### BOSH Director settings

Make settings to access BOSH Director and log in to BOSH Director.

```bash
cat <<'EOF' > bosh-aws-env.sh
export BOSH_CLIENT=admin  
export BOSH_CLIENT_SECRET=$(bosh int ./bosh-aws-creds.yml --path /admin_password)
export BOSH_CA_CERT=$(bosh int ./bosh-aws-creds.yml --path /director_ssl/ca)
export BOSH_ENVIRONMENT=${private_subnet_ip_prefix}.252
EOF
chmod +x bosh-aws-env.sh
```

Execute the following command.


```bash
source bosh-aws-env.sh
```

Confirm `bosh env` and `bosh login`.

```
$ bosh env
Using environment '10.0.2.252' as client 'admin'

Name      bosh-aws  
UUID      7feb01e4-0eee-4eae-a735-8e3183428087  
Version   265.2.0 (00000000)  
CPI       aws_cpi  
Features  compiled_package_cache: disabled  
          config_server: enabled  
          dns: disabled  
          snapshots: disabled  
User      admin  

Succeeded
```

```
$ bosh login
Successfully authenticated with UAA

Succeeded
```

#### Upload Stemcell

Upload Stemcell which is the template image of VM created by BOSH.

```
STEMCELL_VERSION=$(bosh int kubo-deployment/manifests/cfcr.yml --path /stemcells/0/version)
bosh upload-stemcell https://s3.amazonaws.com/bosh-aws-light-stemcells/light-bosh-stemcell-${STEMCELL_VERSION}-aws-xen-hvm-ubuntu-trusty-go_agent.tgz
```

#### Upate Cloud Config

We will create Cloud Config to set the IaaS environment on BOSH Director.

We use [oficial template]((https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.16.0/configurations/aws/cloud-config.yml)) for the template of Cloud Config, 
but because `vm_type`'s name is different from the values used in [`cfcr.yml`](https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.16.0/manifests/cfcr.yml)
we create ops-file to rename ...

```yaml
cat <<EOF > ops-files/cloud-config-rename-vm-types.yml
- type: replace
  path: /vm_types/name=master/name
  value: small
- type: replace
  path: /vm_types/name=worker/name
  value: small-highmem
- type: replace
  path: /compilation/vm_type
  value: small-highmem
EOF
```

Make `instance_type`s smaller.

```yaml
cat <<EOF > ops-files/cloud-config-small-vm-types.yml
- type: replace
  path: /vm_types/name=minimal/cloud_properties/instance_type
  value: t2.micro
- type: replace
  path: /vm_types/name=small/cloud_properties/instance_type
  value: t2.micro
- type: replace
  path: /vm_types/name=small-highmem/cloud_properties/instance_type
  value: t2.medium
EOF
```

Make `vm_extensions` to attach a load balancer to the Master API .

```yaml
cat <<EOF > ops-files/cloud-config-master-lb.yml
- type: replace
  path: /vm_extensions?/-
  value:
    name: master-lb
    cloud_properties:
      elbs:
      - ((master_target_pool))
EOF
```

Create a script to update Cloud Config.

```bash
cat <<'EOF' > update-cloud-config.sh
#!/bin/bash
bosh update-cloud-config kubo-deployment/configurations/aws/cloud-config.yml \
    -o ops-files/cloud-config-rename-vm-types.yml \
    -o ops-files/cloud-config-small-vm-types.yml \
    -o ops-files/cloud-config-master-lb.yml \
    -v az=${zone} \
    -v master_iam_instance_profile=${prefix}-cfcr-master \
    -v worker_iam_instance_profile=${prefix}-cfcr-worker \
    -v internal_cidr=${private_subnet_ip_prefix}.0/24 \
    -v internal_gw=${private_subnet_ip_prefix}.1 \
    -v dns_recursor_ip=${private_subnet_ip_prefix}.1 \
    -v subnet_id=${private_subnet_id} \
    -v master_target_pool=${prefix}-cfcr-api
EOF
chmod +x update-cloud-config.sh
```

Execute the following command.

```bash
./update-cloud-config.sh
```

#### Deploy a Kubernetes cluster

Deployment of Kubernetes is done based on [official manifest](https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.16.0/manifests) with the difference applied by ops-files.

Create an ops-file to use CFCR 0.16.0.

```yaml
cat <<EOF > ops-files/kubernetes-kubo-0.16.0.yml
- type: replace
  path: /releases/name=kubo?
  value:
    name: kubo
    version: 0.16.0
    url: https://bosh.io/d/github.com/cloudfoundry-incubator/kubo-release?v=0.16.0
    sha1: 8a513e48cccdea224c17a92ce73edbda04acee91
EOF
```

Create an ops-file that reduces the number of instances of Worker to 1. (Please change this value if you want to increase Worker)

```yaml
cat <<EOF > ops-files/kubernetes-worker.yml
- type: replace
  path: /instance_groups/name=worker/instances
  value: 1
EOF
```

Create an ops-file that adds `vm_extensions` to attach LB to Master and DNS name of ELB to SAN of Master's TLS certificate.

```yaml
cat <<EOF > ops-files/kubernetes-master-lb.yml
- type: replace
  path: /instance_groups/name=master/vm_extensions?/-
  value: master-lb

- type: replace
  path: /variables/name=tls-kubernetes/options/alternative_names/-
  value: ((kubernetes_master_host))
EOF
```

Addon which we want to register additionally at the time of deployment is smanaged under the `spec` directory.

```bash
mkdir -p specs
```

Create a spec that registers StorageClass for EBS as default.

```yaml
cat <<EOF > specs/aws-storage-class.yml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: EnsureExists
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
EOF
```

Create a script to deploy Kubrnetes.

```bash
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
chmod +x deploy-kubernetes.sh
```

Execute the following command to deploy. ( You need to enter `y` halfway.)

```bash
./deploy-kubernetes.sh
```

The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/40374599-59ebcdb2-5e24-11e8-8631-af8ef0c5f39d.png)

Run `bosh vms` and `bosh instances --ps` to see the VM list and process list.

```
$ bosh -d cfcr vms
Using environment '10.0.2.252' as client 'admin'

Task 13. Done

Deployment 'cfcr'

Instance                                     Process State  AZ  IPs       VM CID               VM Type        Active  
master/bc14d482-2481-4cd4-ab61-f8998959befe  running        z1  10.0.2.4  i-07b65c52ed5de9bfa  small          -  
worker/9a57034a-99a5-48cb-9db0-59841e083a8c  running        z1  10.0.2.5  i-0cadb8a54cec35909  small-highmem  -  
```

```
$ bosh -d cfcr instances --ps
Using environment '10.0.2.252' as client 'admin'

Task 14. Done

Deployment 'cfcr'

Instance                                           Process                  Process State  AZ  IPs  
apply-addons/70988ada-d3b8-4015-b2a7-de93ebd21e92  -                        -              z1  -  
master/bc14d482-2481-4cd4-ab61-f8998959befe        -                        running        z1  10.0.2.4  
~                                                  bosh-dns                 running        -   -  
~                                                  bosh-dns-healthcheck     running        -   -  
~                                                  bosh-dns-resolvconf      running        -   -  
~                                                  etcd                     running        -   -  
~                                                  flanneld                 running        -   -  
~                                                  kube-apiserver           running        -   -  
~                                                  kube-controller-manager  running        -   -  
~                                                  kube-scheduler           running        -   -  
worker/9a57034a-99a5-48cb-9db0-59841e083a8c        -                        running        z1  10.0.2.5  
~                                                  bosh-dns                 running        -   -  
~                                                  bosh-dns-healthcheck     running        -   -  
~                                                  bosh-dns-resolvconf      running        -   -  
~                                                  docker                   running        -   -  
~                                                  flanneld                 running        -   -  
~                                                  kube-proxy               running        -   -  
~                                                  kubelet                  running        -   -  

18 instances
```

If you want to updat CFCR, if there is no breaking change, you can do `git pull` int `kubo-deployment` and re-run `./deploy-kubernetes.sh`. 

#### Deploy Addons

Addons such as KubeDNS and Kubenetes Dashboard are deployed with errand. Execute the following command.

```bash
bosh -d cfcr run-errand apply-addons
```

#### Login to CredHub

Credentials information on Kubernetes clusters is stored in CredHub in BOSH Director VM. 
You need to access CredHub to get the TLS certificate and admin's password.

Create a script to log in to CredHub.

```bash
cat <<'EOF' > credhub-login.sh
#!/bin/bash
credhub login \
        -s ${BOSH_ENVIRONMENT}:8844 \
        --client-name=credhub-admin \
        --client-secret=$(bosh int ./bosh-aws-creds.yml --path /credhub_admin_client_secret) \
        --ca-cert <(bosh int ./bosh-aws-creds.yml --path /uaa_ssl/ca) \
        --ca-cert <(bosh int ./bosh-aws-creds.yml --path /credhub_ca/ca)
EOF
chmod +x credhub-login.sh
```

Run the script and log in to CredHub.

```bash
./credhub-login.sh
```

Since the access token to CredHub expires in one hour, login again when it expires.

#### Access to Kubernetes

Acquire admin's password from CredHub.

```bash
admin_password=$(credhub get -n /bosh-aws/cfcr/kubo-admin-password | bosh int - --path=/value)
```

Obtain the TLS CA certificate of the Master API.

```bash
tmp_ca_file="$(mktemp)"
credhub get -n /bosh-aws/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"
```

Set context for `kubectl`.

```bash
cluster_name="cfcr-aws"
user_name="admin-aws"
context_name="cfcr-aws"

kubectl config set-cluster "${cluster_name}" \
  --server="https://${master_lb_ip_address}:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true

kubectl config set-credentials "${user_name}" --token="${admin_password}"

kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"

kubectl config use-context "${context_name}"
```

Check the cluster info by `kubectl cluster-info`.

```
$ kubectl cluster-info
Kubernetes master is running at https://demo-cfcr-api-658626716.ap-northeast-1.elb.amazonaws.com:8443
Heapster is running at https://demo-cfcr-api-658626716.ap-northeast-1.elb.amazonaws.com:8443/api/v1/namespaces/kube-system/services/heapster/proxy
KubeDNS is running at https://demo-cfcr-api-658626716.ap-northeast-1.elb.amazonaws.com:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
monitoring-influxdb is running at https://demo-cfcr-api-658626716.ap-northeast-1.elb.amazonaws.com:8443/api/v1/namespaces/kube-system/services/monitoring-influxdb/proxy
```

Since the Master API is attached to the Internet Facing ELB,  the contents of `~/.kube/config` can be also used in the laptop.

Finally, the EC2 instances used in this article are as follows.

![image](https://user-images.githubusercontent.com/106908/40376301-f97e7fa6-5e28-11e8-99cf-e40fd3a309ff.png)


#### Limitations of CFCR 0.16.0

CFCR 0.16.0 does not support

* Multi-AZ
* Master HA

These will be supported in the next release (0.17.0).

### Destroy CFCR

Delete the used environment.

#### Destroy the Kubernetes

Delete the Kubernetes cluster with the following command. 
Note that ELB for Service provisioned by Kubernetes and EBS for Persistent Volume are out of BOSH management, so delete them with `kubectl` command in advance.

```bash
bosh -d cfcr delete-deployment
bosh -n clean-up --all
```

#### Delete the BOSH Director

Delete the BOSH Director with the following command.

```bash
eval "$(sed 's/create-env/delete-env/' deploy-bosh.sh)"
```

#### Delete the AWS environment

Delete the AWS environment with the following command.

```bash
terraform destroy
```
