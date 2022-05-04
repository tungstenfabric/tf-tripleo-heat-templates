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
export CERT_SIGNER="SelfSignedCA"
export TF_ROOT_CA_KEY_BASE64=$(cat ca.key.pem | base64 -w 0)
export TF_ROOT_CA_CERT_BASE64=$(cat ca-bundle.pem | base64 -w 0)

... other actions to deploy from tf-operator ...
```

3. Label worker(s) node with subcluster label:
```bash
# for each subcluser nodes
kubectl label node <worker_nodename> subcluster=<subcluster_name>
```

4.Ensure Kubernetes nodes can connect to External, Internal API and Tenant RHOSP networks.
Ensure Kubernetes nodes can resolve RHOSP FQDNs for Overcloud VIPs for External, Internal API and CtlPlane networks.
E.g.

```bash
cat /etc/hosts

192.168.24.53 overcloud.ctlplane.5c7.local
10.1.0.125 overcloud.internalapi.5c7.local
10.2.0.90 overcloud.5c7.local overcloud.5c7.local

#RHOSP Computes
192.168.21.122  overcloud-remotecompute1-0.tenant.dev.localdomain
# ...
#RHOSP Contrail Dpdk
192.168.21.132  overcloud-remotecontraildpdk1-0.tenant.dev.localdomain
# ...
#RHOSP Contrail Sriov
192.168.21.142  overcloud-remotecontrailsriov1-0.tenant.dev.localdomain
# ...
#... other compute addresses if any
... IMPORTANT: all FQDNs of all overcloud nodes (all networks) ...
```
(FQDNs of Overcloud nodes can be taken from /etc/hosts of one of overcloud node)

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
          asnNumber: <asn>
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

2. Run script to generate remote computes heat templates for kernel, dpdk and sriov kinds
```bash
cd
# comma separated list of names
subcluster_names=pop1,pop2
./tripleo-heat-templates/tools/contrail/remote_compute.sh $subcluster_names
```
This script generate one network_data_rcomp.yaml, and the set of files for each subcluster, e.g.
tripleo-heat-templates/roles/RemoteCompute1.yaml
tripleo-heat-templates/roles/RemoteContrailDpdk1.yaml
tripleo-heat-templates/roles/RemoteContrailSriov1.yaml
tripleo-heat-templates/environments/contrail/rcomp1-env.yaml
tripleo-heat-templates/network/config/contrail/compute-nic-config-rcomp1.yaml
tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config-rcomp1.yaml
tripleo-heat-templates/network/config/contrail/contrail-sriov-nic-config-rcomp1.yaml

3. !!IMPORTANT: Adjust generated files and othere templates to your setup (storage, network CIDRs, routes, etc)
Check carefully [the RedHat documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/distributed_compute_node_and_storage_deployment/planning_a_distributed_compute_node_dcn_deployment)

4. Prepare contrail templates with use of generated network data file

4.1. Modify contrail-services.yaml to provide data about Contrail Control plane on K8S
```yaml
  # Set keystone admin port to be on internal_api
  ServiceNetMap:
    # ... others options...
    KeystoneAdminApiNetwork: internal_api

  # FQDN resolving
  ExtraHostFileEntries:
    - 'IP1    <FQDN K8S master1>        <Short name master1>'
    - 'IP2    <FQDN K8S master2>        <Short name master2>'
    - 'IP3    <FQDN K8S master3>        <Short name master3>'
    - 'IP4    <FQDN K8S pop1 worker1>   <Short name pop1 worker1>'
    - 'IP5    <FQDN K8S pop1 worker2>   <Short name pop1 worker2>'
    - 'IP6    <FQDN K8S pop2 worker1>   <Short name pop2 worker1>'
    - 'IP7    <FQDN K8S pop2 worker1>   <Short name pop2 worker2>'

  # main control plane
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
  ContrailCaCertFile: "/etc/pki/ca-trust/source/anchors/contrail-ca-cert.pem"
  SSLRootCertificatePath: "/etc/pki/ca-trust/source/anchors/contrail-ca-cert.pem"
  SSLRootCertificate: |
EOF
# append cert data
cat ca-bundle.pem | while read l ; do
  echo "    $l" >> ca-bundle.yaml
