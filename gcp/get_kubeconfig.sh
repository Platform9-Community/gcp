#!/bin/bash

if [ -z $1 ] ; then
  source "${PWD}/common.sh"
elif [ ! -f ${PWD}/$1 ] ; then
  echo " $1 file is not found in the present directory."
  exit 1
else
  source "${PWD}/$1"
fi

# Running from Mac or Linux ?
os_type

# Download your token for your tenant.
get_token

# Download kubeconfig and add token into it.
get_kubeconfig

# set the kubeconfig file as default kubeconfig
set_default_kubeconfig