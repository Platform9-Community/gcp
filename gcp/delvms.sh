#!/bin/bash
set -x

if [ -z $1 ] ; then
  source "${PWD}/common.sh"
elif [ ! -f ${PWD}/$1 ] ; then
  echo " $1 file is not found in the present directory."
  exit 1
else
  source "${PWD}/$1"
fi

workers
for value in "${workers[@]}"; do
	echo ${value}
	gcloud beta compute instances delete ${value} --quiet
done
gcloud beta compute instances delete ${master} --quiet
