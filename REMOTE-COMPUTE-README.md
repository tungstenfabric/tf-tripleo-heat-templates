# Introduction
Currently the following combinations of Operating System/OpenStack/Deployer/Contrail are supported:

| Operating System  | OpenStack         |
| ----------------- | ----------------- |
| RHEL 8.2          | OSP16             |


This kind of deploy is supposed to be ['Spine-Leaf' deploy](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html-single/spine_leaf_networking/index)
and/or [distributed compute nodes (DCN)](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/distributed_compute_node_and_storage_deployment/index)

This readme is mostly about Contrail specific part.
All scripts are provided 'as is' and as just an example.
Main instruction to prepare setup for deployment must be RedHat documentation 
pointed above.

In this example there is K8S cluster used for Contrail Control plane.
Similar way OpenShift can be used for same purposes.

# Contrail Versions Notes
# Configuration elements
1. Infrastructure
2. Undercloud
3. Overcloud

# Infrastructure considerations
There are many different ways on how to create the infrastructure providing
the control plane elements. In this example all control plane functions
are provided as Virtual Machines hosted on KVM hosts

- VM 1 - k8s managed:
  Contrail Control plane (K8S Master)

- VM 2 - k8s managed:
  Contrail Control service for Remote Compute (non-master K8S node, say, with a sub-cluster label)

- VM 3 - RHOSP undercloud:

- VM 4 - RHOSP overcloud:
  OpenStack Controller

- VM 5 - RHOSP overcloud:
  OpenStack remote compute with SUBCLUSTER param


## Topology example scheme (w/o spine-leaf and/or DCN details)
```
+-----------------------------------------------------------------+
|      +-------------------------+        K8S/Openshift cluster   |
|      | VM CN Controller 3      |                                |
|    +-+-----------------------+ |    +-------------------------+ |
|    | VM CN Controller 2      | |    |  VM Control subcluser X | |
|  +-+-----------------------+ | |  +-+-----------------------+ | |
|  | VM CN Controller 1      | | |  | VM Control subcluster 1 | | |
|  | +---------------------+ | | |  | +---------------------+ | | |
|  | | Contrail Config     | | | |  | | Contrail Control    | | | |
|  | | Contrail Controller | | | |  | | ( SUBCLUSTER XXX)   | | | |
|  | | Contrail Databases  | | | |  | +---------------------+ |-+ |
|  | | Contrail Control    | | |-+  +-------------------------+   |
|  | +---------------------+ |-+                                  |
|  +-------------------------+                                    |
+------+--------------+-------------------+-------+---------------+
       |              |                   |       |
+------+--------------+-------------------+-------+--------+
|                          Network                         |
+------+--------------+-------------------+-------+--------+
       |              |                   |       |
+------+--------------+-------------------+-------+------------------------+
|                                                      Openstack cluster   |
|                        +-----------------+                               |
|                        | VM Controller 3 |                               |
|                      +-+---------------+ |    +------------------------+ |
|                      | VM Controller 2 | |    | VM Compute subcluser 2 | |
| +----------------+ +-+---------------+ | |  +-+----------------------+ | |
| | VM Undercloud  | | VM Controller 1 | | |  | VM Compute subcluser 1 | | |
| |                | | +-------------+ | | |  | +--------------------+ | | |
| |                | | | Openstack   | | | |  | | Openstack Compute  | | | |
| |                | | | Controller  | | | |  | | Vrouter Agent      | | | |
| |                | | |             | | |-+  | | ( SUBCLUSTER XXX)  | | | |
| +----------------+ | +-------------+ |-+    | +--------------------+ |-+ |
|                    +-----------------+      +------------------------+   |
+--------------------------------------------------------------------------+

```

# Prepare k8s-managed hosts

1. Create 2 contrail master and contrail controller machines. Requirements:
 - CentOS 7
 - 32G Memory
 - 80G SDD

