#!/bin/bash

#create otdd-system namespace
kubectl apply -f artifacts/namespace.yaml

#install otdd recorder crd and it's k8s controller
for i in artifacts/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f artifacts/otdd-controller.yaml
#install istio mixer otdd adapter
for i in artifacts/istio-mixer*.yaml; do kubectl apply -f $i; done
kubectl apply -f artifacts/otdd-adapter.yaml
#install the otdd-server
kubectl apply -f artifacts/otdd-server.yaml
