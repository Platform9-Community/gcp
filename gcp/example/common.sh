#!/bin/bash
# based on sa-internal/release-0.5 branch
#management_plane-vars
readonly AUTH_USER="account@platform9.com"
readonly AUTH_PASS="TypePassword"
readonly REGION="lks"
readonly TENANT="sales-eng"
readonly DU_FQDN="du-name.platform9.net"   # MANAGEMENT PLANE FQDN

##cluster-vars
readonly CLUSTER_NAME="lks-test"
readonly CLUSTER_DNS_NAME="lks-test.account.com"
#CLUSTER_DNS_NAME=""
readonly NUM_WORKER_NODES=3

#gcp_virtual_machines-vars
readonly master_machine_type="e2-medium"
readonly worker_machine_type="n1-highmem-2"
readonly master_network_tags="master"
readonly image="ubuntu-1804-bionic-v20200923"
readonly image_project="ubuntu-os-cloud"
readonly boot_disk_size="40GB"
readonly external_static_ip="35.215.126.240"
readonly network_tier="STANDARD"

##!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!no-edits-required-below-this-line!!!!!!!!!!!!!!!!!!!!!!!!!!!!!##
readonly AUTH_URL="https://${DU_FQDN}"
readonly master="${CLUSTER_NAME}-mstr"
readonly SS=15
readonly LS=30

function workers() {

	num=0
	until [ ${num} -eq ${NUM_WORKER_NODES} ]
	do
		workers[${num}]="${CLUSTER_NAME}-wrkr-${num}"
		echo ${workers[${num}]}
		((num=num+1))
		echo $num
	done
	echo ${workers[@]}

}


function get_token() {
  BASE_URL="https://$DU_FQDN"
  AUTH_REQUEST_PAYLOAD="{
  \"auth\":{
    \"identity\":{
      \"methods\":[
        \"password\"
      ],
      \"password\":{
        \"user\":{
          \"name\":\"$AUTH_USER\",
          \"domain\":{
            \"id\":\"default\"
            },
          \"password\":\"$AUTH_PASS\"
          }
        }
      }
    }
  }"
    # ===== KEYSTONE API CALLS ====== #
  KEYSTONE_URL="$BASE_URL/keystone/v3"

  X_AUTH_TOKEN=$(curl -si \
    -H "Content-Type: application/json" \
    $KEYSTONE_URL/auth/tokens\?nocatalog \
    -d "$AUTH_REQUEST_PAYLOAD" | sed -En 's#^x-subject-token:\s(.*)$#\1#pI' | tr -d "\n\r")
  
  PROJECT_UUID=$(curl -s \
    -H "Content-Type: application/json" \
    -H "X-AUTH-TOKEN: $X_AUTH_TOKEN" \
    $KEYSTONE_URL/auth/projects | jq -r '.projects[] | select(.name == '\"$TENANT\"') | .id')
}

function get_pool_uuid() {
  POOL_UUID=$(curl -X GET "${BASE_URL}/qbert/v3/${PROJECT_UUID}/nodePools" -H "accept: application/json" \
  -H "X-Auth-Token: ${X_AUTH_TOKEN}"|jq -r --arg name "defaultPool" '.[]|if .name == $name then .uuid else empty end')
  echo $POOL_UUID
}

function get_cluster_uuid() {
	cluster_uuid=$(curl -X GET "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters" -H "accept: application/json" -H "X-Auth-Token: ${X_AUTH_TOKEN}"\
	|jq -r --arg name "${CLUSTER_NAME}" '.[]|if .name == $name then .uuid else empty end')
	echo ${cluster_uuid}
}

function get_node_uuid() {
	echo ${node_ip}
	node_uuid=$(curl -X GET "${BASE_URL}/qbert/v3/${PROJECT_UUID}/nodes" -H "accept: application/json" \
	-H "X-Auth-Token: ${X_AUTH_TOKEN}"|jq -r --arg name "${node_ip}" '.[]|if .primaryIp == $name then .uuid else empty end')
	echo "\nNode UUID:${node_uuid}"

}

function check_cluster_exists() {
CL_NAME=$(curl -s -X GET "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters" -H "Content-Type: application/json" \
-H "X-Auth-Token:${X_AUTH_TOKEN}"|jq -r --arg name "${CLUSTER_NAME}" '.[]|if .name == $name then .uuid else empty end')
}

function check_cluster_status() {
CL_STATUS=$(curl -s -X GET "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters/${cluster_uuid}" -H "Content-Type: application/json" \
-H "X-Auth-Token:${X_AUTH_TOKEN}"|jq -r .status)
echo "CLUSTER STATUS:${CL_STATUS}"
}

function cluster_post_json() {
cat <<EOF
{
  "name": "${CLUSTER_NAME}",
  "externalDnsName": "${CLUSTER_DNS_NAME}",
  "containersCidr": "10.20.0.0/16",
  "servicesCidr": "10.21.0.0/16",
  "mtuSize": 1440,
  "privileged": true,
  "appCatalogEnabled": false,
  "nodePoolUuid": "${POOL_UUID}",
  "calicoIpIpMode": "Always",
  "calicoNatOutgoing": true,
  "calicoV4BlockSize": "24",
  "networkPlugin": "calico",
  "runtimeConfig": "api/all=true",
  "etcdBackup": {
    "storageType": "local",
    "isEtcdBackupEnabled": 1,
    "storageProperties": {
      "localPath": "/etc/pf9/etcd-backup"
    },
    "intervalInMins": 1440
  },
  "tags": {
    "pf9-system:monitoring": "true"
  }
}
EOF
}

