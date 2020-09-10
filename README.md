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
are provided as Virtual Machines hosted on KVM hosts

- KVM 1:
  OpenStack Controller 1
  Contrail Controller 1

- KVM 2:
  OpenStack Controller 2
  Contrail Controller 2

- KVM 3:
  OpenStack Controller 3
  Contrail Controller 3

## sample toplogy
### Layer 1
```
   +-------------------------------+
   |KVM host 3                     |
 +-------------------------------+ |
 |KVM host 2                     | |
+------------------------------+ | |
|KVM host 1                    | | |
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
|                             KVM            |
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

## Control plane KVM host preparation (KVM 1-3)

### on all KVM hosts

The control plane KVM hosts will host the control plane VMs. Each KVM host
will need virtual switches and the virtual machine definitions. The tasks
described must be done on each of the three hosts.
NIC 1 - 3 have to be substituded with real NIC names.


### Install basic packages
```
yum install -y libguestfs \
 libguestfs-tools \
 openvswitch \
 virt-install \
 kvm libvirt \
 libvirt-python \
 python-virtualbmc \
 python-virtinst
```

### Start libvirtd & ovs
```
systemctl start libvirtd
systemctl start openvswitch
```

#### vSwitch configuration:
- br0
-- provisioning network (vlan700) is the native vlan
-- all other networks (vlan710,20,30,40,50) are configured as trunks
- br1
-- tenant network is untagged

#### Create virtual switches for the undercloud VM
```
ovs-vsctl add-br br0
ovs-vsctl add-br br1
ovs-vsctl add-port br0 NIC1
ovs-vsctl add-port br1 NIC2
cat << EOF > br0.xml
<network>
  <name>br0</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
  <virtualport type='openvswitch'/>
  <portgroup name='overcloud'>
    <vlan trunk='yes'>
      <tag id='700' nativeMode='untagged'/>
      <tag id='710'/>
      <tag id='720'/>
      <tag id='730'/>
      <tag id='740'/>
      <tag id='750'/>
    </vlan>
  </portgroup>
</network>
EOF
cat << EOF > br1.xml
<network>
  <name>br1</name>
  <forward mode='bridge'/>
  <bridge name='br1'/>
  <virtualport type='openvswitch'/>
</network>
EOF
virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0
virsh net-define br1.xml
virsh net-start br1
virsh net-autostart br1
```

### setup vm templates, vbmc and create ironic list (on all hosts hosting overcloud nodes)
```
num=0
ipmi_user=ADMIN
ipmi_password=ADMIN
libvirt_path=/var/lib/libvirt/images
port_group=overcloud
prov_switch=br0

# Define roles and their count
ROLES=compute:2,contrail-controller:1,control:1

/bin/rm ironic_list
IFS=',' read -ra role_list <<< "${ROLES}"
for role in ${role_list[@]}; do
  role_name=`echo $role|cut -d ":" -f 1`
  role_count=`echo $role|cut -d ":" -f 2`
  for count in `seq 1 ${role_count}`; do
    echo $role_name $count
    qemu-img create -f qcow2 ${libvirt_path}/${role_name}_${count}.qcow2 99G
    virsh define /dev/stdin <<EOF
    $(virt-install --name ${role_name}_${count} \
--disk ${libvirt_path}/${role_name}_${count}.qcow2 \
--vcpus=4 \
--ram=16348 \
--network network=br0,model=virtio,portgroup=${port_group} \
--network network=br1,model=virtio \
--virt-type kvm \
--cpu host \
--import \
--os-variant rhel8.2 \
--serial pty \
--console pty,target_type=virtio \
--graphics vnc \
--print-xml)
EOF
    vbmc add ${role_name}_${count} --port 1623${num} --username ${ipmi_user} --password ${ipmi_password}
    vbmc start ${role_name}_${count}
    prov_mac=`virsh domiflist ${role_name}_${count}|grep ${prov_switch}|awk '{print $5}'`
    vm_name=${role_name}-${count}-`hostname -s`
    kvm_ip=`ip route get 1  |grep src |awk '{print $7}'`
    echo ${prov_mac} ${vm_name} ${kvm_ip} ${role_name} 1623${num}>> ironic_list
    num=$(expr $num + 1)
  done
