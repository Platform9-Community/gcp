#!/bin/bash

CL_NAME=""
source "${PWD}/common.sh"
get_token
check_cluster_exists
if [ -z ${CL_NAME} ]; then
        echo "INFO cluster name is acceptable."
else
        echo "ERROR cluster with the name ${CLUSTER_NAME} already exists on the management plane. Choose a different name."
        exit 1
fi