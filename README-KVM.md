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


# Control plane KVM host preparation (KVM 1-3)

### on all KVM hosts

The control plane KVM hosts will host the control plane VMs. Each KVM host
will need virtual switches and the virtual machine definitions. The tasks
described must be done on each of the three hosts.
NIC 1 - 3 have to be substituded with real NIC names.


### Install basic packages
```bash
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
```bash
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
```bash
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
```bash
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
```bash
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

```bash
mkdir ~/images
```
Download rhel-server-8.2-update-1-x86_64-kvm.qcow2 from RedHat portal to ~/images
```bash
cloud_image=~/images/rhel-server-8.2-update-1-x86_64-kvm.qcow2
```

## customize the undercloud VM image
```bash
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
```bash
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
```bash
virsh start ${undercloud_name}
```

## for TLS with RedHat IDM (FreeIPA)
### cusomize the idm VM image
```bash
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
```bash
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
```bash
virsh start ${freeipa_name}
```

