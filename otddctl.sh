#!/bin/bash

usage(){
	echo "Usage: otddctl.sh [apply|delete] options"
	echo -e "\t-t targetDeployment: \t\tthe target deployment to record"
	echo -e "\t-p port: \t\t\tthe deployment's container port"  
	echo -e "\t-n namespace: \t\t\tthe target depoyment's namespace. default value: default"
	echo -e "\t-i interval: \t\t\tthe redirector's interval(in milisecond) to redirect the request. defaults value: 1000"
	echo -e "\t-P protocol: \t\t\tthe target depoyment's protocol. defaults value: http"
        echo -e "\t-v istioVersion (optional): \t\tspecify the istio version"
	echo ""
	echo -e "\texamples: \t\t\totddctl.sh apply -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh delete -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh apply -t reviews-v2 -p 9080 -v 1.2.2"
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
 v) SPECIFIED_ISTIO_VERSION=${OPTARG};;
 t) TARGETDEPLOYMENT=${OPTARG};; 
 p) PORT=${OPTARG};; 
 n) NAMESPACE=${OPTARG};; 
 i) INTERVAL=${OPTARG};; 
 P) PROTOCOL=${OPTARG};; 
 esac 
done

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

if [ $ACTION == "apply" ]
then
  kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT" >/dev/null 2>&1
  RESULT=`echo $?`
  if [ $RESULT != "0" ]
  then
    echo "target deployment: "$TARGETDEPLOYMENT" not found in namespace: "$NAMESPACE" ( kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT" exist with code !=0 ) "
    exit 1
  fi
fi

if [ $ACTION == "delete" ]
then
  kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT-otdd-recorder" >/dev/null 2>&1
  RESULT=`echo $?`
  if [ $RESULT != "0" ]
  then
    echo "target deployment: "$TARGETDEPLOYMENT" not found in namespace: "$NAMESPACE" ( kubectl -n "$NAMESPACE" get deployment "$TARGETDEPLOYMENT-otdd-recorder" exist with code !=0 ) "
    exit 1
  fi
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

  echo "determing installed istio version ..."
  ISTIO_VERSION=`kubectl -n istio-system get configmap istio-sidecar-injector -o jsonpath='{.data.values}'|jq ".global.tag"`
  #trim prefix/suffix quote
  ISTIO_VERSION="${ISTIO_VERSION%\"}"
  ISTIO_VERSION="${ISTIO_VERSION#\"}"

  echo "installed istio version is $ISTIO_VERSION"

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

  #before 1.5.0, it's an standalone istio-sidecar-injector to inject the istio proxy.  
  if [[ $MAJOR_VERSION -eq 1 && $MINOR_VERSION -lt 5  ]]; then 
    STIO_INSTANCE="istio-sidecar-injector"
  else
    ISTIO_INSTANCE="istiod"
  fi

if [[ ! -z "$SPECIFIED_ISTIO_VERSION " ]]
then
  echo "applying recorder for specific istio version $SPECIFIED_ISTIO_VERSION"
  ISTIO_VERSION=$SPECIFIED_ISTIO_VERSION
fi

if [[ ! $ISTIO_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version $ISTIO_VERSION is not supported! only three digit type of version is supported, e.g. 1.4.2 or 1.5.0"
  exit 1
fi

fi

if [ $ACTION == "apply" ]
then

  #replace istio proxyv2 image to otdd proxyv2 to include otdd redirect/recorder plugins by changing the .Values.global.proxy.image in the configmap.
  #write to a temp file then VALUE=`cat .otdd_tmp instead of using VALUE=`...` directly because the \n will lost wiredly.
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config" |awk -v version="$ISTIO_VERSION" '{gsub(/name:[ ]+istio-proxy.+[ ]{4}ports/,"name: istio-proxy\\n    image: docker.io/otdd/proxyv2:" version "-otdd.0.1.0\\n    ports"); print $0}' > .otdd_tmp
  VALUE=`cat .otdd_tmp`
  rm -rf .otdd_tmp
  INJECTOR_BEFORE=`kubectl -n istio-system get pods |grep $ISTIO_INSTANCE|awk '{print $1}'`
  echo "changing istio-sidecar-injector config and restart it.."
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
  kubectl -n istio-system rollout restart deploy/$ISTIO_INSTANCE
  FOUND="1"
  while [ $FOUND == "1" ]
  do
    FOUND="0"
    echo "waiting $ISTIO_INSTANCE to be fully ready.. please do not kill this script."
    sleep 3
    INJECTOR_AFTER=`kubectl -n istio-system get pods |grep $ISTIO_INSTANCE|awk '{print $1}'`
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
  INJECTOR_BEFORE=`kubectl -n istio-system get pods |grep $ISTIO_INSTANCE|awk '{print $1}'`
  echo "restoring back istio-sidecar-injector config and restart it.."
  kubectl -n istio-system get configmap istio-sidecar-injector -o json | jq ".data.config=$VALUE" | kubectl apply -f -
  kubectl -n istio-system rollout restart deploy/$ISTIO_INSTANCE
  FOUND="1"
  while [ $FOUND == "1" ]
  do
    FOUND="0"
    echo "waiting $ISTIO_INSTANCE to be fully ready.. "
    sleep 3
    INJECTOR_AFTER=`kubectl -n istio-system get pods |grep $ISTIO_INSTANCE|awk '{print $1}'`
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