2. Deploy Contrail Control plane in K8S cluster by [tf-operator](https://github.com/tungstenfabric/tf-operator) with at least one worker node(s).
The worker will be used for Contrail Control serving a subcluster (1 for testing, production minimum is 2).
In case of OpenShift for Contrail Control plane check [readme](https://github.com/tungstenfabric/tf-openshift).

In case if RHOSP uses TLS everywhere it is needed to deploy with CA bundle
that includes both own root CA and IPA CA data, e.g.
```bash
# assuming that k8s cluster ca is in ca.crt.pem and IPA CA is in ipa.crt
# (ipa.crt can be copied from undercloud node from /etc/ipa/ca.crt)
cat ca.crt.pem ipa.crt > ca-bundle.pem
# assuming that k8s cluster CA key is in ca.key.pem
export SSL_CACERT=$(cat ~/ca-bundle.pem)
export SSL_CAKEY=$(cat ~/ca.key.pem)
... other actions to deploy from tf-operator ...
```

3. Label worker(s) node with subcluster label:
```bash
# for each subcluser nodes
kubectl label node <worker_nodename> subcluster=<subcluster_name>
```

4. Ensure RHOSP FQDNs are resolvable on K8S master nodes
E.g.
```bash
cat /etc/hosts

#RHOSP VIPs
192.168.21.201  overcloud.internalapi.dev.localdomain
192.168.21.200  overcloud.dev.localdomain

#RHOSP Computes
192.168.21.122  overcloud-remotecompute1-0.tenant.dev.localdomain
#... other compute addresses if any
```

```bash
kubectl edit manager -n tf
```

Add record to controls for each subcluster:

```yaml
    controls:
    - metadata:
        labels:
          tf_cluster: cluster1
        name: control<subcluster_name>
      spec:
        commonConfiguration:
          nodeSelector:
            subcluster: <subcluster_name>
        serviceConfiguration:
          subcluster: <subcluster_name>
          containers:
          - name: control
            image: contrail-controller-control-control
          - name: dns
            image: contrail-controller-control-dns
          - name: named
            image: contrail-controller-control-named
          - name: nodemanager
            image: contrail-nodemgr
          - name: provisioner
            image: contrail-provisioner
```
5. Edit manager manifest - add one more control with node nodeselector and Subcluster param

# Prepare Openstack managed hosts

1. Prepare Openstack hosts and run undercloud setup by [README.md]

2. Run script to generate remote computes heat templates
```bash
cd
# comma separated list of names
subcluster_names=pop1,pop2
./tripleo-heat-templates/tools/contrail/remote_compute.sh $subcluster_names 
```
This script generate one network_data_rcomp.yaml, and the set of files for each subcluster, e.g.
tripleo-heat-templates/roles/RemoteCompute1.yaml
tripleo-heat-templates/environments/contrail/ips-from-pool-rcomp1.yaml
tripleo-heat-templates/network/config/contrail/compute-nic-config-rcomp1.yaml

3. !!IMPORTANT: Adjust generated files and othere templates to your setup (network CIDRs, routes, etc)

4. Prepare contrail templates with use of generated network data file 

4.1. Modify contrail-services.yaml to provide data about Contrail Control plane on K8S
```yaml
  ExtraHostFileEntries:
    - 'IP1    <FQDN K8S master1>    <Short name master1>'
    - 'IP2    <FQDN K8S master2>    <Short name master2>'
    - 'IP3    <FQDN K8S master3>    <Short name master3>'

  ExternalContrailConfigIPs: <comma separated list of IP/FQDNs of K8S master nodes>
  ExternalContrailControlIPs: <comma separated list of IP/FQDNs of K8S master nodes>
  ExternalContrailAnalyticsIPs: <comma separated list of IP/FQDNs of K8S master nodes>

  ControllerExtraConfig:
    contrail_internal_api_ssl: True
  ComputeExtraConfig:
    contrail_internal_api_ssl: True
  # add contrail_internal_api_ssl for all other roles if any
```

4.2. Enable Contrail TLS
4.2.1 Case if RHOSP doesnt use TLS everywhere or use Self-signed root CA
Prepare self-signed certificates in environments/contrail/contrail-tls.yaml
```yaml
resource_registry:
  OS::TripleO::Services::ContrailCertmongerUser: OS::Heat::None

parameter_defaults:
  ContrailSslEnabled: true
  ContrailServiceCertFile: '/etc/contrail/ssl/certs/server.pem'
  ContrailServiceKeyFile: '/etc/contrail/ssl/private/server-privkey.pem'
  ContrailCA: 'local'
  ContrailCaCertFile: '/etc/contrail/ssl/certs/ca-cert.pem'
  ContrailCaKeyFile: '/etc/contrail/ssl/private/ca-key.pem'
  ContrailCaCert: |
    <Root CA certificate from K8S setup>
  ContrailCaKey: |
    <Root CA private key from K8S setup>
```

4.2.2 Case if RHOSP uses TLS everwhere
- Make CA bundle file
```bash
# assuming that k8s cluster ca is in ca.crt.pem
cat /etc/ipa/ca.crt ca.crt.pem > ca-bundle.pem
```

- Prepare environment file ca-bundle.yaml
```bash
# create file
cat <<EOF > ca-bundle.yaml
resource_registry:
  OS::TripleO::NodeTLSCAData: tripleo-heat-templates/puppet/extraconfig/tls/ca-inject.yaml
parameter_defaults:
  ContrailCaCertFile: "/etc/contrail/ssl/certs/ca-cert.pem"
  SSLRootCertificatePath: "/etc/contrail/ssl/certs/ca-cert.pem"
  SSLRootCertificate: |
EOF
# append cert data
cat ca-bundle.pem | while read l ; do
  echo "    $l" >> ca-bundle.yaml
done
# check
cat ca-bundle.yaml
```

4.3. Process heat templates to generate role and network files
```bash
cd
# generate role file (adjust to your role list)
openstack overcloud roles generate --roles-path tripleo-heat-templates/roles \
  -o /home/stack/roles_data.yaml Controller RemoteCompute1
# clean old files if any 
./tripleo-heat-templates/tools/process-templates.py --clean \
  -r /home/stack/roles_data.yaml \
  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -p tripleo-heat-templates/
# generated tripleo stack files
./tripleo-heat-templates/tools/process-templates.py \
  -r /home/stack/roles_data.yaml \
  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -p tripleo-heat-templates/
```

5. Run overcloud deploy
```bash
# Example for the case when RHOSP uses TLS everwhere
# use generated role file, network data file and files for remote computes 
openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file /home/stack/roles_data.yaml \
  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -e tripleo-heat-templates/environments/rhsm.yaml \
  -e tripleo-heat-templates/environments/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-tls.yaml \
  -e tripleo-heat-templates/environments/ssl/tls-everywhere-endpoints-dns.yaml \
  -e tripleo-heat-templates/environments/services/haproxy-public-tls-certmonger.yaml \
  -e tripleo-heat-templates/environments/ssl/enable-internal-tls.yaml \
  -e ca-bundle.yaml \
  -e containers-prepare-parameter.yaml \
  -e rhsm.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/rcomp1-env.yaml
```
