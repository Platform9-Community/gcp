#!/bin/bash
if [ -z $1 ] ; then
  source "${PWD}/common.sh"
elif [ ! -f ${PWD}/$1 ] ; then
  echo " $1 file is not found in the present directory."
  exit 1
else
  source "${PWD}/$1"
fi

get_token
echo ${X_AUTH_TOKEN}
echo ${PROJECT_UUID}