# Introduction
Currently the following combinations of Operating System/OpenStack/Deployer/Contrail are supported:

| Operating System  | OpenStack         | Deployer              | Contrail               |
| ----------------- | ----------------- | --------------------- | ---------------------- |
| RHEL 8.2          | OSP16             | tf-devstack           | Tungsten Fabric latest |


# Contrail Versions Notes
# Configuration elements
1. Infrastructure
2. Undercloud
3. Overcloud

# Infrastructure considerations
There are many different ways on how to create the infrastructure providing
the control plane elements. In this example all control plane functions
are provided as Virtual Machines hosted on KVM or RHEV hosts

- Hypervisor 1:
  OpenStack Controller 1
  Contrail Controller 1

- Hypervisor 2:
  OpenStack Controller 2
  Contrail Controller 2

- Hypervisor 3:
  OpenStack Controller 3
  Contrail Controller 3

## sample toplogy
### Layer 1
```
   +-------------------------------+
   |Hypervisor host 3              |
 +-------------------------------+ |
 |Hypervisor host 2              | |
+------------------------------+ | |
|Hypervisor host 1             | | |
|  +-------------------------+ | | |
|  |  Contrail Controller 1  | | | |
| ++-----------------------+ | | | |      +----------------+
| | OpenStack Controller 1 | | | | |      |Compute Node N  |
| |                        | | | | |    +----------------+ |
| | +-----+        +-----+ +-+ | | |    |Compute Node 2  | |
| | |VNIC1|        |VNIC2| |   | | |  +----------------+ | |
| +----+--------------+----+   | | |  |Compute Node 1  | | |
|      |              |        | | |  |                | | |
|    +-+-+          +-+-+      | | |  |                | | |
|    |br0|          |br1|      | | |  |                | | |
|    +-+-+          +-+-+      | +-+  |                | | |
|      |              |        | |    |                | | |
|   +--+-+          +-+--+     +-+    | +----+  +----+ | +-+
|   |NIC1|          |NIC2|     |      | |NIC1|  |NIC2| +-+
+------+--------------+--------+      +---+-------+----+
       |              |                   |       |
+------+--------------+-------------------+-------+--------+
|                                                          |
|                          Switch                          |
+----------------------------------------------------------+
```

### Layer 2
```
+--------------------------------------------+
|                             Hypervisor     |
|  +--------------+  +---------------------+ |
|  | OpenStack    |  | Contrail Controller | |
|  | Controller   |  |                     | |
|  |              |  |                     | |
|  | +----------+ |  | +-------+  +------+ | |
|  | |  VNIC1   | |  | | VNIC1 |  | VNIC2| | |
|  +--------------+  +---------------------+ |
|     | | | | | |       | | | |        |     |
|  +------------------------------+ +------+ |
|  |  | | | | | |       | | | |   | |  |   | |
|  | +--------------------------+ | |  |   | |
|  | |  | | | | |         | | |   | |  |   | |
|  | | +------------------------+ | |  |   | |
|  | | |  | | | |           | |   | |  |   | |
|  | | | +----------------------+ | |  |   | |
|  | | | |  | | |             |   | |  |   | |
|  | | | | +--------------------+ | |  |   | |
|  | | | | |  | |                 | |  |   | |
|  | | | | | +------------------+ | |  |   | |
|  | | | | | |  |                 | |  |   | |
|  | | | | | | +----------------+ | |  |   | |
|  | | | | | | |                  | |  |   | | +--------------------+
|  | | | | | | |   br0            | |  |br1| | | Compute Node       |
|  +------------------------------+ +------+ | |                    |
|    | | | | | |                       |     | |                    |
| +-------------+                   +------+ | | +-------+ +------+ |
| |   NIC1      |                   | NIC2 | | | | NIC1  | | NIC2 | |
+--------------------------------------------+ +--------------------+
     | | | | | |                       |          | | | |     |
 +---------------------------------------------------------------+
 | |    ge0      |                 | ge1  |     |  ge2  |  | ge3 |
 | +-------------+  switch         +------+     +-------+  +-----+
 |   | | | | | |                      |          | | |       |   |
 |   | | | | | |                      |          | | |       |   |
 |   | | | | | |  tenant (no vlan) -> +----------------------+   |
 |   | | | | | |                                 | | |           |
 |   | | | | | +---storage_mgmt (vlan750)        | | |           |
 |   | | | | |                                   | | |           |
 |   | | | | +-----storage (vlan740)             | | |           |
 |   | | | |                                     | | |           |
 |   | | | +-------management (vlan730)--------------+           |
 |   | | |                                       | |             |
 |   | | +---------external_api (vlan720)        | |             |
 |   | |                                         | |             |
 |   | +-----------internal_api (vlan710)----------+             |
 |   |                                           |               |
 |   +-------------provisioning (vlan700)--------+               |
 |                                                               |
 +---------------------------------------------------------------+
```