done
```
In case '--os-variant rhel8.2' doesn't work for you please install libosinfo and use command 'osinfo-query os' for the list of appropriate distros.

There will be one ironic_list file per KVM host. The ironic_list files of all KVM hosts
has to be combined on the overcloud.
This is an example of a full list across three KVM hosts:
```
52:54:00:e7:ca:9a compute-1-5b3s31 10.87.64.32 compute 16230
52:54:00:30:6c:3f compute-2-5b3s31 10.87.64.32 compute 16231
52:54:00:9a:0c:d5 contrail-controller-1-5b3s31 10.87.64.32 contrail-controller 16232
52:54:00:cc:93:d4 control-1-5b3s31 10.87.64.32 control 16233
52:54:00:28:10:d4 compute-1-5b3s30 10.87.64.31 compute 16230
52:54:00:7f:36:e7 compute-2-5b3s30 10.87.64.31 compute 16231
52:54:00:32:e5:3e contrail-controller-1-5b3s30 10.87.64.31 contrail-controller 16232
52:54:00:d4:31:aa control-1-5b3s30 10.87.64.31 control 16233
52:54:00:d1:d2:ab compute-1-5b3s32 10.87.64.33 compute 16230
52:54:00:ad:a7:cc compute-2-5b3s32 10.87.64.33 compute 16231
52:54:00:55:56:50 contrail-controller-1-5b3s32 10.87.64.33 contrail-controller 16232
52:54:00:91:51:35 control-1-5b3s32 10.87.64.33 control 16233
```

This list will be needed on the undercloud VM later on.
With that the control plane VM KVM host preparation is done.

### RHEL 8.2

```
mkdir ~/images
```
Download rhel-server-8.2-update-1-x86_64-kvm.qcow2 from RedHat portal to ~/images
```
cloud_image=~/images/rhel-server-8.2-update-1-x86_64-kvm.qcow2
```

## customize the undercloud VM image
```
undercloud_name=queensa
undercloud_suffix=local
root_password=contrail123
stack_password=contrail123
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 /var/lib/libvirt/images/${undercloud_name}.qcow2 100G
virt-resize --expand /dev/sda1 ${cloud_image} /var/lib/libvirt/images/${undercloud_name}.qcow2
virt-customize  -a /var/lib/libvirt/images/${undercloud_name}.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --hostname ${undercloud_name}.${undercloud_suffix} \
  --run-command 'useradd stack' \
  --password stack:password:${stack_password} \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --run-command 'yum remove -y cloud-init' \
  --selinux-relabel
```

## virsh define undercloud VM
```
vcpus=8
vram=32000
virt-install --name ${undercloud_name} \
  --disk /var/lib/libvirt/images/${undercloud_name}.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network network=default,model=virtio \
  --network network=br0,model=virtio,portgroup=overcloud \
  --virt-type kvm \
  --import \
  --os-variant rhel8.2 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio
```
In case '--os-variant rhel8.2' doesn't work for you please install libosinfo and use command 'osinfo-query os' for the list of appropriate distros.

## start the undercloud
```
virsh start ${undercloud_name}
```

## for TLS with RedHat IDM (FreeIPA)
### cusomize the idm VM image
```
freeipa_name=freeipa
qemu-img create -f qcow2 /var/lib/libvirt/images/${freeipa_name}.qcow2 100G
virt-resize --expand /dev/sda1 ${cloud_image} /var/lib/libvirt/images/${freeipa_name}.qcow2
virt-customize  -a /var/lib/libvirt/images/${freeipa_name}.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --hostname ${freeipa_name}.${undercloud_suffix} \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --run-command 'yum remove -y cloud-init' \
  --selinux-relabel
