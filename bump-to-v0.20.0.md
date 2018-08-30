### Bump to CFCF 0.20.0

Login to Bastion server.

```
./ssh-bastion.sh 
```

Load BOSH environment variables.

```
cd cfcr-manifests
source bosh-aws-env.sh
```

Fetch v0.20.0 manifests.

```
cd kubo-deployment
git fetch origin --tag
git checkout v0.20.0
cd ..
```

Update stemcells for CFCR v0.20.0.

```
STEMCELL_VERSION=97.3 # latest as of writing
bosh upload-stemcell https://bosh.io/d/stemcells/bosh-aws-xen-hvm-ubuntu-xenial-go_agent?v=${STEMCELL_VERSION}
```

Create a ops-file for CFCR v0.20.0.

```yaml
cat <<EOF > ops-files/kubernetes-kubo-0.20.0.yml
- type: replace
  path: /releases/name=kubo?
  value:
    name: kubo
    version: 0.20.0
    url: https://bosh.io/d/github.com/cloudfoundry-incubator/kubo-release?v=0.20.0
    sha1: 5a58d84c8498cae1c2687daebf4ad23078fcca67
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
    -o ops-files/kubernetes-kubo-0.20.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    --no-redact
EOF
chmod +x deploy-kubernetes.sh
```

Deploy CFCR 0.20.0.

```bash
./deploy-kubernetes.sh
```

Update addons.

```bash
bosh -d cfcr run-errand apply-addons
```

You will get a k8s 1.11.1 cluster!

```
$ kubectl get node -o wide
NAME                                          STATUS    ROLES     AGE       VERSION   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
ip-10-0-8-6.ap-northeast-1.compute.internal   Ready     <none>    51m       v1.11.1   10.0.8.6      Ubuntu 16.04.5 LTS   4.15.0-29-generic   docker://17.12.1-ce
```
