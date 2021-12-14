Tools for migration contrail control plane from rhosp to openshift

ISSU operations:

1. Stop service Device Manager, SChema Transformer and Svc Monitor
Edit manager's manifest and remove devicemanager, schematransformer
and svcmonitor containers from containers section
```bash
kubectl -n tf edit manager
```
Example of edited config section
```yaml
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
            containers:
            - image: tungstenfabric/contrail-controller-config-api:latest
              name: api
            - image: tungstenfabric/contrail-controller-config-dnsmasq:latest
              name: dnsmasq
            - image: tungstenfabric/contrail-nodemgr:latest
              name: nodemanager
            - image: tungstenfabric/contrail-node-init:latest
              name: nodeinit
            - image: tungstenfabric/contrail-provisioner:latest
              name: provisioner
```
Ensure config pod is restarted and removed containers are not present in containers section
```bash
kubectl get pods -n tf config1-config-statefulset-0 -o yaml
```

2. choose one master node to run ISSU scripts and label it
```bash
# ajdust to use your node name
kubectl label nodes node1 contrail-issu=""
```

3. Collect data from operator environment, e.g.
```bash
kubectl -n tf exec -it config1-config-statefulset-0 \
  -c api -- bash -c 'cat /etc/contrailconfigmaps/api.0.$POD_IP'
```

4. Prepare issu configmap
```bash
mkdir -p issu-configmap
cp tf-tripleo-heat-templates/tools/contrail/issu/issu.* \
  tf-tripleo-heat-templates/tools/contrail/issu/*.sh \
  issu-configmap/
```

5. Modify issu.env file according your environment and create configmap
```bash
kubectl create configmap -n tf issu-configmap \
  --from-file=issu.env=issu-configmap/issu.env \
  --from-file=issu.conf=issu-configmap/issu.conf \
  --from-file=issu_node_pair.sh=issu-configmap/issu_node_pair.sh
```

6. Prepare jobs
```bash
sudo mkdir -p /var/log/contrail/issu
mkdir -p issu-jobs
cp tf-tripleo-heat-templates/tools/contrail/issu/*.yaml \
  issu-jobs/
```
Adjust yaml files if customiations needed for your setups
IMPORTANT: modify images to use already pulled images on K8S nodes, because
ISSU jobs doesn pull images and relies on images used for deploy K8S cluster.

7. Pair Control nodes between old and new clusters
Run pair job
```bash
kubectl apply -f issu-jobs/issu-pair-add-job.yaml
```
Wait till job completed and validate log
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-pair-add-job.log
....
INFO: provision_control.py --host_name node-10-100-0-147.localdomain ... exit with code 0
```

8. Presync data to new clsuter
Run presync job
```bash
kubectl apply -f issu-jobs/issu-presync-job.yaml
```
Wait till job completed and validate log
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-presync-job.log
...
Done syncing Configdb uuid
Done syncing bgp keyspace
Done syncing useragent keyspace
Done syncing svc-monitor keyspace
Done syncing dm keyspace
```

9. Run sync data between clusters
- Run sync job
```bash
kubectl apply -f issu-jobs/issu-sync-job.yaml
```
- Check sync job runs normally
```bash
cat /var/log/contrail/issu/issu-sync-job.log
...
Config Sync initiated...
Config Sync done...
Started runtime sync...
Start Compute upgrade...
```
- !!! Important: At this point switch to main istruction and follow RHOSP udpate/upgrade procedure 

10. Stop issu sync job
```bash
kubectl delete -f issu-jobs/issu-sync-job.yaml
# wait till it deleted
kubectl get pods -n tf -w | grep issu
```

11. Finalyze sync
Run sync job
```bash
kubectl apply -f issu-jobs/issu-postsync-job.yaml
```
Check sync job runs normally
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-postsync-job.log
```

12. Finalizy sync ZK data
Run sync job
```bash
kubectl apply -f issu-jobs/issu-post-zk-sync-job.yaml
```
Check sync job runs normally
```bash
cat /var/log/contrail/issu/issu-post-zk-sync-job.log
```

13. Delete pairing of Control nodes between old and new clusters
Run unpair job
```bash
kubectl apply -f issu-jobs/issu-pair-del-job.yaml
```
Wait till job completed and validate log
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-pair-del-job.log
...
```
Note, there are might be errors like
```bash
vnc_api.exceptions.NoIdError: Unknown id: Error: oper 1 url /fqname-to-id body {"fq_name": ["default-domain", "default-project", "ip-fabric", "__default__",
 "overcloud-contrailcontroller-0.dev.localdomain"], "type": "bgp-router"} response Name ['default-domain',
 'default-project',
 'ip-fabric',
 '__default__',
 'overcloud-contrailcontroller-0.dev.localdomain'] not found
++ echo 'provision_control.py --host_name overcloud-contrailcontroller-0.dev.localdomain ... exit with code 1'
```
Ignore these kind of output as it is Ok situation and node is already removed.


14. Start service Device Manager, SChema Transformer and Svc Monitor
Edit manager's manifest and add devicemanager, schematransformer
and svcmonitor containers into containers section (they were removed at #1)
```bash
kubectl -n tf edit manager
```
Example of edited config section
```yaml
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
            containers:
            - image: tungstenfabric/contrail-controller-config-devicemgr:latest
              name: devicemanager
            - image: tungstenfabric/contrail-controller-config-schema:latest
              name: schematransformer
            - image: tungstenfabric/contrail-controller-config-svcmonitor:latest
              name: servicemonitor
            - image: tungstenfabric/contrail-controller-config-api:latest
              name: api
            - image: tungstenfabric/contrail-controller-config-dnsmasq:latest
              name: dnsmasq
            - image: tungstenfabric/contrail-nodemgr:latest
              name: nodemanager
            - image: tungstenfabric/contrail-node-init:latest
              name: nodeinit
            - image: tungstenfabric/contrail-provisioner:latest
              name: provisioner
```
Ensure config pod is restarted and removed containers are not present in containers section
```bash
kubectl get pods -n tf config1-config-statefulset-0 -o yaml
```

15. Remove label from issu node
```bash
# ajdust to use your node name
kubectl label nodes node1 contrail-issu=
```