```

### virsh define IDM VM
```
vcpus=2
vram=4000
virt-install --name ${freeipa_name} \
  --disk /var/lib/libvirt/images/${freeipa_name}.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network network=default,model=virtio \
  --network network=br0,model=virtio,portgroup=overcloud \
  --virt-type kvm \
  --import \
  --os-variant rhl8.2 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio
```

### start the IDM VM
```
virsh start ${freeipa_name}
```

### get IDM ip and log into it
```
freeipa_ip=`virsh domifaddr ${freeipa_name} |grep ipv4 |awk '{print $4}' |awk -F"/" '{print $1}'`
ssh-copy-id ${freeipa_ip}
ssh ${freeipa_ip}
```

### on the IDM VM prepare IDM (FreeIPA)

#### initialize second NIC which should be available in provisioning network (!!!ADJUST an IP)
```
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

#### download setup script
```
cd /root/
yum install -y wget
wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum localinstall -y ./epel-release-latest-7.noarch.rpm
#wget https://raw.githubusercontent.com/openstack/tripleo-heat-templates/stable/queens/ci/scripts/freeipa_setup.sh
wget https://raw.githubusercontent.com/progmaticlab/juniper-ci/master/tripleo/freeipa_setup.sh
chmod +x ./freeipa_setup.sh
```

#### prepare config for freeipa installation (!!!ADJUST) and setup
```
# !!! adjust another name is used
undercloud_name=queensa
####
freeipa_name=`hostname -s`
freeipa_suffix=`hostname -d`
cat <<EOF > ./freeipa-setup.env
Hostname=${freeipa_name}.${freeipa_suffix}
FreeIPAIP=$prov_freeipa_ip
DirectoryManagerPassword=qwe123QWE
AdminPassword=qwe123QWE
UndercloudFQDN=${undercloud_name}.${freeipa_suffix}
CLOUD_DOMAIN_NAME=$freeipa_suffix
# !!! remove if not rhel
ENVIRONMENT_OS=rhel
# ===
EOF
cp ./freeipa-setup.env /tmp/freeipa-setup.env
./freeipa_setup.sh
```

#### read and save OTP for unercloud
```
cat ~/undercloud_otp
```
#### finish ssh on IDM
```
exit
```

## get undercloud ip and log into it
```
undercloud_ip=`virsh domifaddr ${undercloud_name} |grep ipv4 |awk '{print $4}' |awk -F"/" '{print $1}'`
ssh-copy-id ${undercloud_ip}
ssh ${undercloud_ip}
```

# on the undercloud

## Undercloud preparation
```
undercloud_name=`hostname -s`
undercloud_suffix=`hostname -d`
hostnamectl set-hostname ${undercloud_name}.${undercloud_suffix}
hostnamectl set-hostname --transient ${undercloud_name}.${undercloud_suffix}
```
Get the undercloud ip and set the correct entries in /etc/hosts, ie (assuming the mgmt nic is eth0):
```
undercloud_ip=`ip addr sh dev eth0 |grep "inet " |awk '{print $2}' |awk -F"/" '{print $1}'`
echo ${undercloud_ip} ${undercloud_name}.${undercloud_suffix} ${undercloud_name} >> /etc/hosts
```
### Install undercloud according Red Hat documentation
https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.1/html/director_installation_and_usage/director_installation_and_configuration

### OSP16
Register with Satellite (can be done with CDN as well)
```css
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
```
yum install -y python-tripleoclient tmux
su - stack
cp /usr/share/python-tripleoclient/undercloud.conf.sample ~/undercloud.conf
```
### for TLS with RedHat IDM (FreeIPA) case update config
#### (see details in RH documentaion https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.1/html/advanced_overcloud_customization/sect-enabling_ssltls_on_the_overcloud)
An exmaple:
```
### !!! Set to OTP that was saved from IDM VM from the file ~/undercloud_otp
FREE_IPA_OTP="<otp>"
### !!! Adjust this IP to your setup
prov_freeipa_ip=10.87.64.4
The following parameters need to be set within [DEFAULT] section
###
cat << EOF >> ~/undercloud.conf
undercloud_hostname: ${undercloud_name}.${undercloud_suffix}
undercloud_nameservers: $prov_freeipa_ip
overcloud_domain_name: $undercloud_suffix
enable_novajoin: True
ipa_otp: "$FREE_IPA_OTP"
EOF