done
# check
cat ca-bundle.yaml
```

4.3. Prepare central site specifica parameters
```bash
# !!! IMPORTANTN: Adjust to your setup
# (Check more options in RedHat doc)
cat <<EOF > central-env.yaml
parameter_defaults:
  GlanceBackend: swift
  ManageNetworks: true
  ControlPlaneSubnet: leaf0
  ControlControlPlaneSubnet: leaf0
  InternalApiInterfaceRoutes:
    - destination: 10.30.0.0/24
      nexthop: 10.1.0.254
    - destination: 10.40.0.0/24
      nexthop: 10.1.0.254
  StorageMgmtInterfaceRoutes:
    - destination: 10.33.0.0/24
      nexthop: 10.4.0.254
    - destination: 10.33.0.0/24
      nexthop: 10.4.0.254
  StorageInterfaceRoutes:
    - destination: 10.32.0.0/24
      nexthop: 10.3.0.254
    - destination: 10.42.0.0/24
      nexthop: 10.3.0.254
  TenantInterfaceRoutes:
    - destination: 172.20.1.0/24
      nexthop: 172.20.1.254
  ControlPlaneStaticRoutes:
    - destination: 172.30.1.0/24
      nexthop: 192.168.24.254
    - destination: 172.40.1.0/24
      nexthop: 192.168.24.254
  NovaComputeAvailabilityZone: 'central'
  ControllerExtraConfig:
    nova::availability_zone::default_schedule_zone: central
  NovaCrossAZAttach: false
  CinderStorageAvailabilityZone: 'central'
EOF

# If use tenant network on openstack controllers adjust nic file, .e.g:
# vi tripleo-heat-templates/network/config/contrail/controller-nic-config.yaml
               - type: interface
                 name: nic2
                 use_dhcp: false
                 addresses:
                 - ip_netmask:
                     get_param: TenantIpSubnet
                 routes:
                   get_param: TenantInterfaceRoutes
```

4.4. Prepare VIP mapping
```bash
# !!! Adjust to your setup
# Check more options in RedHat doc
cat <<EOF > leaf-vips.yaml
parameter_defaults:
  VipSubnetMap:
    ctlplane: leaf0
    redis: internal_api_subnet
    InternalApi: internal_api_subnet
    Storage: storage_subnet
    StorageMgmt: storage_mgmt_subnet
EOF
```

4.5. Process heat templates to generate role and network files
```bash
cd
# generate role file (adjust to your role list)
openstack overcloud roles generate --roles-path tripleo-heat-templates/roles \
  -o /home/stack/roles_data.yaml Controller RemoteCompute1 RemoteContrailDpdk1 RemoteContrailSriov1
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

5. Deploy central location
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
  -e containers-prepare-parameter.yaml \
  -e rhsm.yaml \
  -e ca-bundle.yaml \
  -e central-env.yaml \
  -e leaf-vips.yaml
```

6. Enable kyestone auth for K8S cluster if it was deployed w/o keystone auth enabled
```bash
# Ensure that all K8S nodes are able to resolve overcloud VIPs FQDNs like overcloud.internalapi.5c7.local
[stack@node1 ~]$ grep overcloud.internalapi.5c7.local  /etc/hosts
10.1.0.125 overcloud.internalapi.5c7.local
...

# Edit manager object to put keystone parameters and set linklocal parameters
kubectl -n tf edit managers cluster1

# Example of configuration
apiVersion: tf.tungsten.io/v1alpha1
kind: Manager
metadata:
  name: cluster1
  namespace: tf
spec:
  commonConfiguration:
    authParameters:
      authMode: keystone
      keystoneAuthParameters:
        address: overcloud.internalapi.5c7.local
        adminPassword: c0ntrail123
        authProtocol: https
        region: regionOne
...
    config:
      metadata:
        labels:
          tf_cluster: cluster1
        name: config1
      spec:
        commonConfiguration:
          nodeSelector:
            node-role.kubernetes.io/master: ""
        serviceConfiguration:
          linklocalServiceConfig:
            ipFabricServiceHost: "overcloud.internalapi.5c7.local"
...
```

7. Deploy remote sites, e.g.
7.1. Export environment form cenral site
```bash
mkdir -p ~/dcn-common
openstack overcloud export \
  --stack overcloud \
  --config-download-dir /var/lib/mistral/overcloud \
  --output-file ~/dcn-common/central-export.yaml
```

6.2. Deploy remote site 1
```bash
openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack pop1 --libvirt-type kvm \
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
  -e containers-prepare-parameter.yaml \
  -e rhsm.yaml \
  -e ca-bundle.yaml \
  -e dcn-common/central-export.yaml \
  -e leaf-vips.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/rcomp1-env.yaml
```

6.3. Follow next steps from [RedHat documentaion, e.g](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/distributed_compute_node_and_storage_deployment/assembly_deploying-storage-at-the-edge)

```
7.1. Deploying edge sites with storage
  8. You must ensure that nova cell_v2 host mappings are created in the nova API database after the edge locations are deployed. Run the following command on the undercloud:
```
```bash
TRIPLEO_PLAN_NAME=overcloud \
  ansible -i /usr/bin/tripleo-ansible-inventory \
    nova_api[0] -b -a \
    "{{ container_cli }} exec -it nova_api \
      nova-manage cell_v2 discover_hosts --by-service --verbose"
```
