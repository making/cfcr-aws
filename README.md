```
cd terraform

cat <<EOF > terraform.tfvars
prefix             = "demo"
access_key         = "abcdef"
secret_key         = "foobar"
region             = "ap-northeast-1"
zone               = "ap-northeast-1a"
vpc_cidr           = "10.0.0.0/16"
ROF

terraform init
terraform plan -out plan
terraform apply plan
```

```
cat terraform.tfstate | jq -r '.modules[0].resources["tls_private_key.deployer"].primary.attributes.private_key_pem' > deployer.pem
export BASTION_IP=`cat terraform.tfstate | jq -r '.modules[0].outputs["bosh_bastion_ip"].value'`

echo "ssh -o StrictHostKeyChecking=no -i $(pwd)/deployer.pem ubuntu@${BASTION_IP}" > ssh-bastion.sh
chmod +x ssh-bastion.sh
```

```
./ssh-bastion.sh
```

```
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

```
mkdir -p ops-files
```

```
cat <<EOF > ops-files/director-size-lite.yml
- type: replace
  path: /resource_pools/name=vms/cloud_properties/instance_type
  value: t2.small
EOF
```

```
cat <<'EOF' > deploy-bosh.sh
#!/bin/bash
bosh create-env bosh-deployment/bosh.yml \
    -o bosh-deployment/aws/cpi.yml \
    -o bosh-deployment/uaa.yml \
    -o bosh-deployment/credhub.yml \
    -o bosh-deployment/jumpbox-user.yml \
    -o bosh-deployment/local-dns.yml \
    -o ops-files/director-size-lite.yml \
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

```
./deploy-bosh.sh
```

```
cat <<'EOF' > bosh-aws-env.sh
export BOSH_CLIENT=admin  
export BOSH_CLIENT_SECRET=$(bosh int ./bosh-aws-creds.yml --path /admin_password)
export BOSH_CA_CERT=$(bosh int ./bosh-aws-creds.yml --path /director_ssl/ca)
export BOSH_ENVIRONMENT=${private_subnet_ip_prefix}.252
EOF
chmod +x bosh-aws-env.sh
```

```
source bosh-aws-env.sh
```

```
STEMCELL_VERSION=$(bosh int kubo-deployment/manifests/cfcr.yml --path /stemcells/0/version)
bosh upload-stemcell https://s3.amazonaws.com/bosh-aws-light-stemcells/light-bosh-stemcell-${STEMCELL_VERSION}-aws-xen-hvm-ubuntu-trusty-go_agent.tgz
```

```
cat <<EOF > ops-files/cloud-config-small-vm-types.yml
- type: replace
  path: /vm_types/name=minimal/cloud_properties/instance_type
  value: t2.micro
- type: replace
  path: /vm_types/name=master/name
  value: small
- type: replace
  path: /vm_types/name=small/cloud_properties/instance_type
  value: t2.micro
- type: replace
  path: /vm_types/name=worker/name
  value: small-highmem
- type: replace
  path: /vm_types/name=small-highmem/cloud_properties/instance_type
  value: t2.medium
- type: replace
  path: /compilation/vm_type
  value: small-highmem
EOF
```

```
cat <<'EOF' > update-cloud-config.sh
#!/bin/bash
bosh update-cloud-config kubo-deployment/configurations/aws/cloud-config.yml \
    -o ops-files/cloud-config-small-vm-types.yml \
    -v az=${zone} \
    -v master_iam_instance_profile=${prefix}-cfcr-master \
    -v worker_iam_instance_profile=${prefix}-cfcr-worker \
    -v internal_cidr=${private_subnet_ip_prefix}.0/24 \
    -v internal_gw=${private_subnet_ip_prefix}.1 \
    -v dns_recursor_ip=${private_subnet_ip_prefix}.1 \
    -v subnet_id=${private_subnet_id}
EOF
chmod +x update-cloud-config.sh
```

```
./update-cloud-config.sh
```

```
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

```
cat <<EOF > ops-files/kubernetes-single-worker.yml
- type: replace
  path: /instance_groups/name=worker/instances
  value: 1
EOF
```

```
cat <<EOF > ops-files/kubernetes-master-lb-san.yml
- type: replace
  path: /variables/name=tls-kubernetes/options/alternative_names/-
  value: ((kubernetes_master_host))
EOF
```

```
mkdir -p specs
```

```
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

```
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-single-worker.yml \
    -o ops-files/kubernetes-master-lb-san.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
chmod +x deploy-kubernetes.sh
```

```
./deploy-kubernetes.sh
```

```
bosh -d cfcr run-errand apply-addons
```

```
cat <<EOF > credhub-login.sh
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

```
./credhub-login.sh
```

```
admin_password=$(credhub get -n /bosh-aws/cfcr/kubo-admin-password | bosh int - --path=/value)
master_host=$(bosh vms -d cfcr | grep master | awk 'NR==1 {print $4}')
```

```
sudo sed -i '/master.cfcr.internal/d' /etc/hosts
echo "${master_host} master.cfcr.internal" | sudo tee -a /etc/hosts
```

```
tmp_ca_file="$(mktemp)"
credhub get -n /bosh-aws/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"
```

```
cluster_name="cfcr"
user_name="admin"
context_name="cfcr"

kubectl config set-cluster "${cluster_name}" \
  --server="https://master.cfcr.internal:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true

kubectl config set-credentials "${user_name}" --token="${admin_password}"

kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"

kubectl config use-context "${context_name}"
```

```
bosh -d cfcr delete-deployment
```

```
eval "$(sed 's/create-env/delete-env/' deploy-bosh.sh)"
```

```
terraform destroy
```