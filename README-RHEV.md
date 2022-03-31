# This readme provides an example of provisioning virtualized controllers for RHOSP16.2 using Red Hat Virtualization.
It is provided 'as is' as it based on the RedHat documentation version actual on Dev 2021.
Check on:
| Operating System  |
| ----------------- |
| RHEL 8.5          |

Theere are more info about virtualized controllers in [RedHat documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html/director_installation_and_usage/creating-virtualized-control-planes)


# Introduction
This readme provides an example of provisioning virtualized controllers for RHOSP16.2 using Red Hat Virtualization.
The main instructions to follow are in the RedHat [documentation](https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4).

The example below is based on [Red Hat Virtualization Manager As Self-Hosted engine](https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4/html/installing_red_hat_virtualization_as_a_self-hosted_engine_using_the_command_line/index)

See more about installation options in the RedHat [documentation](https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4/html/product_guide/installation)

IMPORTNANT: this readme uses NFS as a storage for VMs, note that you need to plan you storage layout
and consider other options (including localfs on dedicated disks) for desired balance of performance,
flexibility and relybility.


# Repare Red Hat Virtualization Manager hosts
More about hosts preparateion in [RedHat instruction](https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4/html/installing_red_hat_virtualization_as_a_self-hosted_engine_using_the_command_line/installing_hosts_for_rhv_she_cli_deploy#Red_Hat_Enterprise_Linux_hosts_SHE_cli_deploy)

## Deploy hosts with RHEL8

## Install and enable required software
```bash
# Register node with RedHat subscription
# (for satelite check RedHat instruction)
sudo subscription-manager register \
  --username <usename> \
  --password <password>

# Attach pools that allow to enable all required repos
# e.g.:
sudo subscription-manager attach \
  --pool <RHOSP16.2 pool ID> \
  --pool <Red Hat Virtualization Manager pool ID>

# Enable repos
sudo subscription-manager repos \
    --disable='*' \
    --enable=rhel-8-for-x86_64-baseos-rpms \
    --enable=rhel-8-for-x86_64-appstream-rpms \
    --enable=rhv-4-mgmt-agent-for-rhel-8-x86_64-rpms \
    --enable=fast-datapath-for-rhel-8-x86_64-rpms \
    --enable=advanced-virt-for-rhel-8-x86_64-rpms \
    --enable=openstack-16.2-cinderlib-for-rhel-8-x86_64-rpms \
    --enable=rhceph-4-tools-for-rhel-8-x86_64-rpms

# Remove cloud-init (in case if it virt test setup and cloud image used for deploy)
sudo dnf remove -y cloud-init || true

# Enable dnf modules and update system
# For Red Hat Virtualization Manager 4.4 use virt:av
# (for previous versions check RedHat documentation)
sudo dnf module reset -y virt
sudo dnf module enable -y virt:av
sudo dnf distro-sync -y --nobest
sudo dnf upgrade -y --nobest

# Enable firewall
sudo dnf install -y firewalld
sudo systemctl enable --now firewalld

# Check current active zone
sudo firewall-cmd --get-active-zones
# exmaple of zones:
#     public
#       interfaces:  eth0

# Add virbr0 interface into the active zone for ovirtmgmt, e.g.
sudo firewall-cmd --zone=public --change-interface=virbr0 --permanent
sudo firewall-cmd --zone=public --add-forward --permanent
# Ensure used interfaces in one zone
sudo firewall-cmd --get-active-zones
# exmaple of zones:
#     [stack@node-10-0-10-147 ~]$ sudo firewall-cmd --get-active-zones
#     public
#       interfaces:  eth0 virbr0

# Enable https and cockpit for RHVM web access and monitoring
sudo firewall-cmd --permanent \
  --add-service=https \
  --add-service=cockpit \
  --add-service nfs

sudo firewall-cmd --permanent \
  --add-port 2223/tcp \
  --add-port 5900-6923/tcp \
  --add-port 2223/tcp \
  --add-port 5900-6923/tcp \
  --add-port 111/tcp --add-port 111/udp \
  --add-port 2049/tcp --add-port 2049/udp \
  --add-port 4045/tcp --add-port 4045/udp \
  --add-port 1110/tcp --add-port 1110/udp

# Prepare NFS Storage
# adjust sysctl settings
cat << EOF | sudo tee /etc/sysctl.d/99-nfs-tf-rhv.conf
net.ipv4.tcp_mem=4096 65536 4194304
net.ipv4.tcp_rmem=4096 65536 4194304
net.ipv4.tcp_wmem=4096 65536 4194304
net.core.rmem_max=8388608
net.core.wmem_max=8388608
EOF
sudo sysctl --system
# install and enable NFS services
sudo dnf install -y nfs-utils
sudo systemctl enable --now nfs-server
sudo systemctl enable --now rpcbind
# prepare special user required by Red Hat Virtualization
getent group kvm || sudo groupadd kvm -g 36
sudo useradd vdsm -u 36 -g kvm
exports="/storage *(rw,all_squash,anonuid=36,anongid=36)\n"
for s in vmengine undercloud ipa overcloud ; do
  sudo mkdir -p /storage/$s
  exports+="/storage/$s *(rw,all_squash,anonuid=36,anongid=36)\n"
done
sudo chown -R 36:36 /storage
sudo chmod -R 0755 /storage
# add storage directory to exports
echo -e "$exports" | sudo tee /etc/exports
# restart NFS services
sudo systemctl restart rpcbind
sudo systemctl restart nfs-server
# check exports
sudo exportfs

# Rebbot system In case if newer kernel availalbe in /lib/modules
latest_kv=$(ls -1 /lib/modules | sort -V | tail -n 1)
active_kv=$(uname -r)
if [[ "$latest_kv" != "$active_kv" ]] ; then
  echo "INFO: newer kernel version $latest_kv is available, active one is $active_kv"
  echo "Perform reboot..."
  sudo reboot
fi

```

## Make sure, that FQDNs can be resolved by DNS or /etc/hosts on all nodes
```bash
[stack@node-10-0-10-147 ~]$ cat /etc/hosts
# Red Hat Virtualization Manager VM
10.0.10.200  vmengine.dev.clouddomain          vmengine.dev          vmengine
# Red Hat Virtualization Hosts
10.0.10.147  node-10-0-10-147.dev.clouddomain  node-10-0-10-147.dev  node-10-0-10-147
10.0.10.148  node-10-0-10-148.dev.clouddomain  node-10-0-10-148.dev  node-10-0-10-148
10.0.10.149  node-10-0-10-149.dev.clouddomain  node-10-0-10-149.dev  node-10-0-10-149
10.0.10.150  node-10-0-10-150.dev.clouddomain  node-10-0-10-150.dev  node-10-0-10-150
```


# Deploy Red Hat Virtualization Manager (RHVM) on first node

## RHVM Appliance
```bash
sudo dnf install -y \
  tmux \
  rhvm-appliance \
  ovirt-hosted-engine-setup
```

## Deploying the self-hosted engine
```bash
# !!! During deploy you need answer questions
sudo hosted-engine --deploy

# example of adding ansible vars into deploy command
#   sudo hosted-engine --deploy --ansible-extra-vars=he_ipv4_subnet_prefix=10.0.10
# example of an answer:
#   ...
#   Please specify the storage you would like to use (glusterfs, iscsi, fc, nfs)[nfs]:
#   Please specify the nfs version you would like to use (auto, v3, v4, v4_0, v4_1, v4_2)[auto]:
#   Please specify the full shared storage connection path to use (example: host:/path): 10.0.10.147:/storage/vmengine
#   ...
```

### NOTE: before proceed with NFS task during deploy ensure required interfaces are in one zone for IP forwarding
```bash
sudo firewall-cmd --get-active-zones
# exmaple of zones:
#     [stack@node-10-0-10-147 ~]$ sudo firewall-cmd --get-active-zones
#     public
#       interfaces: ovirtmgmt eth0 virbr0
```


## To enable virh cli to use ovirt auth
```bash
sudo ln -s /etc/ovirt-hosted-engine/virsh_auth.conf  /etc/libvirt/auth.conf
```

## Enabling the Red Hat Virtualization Manager Repositories

- Login into RHVM
```bash
ssh root@vmengine
```

- Attach Red Hat Virtualization Manager subscription and enable repositories
```bash
sudo subscription-manager register --username <usename> --password <password>
# Attach pools that allow to enable all required repos
# e.g.:
sudo subscription-manager attach \
  --pool <RHOSP16.2 pool ID> \
  --pool <Red Hat Virtualization Manager pool ID>
# Enable repos
sudo subscription-manager repos \
    --disable='*' \
    --enable=rhel-8-for-x86_64-baseos-rpms \
    --enable=rhel-8-for-x86_64-appstream-rpms \
    --enable=rhv-4.4-manager-for-rhel-8-x86_64-rpms \
    --enable=fast-datapath-for-rhel-8-x86_64-rpms \
    --enable=advanced-virt-for-rhel-8-x86_64-rpms \
    --enable=openstack-16.2-cinderlib-for-rhel-8-x86_64-rpms \
    --enable=rhceph-4-tools-for-rhel-8-x86_64-rpms
# Enable modules and sync
sudo dnf module -y enable pki-deps
sudo dnf module -y enable postgresql:12
sudo dnf distro-sync -y --nobest
```

# Deploy nodes, networks and storages

## Prepare ansible env files
```bash
# Common variables
# !!! Adjust to your setup - especially undercloud_mgmt_ip and
#     ipa_mgmt_ip to allow SSH to this machines (e.g. choose IPs from ovirtmgmt network)
cat << EOF > common-env.yaml
---
ovirt_hostname: vmengine.dev.clouddomain
ovirt_user: "admin@internal"
ovirt_password: "qwe123QWE"

datacenter_name: Default

# to access hypervisors
ssh_public_key: false
ssh_root_password: "qwe123QWE"

# gateway for VMs (undercloud and ipa)
mgmt_gateway: "10.0.10.1"

undercloud_name: "undercloud"
undercloud_mgmt_ip: "10.0.10.201"
undercloud_ctlplane_ip: "192.168.24.1"

ipa_name: "ipa"
ipa_mgmt_ip: "10.0.10.205"
ipa_ctlplane_ip: "192.168.24.5"

overcloud_domain: "dev.clouddomain"
EOF

# Hypervisor nodes
# !! Adjust to your setup
# Important: ensure you use correct node name for already registered first hypervisor
# (it is registed at the RHVM deploy command hosted-engine --deploy)
cat << EOF > nodes.yaml
---
nodes:
  # !!! Adjust networks and power management options for your needs
  - name: node-10-0-10-147.dev.clouddomain
    ip: 10.0.10.147
    cluster: Default
    networks:
      - name: ctlplane
        phy_dev: eth1
      - name: tenant
        phy_dev: eth2
    # provide power management if needed (for all nodes)
    # pm:
    #   address: 192.168.122.1
    #   port: 6230
    #   user: ipmi
    #   password: qwe123QWE
    #   type: ipmilan
    #   options:
    #     ipmilanplus: true
  - name: node-10-0-10-148.dev.clouddomain
    ip: 10.0.10.148
    cluster: node-10-0-10-148
    networks:
      - name: ctlplane
        phy_dev: eth1
      - name: tenant
        phy_dev: eth2
  - name: node-10-0-10-149.dev.clouddomain
    ip: 10.0.10.149
    cluster: node-10-0-10-149
    networks:
      - name: ctlplane
        phy_dev: eth1
      - name: tenant
        phy_dev: eth2
  - name: node-10-0-10-150.dev.clouddomain
    ip: 10.0.10.150
    cluster: node-10-0-10-150
    networks:
      - name: ctlplane
        phy_dev: eth1
      - name: tenant
        phy_dev: eth2
# !!! Adjust storages according to your setup architecture
storage:
  - name: undercloud
    mountpoint: "/storage/undercloud"
    host: node-10-0-10-147.dev.clouddomain
    address: node-10-0-10-147.dev.clouddomain
  - name: ipa
    mountpoint: "/storage/ipa"
    host: node-10-0-10-147.dev.clouddomain
    address: node-10-0-10-147.dev.clouddomain
  - name: node-10-0-10-148-overcloud
    mountpoint: "/storage/overcloud"
    host: node-10-0-10-148.dev.clouddomain
    address: node-10-0-10-148.dev.clouddomain
  - name: node-10-0-10-149-overcloud
    mountpoint: "/storage/overcloud"
    host: node-10-0-10-149.dev.clouddomain
    address: node-10-0-10-149.dev.clouddomain
  - name: node-10-0-10-150-overcloud
    mountpoint: "/storage/overcloud"
    host: node-10-0-10-150.dev.clouddomain
    address: node-10-0-10-150.dev.clouddomain
EOF

# Playbook to register hypervisor nodes in RHVM, create storage pools and networks
# Adjust values to your setup!!!
cat << EOF > infra.yaml
- hosts: localhost
  tasks:
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: Create datacenter
    ovirt_datacenter:
      state: present
      auth: "{{ ovirt_auth }}"
      name: "{{ datacenter_name }}"
      local: false
  - name: Create clusters {{ item.name }}
    ovirt_cluster:
      state: present
      auth: "{{ ovirt_auth }}"
      name: "{{ item.cluster }}"
      data_center: "{{ datacenter_name }}"
      ksm: true
      ballooning: true
      memory_policy: server
    with_items:
       - "{{ nodes }}"
  - name: List host in datacenter
    ovirt_host_info:
      auth: "{{ ovirt_auth }}"
      pattern: "datacenter={{ datacenter_name }}"
    register: host_list
  - set_fact:
      hostnames: []
  - name: List hostname
    set_fact:
      hostnames: "{{ hostnames + [ item.name ] }}"
    with_items:
      - "{{ host_list['ovirt_hosts'] }}"
  - name: Register in RHVM
    ovirt_host:
      state: present
      auth: "{{ ovirt_auth }}"
      name: "{{ item.name }}"
      cluster: "{{ item.cluster }}"
      address: "{{ item.ip }}"
      power_management_enabled: "{{ item.power_management_enabled | default(false) }}"
      # unsupported in rhel yet - to avoid reboot create node via web
      # reboot_after_installation: "{{ item.reboot_after_installation | default(false) }}"
      reboot_after_upgrade: "{{ item.reboot_after_upgrade | default(false) }}"
      public_key: "{{ ssh_public_key }}"
      password: "{{ ssh_root_password }}"
    when: item.name not in hostnames
    with_items:
       - "{{ nodes }}"
  - name: Register Power Management for host
    ovirt_host_pm:
      state: present
      auth: "{{ ovirt_auth }}"
      name: "{{ item.name }}"
      address: "{{ item.pm.address }}"
      username: "{{ item.pm.user }}"
      password: "{{ item.pm.password }}"
      type: "{{ item.pm.type }}"
      options: "{{ item.pm.pm_options | default(omit) }}"
    when: item.pm is defined
    with_items:
       - "{{ nodes }}"
  - name: Create storage domains
    ovirt_storage_domain:
      state: present
      auth: "{{ ovirt_auth }}"
      data_center: "{{ datacenter_name }}"
      name: "{{ item.name }}"
      domain_function: "data"
      host: "{{ item.host }}"
      nfs:
        address: "{{ item.address | default(item.host) }}"
        path: "{{ item.mountpoint }}"
        version: "auto"
    retries: 5
    delay: 2
    with_items:
       - "{{ storage }}"
  - name: Create logical networks
    ovirt_network:
      state: present
      auth: "{{ ovirt_auth }}"
      data_center: "{{ datacenter_name }}"
      name: "{{ datacenter_name }}-{{ item.1.name }}"
      clusters:
      - name: "{{ item.0.cluster }}"
      vlan_tag: "{{ item.1.vlan | default(omit)}}"
      vm_network: true
    with_subelements:
      - "{{ nodes }}"
      - networks
  - name: Create host networks
    ovirt_host_network:
      state: present
      auth: "{{ ovirt_auth }}"
      networks:
      - name: "{{ datacenter_name }}-{{ item.1.name }}"
        boot_protocol: none
      name: "{{ item.0.name }}"
      interface: "{{ item.1.phy_dev }}"
    with_subelements:
      - "{{ nodes }}"
      - networks
  - name: Remove vNICs network_filter
    ovirt.ovirt.ovirt_vnic_profile:
      state: present
      auth: "{{ ovirt_auth }}"
      name: "{{ datacenter_name }}-{{ item.1.name }}"
      network: "{{ datacenter_name }}-{{ item.1.name }}"
      data_center: "{{ datacenter_name }}"
      network_filter: ""
    with_subelements:
      - "{{ nodes }}"
      - networks
  - name: Revoke SSO Token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF
```

## Deploy nodes, networks and storages
```bash
ansible-playbook \
  --extra-vars="@common-env.yaml" \
  --extra-vars="@nodes.yaml" \
  infra.yaml
```

# Prepare images
- Make folder for images
```bash
mkdir ~/images
```

- Download rhel8.4 base image from [RedHat downloads](https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.4/x86_64/product-software) into the ~/images folder



# Create Overcloud VMs

## If Contrail Control plane to be deployed in a Kubernetes cluster prepare image for Contrail Conrollers
```bash
cd
cloud_image=images/rhel-8.4-x86_64-kvm.qcow2
root_password=contrail123
stack_password=contrail123
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 images/overcloud.qcow2 100G
virt-resize --expand /dev/sda3 ${cloud_image} images/overcloud.qcow2
virt-customize  -a overcloud.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --run-command 'useradd stack' \
  --password stack:password:${stack_password} \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --selinux-relabel
```

Note that Kubernetes to be deployed on the nodes separately by any suitable way, e.g.
[Kubespray](https://github.com/kubernetes-sigs/kubespray.git)

Contrail Controllers to be deployed by [TF Operator](https://github.com/tungstenfabric/tf-operator) on top of Kubernetes.


## Prepare VMs definitions
```bash
# Overcloud VMs definitions
# Adjust values to your setup!!!
# For deploying Contrail Control plane in a Kuberentes cluster
# remove contrail controller nodes as they are not managed by RHOSP. They to be created at next steps.
cat << EOF > vms.yaml
---
vms:
  - name: controller-0
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:16:54:d8"
    cluster: node-10-0-10-148
    storage: node-10-0-10-148-overcloud
  - name: contrail-controller-0
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:d6:2b:03"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
    cluster: node-10-0-10-148
    storage: node-10-0-10-148-overcloud
  - name: contrail-controller-1
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:d6:2b:13"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
    cluster: node-10-0-10-149
    storage: node-10-0-10-149-overcloud
  - name: contrail-controller-2
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:d6:2b:23"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
    cluster: node-10-0-10-150
    storage: node-10-0-10-150-overcloud
EOF

# Playbook for overcloud VMs
# !!! Adjustto your setup
cat << EOF > overcloud.yaml
- hosts: localhost
  tasks:
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: Create disks
    ovirt_disk:
      auth: "{{ ovirt_auth }}"
      name: "{{ item.name }}"
      interface: virtio
      size: "{{ item.disk_size_gb }}GiB"
      format: cow
      image_path: "{{ item.image | default(omit) }}"
      storage_domain: "{{ item.storage }}"
    retries: 5
    delay: 2
    with_items:
      - "{{ vms }}"
  - name: Deploy VMs
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: "{{ item.state | default('present') }}"
      cluster: "{{ item.cluster }}"
      name: "{{ item.name }}"
      memory: "{{ item.memory_gb }}GiB"
      cpu_cores: "{{ item.cpu_cores }}"
      type: server
      high_availability: yes
      placement_policy: pinned
      operating_system: rhel_8x64
      disk_format: cow
      graphical_console:
        protocol:
          - spice
          - vnc
      serial_console: yes
      nics: "{{ item.nics | default(omit) }}"
      disks:
        - name: "{{ item.name }}"
          bootable: True
      storage_domain: "{{ item.storage }}"
      cloud_init: "{{ item.cloud_init | default(omit) }}"
      cloud_init_nics: "{{ item.cloud_init_nics | default(omit) }}"
    retries: 5
    delay: 2
    with_items:
      - "{{ vms }}"
  - name: Revoke SSO Token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF

ansible-playbook \
  --extra-vars="@common-env.yaml" \
  --extra-vars="@vms.yaml" \
  overcloud.yaml
```

# Create Contrail Control plane VMs for K8S based deployment
This is for side-by-side deployment where Contrail Control plane is
deployed as separate K8S based cluster.

## Customize VM image for K8S VMs
```bash
cd
cloud_image=images/rhel-8.4-x86_64-kvm.qcow2
root_password=contrail123
stack_password=contrail123
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 images/k8s.qcow2 100G
virt-resize --expand /dev/sda3 ${cloud_image} images/k8s.qcow2
virt-customize  -a k8s.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --password stack:password:${stack_password} \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --selinux-relabel
```

## Define K8S VMs
```bash
# !!! Adjust to your setup (addresses in ctlplane, tenant and mgmt networks)
cat << EOF > k8s-vms.yaml
---
vms:
  - name: contrail-controller-0
    state: running
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:16:54:d8"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
      - name: eth2
        interface: virtio
        profile_name: "ovirtmgmt"
    cluster: node-10-0-10-148
    storage: node-10-0-10-148-overcloud
    image: "images/k8s.qcow2"
    cloud_init:
      # ctlplane network
      host_name: "contrail-controller-0.{{ overcloud_domain }}"
      dns_search: "{{ overcloud_domain }}"
      dns_servers: "{{ ipa_ctlplane_ip }}"
      nic_name: "eth0"
      nic_boot_protocol_v6: none
      nic_boot_protocol: static
      nic_ip_address: "192.168.24.7"
      nic_gateway: "{{ undercloud_ctlplane_ip }}"
      nic_netmask: "255.255.255.0"
    cloud_init_nics:
      # tenant network
      - nic_name: "eth1"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.0.201"
        nic_netmask: "255.255.255.0"
      # mgmt network
      - nic_name: "eth2"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.10.210"
        nic_netmask: "255.255.255.0"
  - name: contrail-controller-1
    state: running
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:d6:2b:03"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
      - name: eth2
        interface: virtio
        profile_name: "ovirtmgmt"
    cluster: node-10-0-10-149
    storage: node-10-0-10-149-overcloud
    image: "images/k8s.qcow2"
    cloud_init:
      host_name: "contrail-controller-1.{{ overcloud_domain }}"
      dns_search: "{{ overcloud_domain }}"
      dns_servers: "{{ ipa_ctlplane_ip }}"
      nic_name: "eth0"
      nic_boot_protocol_v6: none
      nic_boot_protocol: static
      nic_ip_address: "192.168.24.8"
      nic_gateway: "{{ undercloud_ctlplane_ip }}"
      nic_netmask: "255.255.255.0"
    cloud_init_nics:
      - nic_name: "eth1"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.0.202"
        nic_netmask: "255.255.255.0"
      # mgmt network
      - nic_name: "eth2"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.10.211"
        nic_netmask: "255.255.255.0"
  - name: contrail-controller-2
    state: running
    disk_size_gb: 100
    memory_gb: 16
    cpu_cores: 4
    nics:
      - name: eth0
        interface: virtio
        profile_name: "{{ datacenter_name }}-ctlplane"
        mac_address: "52:54:00:d6:2b:23"
      - name: eth1
        interface: virtio
        profile_name: "{{ datacenter_name }}-tenant"
      - name: eth2
        interface: virtio
        profile_name: "ovirtmgmt"
    cluster: node-10-0-10-150
    storage: node-10-0-10-150-overcloud
    image: "images/k8s.qcow2"
    cloud_init:
      host_name: "contrail-controller-1.{{ overcloud_domain }}"
      dns_search: "{{ overcloud_domain }}"
      dns_servers: "{{ ipa_ctlplane_ip }}"
      nic_name: "eth0"
      nic_boot_protocol_v6: none
      nic_boot_protocol: static
      nic_ip_address: "192.168.24.9"
      nic_gateway: "{{ undercloud_ctlplane_ip }}"
      nic_netmask: "255.255.255.0"
    cloud_init_nics:
      - nic_name: "eth1"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.0.203"
        nic_netmask: "255.255.255.0"EOF
      # mgmt network
      - nic_name: "eth2"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "10.0.10.212"
        nic_netmask: "255.255.255.0"
EOF

ansible-playbook \
  --extra-vars="@common-env.yaml" \
  --extra-vars="@k8s-vms.yaml" \
  overcloud.yaml
```

## SSH to K8S nodes and configure VLANs for RHOSP Internal API networks
```bash
# Example

# ssh to a node
ssh stack@192.168.24.7

# !!!Adjust to your setup and repeate for all Contrail Controller nodes
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-vlan710
ONBOOT=yes
BOOTPROTO=static
HOTPLUG=no
NM_CONTROLLED=no
PEERDNS=no
USERCTL=yes
VLAN=yes
DEVICE=vlan710
PHYSDEV=eth0
IPADDR=10.1.0.7
NETMASK=255.255.255.0
EOF
sudo ifup vlan710

# Do same for external vlan if needed
```

# Create Undercloud VM

## Customize VM image for Undercloud VM
```bash
cd
cloud_image=images/rhel-8.4-x86_64-kvm.qcow2
undercloud_name=undercloud
domain_name=dev.clouddomain
root_password=contrail123
stack_password=contrail123
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 images/${undercloud_name}.qcow2 100G
virt-resize --expand /dev/sda3 ${cloud_image} images/${undercloud_name}.qcow2
virt-customize  -a ${undercloud_name}.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --hostname ${undercloud_name}.${domain_name} \
  --run-command 'useradd stack' \
  --password stack:password:${stack_password} \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --selinux-relabel
```

## Define Undercloud VM
```bash
cat << EOF > undercloud.yaml
- hosts: localhost
  tasks:
  - set_fact:
      cluster: "Default"
      storage: "undercloud"
  - name: get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: create disks
    ovirt_disk:
      auth: "{{ ovirt_auth }}"
      name: "{{ undercloud_name }}"
      interface: virtio
      format: cow
      size: 100GiB
      image_path: "images/{{ undercloud_name }}.qcow2"
      storage_domain: "{{ storage }}"
    retries: 5
    delay: 2
  - name: deploy vms
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: running
      cluster: "{{ cluster }}"
      name: "{{ undercloud_name }}"
      memory: 32GiB
      cpu_cores: 8
      type: server
      high_availability: yes
      placement_policy: pinned
      operating_system: rhel_8x64
      cloud_init:
        host_name: "{{ undercloud_name }}.{{ overcloud_domain }}"
        dns_search: "{{ overcloud_domain }}"
        dns_servers: "{{ mgmt_gateway }}"
        nic_name: "eth0"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "{{ undercloud_mgmt_ip }}"
        nic_gateway: "{{ mgmt_gateway }}"
        nic_netmask: "255.255.255.0"
      cloud_init_nics:
        - nic_name: "eth1"
          nic_boot_protocol_v6: none
          nic_boot_protocol: static
          nic_ip_address: "{{ undercloud_ctlplane_ip }}"
          nic_netmask: "255.255.255.0"
      disk_format: cow
      graphical_console:
        protocol:
          - spice
          - vnc
      serial_console: yes
      nics:
       - name: eth0
         interface: virtio
         profile_name: "ovirtmgmt"
       - name: eth1
         interface: virtio
         profile_name: "{{ datacenter_name }}-ctlplane"
      disks:
        - name: "{{ undercloud_name }}"
          bootable: true
      storage_domain: "{{ storage }}"
  - name: revoke SSO token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF

ansible-playbook --extra-vars="@common-env.yaml" undercloud.yaml
```


# Create FreeIPA VM

## Customize VM image for RedHat IDM (FreeIPA) VM
This is for TLS everwhere deployment.
```bash
cd
cloud_image=images/rhel-8.4-x86_64-kvm.qcow2
ipa_name=ipa
domain_name=dev.clouddomain
qemu-img create -f qcow2 images/{ipa_name}.qcow2 100G
virt-resize --expand /dev/sda3 ${cloud_image} images/${ipa_name}.qcow2
virt-customize  -a images/${ipa_name}.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --hostname ${ipa_name}.${domain_name} \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --selinux-relabel
```

## RedHat IDM (FreeIPA) VM
```bash
cat << EOF > ipa.yaml
- hosts: localhost
  tasks:
  - set_fact:
      cluster: "Default"
      storage: "ipa"
  - name: get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: create disks
    ovirt_disk:
      auth: "{{ ovirt_auth }}"
      name: "{{ ipa_name }}"
      interface: virtio
      format: cow
      size: 100GiB
      image_path: "images/{{ ipa_name }}.qcow2"
      storage_domain: "{{ storage }}"
    retries: 5
    delay: 2
  - name: deploy vms
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: running
      cluster: "{{ cluster }}"
      name: "{{ ipa_name }}"
      memory: 4GiB
      cpu_cores: 2
      type: server
      high_availability: yes
      placement_policy: pinned
      operating_system: rhel_8x64
      cloud_init:
        host_name: "{{ ipa_name }}.{{ overcloud_domain }}"
        dns_search: "{{ overcloud_domain }}"
        dns_servers: "{{ mgmt_gateway }}"
        nic_name: "eth0"
        nic_boot_protocol_v6: none
        nic_boot_protocol: static
        nic_ip_address: "{{ ipa_mgmt_ip }}"
        nic_gateway: "{{ mgmt_gateway }}"
        nic_netmask: "255.255.255.0"
      cloud_init_nics:
        - nic_name: "eth1"
          nic_boot_protocol_v6: none
          nic_boot_protocol: static
          nic_ip_address: "{{ ipa_ctlplane_ip }}"
          nic_netmask: "255.255.255.0"
      disk_format: cow
      graphical_console:
        protocol:
          - spice
          - vnc
      serial_console: yes
      nics:
       - name: eth0
         interface: virtio
         profile_name: "ovirtmgmt"
       - name: eth1
         interface: virtio
         profile_name: "{{ datacenter_name }}-ctlplane"
      disks:
        - name: "{{ ipa_name }}"
          bootable: true
      storage_domain: "{{ storage }}"
  - name: revoke SSO token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF

ansible-playbook --extra-vars="@common-env.yaml" ipa.yaml
```


## Access to RHVM via a web browser
RHVM can be accessed only using the engine FQDN or one of the engine alternate FQDNs (eg. https://vmengine.dev.clouddomain).

Make sure, that FQDN can be resolved.


## Access to VMs via serical console
[RedHat documentation](https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4/html/virtual_machine_management_guide/starting_the_virtual_machine)
[oVirt documentation](https://www.ovirt.org/documentation/virtual_machine_management_guide)


# Appendix

## Examples of ansible tasks to operate with RHVM
Based on [ovirt ansible documentation](https://docs.ansible.com/ansible/latest/collections/ovirt/ovirt/index.html)

```bash
# List datacenters
cat << EOF > list_dcs.yaml
- hosts: localhost
  tasks:
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - ovirt.ovirt.ovirt_datacenter_info:
      auth: "{{ ovirt_auth }}"
      pattern: "{{ filter | default('*') }}"
    register: result
  - debug:
      msg: "{{ result.ovirt_datacenters | map(attribute='name') | list }}"
EOF
# list in default data center
ansible-playbook --extra-vars="@common-env.yaml" list_dcs.yaml
ansible-playbook --extra-vars="@common-env.yaml" -e filter='name=Def*' list_dcs.yaml

# List clusters for datacenter
cat << EOF > list_clusters.yaml
- hosts: localhost
  tasks:
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - ovirt.ovirt.ovirt_cluster_info:
      auth: "{{ ovirt_auth }}"
      pattern: "{{ filter | default('*') }}"
    register: result
  - debug:
      msg: "{{ result.ovirt_clusters | map(attribute='name') | list }}"
EOF
ansible-playbook --extra-vars="@common-env.yaml" list_clusters.yaml
ansible-playbook --extra-vars="@common-env.yaml" -e filter='datacenter=Default' list_clusters.yaml

# List hosts
cat << EOF > list_hosts.yaml
- hosts: localhost
  tasks:
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: List host in datacenter
    ovirt_host_info:
      auth: "{{ ovirt_auth }}"
      pattern: "{{ filter | default('*') }}"
    register: host_list
  - debug:
      msg: "{{ host_list['ovirt_hosts'] | map(attribute='name') | list }}"
EOF
ansible-playbook --extra-vars="@common-env.yaml" list_hosts.yaml
ansible-playbook --extra-vars="@common-env.yaml" -e filter='datacenter=Default' list_hosts.yaml
ansible-playbook --extra-vars="@common-env.yaml" -e filter='cluster=Default' list_hosts.yaml

# Remove particular host
cat << EOF > remove_host.yaml
- hosts: localhost
  tasks:
  - debug:
      msg: "host is required"
    failed_when: host is not defined
  - debug:
      msg: "cluster is required"
    failed_when: cluster is not defined
  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: Remove host from RHVM
    ovirt_host:
      state: absent
      auth: "{{ ovirt_auth }}"
      name: "{{ host }}"
      cluster: "{{ cluster }}"
EOF
ansible-playbook --extra-vars="@common-env.yaml" -e host=<host name> -e cluster=<cluster name> remove_host.yaml


```