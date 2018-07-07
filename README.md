## How to deploy Cloud Foundry Container Runtime (Kubernetes on BOSH) on AWS

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
prefix             = "changeme"
access_key         = "changeme"
secret_key         = "changeme"
region             = "ap-northeast-1"
availability_zones = ["ap-northeast-1a","ap-northeast-1c","ap-northeast-1d"]
vpc_cidr           = "10.0.0.0/16"
nat_instance_type  = "t2.nano"
EOF
```

Execute Terraform with the following command.

```
terraform init
terraform plan -out plan
terraform apply plan
```

The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/42409133-b6fc430a-8210-11e8-9970-4adcec6a4bf6.png)

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
git checkout v0.17.0
cd ..
git add -A
git commit -m "import CFCR v0.17.0"
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
    -v internal_cidr=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}') \
    -v internal_gw=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}' | sed 's|0/24|1|') \
    -v internal_ip=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}' | sed 's|0/24|252|') \
    -v access_key_id=${AWS_ACCESS_KEY_ID} \
    -v secret_access_key=${AWS_SECRET_ACCESS_KEY} \
    -v region=${region} \
    -v az=$(echo ${availability_zones} | awk -F ',' '{print $1}') \
    -v default_key_name=${default_key_name} \
    -v default_security_groups=[${default_security_groups}] \
    --var-file private_key=${HOME}/deployer.pem \
    -v subnet_id=$(echo ${private_subnet_ids} | awk -F ',' '{print $1}') \
    --vars-store=bosh-aws-creds.yml \
    --state bosh-aws-state.json
EOF
chmod +x deploy-bosh.sh
```

Execute the script to create BOSH Director.

```bash
./deploy-bosh.sh
```

![image](https://user-images.githubusercontent.com/106908/42380355-92610628-8168-11e8-9bcc-c0701a68b3b7.png)

The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/42409141-ce8ee860-8210-11e8-99c1-e57d6f8cb552.png)

If you want to update the BOSH Director , you can do `git pull` in `bosh-deployment` directory and then re-run `./deploy-bosh`.

#### BOSH Director settings

Make settings to access BOSH Director and log in to BOSH Director.

```bash
cat <<'EOF' > bosh-aws-env.sh
export BOSH_CLIENT=admin  
export BOSH_CLIENT_SECRET=$(bosh int ./bosh-aws-creds.yml --path /admin_password)
export BOSH_CA_CERT=$(bosh int ./bosh-aws-creds.yml --path /director_ssl/ca)
export BOSH_ENVIRONMENT=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}' | sed 's|0/24|252|')
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
Using environment '10.0.8.252' as client 'admin'

Name      bosh-aws  
UUID      7ad78602-70fa-434f-a79d-d5dda6006366  
Version   266.4.0 (00000000)  
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

We use [oficial template]((https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.17.0/configurations/aws/cloud-config.yml)) for the template of Cloud Config, 
but because `vm_type`'s name is different from the values used in [`cfcr.yml`](https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.17.0/manifests/cfcr.yml)
we create ops-file to rename ...

```
curl -L -o ops-files/aws-ops.yml https://github.com/cloudfoundry/bosh-bootloader/raw/master/cloudconfig/aws/fixtures/aws-ops.yml
```

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

Enable multi-az

```yaml
cat <<EOF > ops-files/cloud-config-multi-az.yml
- type: replace
  path: /azs/name=z1/cloud_properties/availability_zone
  value: ((az1_name))

- type: replace
  path: /azs/name=z2/cloud_properties/availability_zone
  value: ((az2_name))

- type: replace
  path: /azs/name=z3/cloud_properties/availability_zone
  value: ((az3_name))

- type: replace
  path: /networks/name=default
  value:
    name: default
    subnets:
    - az: z1
      gateway: ((az1_gateway))
      range: ((az1_range))
      reserved:
      - ((az1_gateway))/30
      cloud_properties:
        subnet: ((az1_subnet))
      dns:
      - ((dns_recursor_ip))
    - az: z2
      gateway: ((az2_gateway))
      range: ((az2_range))
      reserved:
      - ((az2_gateway))/30
      cloud_properties:
        subnet: ((az2_subnet))
      dns:
      - ((dns_recursor_ip))
    - az: z3
      gateway: ((az3_gateway))
      range: ((az3_range))
      reserved:
      - ((az3_gateway))/30
      cloud_properties:
        subnet: ((az3_subnet))
      dns:
      - ((dns_recursor_ip))
    type: manual
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
    -o ops-files/cloud-config-multi-az.yml \
    -v master_iam_instance_profile=${prefix}-cfcr-master \
    -v worker_iam_instance_profile=${prefix}-cfcr-worker \
    -v az1_name=$(echo ${availability_zones} | awk -F ',' '{print $1}') \
    -v az1_range=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}') \
    -v az1_gateway=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}' | sed 's|0/24|1|') \
    -v az1_subnet=$(echo ${private_subnet_ids} | awk -F ',' '{print $1}') \
    -v az2_name=$(echo ${availability_zones} | awk -F ',' '{print $2}') \
    -v az2_range=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $2}') \
    -v az2_gateway=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $2}' | sed 's|0/24|1|') \
    -v az2_subnet=$(echo ${private_subnet_ids} | awk -F ',' '{print $2}') \
    -v az3_name=$(echo ${availability_zones} | awk -F ',' '{print $3}') \
    -v az3_range=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $3}') \
    -v az3_gateway=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $3}' | sed 's|0/24|1|') \
    -v az3_subnet=$(echo ${private_subnet_ids} | awk -F ',' '{print $3}') \
    -v dns_recursor_ip=$(echo ${private_subnet_cidr_blocks} | awk -F ',' '{print $1}' | awk -F '.' '{print $1"."$2".0.2"}') \
    -v access_key_id=${AWS_ACCESS_KEY_ID} \
    -v secret_access_key=${AWS_SECRET_ACCESS_KEY} \
    -v region=${region} \
    -v master_target_pool=${prefix}-cfcr-api