```

### create file containers-prepare-parameter.yaml

```
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
      tag: '16.1'
    tag_from_label: '{version}-{release}'
  ContainerImageRegistryCredentials:
    registry.redhat.io:
      YOUR_REDHAT_LOGIN: 'YOUR_REDHAT_PASSWORD'
```

### install undercloud
```
openstack undercloud install
source stackrc
```

## forwarding
```
sudo iptables -A FORWARD -i br-ctlplane -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o br-ctlplane -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

## set overcloud nameserver
### for regular case
```
undercloud_nameserver=8.8.8.8
```
### for TLS with RedHat IDM (FreeIPA) case
```
undercloud_nameserver=$prov_freeipa_ip
```
### set nameserver
```
openstack subnet set `openstack subnet show ctlplane-subnet -c id -f value` --dns-nameserver ${undercloud_nameserver}
```

## add an external api interface
```
sudo ip link add name vlan720 link br-ctlplane type vlan id 720
sudo ip addr add 10.2.0.254/24 dev vlan720
sudo ip link set dev vlan720 up
```

## Overcloud image download and upload to glance
```
mkdir images
cd images
```


### OSP16
```
sudo yum install -y rhosp-director-images rhosp-director-images-ipa
for i in /usr/share/rhosp-director-images/overcloud-full-latest-16.1.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-16.1.tar ; do tar -xvf $i; done
```

```
cd
openstack overcloud image upload --image-path /home/stack/images/
```
## Ironic preparation

### create list with ironic nodes (adjust!!!)
Take the ironic_node lists from the KVM hosts from above.
```
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

### add overcloud nodes to ironic
```
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

DEPLOY_KERNEL=$(openstack image show bm-deploy-kernel -f value -c id)
DEPLOY_RAMDISK=$(openstack image show bm-deploy-ramdisk -f value -c id)

for i in `openstack baremetal node list -c UUID -f value`; do
  openstack baremetal node set $i --driver-info deploy_kernel=$DEPLOY_KERNEL --driver-info deploy_ramdisk=$DEPLOY_RAMDISK
done

for i in `openstack baremetal node list -c UUID -f value`; do
  openstack baremetal node show $i -c properties -f value
done
```

### introspect the nodes
```
for node in $(openstack baremetal node list -c UUID -f value) ; do
  openstack baremetal node manage $node
done
openstack overcloud node introspect --all-manageable --provide
```

## create the flavors
```
for i in compute-dpdk \
compute-sriov \
contrail-controller \
contrail-analytics \
contrail-database \
contrail-analytics-database; do
  openstack flavor create $i --ram 4096 --vcpus 1 --disk 40
  openstack flavor set --property "capabilities:boot_option"="local" \
                       --property "capabilities:profile"="${i}" ${i}
  openstack flavor set --property resources:CUSTOM_BAREMETAL=1 --property resources:DISK_GB='0'
                       --property resources:MEMORY_MB='0'
                       --property resources:VCPU='0' ${i}
