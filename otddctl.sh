#!/bin/bash

usage(){
	echo "Usage: otddctl.sh [apply|delete] options"
	echo -e "\t-t targetDeployment: \t\tthe target deployment to record"
	echo -e "\t-p port: \t\t\tthe deployment's container port"  
	echo -e "\t-n namespace: \t\t\tthe target depoyment's namespace. default value: default"
	echo -e "\t-i interval: \t\t\tthe redirector's interval(in milisecond) to redirect the request. defaults value: 1000"
	echo -e "\t-P protocol: \t\t\tthe target depoyment's protocol. defaults value: http"
	echo ""
	echo -e "\texamples: \t\t\totddctl.sh apply -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh delete -t reviews-v2 -p 9080 -n default -i 1000 -P http"
	echo -e "\t\t\t\t\totddctl.sh apply -t reviews-v2 -p 9080"
	echo -e "\t\t\t\t\totddctl.sh delete -t reviews-v2 -p 9080"
	exit 1
}

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

while getopts t:p:n:i:P: option 
do 
 case "${option}" 
 in 
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
  echo "${ACTION}ing recorder for $TARGETDEPLOYMENT on port:$PORT in namespace:$NAMESPACE, protocol:$PROTOCOL redirecting interval:$INTERVAL"
fi

if [ $ACTION == "delete" ]
then
  echo "${ACTION}ing recorder for $TARGETDEPLOYMENT"
fi

# read the yml template from a file and substitute the string 
# {{MYVARNAME}} with the value of the MYVARVALUE variable
template=`cat "$SCRIPTPATH/template/otdd-recorder.yaml.template" | sed "s/{{TARGETDEPLOYMENT}}/$TARGETDEPLOYMENT/g"`
template=`echo "$template" | sed "s/{{PORT}}/$PORT/g"`
template=`echo "$template" | sed "s/{{NAMESPACE}}/$NAMESPACE/g"`
template=`echo "$template" | sed "s/{{INTERVAL}}/$INTERVAL/g"`
template=`echo "$template" | sed "s/{{PROTOCOL}}/$PROTOCOL/g"`

#echo "$template"
# apply the yml with the substituted value

echo "$template" | kubectl $ACTION -f -
