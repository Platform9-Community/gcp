# Tested on MacOS 10.15.4, ubuntu 18.04 and 16.04.
# Verify in the UI that the VMs proivisoned via this script are visible as connected to mgmt plane before running cluster.sh 
#!/bin/bash
set -x

source "${PWD}/common.sh"
cfile="common.sh"

# get the type of OS you are running the script from. Script is tested with MacOS 10.5.4 and Ubuntu 18.04 and 16.04
os_type

# create an array of workers
workers

# Fetch token
get_token

CL_NAME=""
check_cluster_exists
if [ -z ${CL_NAME} ]; then
        echo "INFO cluster name is acceptable."
else
        echo "ERROR cluster with the name ${CLUSTER_NAME} already exists on the management plane. Choose a different name and start again."
        exit 1
fi


#build vms
for value in "${workers[@]}"; do
	echo ${value}
	gcloud beta compute instances create ${value} --machine-type=${worker_machine_type} \
	--image=${image} --image-project=${image_project} --boot-disk-size=${boot_disk_size}
done	


#create master virtual machine instance
if [ -z ${external_static_ip} ]; then
	gcloud beta compute instances create ${master} --machine-type=${master_machine_type} --tags=${master_network_tags} \
	--image=${image} --image-project=${image_project} --boot-disk-size=${boot_disk_size} --network-tier=${network_tier}
else
	gcloud beta compute instances create ${master} --machine-type=${master_machine_type} --tags=${master_network_tags} \
	--image=${image} --image-project=${image_project} --boot-disk-size=${boot_disk_size} --network-tier=${network_tier} --address=${external_static_ip} 
fi

#wait for sufficient time to get ssh service respond on all vms
sleep ${LS}

#scp the files
unset value
for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute scp ${cfile} pf9agent.sh ${value}:/tmp
	if [ $? -ne 0 ]; then
		sleep ${LS}
		gcloud compute scp ${cfile} pf9agent.sh ${value}:/tmp
	fi
done


gcloud compute scp ${cfile} pf9agent.sh ${master}:/tmp
if [ $? -ne 0 ]; then
	sleep ${LS}
	gcloud compute scp ${cfile} pf9agent.sh ${value}:/tmp
fi	


gcloud compute ssh ${master} -- 'cd /tmp && ./pf9agent.sh' &


unset value
for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute ssh ${value} -- 'cd /tmp && ./pf9agent.sh' &
	#gcloud compute ssh ${value} --command "cd /tmp && ./pf9agent.sh ${cfile}" &
done
wait


for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute scp ${value}:/tmp/logfile ./logs/${value}-logfile
done

gcloud compute scp ${master}:/tmp/logfile ./logs/${master}-logfile
