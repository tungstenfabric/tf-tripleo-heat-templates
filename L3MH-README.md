Render command example:

./tripleo-heat-templates/tools/process-templates.py --clean \
  -r /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
  -n network_data_l3mh.yaml \
  -p tripleo-heat-templates/

./tripleo-heat-templates/tools/process-templates.py \
  -r /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
  -n network_data_l3mh.yaml \
  -p tripleo-heat-templates/



Deploy command example:

openstack overcloud deploy --templates tripleo-heat-templates/ \
   --stack overcloud --libvirt-type kvm \
   --roles-file /home/cloud-user/tripleo-heat-templates/roles/ContrailAioL3mh.yaml \
   --networks-file tripleo-heat-templates/network_data_l3mh.yaml \
   --disable-validations --deployed-server --overcloud-ssh-user cloud-user --overcloud-ssh-key .ssh/id_rsa \
   -e overcloud_containers.yaml \
   -e tripleo-heat-templates/environments/deployed-server-environment.yaml \
   -e ctlplane-assignments.yaml \
   -e hostname-map.yaml \
   -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
   -e tripleo-heat-templates/environments/ips-from-pool-l3mh.yaml \
   -e tripleo-heat-templates/environments/contrail/contrail-net-l3mh.yaml \
   -e tripleo-heat-templates/environments/contrail/contrail-plugins.yaml \
   -e tripleo-heat-templates/environments/contrail/endpoints-public-dns.yaml \
   -e misc_opts.yaml \
   -e contrail-parameters.yaml \
   -e containers-prepare-parameter.yaml

