#!/bin/bash

CONTRAIL_IMAGE_PREFIX=${CONTRAIL_IMAGE_PREFIX:-'contrail-'}
CONTRAIL_NEW_IMAGE_TAG=${CONTRAIL_NEW_IMAGE_TAG:-'latest'}

sudo podman images --format 'table {{.Repository}}:{{.Tag}}' | grep "$CONTRAIL_IMAGE_PREFIX" | sed -e "s/:[^:]\+$/:${CONTRAIL_NEW_IMAGE_TAG}/" | sort -u >/tmp/container_images.list
echo Pulling new container images
for image in $(cat /tmp/container_images.list); do
    sudo podman pull $image
done
