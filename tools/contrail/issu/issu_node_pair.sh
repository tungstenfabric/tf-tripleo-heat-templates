#!/bin/bash

set -ex
set -o pipefail

oper=${1}
if [ -z "$oper" ] ; then
    echo "ERROR: operation not provided: add or del"
    exit -1
fi

if [[ -z "$admin_user" || \
      -z "$admin_tenant_name" || \
      -z "$admin_password" || \
      -z "$router_asn" || \
      -z "$issu_ips_list_space" || \
      -z "$issu_control_ips_space" || \
      -z "$issu_api_server_ip" || \
      -z "$old_api_server_ip" || \
      -z "$old_control_servers_list_space" ]] ; then
   echo "ERRPR: check that admin_user, admin_tenant_name, admin_password, router_asn, issu_ips_list_space, issu_control_ips_space, issu_api_server_ip, old_api_server_ip, old_control_servers_list_space are not empty."
   exit -1
fi

for i in $old_control_servers_list_space $issu_control_ips_space ; do
  if [ -z "${node_name[$i]}" ] ; then
    echo "ERROR: node_name array doesnt have map ip=>fqdn for $i"
    exit -1
  fi
done

AUTH_PARAMS="--admin_password $admin_password"
AUTH_PARAMS+=" --admin_tenant_name $admin_tenant_name"
AUTH_PARAMS+=" --admin_user $admin_user"

asn_opts="--router_asn $router_asn"

bgp_auto_mesh_opts=''
if [[ ${bgp_auto_mesh,,} == 'true' ]] ; then
  bgp_auto_mesh_opts="--ibgp_auto_mesh"
fi

old_api_server_port=${old_api_server_port:-'18082'}
issu_api_server_port=${issu_api_server_port:-'8082'}

function provision() {
  local ip=$1
  shift 1
  local name=$1
  shift 1
  local api=$1
  shift 1
  local api_port=$1
  shift 1
  local provision_script=$1
  shift 1
  local opts="$@"
  local ret=0
  python /opt/contrail/utils/${provision_script} \
    --host_name $name \
    --host_ip $ip \
    --api_server_ip $api \
    --api_server_port $api_port \
    --oper $oper \
    --api_server_use_ssl true \
    $AUTH_PARAMS $opts || ret=1
  if [[ "$ret" == '0' || "$oper" == 'del' ]] ; then
    if [[ "$ret" != '0' ]] ; then
      # it is ok if on del operation id is not found
      ret=0
      echo "INFO: ignoring errors for delete operations"
    fi
    echo "INFO: ${provision_script} --host_name $name --oper $oper done successfully"
  else
    echo "ERROR: ${provision_script} --host_name $name --oper $oper failed"
  fi
  return $ret
}

function provision_control() {
  local ip=$1
  local name=$2
  local api=$3
  local port=$4

  provision $ip $name $api $port provision_control.py $asn_opts $bgp_auto_mesh_opts
}

#Pair/unpair control nodes with issu node.
for ip in $old_control_servers_list_space ; do
  provision_control $ip ${node_name[$ip]} $issu_api_server_ip $issu_api_server_port || {
    echo "ERROR: failed to provision old control node $ip in ISSU cluster $issu_api_server_ip"
    exit -1
  }
done

#Pair/unpair issu control nodes in with cluster
for ip in $issu_control_ips_space ; do
  provision_control $ip ${node_name[$ip]} $old_api_server_ip $old_api_server_port || {
    echo "ERROR: failed to provision ISSU control node $ip in old cluster $old_api_server_ip"
    exit -1
  }
done

if [[ "$oper" == 'del' ]] ; then
  # remove from issu node old config, analytics & analytics db nodes registered by issu_sync
  for ip in $old_config_servers_list_space ; do
    provision $ip ${node_name[$ip]} $issu_api_server_ip $issu_api_server_port provision_config_node.py $config_container_id
  done
  for ip in $old_analytics_servers_list_space ; do
    provision $ip ${node_name[$ip]} $issu_api_server_ip $issu_api_server_port provision_analytics_node.py $analytics_container_id
  done
  for ip in $old_analyticsdb_servers_list_space ; do
    provision $ip ${node_name[$ip]} $issu_api_server_ip $issu_api_server_port provision_database_node.py $analyticsdb_container_id
  done
fi

echo "INFO: operation finished successfully"
