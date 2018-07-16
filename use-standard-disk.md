## Use Standard (cheaper) Disk

### Director

```yaml
cat <<EOF > ops-files/director-disk-size.yml
- type: replace
  path: /resource_pools/name=vms/cloud_properties/ephemeral_disk
  value: 
    size: 20_000
    type: standard
- type: replace
  path: /disk_pools/name=disks/cloud_properties/type?
  value: standard
- type: replace
  path: /disk_pools/name=disks/disk_size
  value: 20_000
EOF
```

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
    -o ops-files/director-spot-instance.yml \
    -o ops-files/director-disk-size.yml \
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
```

```
./deploy-bosh.sh
```

### Kubernetes

```yaml
cat <<EOF > ops-files/cloud-config-standard-disk.yml
- type: replace
  path: /vm_extensions?/-
  value:
    name: standard-disk
    cloud_properties:
      root_disk:
        type: standard
      ephemeral_disk:
        type: standard
EOF
```

```yaml
cat <<EOF > ops-files/cloud-config-disk-types.yml
- type: replace
  path: /disk_types?/-
  value:
    name: '5120'
    disk_size: 5120
    cloud_properties:
      type: standard
- type: replace
  path: /disk_types?/-
  value:
    name: '10240'
    disk_size: 10240
    cloud_properties:
      type: standard
EOF
```

```bash
cat <<'EOF' > update-cloud-config.sh
#!/bin/bash
bosh update-cloud-config kubo-deployment/configurations/aws/cloud-config.yml \
    -o ops-files/cloud-config-rename-vm-types.yml \
    -o ops-files/cloud-config-small-vm-types.yml \
    -o ops-files/cloud-config-master-lb.yml \
    -o ops-files/cloud-config-multi-az.yml \
    -o ops-files/cloud-config-spot-instance.yml \
    -o ops-files/cloud-config-standard-disk.yml \
    -o ops-files/cloud-config-disk-types.yml \
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
```

```
./update-cloud-config.sh
```

```yaml
cat <<EOF > ops-files/kubernetes-standard-disk.yml
- type: replace
  path: /instance_groups/name=master/vm_extensions?/-
  value: standard-disk
- type: replace
  path: /instance_groups/name=worker/vm_extensions?/-
  value: standard-disk
EOF
```

```yaml
cat <<EOF > ops-files/kubernetes-persistent-disk-type.yml
- type: remove
  path: /instance_groups/name=master/persistent_disk?
- type: remove
  path: /instance_groups/name=worker/persistent_disk?
- type: replace
  path: /instance_groups/name=master/persistent_disk_type?
  value: '5120'
- type: replace
  path: /instance_groups/name=worker/persistent_disk_type?
  value: '10240'
EOF
```

```bash
cat <<'EOF' > deploy-kubernetes.sh 
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/misc/single-master.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.18.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    -o ops-files/kubernetes-spot-instance.yml \
    -o ops-files/kubernetes-standard-disk.yml \
    -o ops-files/kubernetes-persistent-disk-type.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
```

```
./deploy-kubernetes.sh 
```
