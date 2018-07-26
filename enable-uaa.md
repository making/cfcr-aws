## Enable UAA integration

In this section, we will install [UAA](https://github.com/cloudfoundry/uaa-release) as a OpenID Connect Provider and integrate with Kubernetes. 

Login to Bastion server.

```bash
./ssh-bastion.sh 
```

Load BOSH environment variables.

```bash
cd cfcr-manifests
source bosh-aws-env.sh
```

### Install UAA

To reduce IaaS cost, we will colocate a UAA server in each master node.

![image](https://user-images.githubusercontent.com/106908/41496786-1454d70e-7183-11e8-88e0-a61d80a12874.png)

```yaml
cat <<EOF > ops-files/kubernetes-uaa.yml
- type: replace
  path: /releases/-
  value:
    name: uaa
    version: "57.4"
    url: https://bosh.io/d/github.com/cloudfoundry/uaa-release?v=57.4
    sha1: f8a5f456f0883f85ca17db41414458d318204882
- type: replace
  path: /releases/-
  value:
    name: postgres
    version: 29
    url: https://bosh.io/d/github.com/cloudfoundry/postgres-release?v=29
    sha1: 24d2e2887a45258b71bc40577c0f406180e47701

# Add UAA DB (postgresql)
- type: replace
  path: /instance_groups/0:before
  value:
    name: uaa-db
    instances: 1
    azs: [z1]
    networks:
    - name: default
    stemcell: trusty
    vm_type: small
    persistent_disk: 1024
    jobs:
    - release: postgres
      name: postgres
      properties:
        databases:
          tls:
            ca: ((postgres_tls.ca))
            certificate: ((postgres_tls.certificate))
            private_key: ((postgres_tls.private_key))
          databases:
          - name: uaa
            tag: uaa
          db_scheme: postgres
          port: 5432
          roles:
          - name: uaa
            password: ((uaa_database_password))
            tag: admin
- type: replace
  path: /instance_groups/name=master/jobs/-
  value:
    name: uaa
    release: uaa
    properties:
      encryption:
        active_key_label: default_key
        encryption_keys:
        - label: default_key
          passphrase: ((uaa_default_encryption_passphrase))
      login:
        self_service_links_enabled: false
        saml:
          serviceProviderCertificate: "((uaa_service_provider_ssl.certificate))"
          serviceProviderKey: "((uaa_service_provider_ssl.private_key))"
          serviceProviderKeyPassword: ""
          activeKeyId: key-1
          keys:
            key-1:
              key: "((uaa_login_saml.private_key))"
              certificate: "((uaa_login_saml.certificate))"
              passphrase: ""
      uaa:
        port: 8081
        ssl:
          port: 9443
        url: "https://((kubernetes_uaa_host)):9443"
        catalina_opts: -Djava.security.egd=file:/dev/./urandom
        sslPrivateKey: ((uaa_ssl.private_key))
        sslCertificate: ((uaa_ssl.certificate))
        jwt:
          revocable: true
          policy:
            active_key_id: key-1
            keys:
              key-1:
                signingKey: "((uaa_jwt_signing_key.private_key))"
        logging_level: INFO
        scim:
          users:
          - name: admin
            password: ((uaa_admin_password))
            groups:
            - openid
            - scim.read
            - scim.write
        admin:
          client_secret: "((uaa_admin_client_secret))"
        login:
          client_secret: "((uaa_login_client_secret))"
        clients:
          kubernetes:
            override: true
            authorized-grant-types: password,refresh_token
            scope: openid,roles
            authorities: uaa.none
            access-token-validity: 86400 # 1 day
            refresh-token-validity: 604800 # 7 days
            secret: ""
        zones:
          internal:
            hostnames: []
      uaadb:
        port: 5432
        db_scheme: postgresql
        tls_enabled: true
        skip_ssl_validation: true
        databases:
        - tag: uaa
          name: uaa
        roles:
        - name: uaa
          password: ((uaa_database_password))
          tag: admin

- type: replace
  path: /instance_groups/name=master/jobs/name=kube-apiserver/properties/oidc?
  value:
    issuer-url: https://((kubernetes_uaa_host)):9443/oauth/token
    client-id: kubernetes
    username-claim: user_name
    username-prefix: "-" # noUsernamePrefix
    ca: ((uaa_ssl.ca))

- type: replace
  path: /variables/-
  value:
    name: uaa_default_encryption_passphrase
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_jwt_signing_key
    type: rsa

- type: replace
  path: /variables/-
  value:
    name: uaa_admin_password
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_admin_client_secret
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_login_client_secret
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_ssl
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa.cfcr.internal
      alternative_names:
      - ((kubernetes_uaa_host))

- type: replace
  path: /variables/-
  value:
    name: uaa_login_saml
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa_login_saml

- type: replace
  path: /variables/-
  value:
    name: uaa_service_provider_ssl
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa.cfcr.internal
      alternative_names:
      - ((kubernetes_uaa_host))

- type: replace
  path: /variables/-
  value:
    name: uaa_database_password
    type: password

- type: replace
  path: /variables/-
  value:
    name: postgres_tls
    type: certificate
    options:
      ca: kubo_ca
      common_name: postgres.cfcr.internal
      alternative_names:
      - "*.postgres.default.cfcr.bosh"
EOF
```

```yaml
cat <<EOF > specs/uaa-admin.yml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: uaa-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: admin
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
    -o ops-files/kubernetes-kubo-0.17.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    -o ops-files/kubernetes-uaa.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    -v kubernetes_uaa_host=${master_lb_ip_address} \
    --no-redact
EOF
```

You also need to add `9443` port (TCP) to listen on the existing load balancer to the master node and allow port `9443` to security groups to `<prefix>-api-access` and `<prefix>-node-access`. (**TODO** update terraform tempaltes)


```bash
./deploy-kubernetes.sh
```

and

```bash
bosh -d cfcr run-errand apply-addons
```

### Login as a UAA admin


```bash
./credhub-login.sh
```

```bash
tmp_ca_file="$(mktemp)"
credhub get -n /bosh-aws/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"

cluster_name="cfcr-aws"
user_name="uaa-admin"
context_name="${cluster_name}-${user_name}"

kubectl config set-cluster "${cluster_name}" \
  --server="https://${master_lb_ip_address}:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true

uaa_url=https://${master_lb_ip_address}:9443

access_token=`curl -s ${uaa_url}/oauth/token \
  --cacert <(credhub get -n /bosh-aws/cfcr/uaa_ssl | bosh int - --path=/value/ca) \
  -d grant_type=password \
  -d response_type=id_token \
  -d scope=openid \
  -d client_id=kubernetes \
  -d client_secret= \
  -d username=admin \
  -d password=$(credhub get -n /bosh-aws/cfcr/uaa_admin_password | bosh int - --path /value)`

kubectl config set-credentials "${user_name}" \
  --auth-provider=oidc \
  --auth-provider-arg=idp-issuer-url=${uaa_url}/oauth/token \
  --auth-provider-arg=client-id=kubernetes \
  --auth-provider-arg=client-secret= \
  --auth-provider-arg=id-token=$(echo $access_token | bosh int - --path /id_token) \
  --auth-provider-arg=refresh-token=$(echo $access_token | bosh int - --path /refresh_token) \
  --auth-provider-arg=idp-certificate-authority-data="$(credhub get -n /bosh-aws/cfcr/uaa_ssl | bosh int - --path=/value/ca | base64)"
  
kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"

kubectl config use-context "${context_name}"
```

## Enable LDAP

In order to use `groups-claim` in kubernetes's oidc integration, external id provider need to be configured (LDAP or SAML).

**Configure `kubernetes-uaa-ldap.yml` below according to your LDAP environment.**

```yaml
cat <<EOF > kubernetes-uaa-ldap.yml
- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/enabled?
  value: true

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/url?
  value: "ldaps://ldap.example.com:636"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/userDN?
  value: "uid=root,cn=users,dc=ldap,dc=example,dc=com"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/userPassword?
  value: "((ldap_password))"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/searchBase?
  value: "cn=users,dc=ldap,dc=example,dc=com"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/searchFilter?
  value: "mail={0}"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/ssl?/skipverification?
  value: true 

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/groups?/searchBase?
  value: "cn=groups,dc=ldap,dc=example,dc=com" 

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/groups?/profile_type?
  value: "groups-as-scopes"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/groups?/groupRoleAttribute?
  value: "cn"

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/attributeMappings?
  value:
    phone_number: telephoneNumber

- type: replace
  path: /instance_groups/name=master/jobs/name=uaa/properties/uaa?/ldap?/externalGroupsWhitelist
  value:
  - administrators
  - users

- type: replace
  path: /instance_groups/name=master/jobs/name=kube-apiserver/properties/oidc/groups-claim?
  value: roles
EOF
```

```yaml
cat << EOF > specs/uaa-groups.yml 
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: uaa-admin-group
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: administrators
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: uaa-admin-group
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- kind: Group
  name: users
  namespace: default
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
    -o ops-files/kubernetes-kubo-0.17.0.yml \
    -o ops-files/kubernetes-worker.yml \
    -o ops-files/kubernetes-master-lb.yml \
    -o ops-files/kubernetes-uaa.yml \
    -o ops-files/kubernetes-uaa-ldap.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_cluster_tag=${kubernetes_cluster_tag} \
    -v kubernetes_master_host=${master_lb_ip_address} \
    -v kubernetes_uaa_host=${master_lb_ip_address} \
    -v ldap_password=${ldap_password} \
    --no-redact
EOF
```

```bash
export ldap_password=changeme
./deploy-kubernetes.sh
```

and

```bash
bosh -d cfcr run-errand apply-addons
```

### Login as a LDAP user


```bash
./credhub-login.sh
```

```bash
ldap_username=changeme@example.com
ldap_password=changeme

tmp_ca_file="$(mktemp)"
credhub get -n /bosh-aws/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"

cluster_name="cfcr-aws"
user_name=$(echo $ldap_username | awk -F '@' '{print $1}')
context_name="${cluster_name}-${user_name}"

kubectl config set-cluster "${cluster_name}" \
  --server="https://${master_lb_ip_address}:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true

uaa_url=https://${master_lb_ip_address}:9443

access_token=`curl -s ${uaa_url}/oauth/token \
  --cacert <(credhub get -n /bosh-aws/cfcr/uaa_ssl | bosh int - --path=/value/ca) \
  -d grant_type=password \
  -d response_type=id_token \
  -d scope=openid,roles \
  -d client_id=kubernetes \
  -d client_secret= \
  -d username=${ldap_username} \
  -d password=${ldap_password}`

kubectl config set-credentials "${user_name}" \
  --auth-provider=oidc \
  --auth-provider-arg=idp-issuer-url=${uaa_url}/oauth/token \
  --auth-provider-arg=client-id=kubernetes \
  --auth-provider-arg=client-secret= \
  --auth-provider-arg=id-token=$(echo $access_token | bosh int - --path /id_token) \
  --auth-provider-arg=refresh-token=$(echo $access_token | bosh int - --path /refresh_token) \
  --auth-provider-arg=idp-certificate-authority-data="$(credhub get -n /bosh-aws/cfcr/uaa_ssl | bosh int - --path=/value/ca | base64)"
  
kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"

kubectl config use-context "${context_name}"
```

### Farther reading

* https://github.com/cloudfoundry/uaa-release/blob/develop/jobs/uaa/spec
* https://github.com/cloudfoundry/uaa/blob/master/docs/UAA-LDAP.md
