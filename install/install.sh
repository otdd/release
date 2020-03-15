#!/bin/bash

echo "determine istio version ..."
ISTIO_VERSION=`kubectl -n istio-system get configmap istio-sidecar-injector -o jsonpath='{.data.values}'|jq ".global.tag"`
#trim prefix/suffix quote
ISTIO_VERSION="${ISTIO_VERSION%\"}"
ISTIO_VERSION="${ISTIO_VERSION#\"}"

if [ -z $ISTIO_VERSION ]; then
	#before 1.2 the istio version is hard coded.
	ISTIO_VERSION=`kubectl -n istio-system get configmap istio-sidecar-injector -o jsonpath='{.data.config}'|grep image |grep proxyv2|awk -F':' '{print $3}'|awk -F'"' '{print $1}'`
fi

if [ -z $ISTIO_VERSION ]; then
	echo "cannot determine istio version. please install istio first."
	exit 1
fi

echo "istio version is $ISTIO_VERSION"

DIGITS=$(echo $ISTIO_VERSION | tr "\." "\n")

INDEX=0
for DIGIT in $DIGITS
do
	if [ $INDEX -eq 0 ]; then
		MAJOR_VERSION=$DIGIT	
	fi
	if [ $INDEX -eq 1 ]; then
		MINOR_VERSION=$DIGIT	
	fi
	INDEX=$(( $INDEX + 1 ))
done

if [ -z "$MAJOR_VERSION" ]; then
	echo "istio version formmat not recognized:" $ISTIO_VERSION
	exit 1
fi

if [ -z "$MINOR_VERSION" ]; then
	echo "istio version formmat not recognized: " $ISTIO_VERSION
	exit 1
fi

#create otdd-system namespace
kubectl apply -f artifacts/namespace.yaml

#install otdd recorder crd and it's k8s controller
for i in artifacts/crd*yaml; do kubectl apply -f $i; done
kubectl apply -f artifacts/otdd-controller.yaml

if [[ $MAJOR_VERSION -eq 1 && $MINOR_VERSION -lt 5  ]]; then
	#install istio mixer otdd adapter for istio version before istio version 1.5.0
	for i in artifacts/before_1.5/*.yaml; do kubectl apply -f $i; done
fi
#install the otdd-server
kubectl apply -f artifacts/otdd-server.yaml
