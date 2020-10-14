#!/bin/bash
set -x

source "${PWD}/common.sh"

workers
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

#wait for vms to allow ssh
sleep ${LS}

#scp the files
unset value
for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute scp common.sh pf9agent.sh ${value}:/tmp
	if [ $? -ne 0 ]; then
		sleep ${LS}
		gcloud compute scp common.sh pf9agent.sh ${value}:/tmp
	fi
done


gcloud compute scp common.sh pf9agent.sh ${master}:/tmp
if [ $? -ne 0 ]; then
	sleep ${LS}
	gcloud compute scp common.sh pf9agent.sh ${value}:/tmp
fi	


gcloud compute ssh ${master} -- 'cd /tmp && ./pf9agent.sh' &


unset value
for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute ssh ${value} -- 'cd /tmp && ./pf9agent.sh' &
done
wait


for value in "${workers[@]}"; do
	echo ${value}
	gcloud compute scp ${value}:/tmp/logfile ./${value}-logfile
done

gcloud compute scp ${master}:/tmp/logfile ./${master}-logfile
