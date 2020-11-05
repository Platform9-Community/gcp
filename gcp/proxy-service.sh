#!/bin/bash
kubectl get svc proxy -o json|jq '.spec.externalTrafficPolicy = "Cluster"' |kubectl replace -f -
kubectl get svc proxy -o json|jq '.spec.ports[].nodePort = 31237'|kubectl replace -f  -
kubectl get svc proxy -o wide