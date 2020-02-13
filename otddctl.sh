#!/bin/bash

usage(){
	echo "Usage: otddctl.sh [apply|delete] options"
	echo -e "\t-v istioVersion: \t\tthe istio version when using apply command"
	echo -e "\t-t targetDeployment: \t\tthe target deployment to record"
	echo -e "\t-p port: \t\t\tthe deployment's container port"  
	echo -e "\t-n namespace: \t\t\tthe target depoyment's namespace. default value: default"
	echo -e "\t-i interval: \t\t\tthe redirector's interval(in milisecond) to redirect the request. defaults value: 1000"
	echo -e "\t-P protocol: \t\t\tthe target depoyment's protocol. defaults value: http"
	echo ""
	echo -e "\texamples: \t\t\totddctl.sh apply -v 1.2.2 -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh delete -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh apply -v 1.2.2 -t reviews-v2 -p 9080"
	echo -e "\t\t\t\t\totddctl.sh delete -t reviews-v2 -p 9080"
	exit 1
}

if ! jq_loc="$(type -p "jq")" || [[ -z $jq_loc ]]; then
  echo "jq not installed. please refer to https://stedolan.github.io/jq/download/"
  exit
fi

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

NAMESPACE="default"
INTERVAL=1000
PROTOCOL="http"
if [ "$1" == "apply" ]
then
  ACTION=$1
  shift
fi

if [ "$1" == "delete" ]
then
  ACTION=$1
  shift
fi

if [ -z "$ACTION" ]
then
  usage
fi

while getopts v:t:p:n:i:P: option 
do 
 case "${option}" 
 in 
 v) ISTIO_VERSION=${OPTARG};; 
 t) TARGETDEPLOYMENT=${OPTARG};; 
 p) PORT=${OPTARG};; 
 n) NAMESPACE=${OPTARG};; 
 i) INTERVAL=${OPTARG};; 
 P) PROTOCOL=${OPTARG};; 
 esac 
done


if [ -z "$ISTIO_VERSION" ] && [ $ACTION != "delete" ]
then
  usage
fi

if [ -z "$TARGETDEPLOYMENT" ]
then
  usage
fi

if [ -z "$PORT" ] && [ $ACTION != "delete" ]
then
  usage
fi

if [ -z "$PORT" ]
then
  PORT=8080
fi

#for i in $@; do :; done
if [ $ACTION == "apply" ]
then
  echo "applying recorder for $TARGETDEPLOYMENT on port:$PORT in namespace:$NAMESPACE, protocol:$PROTOCOL redirecting interval:$INTERVAL"
fi

if [ $ACTION == "delete" ]
then
  echo "deleting recorder for $TARGETDEPLOYMENT"
fi

#check whether the target deployment exists

kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT" >/dev/null 2>&1
RESULT=`echo $?`
if [ $RESULT != "0" ]
then
  echo "target deployment: "$TARGETDEPLOYMENT" not found in namespace: "$NAMESPACE" ( kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT" exist with code !=0 ) "
  exit 1
fi

# read the yml template from a file and substitute the string 
# {{MYVARNAME}} with the value of the MYVARVALUE variable
template=`cat "$SCRIPTPATH/template/otdd-recorder.yaml.template" | sed "s/{{TARGETDEPLOYMENT}}/$TARGETDEPLOYMENT/g"`
template=`echo "$template" | sed "s/{{PORT}}/$PORT/g"`
template=`echo "$template" | sed "s/{{NAMESPACE}}/$NAMESPACE/g"`
template=`echo "$template" | sed "s/{{INTERVAL}}/$INTERVAL/g"`
template=`echo "$template" | sed "s/{{PROTOCOL}}/$PROTOCOL/g"`


if [ $ACTION == "apply" ]
then
  #replace istio proxyv2 image to otdd proxyv2 to include otdd redirect/recorder plugins by changing the .Values.global.proxy.image in the configmap.
  #write to a temp file then VALUE=`cat .otdd_tmp instead of using VALUE=`...` directly because the \n will lost wiredly.
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config" |awk -v version="$ISTIO_VERSION" '{gsub(/name:[ ]+istio-proxy.+[ ]{4}ports/,"name: istio-proxy\\n    image: docker.io/otdd/proxyv2:" version "-otdd.0.1.0\\n    ports"); print $0}' > .otdd_tmp
  VALUE=`cat .otdd_tmp`
  rm -rf .otdd_tmp
  INJECTOR_BEFORE=`kubectl -n istio-system get pods |grep istio-sidecar-injector|awk '{print $1}'`
  echo "changing istio-sidecar-injector config and restart it.."
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
  kubectl -n istio-system rollout restart deploy/istio-sidecar-injector
  FOUND="1"
  while [ $FOUND == "1" ]
  do
    FOUND="0"
    echo "waiting istio-sidecar-injector to be fully ready.. please do not kill this script."
    sleep 3
    INJECTOR_AFTER=`kubectl -n istio-system get pods |grep istio-sidecar-injector|awk '{print $1}'`
    for i in $INJECTOR_BEFORE ; do
      for j in $INJECTOR_AFTER ; do
        if [[ $i == $j ]]
        then
             # some old injector still not terminated.
             FOUND="1"
        fi
      done
    done
  done
fi
#echo "$template"
# apply the yml with the substituted value
#install the redirector/recorder
echo "$template" | kubectl $ACTION -f -

if [ $ACTION == "apply" ]
then
  #restore back the istio injector config
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config" |awk '{gsub(/name:[ ]+istio-proxy.+[ ]{4}ports/,"name: istio-proxy\\n  {{- if contains \\\"/\\\" .Values.global.proxy.image }}\\n    image: \\\"{{ annotation .ObjectMeta `sidecar.istio.io/proxyImage` .Values.global.proxy.image }}\\\"\\n  {{- else }}\\n    image: \\\"{{ annotation .ObjectMeta `sidecar.istio.io/proxyImage` .Values.global.hub }}/{{ .Values.global.proxy.image }}:{{ .Values.global.tag }}\\\"\\n  {{- end }}\\n    ports"); print $0}' > .otdd_tmp_uninstall
  VALUE=`cat .otdd_tmp_uninstall`
  rm -rf .otdd_tmp_uninstall
  INJECTOR_BEFORE=`kubectl -n istio-system get pods |grep istio-sidecar-injector|awk '{print $1}'`
  echo "restoring back istio-sidecar-injector config and restart it.."
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
  kubectl -n istio-system rollout restart deploy/istio-sidecar-injector
  FOUND="1"
  while [ $FOUND == "1" ]
  do
    FOUND="0"
    echo "waiting istio-sidecar-injector to be fully ready.. "
    sleep 3
    INJECTOR_AFTER=`kubectl -n istio-system get pods |grep istio-sidecar-injector|awk '{print $1}'`
    for i in $INJECTOR_BEFORE ; do
      for j in $INJECTOR_AFTER ; do
        if [[ $i == $j ]]
        then
             # some old injector still not terminated.
             FOUND="1"
        fi
      done
    done
  done
  echo "all done!"
fi