done
```

## create tht template copy
```
cp -r /usr/share/openstack-tripleo-heat-templates/ tripleo-heat-templates
git clone https://github.com/tungstenfabric/tf-tripleo-heat-templates -b stable/train
cp -r tf-tripleo-heat-templates/* tripleo-heat-templates/
```

## Tripleo container management

```
su - stack
source stackrc
```

### Create file rhsm.yaml with redhat credentials
```

parameter_defaults:
  RhsmVars:
    rhsm_repos:
      - fast-datapath-for-rhel-8-x86_64-rpms
      - openstack-16.1-for-rhel-8-x86_64-rpms
      - satellite-tools-6.5-for-rhel-8-x86_64-rpms
      - ansible-2-for-rhel-8-x86_64-rpms
      - rhel-8-for-x86_64-highavailability-rpms
      - rhel-8-for-x86_64-appstream-rpms
      - rhel-8-for-x86_64-baseos-rpms
    rhsm_username: "YOUR_REDHAT_LOGIN"
    rhsm_password: "YOUR_REDHAT_PASSWORD"
    rhsm_org_id: "YOUR_REDHAT_ID"
    rhsm_pool_ids: "YOUR_REDHAT_POOL_ID"
```



### Get and upload the containers into local registry

#### OSP16

```
sudo openstack tripleo container image prepare \
  -e ~/containers-prepare-parameter.yaml
  -e ~/rhsm.yaml > ~/overcloud_containers.yaml

sudo openstack overcloud container image upload --config-file ~/overcloud_containers.yaml

```
#### tripleo

```
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
```
cd ~/tf-heat-templates/tools/contrail
./import_contrail_container.sh -f container_outputfile -r registry -t tag [-i insecure] [-u username] [-p password] [-c certificate path]
```

Examples:
```
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
```
tripleo-heat-templates/network/config/contrail/compute-nic-config.yaml
tripleo-heat-templates/network/config/contrail/contrail-controller-nic-config.yaml
tripleo-heat-templates/network/config/contrail/controller-nic-config.yaml
```
### overcloud network config
```
tripleo-heat-templates/environments/contrail/contrail-net.yaml
```
### overcloud service config
```
tripleo-heat-templates/environments/contrail/contrail-services.yaml
```
### for TLS with RedHat IDM (FreeIPA) case
#### add options for cloud name
```
cat << EOF >> tripleo-heat-templates/environments/contrail/contrail-tls.yaml
  CloudName: overcloud.$undercloud_suffix
  CloudNameInternal: overcloud.internalapi.$undercloud_suffix
  CloudNameCtlplane: overcloud.ctlplane.$undercloud_suffix
EOF
```
#### set option DnsServers to $prov_freeipa_ip in the overcloud network config file
```
vi tripleo-heat-templates/environments/contrail/contrail-net.yaml
```
#### process templates to generate file for OS::TripleO::{{role}}ServiceServerMetadataHook definitions
These files are used by the file  ~/tripleo-heat-templates/environments/ssl/enable-internal-tls.yaml
that is generated during that processing
```
  python ~/tripleo-heat-templates/tools/process-templates.py  --safe \
    -r ~/tripleo-heat-templates/roles_data_contrail_aio.yaml \
    -p ~/tripleo-heat-templates/
```

### for compute nodes hugepages are enabled by default
To disable edit and remove/modify related to hugepages settings
```
vi tripleo-heat-templates/environments/contrail/contrail-services.yaml
```
```
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
```
vi tripleo-heat-templates/environments/contrail/contrail-services.yaml
```
#### enable hugepages and iommu in kernel args (use suitable values for your setup), e.g.
```
  # For Intel CPU
  ContrailDpdkParameters:
    KernelArgs: "intel_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=4 hugepagesz=2M hugepages=1024"
    ExtraSysctlSettings:
      # must be equal to value from kernel args: hugepages=4
      vm.nr_hugepages:
        value: 4
      vm.max_map_count:
        value: 128960
```
```
  # For AMD CPU
  ContrailDpdkParameters:
    KernelArgs: "amd_iommu=on iommu=pt default_hugepagesz=1GB hugepagesz=1G hugepages=4 hugepagesz=2M hugepages=1024"
    ExtraSysctlSettings:
      # must be equal to value from kernel args: hugepages=2
      vm.nr_hugepages:
        value: 4
      vm.max_map_count:
        value: 128960
```
#### adjust performance settings according to your setup, e.g.
```
  ContrailDpdkParameters:
    TunedProfileName: "cpu-partitioning"
    IsolCpusList: "1-16"
    ContrailSettings:
      # service threads pinning
      # SERVICE_CORE_MASK: 3,4
      # dpdk ctrl threads pinning
      # DPDK_CTRL_THREAD_MASK: 5,6
      # others params for ContrailSettings as role based are not merged with global
      DPDK_UIO_DRIVER: uio_pci_generic
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
### OSP16
```
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
```
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
