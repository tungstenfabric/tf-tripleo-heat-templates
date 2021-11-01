# Introduction
Currently the following combinations of Operating System/OpenStack/Deployer/Contrail are supported:

| Operating System  | OpenStack         |
| ----------------- | ----------------- |
| RHEL 8.2          | OSP16             |


This kind of deploy is supposed to be 'Spine-Leaf' deploy
[https://access.redhat.com/documentation/en-us/red_hat_openstack_platform/16.2/html-single/spine_leaf_networking/index]

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


## Topology example scheme (w/o spine-leaf details)
### Layer 1
```
+---------------------------------------------------------------+
|      +-------------------------+        K8S/Openshift cluster |
|      | VM CN Controller 3      |                              |
|    +-+-----------------------+ |    +-----------------------+ |
|    | VM CN Controller 2      | |    |  VM 2 Control         | |
|  +-+-----------------------+ | |  +-+---------------------+ | |
|  | VM CN Controller 1      | | |  | VM 1 Control          | | |
|  | +---------------------+ | | |  | +-------------------+ | | |
|  | | Contrail Config     | | | |  | | Contrail Control  | | | |
|  | | Contrail Controller | | | |  | | ( SUBCLUSTER XXX) | | | |
|  | | Contrail Databases  | | | |  | +-------------------+ |-+ |
|  | | Contrail Control    | | |-+  +-----------------------+   |
|  | +---------------------+ |-+                                |
|  +-------------------------+                                  |
+------+--------------+-------------------+-------+-------------+
       |              |                   |       |
+------+--------------+-------------------+-------+--------+
|                                                          |
|                          Network                         |
+------+--------------+-------------------+-------+--------+
       |              |                   |       |
+------+--------------+-------------------+-------+------------------------+
|                                                      Openstack cluster   |
|                        +-----------------+                               |
|                        | VM Controller 3 |                               |
|                      +-+---------------+ |    +------------------------+ |
|                      | VM Controller 2 | |    | VM Compute 2           | |
| +----------------+ +-+---------------+ | |  +-+----------------------+ | |
| | VM Undercloud  | | VM Controller 1 | | |  | VM Compute 1           | | |
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

2. Deploy Contrail Control plane in K8S cluster by tf-operator [https://github.com/tungstenfabric/tf-operator] with at least one worker node(s).
The worker will be used for Contrail Control serving a subcluster (1 for testing, production minimum is 2).
In case of OpenShift for Contrail Control plane check readme [https://github.com/tungstenfabric/tf-openshift].

3. Label worker(s) node with subcluster label:
```
kubectl label node <worker_nodename> subcluster=<subcluster_id>
```

4. Edit manager manifest - add one more control with node nodeselector and Subcluster param

```
kubectl edit manager -n tf
```

Add record to controls:

```yaml
    controls:
    - metadata:
        labels:
          tf_cluster: cluster1
        name: control<subcluster_id>
      spec:
        commonConfiguration:
          nodeSelector:
            subcluster: <subcluster_id>
        serviceConfiguration:
          subcluster: <subcluster_id>
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

# Prepare Openstack managed hosts

1. Prepare Openstack hosts and run undercloud setup as described here [https://github.com/tungstenfabric/tf-tripleo-heat-templates/tree/stable/train#readme]

2. ssh to undercloud node

3. Run script to generate remote computes heat templates
```bash
cd /home/stack/tripleo-heat-templates/tools/contrail
subcluster_ids=0,1,2
./remote_compute.sh $subcluster_ids 
```
This script generate one network_data_rcomp.yaml, and the set of files for each subcluster, e.g.
tripleo-heat-templates/roles/RemoteCompute0.yaml
tripleo-heat-templates/environments/contrail/ips-from-pool-rcomp0.yaml
tripleo-heat-templates/network/config/contrail/compute-nic-config-rcomp0.yaml

4. Add generated role(s) tripleo-heat-templates/roles/RemoteCompute0.yaml into your role file (e.g. roles_data.yaml)

5. Adjust generated files and othere templates to your setup (network CIDRs, routes, etc)

6. Prepare contrail templates with use of generated network data file 
```bash
cd
./tripleo-heat-templates/tools/process-templates.py --clean \
  -r /home/stack/roles_data.yaml  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -p tripleo-heat-templates/

./tripleo-heat-templates/tools/process-templates.py \
  -r /home/stack/roles_data.yaml  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -p tripleo-heat-templates/
```

7. Run overcloud deploy

```bash
openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file /home/stack/roles_data.yaml  -n /home/stack/tripleo-heat-templates/network_data_rcomp.yaml \
  -e overcloud_containers.yaml \
  -e /home/stack/rhsm.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/contrail-net-single.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
  -e misc_opts.yaml \
  -e contrail-parameters.yaml \
  -e containers-prepare-parameter.yaml \
  -e /home/stack/tripleo-heat-templates/environments/contrail/ips-from-pool-rcomp0.yaml
```
(you need to include all ips-from-pool-rcomp0.yaml like files into deploy command)