# Infrastructure configuration

## Physical switch
- ge0
-- all networks (vlan700,10,20,30,40,50) are configured as trunks
- ge1
-- tenant network is untagged and can be a trunk
- ge2
-- provisioning network (vlan700) is the native vlan
-- all other networks (vlan710,20,30,40,50) are configured as trunks
- ge3
-- tenant network is untagged and can be trunk

## Provisioning of Control plane VMs

For KVM case: See [README-KVM.md](README-KVM.md)
For RHEV case: See [README-RHEV.md](README-RHEV.md)


## Setup tripleo controlplane

### Setup IDM VM (FreeIPA) 
```bash
freeipa_ip=`virsh domifaddr ${freeipa_name} |grep ipv4 |awk '{print $4}' |awk -F"/" '{print $1}'`
ssh-copy-id ${freeipa_ip}
ssh ${freeipa_ip}
```

### on the IDM VM prepare IDM (FreeIPA)

#### initialize second NIC which should be available in provisioning network (!!!ADJUST an IP)
```bash
### !!! Adjust this IP to your setup
prov_freeipa_ip=10.87.64.4
###
cat << EOM > /etc/sysconfig/network-scripts/ifcfg-eth1
DEVICE=eth1
ONBOOT=yes
HOTPLUG=no
NM_CONTROLLED=no
BOOTPROTO=static
IPADDR=$prov_freeipa_ip
NETMASK=255.255.255.0
EOM
ifdown eth1
ifup eth1
```

#### download setup script and deploy freeipa
Follow main RedHat [procedure](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html-single/installing_identity_management/index)
```bash
# example of deploy with help of tf-devstack
git clone https://github.com/tungstenfabric/tf-devstack.git
# adjust parameters to your setup
export AdminPassword='qwe123QWe'
export CLOUD_DOMAIN_NAME='dev.localdomain'
export UndercloudFQDN='queensa.dev.localdomain'
./tf-devstack/rhosp/ipa/freeipa_setup.sh
```

#### read and save OTP for unercloud
```bash
cat ~/undercloud_otp
```
#### finish ssh on IDM
```bash
exit
```

## get undercloud ip and log into it
```bash
undercloud_ip=`virsh domifaddr ${undercloud_name} |grep ipv4 |awk '{print $4}' |awk -F"/" '{print $1}'`
ssh-copy-id ${undercloud_ip}
ssh ${undercloud_ip}
```

# Undercloud deploy

## Undercloud preparation
```bash
undercloud_name=`hostname -s`
undercloud_suffix=`hostname -d`
hostnamectl set-hostname ${undercloud_name}.${undercloud_suffix}
hostnamectl set-hostname --transient ${undercloud_name}.${undercloud_suffix}
```
Get the undercloud ip and set the correct entries in /etc/hosts, ie (assuming the mgmt nic is eth0):
```bash 
undercloud_ip=`ip addr sh dev eth0 |grep "inet " |awk '{print $2}' |awk -F"/" '{print $1}'`
echo ${undercloud_ip} ${undercloud_name}.${undercloud_suffix} ${undercloud_name} >> /etc/hosts
```
### Install undercloud according Red Hat documentation
https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/director_installation_and_usage/director_installation_and_configuration

