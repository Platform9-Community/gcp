# Tested on MacOS 10.15.4, ubuntu 18.04 and 16.04.
# If the script is run without any specific common.sh file as argument, the script will source common.sh in the directory.
# script can take only one argument as the name of a custom common.sh file. Example file is 'common.sh' in the same directory as this script.
# Example: ./vms.sh common-demo-cl.sh
# Make sure same ecommon.sh file is used with vms.sh and cluster.sh scripts
# Verify in the UI that the VMs proivisoned via vms.sh script are connected to mgmt plane before running cluster.sh. 
#!/bin/bash

if [ ! -f ${HOME}/cloud-sa.json ]; then
  echo "${HOME}/cloud-sa.json not found. Create the file with service account key json and run this script again."
  exit 1
fi

if [ -z $1 ] ; then
  source "${PWD}/common.sh"
elif [ ! -f ${PWD}/$1 ] ; then
  echo " $1 file is not found in the present directory."
  exit 1
else
  source "${PWD}/$1"
fi

# get the type of OS you are running the script from. Script is tested with MacOS 10.5.4 and Ubuntu 18.04 and 16.04
os_type
echo ${os_type}

# get token
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

# check and install kubectl v1.17.9 under /usr/local/bin (for lks 4.5.2). Runs on both Mac and Linux
lks_kubectl

#Download kubeconfig immediately after adding the master node. Works on both Mac and Linux
get_first_kubeconfig

# Install kustomize. Runs on both Mac and Linux
get_kustomize

#install GKE CSI driver for PV provisioning.
deploy_gke_csi_driver_v1.1

# set the kubeconfig file as default kubeconfig
set_default_kubeconfig
