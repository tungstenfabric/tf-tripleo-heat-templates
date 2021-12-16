# Finalyze ISSU

1. Stop issu sync job
```bash
kubectl delete -f issu-jobs/issu-sync-job.yaml
# wait till it deleted
kubectl get pods -n tf -w | grep issu
```

2. Finalize sync
Run sync job
```bash
kubectl apply -f issu-jobs/issu-postsync-job.yaml
```
Check sync job runs normally
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-postsync-job.log
```

3. Finalizy sync ZK data
Run sync job
```bash
kubectl apply -f issu-jobs/issu-post-zk-sync-job.yaml
```
Check sync job runs normally
```bash
cat /var/log/contrail/issu/issu-post-zk-sync-job.log
```

4. Delete pairing of Control nodes between old and new clusters
Run unpair job
```bash
kubectl apply -f issu-jobs/issu-pair-del-job.yaml
```
Wait till job completed and validate log
```bash
kubectl get pods -n tf -w | grep issu
cat /var/log/contrail/issu/issu-pair-del-job.log
....
INFO: operation finished successfully
...
```
Note, there are might be errors in log like
```bash
vnc_api.exceptions.NoIdError: Unknown id: Error: oper 1 url /fqname-to-id body {"fq_name": ["default-domain", "default-project", "ip-fabric", "__default__",
 "overcloud-contrailcontroller-0.dev.localdomain"], "type": "bgp-router"} response Name ['default-domain',
 'default-project',
 'ip-fabric',
 '__default__',
 'overcloud-contrailcontroller-0.dev.localdomain'] not found
```
Ignore these kind of output as it is Ok situation and node is already removed.


5. Start service Device Manager, SChema Transformer and Svc Monitor
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

6. Remove label from issu node and issu-config configmap
```bash
# ajdust to use your node name
kubectl label nodes node1 contrail-issu-
kubectl delete configmap -n tf issu-configmap
```

7. Return to main updae workflow