### OSP16
Register with Satellite (can be done with CDN as well)
```bash
satellite_fqdn=satellite.englab.juniper.net
act_key=osp16
org=Juniper
yum localinstall -y http://${satellite_fqdn}/pub/katello-ca-consumer-latest.noarch.rpm
subscription-manager register --activationkey=${act_key} --org=${org}
```

## for TLS with RedHat IDM (FreeIPA) case
### install IDM according to RH documentaion
https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/installing_identity_management/index

## Install the undercloud
### prepare config for undercloud installation
```bash
yum install -y python-tripleoclient tmux
su - stack
cp /usr/share/python-tripleoclient/undercloud.conf.sample ~/undercloud.conf
```
### for TLS with RedHat IDM (FreeIPA) case update config
#### (see details in RH documentaion https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/advanced_overcloud_customization/sect-enabling_ssltls_on_the_overcloud)
An exmaple:
```bash
# !!! Set to OTP that was saved from IDM VM from the file ~/undercloud_otp
FREE_IPA_OTP="<otp>"
# !!! Adjust this IP to your setup
prov_freeipa_ip=10.87.64.4
# The following parameters need to be set within [DEFAULT] section
cat << EOF >> ~/undercloud.conf
undercloud_hostname: ${undercloud_name}.${undercloud_suffix}
undercloud_nameservers: $prov_freeipa_ip
overcloud_domain_name: $undercloud_suffix
enable_novajoin: True
ipa_otp: "$FREE_IPA_OTP"
EOF

# If use RedHat Virtualization for virtualized controllers enable staging-ovirt driver
cat <<EOF >> ~/undercloud.conf
enabled_hardware_types = ipmi,redfish,ilo,idrac,staging-ovirt
EOF
```

### create file containers-prepare-parameter.yaml

```yaml
parameter_defaults:
  ContainerImagePrepare:
  - push_destination: true
    excludes:
      - ceph
    set:
      name_prefix: openstack-
      name_suffix: ''
      namespace: registry.redhat.io/rhosp-rhel8
      neutron_driver: null
      rhel_containers: false
      tag: '16.2'
    tag_from_label: '{version}-{release}'
  ContainerImageRegistryCredentials:
    registry.redhat.io:
      YOUR_REDHAT_LOGIN: 'YOUR_REDHAT_PASSWORD'
```

### install undercloud
```bash
openstack undercloud install
source stackrc
```

### enable forwarding
```bash
sudo iptables -A FORWARD -i br-ctlplane -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o br-ctlplane -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

## set overcloud nameserver
### for regular case
```bash
undercloud_nameserver=8.8.8.8
```
### for TLS with RedHat IDM (FreeIPA) case
```bash
undercloud_nameserver=$prov_freeipa_ip
```
### set nameserver
```bash
openstack subnet set `openstack subnet show ctlplane-subnet -c id -f value` --dns-nameserver ${undercloud_nameserver}
```

## add an external api interface
```bash
sudo ip link add name vlan720 link br-ctlplane type vlan id 720
sudo ip addr add 10.2.0.254/24 dev vlan720
sudo ip link set dev vlan720 up
```

# If external Contrail Control plane in a Kubernetes cluster to be used (side-by-side deployment)
Prepare and deploy separately Contrail Control plane in a Kubernetes cluster.
E.g. for Kuberenetes use [Kubespray](https://github.com/kubernetes-sigs/kubespray.git)
Contrail Controllers to be deployed by [TF Operator](https://github.com/tungstenfabric/tf-operator).
NOTE: In case of RedHat IDM (FreeIPA) used in RHOSP) it is needed to ensure that
for Contrail in Kuberentes uses CA certificate bundle that contains
own self-igned certificate and IPA CA. Example how to provide variable for TF Operator:
```bash
cat k8s-root-ca.pem /etc/ipa/ca.crt  > ca-bundle.pem
export SSL_CACERT=$(cat ~/ca-bundle.pem)
export SSL_CAKEY=$(cat ~/k8s-root-ca-key.pem)
```
Ensure Kubernetes nodes can connect to Internal API and Tenant networks.
Ensure Kubernetes nodes can resolve RHOSP FQDNs for Overcloud VIPs and for Compute nodes in CtlPlane and Tenant networks.


# Overcloud deploy

## Overcloud image download and upload to glance
```bash
mkdir images
cd images

