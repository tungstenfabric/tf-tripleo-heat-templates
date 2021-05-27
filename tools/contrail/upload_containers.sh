#!/bin/bash
function show_help {
  echo ""
  echo ""
  echo "Usage:"
  echo "./upload_container.sh -r remote_registry -t tag [-u username] [-p password]"
  echo ""
  echo "Examples:"
  echo "Pull from password protectet public registry:"
  echo "./upload_container.sh -r hub.juniper.net/contrail -t 123 -u USERNAME -p PASSWORD -t 1234"
  echo ""
}

getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "I’m sorry, `getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=r:t:u:p:h
LONGOPTIONS=remote:,tag:,username:,password:,help

# -temporarily store output to be able to check for errors
# -e.g. use “--options” parameter by name to activate quoting/enhanced mode
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # e.g. $? == 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

tag='latest'

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--remote)
            remote_registry="$2"
            shift 2
            ;;
        -t|--tag)
            tag="$2"
            shift 2
            ;;
        -u|--username)
            user="$2"
            shift 2
            ;;
        -p|--password)
            password="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

# handle non-option arguments
#if [[ $# -ne 1 ]]; then
#    echo "$0: A single input file is required."
#    exit 4
#fi

is_5_0=$(echo "$tag" | grep -c '5\.0')

if [[ $is_5_0 == 1 ]] ; then
  topology_name='contrail-analytics-topology'
else
  topology_name='contrail-analytics-snmp-topology'
fi

function is_less_than() {
  local tag=$1
  local val=$2
  awk -v val="$val" '{
  n = split($0, arr, "-");
  for (i = 0; ++i <= n;){
      k = split(arr[i], arr_inner, ".");
      for (j=0; ++j <= k;){
        if(match(arr_inner[j], /^[0-9]{4,}$/) && arr_inner[j] < val){
          print 1;
          exit 0;
        }
        if(match(arr_inner[j], /^r[0-9]{4}$/) && substr(arr_inner[j], 2) < val){
            print 1;
            exit 0;
        }
      }
  };
  print 0;
}' <<< $tag
}

# check if not 5.x
is_5_x=$(awk '{
  n = split($0, arr, "-");
  for (i = 0; ++i <= n;){
    if(match(arr[i], /^5\.[0-2]{1,}/)){
      print 1;
      exit 0;
    }
  };
  print 0;
}' <<< $tag)

if [[ "$is_5_x" == 1 ]] ; then
  stunnel=''
else
  stunnel='contrail-external-stunnel'
fi

# Check if tag contains numbers less than 2002
is_less_2002=$(is_less_than $tag 2002)
# Check if tag contains numbers less than 2008
is_less_2008=$(is_less_than $tag 2008)

provisioner=""
# if tag is latest or contrail version >= 2002 add provisioner container
if [[ "$is_5_x" == 0 ]] && [[ "$is_less_2002" == 0 || "$tag" =~ "latest" || "$tag" =~ "master" || "$tag" =~ "dev" ]]; then
  provisioner="contrail-provisioner"
fi

contrail_tools=""
# if tag is latest or contrail version >= 2008 add contrail-tools container
if [[ "$is_5_x" == 0 ]] && [[ "$is_less_2008" == 0 || "$tag" =~ "latest" || "$tag" =~ "master" || "$tag" =~ "dev" ]]; then
  contrail_tools="contrail-tools"
fi

if [[ -n "${user}" && -n "${password}" ]]; then
  echo "login to remote registry: $remote_registry"
  sudo podman login -u ${user} -p ${password} ${remote_registry}
fi

for image in \
contrail-analytics-alarm-gen \
contrail-analytics-api \
contrail-analytics-collector \
contrail-analytics-query-engine \
contrail-analytics-snmp-collector \
${topology_name} \
contrail-external-cassandra \
contrail-controller-config-api \
contrail-controller-config-devicemgr \
contrail-controller-config-schema \
contrail-controller-config-svcmonitor \
contrail-controller-control-control \
contrail-controller-control-dns \
contrail-controller-control-named \
contrail-openstack-heat-init \
contrail-external-kafka \
contrail-openstack-neutron-init \
contrail-node-init \
contrail-nodemgr \
contrail-openstack-compute-init \
contrail-external-rabbitmq \
contrail-external-redis \
contrail-status \
contrail-vrouter-agent \
contrail-vrouter-agent-dpdk \
contrail-vrouter-agent \
contrail-vrouter-kernel-init-dpdk \
contrail-vrouter-kernel-init \
contrail-controller-webui-job \
contrail-controller-webui-web \
contrail-external-zookeeper \
contrail-kubernetes-cni-init \
contrail-kubernetes-kube-manager \
contrail-controller-config-dnsmasq \
${stunnel} \
${provisioner} \
${contrail_tools}
do
  container="${remote_registry}/${image}:${tag}"
  echo "pull $container"
  sudo podman pull $container
  echo "push local $container"
  sudo openstack tripleo container image push --local $container
done
