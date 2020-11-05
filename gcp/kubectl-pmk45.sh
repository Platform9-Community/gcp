# Tested on MacOS 10.15.4 and PMK 4.5.2 (k8s v1.17.9)
#!/bin/bash
#curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.17.9/bin/linux/amd64/kubectl

install_kubectl() {
	curl -LO "https://storage.googleapis.com/kubernetes-release/release/v1.17.9/bin/darwin/amd64/kubectl"
	chmod a+x kubectl
	mv kubectl /usr/local/bin
}


ver=$(/usr/local/bin/kubectl version|awk -F: '{print $5}'|awk -F, '{print $1}'|head -1)

if [ ! -f /usr/local/bin/kubectl ]; then 
	install_kubectl
elif [[ ${ver} != "\"v1.17.9\"" ]]; then
	echo $ver
	install_kubectl
fi



