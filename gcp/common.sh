#!/bin/bash
#management_plane-vars
readonly AUTH_USER="lks@platform9.com"
readonly AUTH_PASS="F%r4Et*="
readonly REGION="pmk45"
readonly TENANT="lks"
readonly DU_FQDN="se-surendra-45.platform9.horse"   # MANAGEMENT PLANE FQDN

##cluster-vars
readonly CLUSTER_NAME="lks-test"
readonly CLUSTER_DNS_NAME="lks-test.platform9.horse"
#CLUSTER_DNS_NAME=""
readonly NUM_WORKER_NODES=1

#gcp_virtual_machines-vars
readonly master_machine_type="e2-medium"
readonly worker_machine_type="e2-standard-2"
readonly master_network_tags="master"
readonly image="ubuntu-1804-bionic-v20201014"
readonly image_project="ubuntu-os-cloud"
readonly boot_disk_size="10GB"
readonly external_static_ip="35.215.126.240"
readonly network_tier="STANDARD"

##!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!no-edits-required-below-this-line!!!!!!!!!!!!!!!!!!!!!!!!!!!!!##
readonly AUTH_URL="https://${DU_FQDN}"
readonly master="${CLUSTER_NAME}-mstr"
readonly kubectl="/tmp/kubectl"
readonly kustomize="/tmp/kustomize"
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

function os_type() {
	if [[  $(/usr/bin/sw_vers -productName|grep Mac) ]]; then
		os_type="mac"
	elif [[ $(/usr/bin/lsb_release -d|grep Ubuntu) ]]; then
		os_type="ubuntu"
	else
		os_type=""
	fi
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
      },
     \"scope\":{
       \"project\":{
         \"name\":\"${TENANT}\",
         \"domain\":{
           \"id\":\"default\"
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
    -d "$AUTH_REQUEST_PAYLOAD" | grep -i ^X-Subject-Token: | cut -f2 -d':' | tr -d '\r' | tr -d ' ')
  
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
    if [[ ${os_type} == "mac" ]]; then
    	sed -i '' "s/__INSERT_BEARER_TOKEN_HERE__/${X_AUTH_TOKEN}/" "$PWD/kubeconfig"
    else
    	sed -i "s/__INSERT_BEARER_TOKEN_HERE__/${X_AUTH_TOKEN}/" "$PWD/kubeconfig"
    fi
    export KUBECONFIG="${PWD}/kubeconfig"
    ${kubectl} config get-contexts
    ${kubectl} get pods -n kube-system
}

function install_kustomize() {
	${PWD}/install_kustomize.sh 3.8.6
	mv ${PWD}/kustomize /tmp
	${kustomize} version
}

function get_kustomize() {
#	if [[ ${os_type} == "mac" ]]; then
		if [ ! -f ${kustomize} ]; then
			install_kustomize
		elif [[ $(${kustomize} version|awk -F/ '{print $2}'|cut -c -6) != "v3.8.6" ]]; then
			install_kustomize
		else
			echo "Kustomize is already at the required version."
			${kustomize} version
		fi
#   elif [[ ${os_type} == "ubuntu" ]]; then
#		echo "Skipping kustomize installation on Linux. It will be installed via CSI driver script."
#	fi
}

function install_kubectl() {
	if [[ ${os_type} == "mac" ]]; then
		curl -LO "https://storage.googleapis.com/kubernetes-release/release/v1.17.9/bin/darwin/amd64/kubectl"
	elif [[ ${os_type} == "ubuntu" ]]; then
		curl -LO "https://storage.googleapis.com/kubernetes-release/release/v1.17.9/bin/linux/amd64/kubectl"
	fi
	chmod a+x kubectl
	mv kubectl /tmp
}

function lks_kubectl() {
	if [ -f ${kubectl} ]; then
		ver=$(${kubectl} version --client|awk -F: '{print $5}'|awk -F, '{print $1}'|head -1)
		if [[ ${ver} != "\"v1.17.9\"" ]]; then
			echo $ver
			rm ${kubectl}
			echo "Downloading and installing kubectl v1.17.9"
			install_kubectl
		fi	
	else
		echo "Downloading and installing kubectl v1.17.9"
		install_kubectl
	fi	
}

function deploy_gke_csi_driver_v1.1() {
	export GOPATH=${PWD}/csi-1.1
	export GCE_PD_SA_DIR=${HOME} 
    ${GOPATH}/src/sigs.k8s.io/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/deploy-driver.sh --skip-sa-check
	if [ -f ${PWD}/sc.yaml ] ; then
		${kubectl} apply -f sc.yaml
	fi
}


function set_default_kubeconfig() {
	if [ ! -d ${HOME}/.kube ]; then
		mkdir "${HOME}/.kube"
		cp -p "${PWD}/kubeconfig" "${HOME}/.kube/config"
	elif [ -f ${HOME}/.kube/config ]; then
		if [ -f ${HOME}/.kube/config-pre ]; then
			cp -p "${HOME}/.kube/config-pre" "${HOME}/.kube/config-pre-$(date +%F+%T)"
		fi	
		cp -p "${HOME}/.kube/config" "${HOME}/.kube/config-pre"
		cp -p "${PWD}/kubeconfig" "${HOME}/.kube/config"
	else	# .kube exists without config
		cp -p "${PWD}/kubeconfig" "${HOME}/.kube/config"		
	fi
	export KUBECONFIG="${HOME}/.kube/config"
	${kubectl} config rename-context default ${CLUSTER_NAME}
	${kubectl} config get-contexts
	${kubectl} get nodes
	${kubectl} get pods,sc -A	
}

function get_kubeconfig() {
	get_cluster_uuid
	CL_STATUS=""
	counter=20
	# cluster status remains ok.
	until [[ ${CL_STATUS} = "ok" || ${counter} -eq 0 ]] ; do
		echo "Counter ${counter}"
		if [ ${counter} -eq 0 ]; then
			echo "ERROR downloading the kubeconfig. Cluster API status: ${CL_STATUS}."
			exit 1
		fi
		check_cluster_status
		if [ "${CL_STATUS}" = "ok" ]; then
			echo "Cluster API Status: ${CL_STATUS}"
		fi
		let counter--
		sleep ${SS}
	done

	QBERT_URL="${BASE_URL}/qbert/v3"
	curl -s -o "kubeconfig"\
    -H "Content-Type: application/json" \
    -H "X-AUTH-TOKEN: $X_AUTH_TOKEN" \
    "$QBERT_URL/$PROJECT_UUID/kubeconfig/$cluster_uuid"
    if [[ ${os_type} == "mac" ]]; then
    	sed -i '' "s/__INSERT_BEARER_TOKEN_HERE__/${X_AUTH_TOKEN}/" "$PWD/kubeconfig"
    else
    	sed -i "s/__INSERT_BEARER_TOKEN_HERE__/${X_AUTH_TOKEN}/" "$PWD/kubeconfig"
    fi
    export KUBECONFIG="${PWD}/kubeconfig"
    ${kubectl} config get-contexts
    ${kubectl} get pods -n kube-system
}
