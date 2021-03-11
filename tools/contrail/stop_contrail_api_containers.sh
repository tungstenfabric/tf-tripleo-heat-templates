#!/bin/bash

#In OSP16 podman containers are managed by systemctl services. 
#list of services that must be stopped before update procedure
STOP_SERVICES=${STOP_SERVICES:-'contrail_config_api contrail_analytics_api'}


#Detecting services to stop
for service in $STOP_SERVICES; do
    check=$(sudo systemctl -a | cut -d ' ' -f3 | grep -c "$service")
    if [ $check -gt 0 ]; then
       echo Found service $service. Stopping
       sudo systemctl stop $service || true
    fi
done

