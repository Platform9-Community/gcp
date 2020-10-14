#!/bin/bash

if [ ! -f ${HOME}/cloud-sa.json ]; then
  echo "${HOME}/cloud-sa.json not found. Create the file with service account key json and run this script again."
  exit 1
fi

source "${PWD}/common.sh"

get_token
echo $X_AUTH_TOKEN
echo $PROJECT_UUID

# Get defaultPool UUID
get_pool_uuid

# Create BareOS cluster
create_cluster

# Get cluster UUID
get_cluster_uuid

#Add master node
add_master_node

#add_worker_node
add_worker_node

#Download kubeconfig immediately after adding the master node. 
get_first_kubeconfig

#install GKE CSI driver for PV provisioning
deploy_gke_csi_driver

# set the kubeconfig file as default kubeconfig
set_default_kubeconfig
