#!/bin/bash -e

which greadlink >/dev/null 2>&1 && rlink='greadlink' || rlink='readlink'

my_file="$($rlink -e "$0")"
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
    export REMOTE_INDEX=$((i))
    echo subcluster ${subclusters[$((REMOTE_INDEX-1))]}
    export SUBCLUSTER=${subclusters[$((REMOTE_INDEX-1))]}
    # generate roles
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/RemoteCompute.yaml.j2 > ${my_dir}/../../roles/RemoteCompute${REMOTE_INDEX}.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/RemoteContrailDpdk.yaml.j2 > ${my_dir}/../../roles/RemoteContrailDpdk${REMOTE_INDEX}.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/RemoteContrailSriov.yaml.j2 > ${my_dir}/../../roles/RemoteContrailSriov${REMOTE_INDEX}.yaml
    # generate compute-nic-config-rcomp.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/compute-nic-config-rcomp.yaml.j2 > ${my_dir}/../../network/config/contrail/compute-nic-config-rcomp${REMOTE_INDEX}.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/contrail-dpdk-nic-config-rcomp.yaml.j2 > ${my_dir}/../../network/config/contrail/contrail-dpdk-nic-config-rcomp${REMOTE_INDEX}.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/contrail-sriov-nic-config-rcomp.yaml.j2 > ${my_dir}/../../network/config/contrail/contrail-sriov-nic-config-rcomp${REMOTE_INDEX}.yaml
    # generate rcomp-env.yaml
    ${my_dir}/jinja_render.py 0<${my_dir}/templates/rcomp-env.yaml.j2 > ${my_dir}/../../environments/contrail/rcomp${REMOTE_INDEX}-env.yaml
done

# generate network_data_rcomp.yaml
${my_dir}/jinja_render.py 0<${my_dir}/templates/network_data_rcomp.yaml.j2 > ${my_dir}/../../network_data_rcomp.yaml

echo Completed