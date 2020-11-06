# Tested only on Ubuntu 18.04.
#!/bin/bash
exec &> /tmp/logfile
set -x
date

source "${PWD}/common.sh"
	

grep "Ubuntu" /etc/os-release
if [ $? -eq 0 ]; then
	export LC_ALL=C.UTF-8
	export LANG=C.UTF-8
else
	echo "ERROR unsupported OS type. Only Ubuntu is supported for running this script."
	exit 1
fi


sudo apt-get install xsltproc -y

curl -sL http://pf9.io/get_cli > ./pf9_installer
chmod +x ./pf9_installer
./pf9_installer --install_only
if [ $? -ne 0 ]; then
	echo "INFO sleeping on $(hostnamectl --static) for ${LS} seconds before trying to run pf9ctl second time."
	sleep ${LS}
	./pf9_installer --install_only
	if [ $? -ne 0 ]; then
		echo "ERROR could not install the pf9ctl on $(hostnamectl --static) after two attempts."
		exit 1
	fi
fi


if [ ! -f /usr/bin/pf9ctl ]; then
	echo "ERROR /usr/bin/pf9ctl not found on $(hostnamectl --static)"
	exit 1
else
	echo "INFO /usr/bin/pf9ctl present on $(hostnamectl --static)"
fi


pf9ctl config  create --du_url "${AUTH_URL}" --os_username "${AUTH_USER}" --os_password "${AUTH_PASS}" \
--os_region "${REGION}"  --os_tenant "${TENANT}"


pf9ctl config validate

if [ $? -eq 0 ]; then
	echo "INFO successfully authenticated from node $(hostnamectl --static) to ${AUTH_URL}"
else
	echo "ERROR authenticating from node $(hostnamectl --static) to ${AUTH_URL}"
	exit 1
fi

echo "INFO Preparing node $(hostnamectl --static) to connect with ${AUTH_URL}."
echo "Y"|pf9ctl cluster prep-node
if [ $? -ne 0 ]; then
	echo "ERROR connecting node $(hostnamectl --static) to ${AUTH_URL}"
else
	echo "SUCCESS connected node $(hostnamectl --static) to ${AUTH_URL}"
	sleep ${SS}
fi
date