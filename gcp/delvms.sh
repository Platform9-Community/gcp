#!/bin/bash
set -x

source "${PWD}/common.sh"

workers
for value in "${workers[@]}"; do
	echo ${value}
	gcloud beta compute instances delete ${value} --quiet
done
gcloud beta compute instances delete ${master} --quiet