sudo yum install -y rhosp-director-images rhosp-director-images-ipa
for i in  /usr/share/rhosp-director-images/overcloud-full-latest-16.2.tar \
          /usr/share/rhosp-director-images/ironic-python-agent-latest-16.2.tar ; do
  tar -xvf $i
done

openstack overcloud image upload --image-path .

cd

# prepare kernel and ramdisk images
openstack image create \
  --container-format aki \
  --disk-format aki \
  --public \
  --file /var/lib/ironic/httpboot/agent.kernel \
  bm-deploy-kernel

openstack image create \
  --container-format ari \
  --disk-format ari \
  --public \
  --file /var/lib/ironic/httpboot/agent.ramdisk \
  bm-deploy-ramdisk
```


## Ironic preparation

### If use KVM and IPMI for power management for virtualized controllers
- Create list with ironic nodes (adjust!!!)
Take the ironic_node lists from the KVM hosts.
```bash
cd
cat << EOM > ironic_list
52:54:00:16:54:d8 control-1-at-5b3s30 10.87.64.31 control 16235
52:54:00:2a:7d:99 compute-1-at-5b3s30 10.87.64.31 compute 16230
52:54:00:e0:54:b3 tsn-1-at-5b3s30 10.87.64.31 contrail-tsn 16231
52:54:00:d6:2b:03 contrail-controller-1-at-5b3s30 10.87.64.31 contrail-controller 16234
52:54:00:01:c1:af contrail-analytics-1-at-5b3s30 10.87.64.31 contrail-analytics 16233
52:54:00:4a:9e:52 contrail-analytics-database-1-at-5b3s30 10.87.64.31 contrail-analytics-database 16232
52:54:00:40:9e:13 control-1-at-centos 10.87.64.32 control 16235
52:54:00:1d:58:4d compute-dpdk-1-at-centos 10.87.64.32 compute-dpdk-1-at-centos 16230
52:54:00:6d:89:2d compute-2-at-centos 10.87.64.32 compute 16231
52:54:00:a8:46:5a contrail-controller-1-at-centos 10.87.64.32 contrail-controller 16234
52:54:00:b3:2f:7d contrail-analytics-1-at-centos 10.87.64.32 contrail-analytics 16233
52:54:00:59:e3:10 contrail-analytics-database-1-at-centos 10.87.64.32 contrail-analytics-database 16232
52:54:00:1d:8c:39 control-1-at-5b3s32 10.87.64.33 control 16235
52:54:00:9c:4b:bf compute-1-at-5b3s32 10.87.64.33 compute 16230
52:54:00:1d:a9:d9 compute-2-at-5b3s32 10.87.64.33 compute 16231
52:54:00:cd:59:92 contrail-controller-1-at-5b3s32 10.87.64.33 contrail-controller 16234
52:54:00:2f:81:1a contrail-analytics-1-at-5b3s32 10.87.64.33 contrail-analytics 16233
52:54:00:a1:4a:23 contrail-analytics-database-1-at-5b3s32 10.87.64.33 contrail-analytics-database 16232
EOM
```

- Add overcloud nodes to ironic
```bash
ipmi_password=ADMIN
ipmi_user=ADMIN
while IFS= read -r line; do
  mac=`echo $line|awk '{print $1}'`
  name=`echo $line|awk '{print $2}'`
  kvm_ip=`echo $line|awk '{print $3}'`
  profile=`echo $line|awk '{print $4}'`
  ipmi_port=`echo $line|awk '{print $5}'`
  uuid=`openstack baremetal node create --driver ipmi \
                                        --property cpus=4 \
                                        --property memory_mb=16348 \
                                        --property local_gb=100 \
                                        --property cpu_arch=x86_64 \
                                        --driver-info ipmi_username=${ipmi_user}  \
                                        --driver-info ipmi_address=${kvm_ip} \
                                        --driver-info ipmi_password=${ipmi_password} \
                                        --driver-info ipmi_port=${ipmi_port} \
                                        --name=${name} \
                                        --property capabilities=profile:${profile},boot_option:local \
                                        -c uuid -f value`
  openstack baremetal port create --node ${uuid} ${mac}