function node_post_json() {
cat <<EOF
[
	{
  		"uuid": "${node_uuid}",
		 "isMaster": ${type}
	}
]

EOF
}


function create_cluster() {
	#if [ -z ${CLUSTER_DNS_NAME} ]; then
	#	CLUSTER_DNS_NAME=$(gcloud compute instances describe ${master}|grep natIP|awk '{print $2}')
	#fi
	#echo ${CLUSTER_DNS_NAME}
	cluster_uuid_json=$(curl -s -X POST "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters" -H "Content-Type: application/json" \
	-H "X-Auth-Token:${X_AUTH_TOKEN}" -H  "Cookie: X-Auth-Token=${X_AUTH_TOKEN}" -d "$(cluster_post_json)")
	export cluster_uuid=$(echo ${cluster_uuid_json} | jq -r .uuid)
	echo "cluster uuid:" $cluster_uuid
}


function add_master_node() {
	type="true"
	get_cluster_uuid
	#[ -z ${cluster_uuid}] && get_cluster_uuid
	node_ip=$(gcloud compute instances describe ${master}|grep networkIP|awk '{print $2}')
	if [ $? -ne 0 ]; then
		echo "ERROR Could not fetch details for GCP virtual machine ${master}."
		exit 1
	fi
	echo ${node_ip}
    get_node_uuid
    node_post_json
	add_master=$(curl -X POST "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters/${cluster_uuid}/attach" -H "accept: application/json" \
	-H "X-Auth-Token:${X_AUTH_TOKEN}" -H "Content-Type: application/json" -d "$(node_post_json)")
	echo ${add_master}
}


function add_worker_node() {
	type="false"
	get_cluster_uuid
	#[ -z ${cluster_uuid}] && get_cluster_uuid
	workers
	for value in "${workers[@]}"; do
    	echo ${value}
    	node_ip=$(gcloud compute instances describe ${value}|grep networkIP|awk '{print $2}')
    	echo ${node_ip}
    	get_node_uuid
    	node_post_json
    	add_worker=$(curl -X POST "${BASE_URL}/qbert/v3/${PROJECT_UUID}/clusters/${cluster_uuid}/attach" -H "accept: application/json" \
    	-H "X-Auth-Token:${X_AUTH_TOKEN}" -H "Content-Type: application/json" -d "$(node_post_json)")
    	echo ${add_worker}    	
    done  
}

function get_first_kubeconfig() {
	get_cluster_uuid
	CL_STATUS=""
	counter=0
	until [ "${CL_STATUS}" = "pending" ]; do
		check_cluster_status
		sleep 2
		let counter++
		if [ ${counter} -eq 60 ]; then
			echo "ERROR with kubernetes API."
			break
		fi
	done
	counter=40
	# cluster status remains ok.
	until [[ ${CL_STATUS} = "ok" || ${counter} -eq 0 ]] ; do
		sleep ${SS}
		check_cluster_status
		echo "Counter ${counter}"
		if [ ${counter} -eq 0 ]; then
			echo "ERROR downloading the kubeconfig. Cluster API status: ${CL_STATUS}."
			exit 1
		fi
		if [ "${CL_STATUS}" = "ok" ]; then
			echo "SUCCESS. Cluster API Status: ${CL_STATUS}"
		fi
		let counter--
	done

	QBERT_URL="${BASE_URL}/qbert/v3"
	curl -s -o "kubeconfig"\
    -H "Content-Type: application/json" \
    -H "X-AUTH-TOKEN: $X_AUTH_TOKEN" \
    "$QBERT_URL/$PROJECT_UUID/kubeconfig/$cluster_uuid"
    sed -i "s/__INSERT_BEARER_TOKEN_HERE__/${X_AUTH_TOKEN}/" "$PWD/kubeconfig"
    export KUBECONFIG="${PWD}/kubeconfig"
    kubectl config get-contexts
    kubectl get pods -n kube-system
}


function deploy_gke_csi_driver() {
	export GOPATH=${HOME}/gcloud-csi
	mkdir -p ${GOPATH}/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver
	git clone --single-branch --branch release-0.7 https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver  \
	${GOPATH}/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver
	export GCE_PD_SA_DIR=${HOME}
	${GOPATH}/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/deploy-driver.sh --skip-sa-check
	if [ -f ${PWD}/sc.yaml ] ; then
		kubectl apply -f sc.yaml
	fi
}


function set_default_kubeconfig() {
	if [ ! -d ${HOME}/.kube ]; then
		mkdir "${HOME}/.kube"
		cp -p "${PWD}/kubeconfig" "${HOME}/.kube/config"
	elif [ -f ${HOME}/.kube/config ]; then
		cp -pr "${HOME}/.kube/config" "${HOME}/.kube/config-pre"
		cp -p "${PWD}/kubeconfig" "${HOME}/.kube/config"
	fi
	export KUBECONFIG="${HOME}/.kube/config"
	kubectl config rename-context default ${CLUSTER_NAME}
	kubectl config get-contexts
	kubectl get nodes
	kubectl get pods,sc -A	
}