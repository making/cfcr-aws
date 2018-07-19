### Bump to CFCF 0.19.0

Login to Bastion server.

```
./ssh-bastion.sh 
```

Load BOSH environment variables.

```
cd cfcr-manifests
source bosh-aws-env.sh
```

Fetch v0.19.0 manifests.

```
cd kubo-deployment
git fetch origin --tag
git checkout v0.19.0
cd ..
```

Update stemcells for CFCR v0.19.0.

```
STEMCELL_VERSION=$(bosh int kubo-deployment/manifests/cfcr.yml --path /stemcells/0/version)
bosh upload-stemcell https://s3.amazonaws.com/bosh-aws-light-stemcells/light-bosh-stemcell-${STEMCELL_VERSION}-aws-xen-hvm-ubuntu-trusty-go_agent.tgz
```

Create a ops-file for CFCR v0.19.0.

```yaml
cat <<EOF > ops-files/kubernetes-kubo-0.19.0.yml
- type: replace
  path: /releases/name=kubo?
  value:
    name: kubo
    version: 0.19.0
    url: https://bosh.io/d/github.com/cloudfoundry-incubator/kubo-release?v=0.19.0
    sha1: 03a540bbe32e074abd9eb41503b9e39d29a1321d
EOF
```

Update `deploy-kubernetes.sh`.

```bash
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/misc/single-master.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/lb.yml \
    -o kubo-deployment/manifests/ops-files/iaas/aws/cloud-provider.yml \
    -o ops-files/kubernetes-kubo-0.19.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
chmod +x deploy-kubernetes.sh
```

Deploy CFCR 0.19.0.

```bash
./deploy-kubernetes.sh
```

Update addons.

```bash
bosh -d cfcr run-errand apply-addons
```

You will get a k8s 1.10.5 cluster!

```
$ kubectl get node -o wide
NAME                                          STATUS    ROLES     AGE       VERSION   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
ip-10-0-8-6.ap-northeast-1.compute.internal   Ready     <none>    51m       v1.10.5   <none>        Ubuntu 14.04.5 LTS   4.4.0-130-generic   docker://17.12.1-ce
```