done < <(cat ironic_list)
```

### If use RedHat Virtualization for virtualized controllers
[More info in the  RedHat documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/director_installation_and_usage/creating-virtualized-control-planes)

- Ensure staging-ovirt driver is enabled
```bash
openstack baremetal driver list | grep staging-ovirt
```

- Create list with ironic nodes (adjust!!!)
Take the ironic_node lists from the RHVH hosts.

IMPORTANT: In case of Contrail Control plane to be deployed in a Kubernetes cluster remove Contrail nodes.
Kuberentes and Contrail are to be deployed separately and are not managed by RHOSP.


```bash
cd
cat << EOM > ironic_list
52:54:00:16:54:d8 controller-0          control
52:54:00:d6:2b:03 contrail-controller-0 contrail-controller
52:54:00:d6:2b:13 contrail-controller-1 contrail-controller
52:54:00:d6:2b:23 contrail-controller-2 contrail-controller
EOM
```

- Add overcloud nodes to ironic
```bash
pm_user="admin@internal"
pm_password="qwe123QWE"
# ensure RHVM is resolved and accessible
pm_addr="vmengine.dev.clouddomain"
while IFS= read -r line; do
  mac=`echo $line|awk '{print $1}'`
  name=`echo $line|awk '{print $2}'`
  profile=`echo $line|awk '{print $3}'`
  uuid=`openstack baremetal node create \
    --property cpus=4 \
    --property memory_mb=16348 \
    --property local_gb=100 \
    --property cpu_arch=x86_64 \
    --driver "staging-ovirt" \
    --power-interface staging-ovirt \
    --console-interface no-console \
    --management-interface staging-ovirt \
    --vendor-interface no-vendor \
    --driver-info ovirt_username=${pm_user} \
    --driver-info ovirt_password=${pm_password} \
    --driver-info ovirt_address=${pm_addr} \
    --driver-info ovirt_vm_name=${name} \
    --name=${name} \
    --property capabilities=profile:${profile},boot_option:local \
    -c uuid -f value`
  openstack baremetal port create --node ${uuid} ${mac}
done < <(cat ironic_list)
```

- Set kernel and ramdisk images
```bash
DEPLOY_KERNEL=$(openstack image show bm-deploy-kernel -f value -c id)
DEPLOY_RAMDISK=$(openstack image show bm-deploy-ramdisk -f value -c id)
# ensure kernel and deploy vars are read correctly
echo $DEPLOY_KERNEL
echo $DEPLOY_RAMDISK
# set custom deploy kernel and ramdisk
for i in `openstack baremetal node list -c UUID -f value`; do
  openstack baremetal node set $i \
    --driver-info deploy_kernel=$DEPLOY_KERNEL \
    --driver-info deploy_ramdisk=$DEPLOY_RAMDISK
done
# check properties
for i in `openstack baremetal node list -c UUID -f value`; do
  openstack baremetal node show $i -c properties -f value
done
```

### introspect the nodes
```bash
for node in $(openstack baremetal node list -c UUID -f value) ; do
  openstack baremetal node manage --wait 0 $node
done
openstack overcloud node introspect --all-manageable --provide
```

## create the flavors
```bash
for i in compute-dpdk \
compute-sriov \
contrail-controller \
contrail-analytics \
contrail-database \
contrail-analytics-database; do
  openstack flavor create $i --ram 4096 --vcpus 1 --disk 40
  openstack flavor set --property "capabilities:boot_option"="local" \
                       --property "capabilities:profile"="${i}" ${i}
  openstack flavor set --property resources:CUSTOM_BAREMETAL=1 --property resources:DISK_GB='0' \
                       --property resources:MEMORY_MB='0' \
                       --property resources:VCPU='0' ${i}
