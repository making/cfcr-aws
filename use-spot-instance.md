## Use Spot Insatnce

```yaml
cat <<EOF > ops-files/cloud-config-spot-instance.yml 
- type: replace
  path: /vm_extensions?/-
  value:
    name: spot-instance-t2.micro
    cloud_properties:
      spot_bid_price: 0.0047
      spot_ondemand_fallback: true

- type: replace
  path: /vm_extensions?/-
  value:
    name: spot-instance-t2.medium
    cloud_properties:
      spot_bid_price: 0.0183
      spot_ondemand_fallback: true
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

```bash
./update-cloud-config.sh
```

```yaml
cat <<EOF > ops-files/kubernetes-spot-instance.yml 
- type: replace
  path: /instance_groups/name=master/vm_extensions?/-
  value: spot-instance-t2.micro
- type: replace
  path: /instance_groups/name=worker/vm_extensions?/-
  value: spot-instance-t2.medium
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
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
```

```bash
./deploy-kubernetes.sh 
```
