# Tested on MacOS 10.15.4 and PMK 4.5.2 (k8s v1.17.9)
#!/bin/bash
# The user must have access to write to /usr/local/bin
#curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.17.9/bin/linux/amd64/kubectl


#!/bin/bash
if [ -z $1 ] ; then
  source "${PWD}/common.sh"
elif [ ! -f ${PWD}/$1 ] ; then
  echo " $1 file is not found in the present directory."
  exit 1
else
  source "${PWD}/$1"
fi

install_kubectl

cp -pr /tmp/kubectl /usr/local/bin



