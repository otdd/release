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

#replace istio proxyv2 image to otdd proxyv2 to include otdd redirect/recorder plugins by changing the .Values.global.proxy.image in the configmap.
#write to a temp file then VALUE=`cat .otdd_tmp instead of using VALUE=`...` directly because the \n will lost wiredly. 
kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config" |awk -v version="$ISTIO_VERSION" '{gsub(/name:[ ]+istio-proxy.+[ ]{4}ports/,"name: istio-proxy\\n    image: docker.io/otdd/proxyv2:" version "-otdd.0.1.0\\n    ports"); print $0}' > .otdd_tmp
VALUE=`cat .otdd_tmp`
rm -rf .otdd_tmp
kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
kubectl -n istio-system rollout restart deploy/istio-sidecar-injector

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
