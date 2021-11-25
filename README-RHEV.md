# Introduction
Currently the following combinations of Operating System/OpenStack/Deployer/Contrail are supported:

| Operating System  | OpenStack         | Deployer              | Contrail               |
| ----------------- | ----------------- | --------------------- | ---------------------- |
| RHEL 8.4          | OSP16             | OSPd16                | Contrail 21.4          |




## Control plane RHVH host preparation (RHVH 1-3)

### on all RHVH hosts

The control plane RHVH hosts will host the control plane VMs. Each RHVH host
will need virtual switches and the virtual machine definitions. The tasks
described must be done on each of the three hosts.
NIC 1 - 3 have to be substituded with real NIC names.


### Install basic packages
```bash
subscription-manager repos --enable=rhv-4-mgmt-agent-for-rhel-8-x86_64-rpms
subscription-manager repos --enable=advanced-virt-for-rhel-8-x86_64-rpms
yum module enable virt:av
subscription-manager repos --enable=fast-datapath-for-rhel-8-x86_64-rpms


yum install -y libguestfs \
      libvirt \
      libvirt-client \
      libvirt-daemon \
      tmux \
      nfs-utils \
      ovirt-hosted-engine-setup
```

(refer to https://access.redhat.com/documentation/en-us/red_hat_virtualization/4.4/html/installing_red_hat_virtualization_as_a_standalone_manager_with_local_databases/installing_the_red_hat_virtualization_manager_sm_localdb_deploy)

### Start libvirtd & NFS server
```bash
systemctl start libvirtd
systemctl start nfs-server
systemctl start rpcbind
```

### Create storage mountpoints
```bash
for dir in engine undercloud
do
    mkdir -p /storage/$dir
    chmod 0777 /storage/$dir
done

cat > /etc/exports <<< EOF
/storage/engine *(rw)
EOF

exportfs -arv

systemctl restart rpcbind
systemctl restart nfs-server

```

### Deploy RHVM

#### Asume following while deploing RHVM

Engine hostname is vmengine.rhv

Manager hostname is manage.rhv

admin password qwe123QWE


Make sure, that FQDNs can be resolved by DNS or /etc/hosts

```bash
hosted-engine --deploy
```

### Add hosts, configure storage and networks
```bash
cat << EOF > hosts.yaml
- hosts: localhost
  tasks:
  - name: set facts
    set_fact:
      ovirt_hostname: vmengine.rhv
      ovirt_user: "admin@internal"
      ovirt_password: "qwe123QWE"
      cluster_name: Default
      datacenter_name: Default
      nodes:
        - name: manage.rhv
          ip: 192.168.122.53
          networks:
            - name: tenant
              phy_dev: eth0
              # keep vlan for the network same across all nodes
              vlan: 700
            - name: ctlplane
              vlan: 720
              phy_dev: eth0
          pm:
            pm_addr: 192.168.122.1
            pm_port: 6230
            pm_user: ipmi
            pm_password: qwe123QWE
            pm_type: ipmilan
            pm_options:
              ipmilanplus: true
      storage:
        - name: local_storage
          mountpoint: "/storage/undercloud"
      hostnames: []

  - name: Get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: Create datacenter
    ovirt_datacenter:
      auth: "{{ ovirt_auth }}"
      name: "{{ datacenter_name }}"
      local: true
  - name: Create cluster
    ovirt_cluster:
      auth: "{{ ovirt_auth }}"
      name: "{{ cluster_name }}"
      data_center: "{{ datacenter_name }}"
      description: "{{ cluster_name }} cluster"
      ksm: true
      ballooning: true
      memory_policy: server
  - name: List host in datacenter
    ovirt_host_info:
      auth: "{{ ovirt_auth }}"
      pattern: "datacenter={{ datacenter_name }}"
    register: host_list
  - name: List hostname
    set_fact:
      hostnames: "{{ hostnames + [ item.name ] }}"
    with_items:
      - "{{ host_list['ovirt_hosts'] }}"
  - name: Register in RHVM
    ovirt_host:
      auth: "{{ ovirt_auth }}"
      name: "{{ item.name }}"
      cluster: "{{ cluster_name }}"
      address: "{{ item.ip }}"
      power_management_enabled: false
      public_key: true
    when: item.name not in hostnames
    with_items:
       - "{{ nodes }}"
  - name: Register Power Management for host
    ovirt_host_pm:
      auth: "{{ ovirt_auth }}"
      name: "{{ item.name }}"
      address: "{{ item.pm.pm_addr }}"
      username: "{{ item.pm.pm_user }}"
      password: "{{ item.pm.pm_password }}"
      type: "{{ item.pm.pm_type }}"
      #options: "{{ item.pm.pm_options }}"
    with_items:
       - "{{ nodes }}"
  - name: Create storage domains
    ovirt_storage_domain:
      auth: "{{ ovirt_auth }}"
      name: "{{ datacenter_name }}-{{ item.name }}"
      host: "{{ nodes[0].name }}"
      data_center: "{{ datacenter_name }}"
      localfs:
        path: "{{ item.mountpoint }}"
    register: storage_domain
    retries: 10
    delay: 10
    until: storage_domain is succeeded
    with_items:
       - "{{ storage }}"
  - name: Create logical networks
    ovirt_network:
      auth: "{{ ovirt_auth }}"
      data_center: "{{ datacenter_name }}"
      name: "{{ datacenter_name }}-{{ item.1.name }}"
      clusters:
      - name: "{{ cluster_name }}"
      vlan_tag: "{{ item.1.vlan | default(omit)}}"
      vm_network: true
    with_subelements:
      - "{{ nodes }}"
      - networks
  - name: Create host networks
    ovirt_host_network:
      auth: "{{ ovirt_auth }}"
      state: present
      networks:
      - name: "{{ datacenter_name }}-{{ item.1.name }}"
        boot_protocol: none
      name: "{{ item.0.name }}"
      interface: "{{ item.1.phy_dev }}"
    with_subelements:
      - "{{ nodes }}"
      - networks
  - name: Revoke SSO Token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF
ansible-playbook hosts.yaml
```

### setup vm templates
```bash
cat << EOF > vms.yaml
- hosts: localhost
  tasks:
  - name: set vm fact dc_name
    set_fact:
      datacenter_name: Default
      ovirt_hostname: vmengine.rhv
      ovirt_user: "admin@internal"
      ovirt_password: "qwe123QWE"
      cluster_name: Default
  - name: set vm facts
    set_fact:
      vms:
        - name: compute-1
          disk_size_gb: 10
          memory_gb: 1
          cpu_cores: 2
          cpu_sockets: 2
          cpu_shares: 1024
          nics:
            - name: nic1
              profile_name: "{{ datacenter_name }}-ctlplane"
            - name: nic2
              profile_name: "{{ datacenter_name }}-tenant"
        - name: compute-2
          disk_size_gb: 100
          memory_gb: 2
          cpu_cores: 2
          cpu_sockets: 2
          cpu_shares: 1024
          nics:
            - name: nic1
              profile_name: "{{ datacenter_name }}-ctlplane"
            - name: nic2
              profile_name: "{{ datacenter_name }}-tenant"
        - name: contrail-controller
          disk_size_gb: 100
          memory_gb: 2
          cpu_cores: 2
          cpu_sockets: 2
          cpu_shares: 1024
          nics:
            - name: nic1
              profile_name: "{{ datacenter_name }}-ctlplane"
            - name: nic2
              profile_name: "{{ datacenter_name }}-tenant"
        - name: control
          disk_size_gb: 100
          memory_gb: 2
          cpu_cores: 2
          cpu_sockets: 2
          cpu_shares: 1024
          nics:
            - name: nic1
              profile_name: "{{ datacenter_name }}-ctlplane"
            - name: nic2
              profile_name: "{{ datacenter_name }}-tenant"
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
      # local_storage is a storage name deployed earlier
      storage_domain: "{{ datacenter_name }}-local_storage"
    with_items:
      - "{{ vms }}"
  - name: Deploy VMs
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: present
      cluster: "{{ cluster_name }}"
      name: "{{ item.name }}"
      memory: "{{ item.memory_gb }}GiB"
      cpu_cores: "{{ item.cpu_cores }}"
      cpu_sockets: "{{ item.cpu_sockets }}"
      cpu_shares: "{{ item.cpu_shares }}"
      type: server
      operating_system: rhel_8x64
      state: running
      disks:
        - name: "{{ item.name }}"
          bootable: True
      nics: "{{ item.nics }}"
    with_items:
      - "{{ vms }}"
  - name: Revoke SSO Token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF
ansible-playbook vms.yaml
```

## create undercloud VM on KVM host hosting the undercloud
### RHEL 8.4

```bash
mkdir ~/images
```
Download rhel-8.4-x86_64-kvm.qcow2 from RedHat portal to ~/images
```bash
cloud_image=~/images/rhel-8.4-x86_64-kvm.qcow2
```

## customize the undercloud VM image
```bash
undercloud_name=undercloud
undercloud_suffix=local
root_password=contrail123
stack_password=contrail123
export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 /var/lib/libvirt/images/${undercloud_name}.qcow2 11G
virt-resize --expand /dev/sda3 ${cloud_image} /var/lib/libvirt/images/${undercloud_name}.qcow2
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

## define undercloud VM
```bash
cat << EOF > undercloud.yaml
- hosts: localhost
  tasks:
  - name: set facts
    set_fact:
      ovirt_hostname: vmengine.rhv
      ovirt_user: "admin@internal"
      ovirt_password: "qwe123QWE"
      cluster_name: Default
      datacenter_name: Default
      undercloud_name: "undercloud"
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
      size: 11GiB
      image_path: "/var/lib/libvirt/images/{{ undercloud_name }}.qcow2"
      # local_storage is a storage name deployed earlier
      storage_domain: "{{ datacenter_name }}-local_storage"
  - name: deploy vms
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: present
      cluster: "{{ cluster_name }}"
      name: "{{ undercloud_name }}"
      memory: 2GiB
      cpu_cores: 4
      cpu_sockets: 1
      type: server
      operating_system: rhel_8x64
      state: running
      disks:
        - name: "{{ undercloud_name }}"
          bootable: true
      nics:
       - name: nic1
         interface: virtio
         profile_name: "ovirtmgmt"
       - name: nic2
         interface: virtio
         profile_name: "{{ datacenter_name }}-ctlplane"
      serial_console: yes
  - name: revoke SSO token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF
ansible-playbook undercloud.yaml
```

## for TLS with RedHat IDM (FreeIPA)
### cusomize the idm VM image
```bash
freeipa_name=freeipa
qemu-img create -f qcow2 /var/lib/libvirt/images/${freeipa_name}.qcow2 11G
virt-resize --expand /dev/sda3 ${cloud_image} /var/lib/libvirt/images/${freeipa_name}.qcow2
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
cat << EOF > idm.yaml
- hosts: localhost
  tasks:
  - name: set facts
    set_fact:
      ovirt_hostname: vmengine.rhv
      ovirt_user: "admin@internal"
      ovirt_password: "qwe123QWE"
      cluster_name: Default
      datacenter_name: Default
      freeipa_name: freeipa
  - name: get RHVM token
    ovirt_auth:
      url: "https://{{ ovirt_hostname }}/ovirt-engine/api"
      username: "{{ ovirt_user }}"
      password: "{{ ovirt_password }}"
      insecure: true
  - name: create disks
    ovirt_disk:
      auth: "{{ ovirt_auth }}"
      name: "{{ freeipa_name }}"
      interface: virtio
      format: cow
      size: 11GiB
      image_path: "/var/lib/libvirt/images/{{ freeipa_name }}.qcow2"
      # local_storage is a storage name deployed earlier
      storage_domain: "{{ datacenter_name }}-local_storage"
  - name: deploy vms
    ovirt.ovirt.ovirt_vm:
      auth: "{{ ovirt_auth }}"
      state: present
      cluster: "{{ cluster_name }}"
      name: "{{ freeipa_name }}"
      memory: 4GiB
      cpu_cores: 2
      cpu_sockets: 2
      type: server
      operating_system: rhel_8x64
      state: running
      disks:
        - name: "{{ freeipa_name }}"
          bootable: true
      nics:
       - name: nic1
         interface: virtio
         profile_name: "ovirtmgmt"
       - name: nic2
         interface: virtio
         profile_name: "{{ datacenter_name }}-ctlplane"
      serial_console: yes
  - name: revoke SSO token
    ovirt_auth:
      state: absent
      ovirt_auth: "{{ ovirt_auth }}"
EOF
ansible-playbook idm.yaml
```

### Access to RHVM via a web browser

RHVM can be accessed only using the engine FQDN or one of the engine alternate FQDNs (eg. https://vmengine.rhv).

Make sure, that FQDN can be resolved.