done
```

## create tht template copy
```bash
cp -r /usr/share/openstack-tripleo-heat-templates/ tripleo-heat-templates
git clone https://github.com/tungstenfabric/tf-tripleo-heat-templates -b stable/train
cp -r tf-tripleo-heat-templates/* tripleo-heat-templates/
```

## Tripleo container management

```bash
su - stack
source stackrc
```

### Create file rhsm.yaml with redhat credentials
!!! Adjust to your setup.
For RHOSP16.2 use 8.2 release.
```yaml
parameter_defaults:
  RhsmVars:
    rhsm_repos:
      - fast-datapath-for-rhel-8-x86_64-rpms
      - openstack-16.2-for-rhel-8-x86_64-rpms
      - satellite-tools-6.5-for-rhel-8-x86_64-rpms
      - ansible-2-for-rhel-8-x86_64-rpms
      - rhel-8-for-x86_64-highavailability-rpms
      - rhel-8-for-x86_64-appstream-rpms
      - rhel-8-for-x86_64-baseos-rpms
    rhsm_username: "YOUR_REDHAT_LOGIN"
    rhsm_password: "YOUR_REDHAT_PASSWORD"
    rhsm_org_id: "YOUR_REDHAT_ID"
    rhsm_pool_ids: "YOUR_REDHAT_POOL_ID"
    rhsm_release: "8.4"
```


### Get and upload the containers into local registry

#### OSP16
```bash
sudo openstack tripleo container image prepare \
  -e ~/containers-prepare-parameter.yaml \
  -e ~/rhsm.yaml > ~/overcloud_containers.yaml

sudo openstack overcloud container image upload --config-file ~/overcloud_containers.yaml
```

#### Contrail
```bash
registry=${CONTAINER_REGISTRY:-'docker.io/tungstenfabric'}
tag=${CONTRAIL_CONTAINER_TAG:-'latest'}

~/tf-tripleo-heat-templates/tools/contrail/import_contrail_container.sh \
    -f ~/contrail_containers.yaml -r $registry -t $tag

#Check file ~/contrail_containers.yaml and fix registry ip if needed
#sed -i ~/contrail_containers.yaml -e "s/192.168.24.1/192.168.24.2/"

sudo openstack overcloud container image upload --config-file ~/contrail_containers.yaml

```


#### Optional: create Contrail container upload file for uploading Contrail containers to undercloud registry
In case the Contrail containers must be stored in the undercloud registry
```bash
cd ~/tf-heat-templates/tools/contrail
./import_contrail_container.sh -f container_outputfile -r registry -t tag [-i insecure] [-u username] [-p password] [-c certificate path]
```

Examples:
```bash
Pull from password protectet public registry:
./import_contrail_container.sh -f /tmp/contrail_container -r hub.juniper.net/contrail -u USERNAME -p PASSWORD -t 1234
#######################################################################
Pull from dockerhub:
./import_contrail_container.sh -f /tmp/contrail_container -r docker.io/opencontrailnightly -t 1234
#######################################################################
Pull from private secure registry:
./import_contrail_container.sh -f /tmp/contrail_container -r satellite.englab.juniper.net:5443 -c http://satellite.englab.juniper.net/pub/satellite.englab.juniper.net.crt -t 1234
#######################################################################
Pull from private INsecure registry:
./import_contrail_container.sh -f /tmp/contrail_container -r 10.0.0.1:5443 -i 1 -t 1234
#######################################################################
```

#### Optional: upload Contrail containers to undercloud registry
```
openstack overcloud container image upload --config-file /tmp/contrail_container
```


## overcloud config files

### nic templates
```bash
tripleo-heat-templates/network/config/contrail/compute-nic-config.yaml
tripleo-heat-templates/network/config/contrail/contrail-controller-nic-config.yaml
tripleo-heat-templates/network/config/contrail/controller-nic-config.yaml
```

### overcloud network config
```
tripleo-heat-templates/environments/contrail/contrail-net.yaml
```

### overcloud service config
```bash
tripleo-heat-templates/environments/contrail/contrail-services.yaml
```

### For Contral Control plane deployed separetly in a Kubernetes cluster

- Modify contrail-services.yaml to point to use external Contrail Control plane
```yaml
  # Disable RHOSP Contrail Control plane roles
  ContrailControllerCount: 0
  ContrailAnalyticsCount: 0
  ContrailAnalyticsDatabaseCount: 0
  ContrailControlOnlyCount: 0

  # Add hosts entries to resolve externak Kubernetes nodes FQDN (or use proper DNS configured)
  ExtraHostFileEntries:
    - 'IP1    <FQDN K8S master1>    <Short name master1>'
    - 'IP2    <FQDN K8S master2>    <Short name master2>'
    - 'IP3    <FQDN K8S master3>    <Short name master3>'

  # Provide Contrail Control plane IPs
  ExternalContrailConfigIPs: <comma separated list of IP/FQDNs of K8S master nodes>
  ExternalContrailControlIPs: <comma separated list of IP/FQDNs of K8S master nodes>
  ExternalContrailAnalyticsIPs: <comma separated list of IP/FQDNs of K8S master nodes>

  # Use rbac (tf-operator enables RBAC in case if Keystone auth is used)
  #(If rbac is not desire disable it in TF Operator and adjust this setting)
  AAAMode: rbac

  # Enable SSL for neutron plugin and compute nodes
  ControllerExtraConfig:
    contrail_internal_api_ssl: True
  ComputeExtraConfig:
    contrail_internal_api_ssl: True
  ContrailDpdkExtraConfig:
    contrail_internal_api_ssl: True
  # ... add same for all compute roles ..."

```

- For TLS with RedHat IDM (FreeIPA) provide CA bundle including CA certificate from Kubernetes cluster
This is to distribute self signed root CA of K8S cluster on Contrail Controller nodes as trusted CA in RHOSP

- Copy CA from kubernetes cluster into the file k8s-root-ca.pem

- Make CA bundle file
```bash
cat /etc/ipa/ca.crt k8s-root-ca.pem > ca-bundle.pem
```

- Modify tripleo-heat-templates/environments/contrail/contrail-tls.yaml to include
```yaml
resource_registry:
  # ... othere definitions ...

  OS::TripleO::NodeTLSCAData: tripleo-heat-templates/puppet/extraconfig/tls/ca-inject.yaml

parameter_defaults:
  #... other definitions ...

  # Contrail to use CA bundle
  ContrailCaCertFile: "/etc/contrail/ssl/certs/ca-cert.pem"
  SSLRootCertificatePath: "/etc/contrail/ssl/certs/ca-cert.pem"
  # SSLRootCertificate: |
  #   <ca-bundle.pem content>
  SSLRootCertificate: |
```
- Append CA bundle content to SSLRootCertificate parameter (ensure SSLRootCertificate: is latest line in the file)
```bash
cat ca-bundle.pem | while read l ; do
  echo "    $l" >> tripleo-heat-templates/environments/contrail/contrail-tls.yaml
done
```

#### set option DnsServers to $prov_freeipa_ip in the overcloud network config file
```bash
vi tripleo-heat-templates/environments/contrail/contrail-net.yaml
```

#### process templates to generate file for OS::TripleO::{{role}}ServiceServerMetadataHook definitions
These files are used by the file  ~/tripleo-heat-templates/environments/ssl/enable-internal-tls.yaml
that is generated during that processing
```bash
python3 ~/tripleo-heat-templates/tools/process-templates.py --safe \
  -r ~/tripleo-heat-templates/roles_data_contrail_aio.yaml \
  -p ~/tripleo-heat-templates/
```

### for compute nodes hugepages are enabled by default
To disable edit and remove/modify related to hugepages settings
```bash
vi tripleo-heat-templates/environments/contrail/contrail-services.yaml
```
```yaml
  ComputeParameters:
    KernelArgs: "default_hugepagesz=1GB hugepagesz=1G hugepages=4"
    ExtraSysctlSettings:
      # must be equal to value from kernel args: hugepages=2
      vm.nr_hugepages:
        value: 4
      vm.max_map_count:
        value: 128960
```

### for dpdk nodes
```bash
vi tripleo-heat-templates/environments/contrail/contrail-services.yaml
```

#### enable hugepages and iommu in kernel args (use suitable values for your setup), e.g.
```yaml
  ContrailDpdkParameters:
    # For Intel CPU
    KernelArgs: "intel_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=4 hugepagesz=2M hugepages=1024"
    # For AMD CPU uncomment
    # KernelArgs: "amd_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=4 hugepagesz=2M hugepages=1024"
    TunedProfileName: "cpu-partitioning"
    IsolCpusList: "1-16"
    ExtraSysctlSettings:
      # must be equal to value from kernel args: hugepages=4
      vm.nr_hugepages:
        value: 4
      vm.max_map_count:
        value: 128960
    ContrailSettings:
      # service threads pinning
      # SERVICE_CORE_MASK: 3,4
      # dpdk ctrl threads pinning
      # DPDK_CTRL_THREAD_MASK: 5,6
      # others params for ContrailSettings as role based are not merged with global
      DPDK_UIO_DRIVER: "vfio-pci"
      VROUTER_GATEWAY: 10.0.0.1
      BGP_ASN: 64512
      BGP_AUTO_MESH: true
```

#### set cpu_list options in NIC file accordingly for forwarding threads
```
vi tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config.yaml
```
```
  - type: contrail_vrouter_dpdk
    name: vhost0
    cpu_list: '0x03'
```

#### optionally provide additional parameters
```
  ContrailDpdkParameters:
    ContrailDpdkOptions: "--vr_mempool_sz 131072 --dpdk_txd_sz 2048 --dpdk_rxd_sz 2048 --vr_flow_entries=4000000"
```

#### modify NIC file to set network params and DPDK driver according to your setup, e.g.
```
vi tripleo-heat-templates/network/config/contrail/contrail-dpdk-nic-config.yaml
```
```
  - type: contrail_vrouter_dpdk
    name: vhost0
    driver: "vfio-pci"
    bond_mode: 4
    bond_policy: layer2+3
    members:
    - type: interface
      name: nic3
    - type: interface
      name: nic4
    mtu:
      get_param: TenantMtu
    addresses:
    - ip_netmask:
        get_param: TenantIpSubnet
```

## deploy the stack

### OSP16 w/o TLS
```bash
role_file=~/tripleo-heat-templates/roles_data_contrail_aio.yaml
openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file $role_file \
  -e tripleo-heat-templates/environments/rhsm.yaml \
  -e tripleo-heat-templates/environments/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
  -e containers-prepare-parameter.yaml \
  -e rhsm.yaml
```

### OSP16 for TLS everwhere with RedHat IDM (FreeIPA) case
```bash
role_file=~/tripleo-heat-templates/roles_data_contrail_aio.yaml

python3 tripleo-heat-templates/tools/process-templates.py --clean \
  -r $role_file \
  -p tripleo-heat-templates/

python3 tripleo-heat-templates/tools/process-templates.py \
  -r $role_file \
  -p tripleo-heat-templates/

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file $role_file \
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
  -e rhsm.yaml

```

L3MH case specifics [L3MH-README.md]

# quick VM start
```
source overcloudrc
curl -O http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
openstack image create --container-format bare --disk-format qcow2 --file cirros-0.3.5-x86_64-disk.img cirros
openstack flavor create --public cirros --id auto --ram 64 --disk 0 --vcpus 1
openstack network create net1
openstack subnet create --subnet-range 1.0.0.0/24 --network net1 sn1
nova boot --image cirros --flavor cirros --nic net-id=`openstack network show net1 -c id -f value` --availability-zone nova:overcloud-novacompute-0.localdomain c1
nova list
```
