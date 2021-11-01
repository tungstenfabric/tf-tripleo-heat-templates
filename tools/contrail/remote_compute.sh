#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

set -xe

if [[ -z "$1" ]]; then
    echo "Pass comma separated list of subclusters"
    exit 1
fi

declare -a subclusters=($(echo $1 | tr "," " "))
# For each subcluster
export SUBSLUSTERS_COUNT=${#subclusters[@]}
for i in $(seq 1 ${SUBSLUSTERS_COUNT}); do
    export REMOTE_INDEX=$((i-1))
    echo subcluster ${subclusters[${REMOTE_INDEX}]}
    export SUBCLUSTER=${subclusters[${REMOTE_INDEX}]}
    # generate roles
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/RemoteCompute.yaml.j2 > ${my_dir}/../../roles/RemoteCompute${REMOTE_INDEX}.yaml
    # generate compute-nic-config-rcomp.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/compute-nic-config-rcomp.yaml.j2 > ${my_dir}/../../network/config/contrail/compute-nic-config-rcomp${REMOTE_INDEX}.yaml
    # generate ips-from-pool-rcomp.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/ips-from-pool-rcomp.yaml.j2 > ${my_dir}/../../environments/contrail/ips-from-pool-rcomp${REMOTE_INDEX}.yaml
done

# generate network_data_rcomp.yaml
${my_dir}/jinja_render.py 0<${my_dir}/templates/network_data_rcomp.yaml.j2 > ${my_dir}/../../network_data_rcomp.yaml