EOF
chmod +x update-cloud-config.sh
```

Execute the following command.

```bash
./update-cloud-config.sh
```

#### Deploy a Kubernetes cluster

Deployment of Kubernetes is done based on [official manifest](https://github.com/cloudfoundry-incubator/kubo-deployment/blob/v0.17.0/manifests) with the difference applied by ops-files.

Create an ops-file to use CFCR 0.17.0.

```yaml
cat <<EOF > ops-files/kubernetes-kubo-0.17.0.yml
- type: replace
  path: /releases/name=kubo?
  value:
    name: kubo
    version: 0.17.0
    url: https://bosh.io/d/github.com/cloudfoundry-incubator/kubo-release?v=0.17.0
    sha1: 0ab676b9f6f5363377498e93487e8ba31622768e
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

Create a script to deploy Kubrnetes. We will use single master node.

```bash
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/misc/single-master.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.17.0.yml \
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

![image](https://user-images.githubusercontent.com/106908/42381708-e6535570-816c-11e8-8a00-a4773cf192ad.png)

Run `bosh vms` and `bosh instances --ps` to see the VM list and process list.

```
$ bosh -d cfcr vms
Using environment '10.0.8.252' as client 'admin'

Task 13. Done

Deployment 'cfcr'

Instance                                     Process State  AZ  IPs       VM CID               VM Type        Active  
master/0c9bf70c-db82-482d-b38f-fd05dfe0819d  running        z1  10.0.8.4  i-0662d0d4a543d63ba  small          true  
worker/d9808c82-0e18-4a45-87ce-c57b9874db2f  running        z1  10.0.8.5  i-0da422703dd4ecb8c  small-highmem  true  

2 vms

Succeeded
```

```
$ bosh -d cfcr instances --ps
Using environment '10.0.8.252' as client 'admin'

Task 12. Done

Deployment 'cfcr'

Instance                                           Process                  Process State  AZ  IPs  
apply-addons/73dd46d1-14ba-4b1b-8bd8-488f2ea3baaf  -                        -              z1  -  
master/0c9bf70c-db82-482d-b38f-fd05dfe0819d        -                        running        z1  10.0.8.4  
~                                                  bosh-dns                 running        -   -  
~                                                  bosh-dns-healthcheck     running        -   -  
~                                                  bosh-dns-resolvconf      running        -   -  
~                                                  etcd                     running        -   -  
~                                                  flanneld                 running        -   -  
~                                                  kube-apiserver           running        -   -  
~                                                  kube-controller-manager  running        -   -  
~                                                  kube-scheduler           running        -   -  
worker/d9808c82-0e18-4a45-87ce-c57b9874db2f        -                        running        z1  10.0.8.5  
~                                                  bosh-dns                 running        -   -  
~                                                  bosh-dns-healthcheck     running        -   -  
~                                                  bosh-dns-resolvconf      running        -   -  
~                                                  docker                   running        -   -  
~                                                  flanneld                 running        -   -  
~                                                  kube-proxy               running        -   -  
~                                                  kubelet                  running        -   -  

18 instances

Succeeded
```

If you want to updat CFCR, if there is no breaking change, you can do `git pull` int `kubo-deployment` and re-run `./deploy-kubernetes.sh`. 


The environment as shown in the following figure should be made.

![image](https://user-images.githubusercontent.com/106908/42409160-2c9ec920-8211-11e8-89cc-34b59249e11e.png)

#### Deploy Addons

Addons such as KubeDNS and Kubenetes Dashboard are deployed with errand. Execute the following command.

```bash
bosh -d cfcr run-errand apply-addons
```

#### Run smoke tests

```bash
bosh -d cfcr run-errand smoke-tests
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

### Scale out the k8s cluster

Let's scale out worker to 2 and master to 3 (must be odd).

```yaml
cat <<EOF > ops-files/kubernetes-worker.yml
- type: replace
  path: /instance_groups/name=worker/instances
  value: 2
EOF
```

```bash
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.17.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
```

```
./deploy-kubernetes.sh 
```

Run `bosh vms` to see the VM list.

```
$ bosh -d cfcr vms
Using environment '10.0.8.252' as client 'admin'

Task 18. Done

Deployment 'cfcr'

Instance                                     Process State  AZ  IPs        VM CID               VM Type        Active  
master/0c9bf70c-db82-482d-b38f-fd05dfe0819d  running        z1  10.0.8.4   i-0662d0d4a543d63ba  small          true  
master/517f31c1-d1a5-438d-b508-a0c45f0be822  running        z2  10.0.9.4   i-05acda1e48ce5da70  small          true  
master/d88a8853-d92e-4746-b7a4-c3e36fe741fd  running        z3  10.0.10.4  i-0e22869ccc18676c1  small          true  
worker/d9808c82-0e18-4a45-87ce-c57b9874db2f  running        z1  10.0.8.5   i-0da422703dd4ecb8c  small-highmem  true  
worker/ebcd08bf-eafb-403e-b0e4-c849971f4754  running        z2  10.0.9.5   i-05bb0c65aca895cb9  small-highmem  true  

5 vms

Succeeded
```

The environment as shown in the following figure should be made.
![image](https://user-images.githubusercontent.com/106908/42409164-37fa45ba-8211-11e8-851d-051914841641.png)

EC2 console will look like following:

![image](https://user-images.githubusercontent.com/106908/42382726-2926b48e-8170-11e8-9131-5c70d718caba.png)

### Enable UAA integration

[Enable UAA](enable-uaa.md)

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
