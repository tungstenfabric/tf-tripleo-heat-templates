Render command example:
(prepare and use own role file where L3MH specific roles for computes are difined,
the below is just an example)

./tripleo-heat-templates/tools/process-templates.py --clean \
  -r /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
  -n network_data_l3mh.yaml \
  -p tripleo-heat-templates/

./tripleo-heat-templates/tools/process-templates.py \
  -r /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
  -n network_data_l3mh.yaml \
  -p tripleo-heat-templates/


Deploy command example:
(L3MH requires to use custom network data file and static IPs 
allocation from pool)

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --stack overcloud --libvirt-type kvm \
  --roles-file /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
  --networks-file tripleo-heat-templates/network_data_l3mh.yaml \
  -e tripleo-heat-templates/environments/rhsm.yaml \
  -e tripleo-heat-templates/environments/network-isolation.yaml \
  -e tripleo-heat-templates/environments/ips-from-pool-l3mh.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-tls.yaml \
  -e tripleo-heat-templates/environments/ssl/tls-everywhere-endpoints-dns.yaml \
  -e tripleo-heat-templates/environments/services/haproxy-public-tls-certmonger.yaml \
  -e tripleo-heat-templates/environments/ssl/enable-internal-tls.yaml \
  -e containers-prepare-parameter.yaml \
  -e rhsm.yaml
