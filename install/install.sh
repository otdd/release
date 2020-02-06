#!/bin/bash

usage(){
        echo "Usage: install.sh -v istio-version"
        echo ""
        echo -e "\texamples: \t\t./install.sh -v 1.2.2"
        exit 1
}

while getopts v: option
do
 case "${option}"
 in
 v) ISTIO_VERSION=${OPTARG};;
 esac
done

if [ -z "$ISTIO_VERSION" ]
then
  usage
fi

#change istio proxyv2 to include otdd redirect/recorder plugins.
kubectl -n istio-system get configmap istio-sidecar-injector -o yaml | sed "s/istio\/proxyv2:$ISTIO_VERSION/otdd\/proxyv2:$ISTIO_VERSION-otdd.0.1.0/g"| kubectl apply -f -
kubectl -n istio-system rollout restart deploy/istio-sidecar-injector

#create otdd-system namespace
kubectl apply -f artifacts/namespace.yaml

#install otdd recorder crd and it's k8s controller
for i in artifacts/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f artifacts/otdd-controller.yaml
#install istio mixer otdd adapter
for i in artifacts/istio-mixer*.yaml; do kubectl apply -f $i; done
kubectl apply -f artifacts/otdd-adapter.yaml
